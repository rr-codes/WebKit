/*
 * Copyright (C) 2015-2021 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "config.h"
#include "MemoryIDBBackingStore.h"

#include "IDBCursorInfo.h"
#include "IDBGetAllRecordsData.h"
#include "IDBGetRecordData.h"
#include "IDBGetResult.h"
#include "IDBIndexInfo.h"
#include "IDBIterateCursorData.h"
#include "IDBKeyRangeData.h"
#include "Logging.h"
#include "MemoryIndexCursor.h"
#include "MemoryObjectStore.h"
#include "MemoryObjectStoreCursor.h"
#include <wtf/TZoneMallocInlines.h>

namespace WebCore {
namespace IDBServer {

// The IndexedDB spec states the maximum value you can get from the key generator is 2^53.
constexpr uint64_t maxGeneratedKeyValue = 0x20000000000000;

WTF_MAKE_TZONE_ALLOCATED_IMPL(MemoryIDBBackingStore);

MemoryIDBBackingStore::MemoryIDBBackingStore(const IDBDatabaseIdentifier& identifier)
    : m_identifier(identifier)
{
}

MemoryIDBBackingStore::~MemoryIDBBackingStore() = default;

IDBError MemoryIDBBackingStore::getOrEstablishDatabaseInfo(IDBDatabaseInfo& info)
{
    if (!m_databaseInfo)
        m_databaseInfo = makeUnique<IDBDatabaseInfo>(m_identifier.databaseName(), 0, 0);

    info = *m_databaseInfo;
    return IDBError { };
}

uint64_t MemoryIDBBackingStore::databaseVersion()
{
    return m_databaseInfo ? m_databaseInfo->version() : 0;
}

void MemoryIDBBackingStore::setDatabaseInfo(const IDBDatabaseInfo& info)
{
    // It is not valid to directly set database info on a backing store that hasn't already set its own database info.
    ASSERT(m_databaseInfo);

    m_databaseInfo = makeUnique<IDBDatabaseInfo>(info);
}

IDBError MemoryIDBBackingStore::beginTransaction(const IDBTransactionInfo& info)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::beginTransaction");

    if (m_transactions.contains(info.identifier()))
        return IDBError { ExceptionCode::InvalidStateError, "Backing store asked to create transaction it already has a record of"_s };

    auto transaction = MemoryBackingStoreTransaction::create(*this, info);

    // VersionChange transactions are scoped to "every object store".
    if (transaction->isVersionChange()) {
        for (auto& objectStore : m_objectStoresByIdentifier.values())
            transaction->addExistingObjectStore(*objectStore);
    } else if (transaction->isWriting()) {
        for (auto& iterator : m_objectStoresByName) {
            if (info.objectStores().contains(iterator.key))
                transaction->addExistingObjectStore(Ref { *iterator.value });
        }
    }

    m_transactions.set(info.identifier(), WTFMove(transaction));

    return IDBError { };
}

IDBError MemoryIDBBackingStore::abortTransaction(const IDBResourceIdentifier& transactionIdentifier)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::abortTransaction - %s", transactionIdentifier.loggingString().utf8().data());

    auto transaction = m_transactions.take(transactionIdentifier);
    if (!transaction)
        return IDBError { ExceptionCode::InvalidStateError, "Backing store asked to abort transaction it didn't have record of"_s };

    transaction->abort();

    return IDBError { };
}

IDBError MemoryIDBBackingStore::commitTransaction(const IDBResourceIdentifier& transactionIdentifier)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::commitTransaction - %s", transactionIdentifier.loggingString().utf8().data());

    auto transaction = m_transactions.take(transactionIdentifier);
    if (!transaction)
        return IDBError { ExceptionCode::InvalidStateError, "Backing store asked to commit transaction it didn't have record of"_s };

    transaction->commit();

    return IDBError { };
}

IDBError MemoryIDBBackingStore::createObjectStore(const IDBResourceIdentifier& transactionIdentifier, const IDBObjectStoreInfo& info)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::createObjectStore - adding OS %s with ID %" PRIu64, info.name().utf8().data(), info.identifier().toRawValue());

    ASSERT(m_databaseInfo);
    if (m_databaseInfo->hasObjectStore(info.name()))
        return IDBError { ExceptionCode::ConstraintError };

    ASSERT(!m_objectStoresByIdentifier.contains(info.identifier()));
    auto objectStore = MemoryObjectStore::create(info);

    m_databaseInfo->addExistingObjectStore(info);

    RefPtr rawTransaction = m_transactions.get(transactionIdentifier);
    RELEASE_ASSERT(rawTransaction);
    RELEASE_ASSERT(rawTransaction->isVersionChange());

    rawTransaction->addNewObjectStore(objectStore.get());
    registerObjectStore(WTFMove(objectStore));

    return IDBError { };
}

IDBError MemoryIDBBackingStore::deleteObjectStore(const IDBResourceIdentifier& transactionIdentifier, IDBObjectStoreIdentifier objectStoreIdentifier)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::deleteObjectStore");

    ASSERT(m_databaseInfo);
    if (!m_databaseInfo->infoForExistingObjectStore(objectStoreIdentifier))
        return IDBError { ExceptionCode::ConstraintError };

    RefPtr transaction = m_transactions.get(transactionIdentifier);
    RELEASE_ASSERT(transaction);
    RELEASE_ASSERT(transaction->isVersionChange());

    auto objectStore = takeObjectStoreByIdentifier(objectStoreIdentifier);
    ASSERT(objectStore);
    if (!objectStore)
        return IDBError { ExceptionCode::ConstraintError };

    m_databaseInfo->deleteObjectStore(objectStore->info().name());
    transaction->objectStoreDeleted(*objectStore);

    return IDBError { };
}

IDBError MemoryIDBBackingStore::renameObjectStore(const IDBResourceIdentifier& transactionIdentifier, IDBObjectStoreIdentifier objectStoreIdentifier, const String& newName)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::renameObjectStore");

    ASSERT(m_databaseInfo);
    if (!m_databaseInfo->infoForExistingObjectStore(objectStoreIdentifier))
        return IDBError { ExceptionCode::ConstraintError };

    RefPtr transaction = m_transactions.get(transactionIdentifier);
    RELEASE_ASSERT(transaction);
    RELEASE_ASSERT(transaction->isVersionChange());

    RefPtr objectStore = m_objectStoresByIdentifier.get(objectStoreIdentifier);
    ASSERT(objectStore);
    if (!objectStore)
        return IDBError { ExceptionCode::ConstraintError };

    String oldName = objectStore->info().name();
    objectStore->rename(newName);
    transaction->objectStoreRenamed(*objectStore, oldName);

    m_objectStoresByName.remove(oldName);
    m_objectStoresByName.set(newName, objectStore);

    m_databaseInfo->renameObjectStore(objectStoreIdentifier, newName);

    return IDBError { };
}

IDBError MemoryIDBBackingStore::clearObjectStore(const IDBResourceIdentifier& transactionIdentifier, IDBObjectStoreIdentifier objectStoreIdentifier)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::clearObjectStore");

    ASSERT_UNUSED(transactionIdentifier, m_transactions.contains(transactionIdentifier));

#ifndef NDEBUG
    RefPtr transaction = m_transactions.get(transactionIdentifier);
    ASSERT_UNUSED(transaction, transaction->isWriting());
#endif

    RefPtr objectStore = m_objectStoresByIdentifier.get(objectStoreIdentifier);
    if (!objectStore)
        return IDBError { ExceptionCode::ConstraintError };

    objectStore->clear();

    return IDBError { };
}

IDBError MemoryIDBBackingStore::deleteIndex(const IDBResourceIdentifier& transactionIdentifier, IDBObjectStoreIdentifier objectStoreIdentifier, IDBIndexIdentifier indexIdentifier)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::deleteIndex");

    ASSERT(m_databaseInfo);
    auto* objectStoreInfo = m_databaseInfo->infoForExistingObjectStore(objectStoreIdentifier);
    if (!objectStoreInfo)
        return IDBError { ExceptionCode::ConstraintError };

    auto* indexInfo = objectStoreInfo->infoForExistingIndex(indexIdentifier);
    if (!indexInfo)
        return IDBError { ExceptionCode::ConstraintError };

    RefPtr rawTransaction = m_transactions.get(transactionIdentifier);
    RELEASE_ASSERT(rawTransaction);
    RELEASE_ASSERT(rawTransaction->isVersionChange());

    RefPtr objectStore = m_objectStoresByIdentifier.get(objectStoreIdentifier);
    if (!objectStore)
        return IDBError { ExceptionCode::ConstraintError };

    auto error = objectStore->deleteIndex(*rawTransaction, indexIdentifier);
    if (error.isNull())
        objectStoreInfo->deleteIndex(indexIdentifier);

    return error;
}

IDBError MemoryIDBBackingStore::renameIndex(const IDBResourceIdentifier& transactionIdentifier, IDBObjectStoreIdentifier objectStoreIdentifier, IDBIndexIdentifier indexIdentifier, const String& newName)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::renameIndex");

    ASSERT(m_databaseInfo);
    auto* objectStoreInfo = m_databaseInfo->infoForExistingObjectStore(objectStoreIdentifier);
    if (!objectStoreInfo)
        return IDBError { ExceptionCode::ConstraintError };

    auto* indexInfo = objectStoreInfo->infoForExistingIndex(indexIdentifier);
    if (!indexInfo)
        return IDBError { ExceptionCode::ConstraintError };

    RefPtr transaction = m_transactions.get(transactionIdentifier);
    RELEASE_ASSERT(transaction);
    RELEASE_ASSERT(transaction->isVersionChange());

    RefPtr objectStore = m_objectStoresByIdentifier.get(objectStoreIdentifier);
    ASSERT(objectStore);
    if (!objectStore)
        return IDBError { ExceptionCode::ConstraintError };

    auto* index = objectStore->indexForIdentifier(indexIdentifier);
    ASSERT(index);
    if (!index)
        return IDBError { ExceptionCode::ConstraintError };

    String oldName = index->info().name();
    objectStore->renameIndex(*index, newName);
    transaction->indexRenamed(*index, oldName);

    indexInfo->rename(newName);

    return IDBError { };
}

void MemoryIDBBackingStore::renameObjectStoreForVersionChangeAbort(MemoryObjectStore& objectStore, const String& oldName)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::renameObjectStoreForVersionChangeAbort");

    auto identifier = objectStore.info().identifier();
    auto currentName = objectStore.info().name();
    m_objectStoresByName.remove(currentName);
    m_objectStoresByName.set(oldName, &objectStore);
    m_databaseInfo->renameObjectStore(identifier, oldName);
    objectStore.rename(oldName);
}

void MemoryIDBBackingStore::removeObjectStoreForVersionChangeAbort(MemoryObjectStore& objectStore)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::removeObjectStoreForVersionChangeAbort");

    if (!m_objectStoresByIdentifier.contains(objectStore.info().identifier()))
        return;

    ASSERT(m_objectStoresByIdentifier.get(objectStore.info().identifier()) == &objectStore);

    unregisterObjectStore(objectStore);
}

void MemoryIDBBackingStore::restoreObjectStoreForVersionChangeAbort(Ref<MemoryObjectStore>&& objectStore)
{
    registerObjectStore(WTFMove(objectStore));
}

IDBError MemoryIDBBackingStore::keyExistsInObjectStore(const IDBResourceIdentifier&, IDBObjectStoreIdentifier objectStoreIdentifier, const IDBKeyData& keyData, bool& keyExists)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::keyExistsInObjectStore");

    RefPtr objectStore = m_objectStoresByIdentifier.get(objectStoreIdentifier);
    RELEASE_ASSERT(objectStore);

    keyExists = objectStore->containsRecord(keyData);
    return IDBError { };
}

IDBError MemoryIDBBackingStore::deleteRange(const IDBResourceIdentifier& transactionIdentifier, IDBObjectStoreIdentifier objectStoreIdentifier, const IDBKeyRangeData& range)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::deleteRange");

    if (!m_transactions.contains(transactionIdentifier))
        return IDBError { ExceptionCode::UnknownError, "No backing store transaction found to delete from"_s };

    RefPtr objectStore = m_objectStoresByIdentifier.get(objectStoreIdentifier);
    if (!objectStore)
        return IDBError { ExceptionCode::UnknownError, "No backing store object store found"_s };

    objectStore->deleteRange(range);
    return IDBError { };
}

IDBError MemoryIDBBackingStore::addRecord(const IDBResourceIdentifier& transactionIdentifier, const IDBObjectStoreInfo& objectStoreInfo, const IDBKeyData& keyData, const IndexIDToIndexKeyMap& indexKeys, const IDBValue& value)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::addRecord");

    RefPtr transaction = m_transactions.get(transactionIdentifier);
    if (!transaction)
        return IDBError { ExceptionCode::UnknownError, "No backing store transaction found to put record"_s };

    RefPtr objectStore = m_objectStoresByIdentifier.get(objectStoreInfo.identifier());
    if (!objectStore)
        return IDBError { ExceptionCode::UnknownError, "No backing store object store found to put record"_s };

    return objectStore->addRecord(*transaction, keyData, indexKeys, value);
}

IDBError MemoryIDBBackingStore::getRecord(const IDBResourceIdentifier& transactionIdentifier, IDBObjectStoreIdentifier objectStoreIdentifier, const IDBKeyRangeData& range, IDBGetRecordDataType type, IDBGetResult& outValue)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::getRecord");

    if (!m_transactions.contains(transactionIdentifier))
        return IDBError { ExceptionCode::UnknownError, "No backing store transaction found to get record"_s };

    RefPtr objectStore = m_objectStoresByIdentifier.get(objectStoreIdentifier);
    if (!objectStore)
        return IDBError { ExceptionCode::UnknownError, "No backing store object store found"_s };

    switch (type) {
    case IDBGetRecordDataType::KeyAndValue: {
        auto key = objectStore->lowestKeyWithRecordInRange(range);
        outValue = { key, key.isNull() ? ThreadSafeDataBuffer() : objectStore->valueForKey(key), objectStore->info().keyPath() };
        break;
    }
    case IDBGetRecordDataType::KeyOnly:
        outValue = objectStore->lowestKeyWithRecordInRange(range);
        break;
    }

    return IDBError { };
}

IDBError MemoryIDBBackingStore::getAllRecords(const IDBResourceIdentifier& transactionIdentifier, const IDBGetAllRecordsData& getAllRecordsData, IDBGetAllResult& result)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::getAllRecords");

    if (!m_transactions.contains(transactionIdentifier))
        return IDBError { ExceptionCode::UnknownError, "No backing store transaction found to get all records"_s };

    RefPtr objectStore = m_objectStoresByIdentifier.get(getAllRecordsData.objectStoreIdentifier);
    if (!objectStore)
        return IDBError { ExceptionCode::UnknownError, "No backing store object store found"_s };

    if (getAllRecordsData.indexIdentifier) {
        auto* index = objectStore->indexForIdentifier(*getAllRecordsData.indexIdentifier);
        if (!index)
            return IDBError { ExceptionCode::UnknownError, "No backing store index found"_s };

        index->getAllRecords(getAllRecordsData.keyRangeData, getAllRecordsData.count, getAllRecordsData.getAllType, result);
    } else
        objectStore->getAllRecords(getAllRecordsData.keyRangeData, getAllRecordsData.count, getAllRecordsData.getAllType, result);

    return IDBError { };
}

IDBError MemoryIDBBackingStore::getIndexRecord(const IDBResourceIdentifier& transactionIdentifier, IDBObjectStoreIdentifier objectStoreIdentifier, IDBIndexIdentifier indexIdentifier, IndexedDB::IndexRecordType recordType, const IDBKeyRangeData& range, IDBGetResult& outValue)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::getIndexRecord");

    if (!m_transactions.contains(transactionIdentifier))
        return IDBError { ExceptionCode::UnknownError, "No backing store transaction found to get record"_s };

    RefPtr objectStore = m_objectStoresByIdentifier.get(objectStoreIdentifier);
    if (!objectStore)
        return IDBError { ExceptionCode::UnknownError, "No backing store object store found"_s };

    outValue = objectStore->indexValueForKeyRange(indexIdentifier, recordType, range);
    return IDBError { };
}

IDBError MemoryIDBBackingStore::getCount(const IDBResourceIdentifier& transactionIdentifier, IDBObjectStoreIdentifier objectStoreIdentifier, std::optional<IDBIndexIdentifier> indexIdentifier, const IDBKeyRangeData& range, uint64_t& outCount)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::getCount");

    if (!m_transactions.contains(transactionIdentifier))
        return IDBError { ExceptionCode::UnknownError, "No backing store transaction found to get count"_s };

    RefPtr objectStore = m_objectStoresByIdentifier.get(objectStoreIdentifier);
    if (!objectStore)
        return IDBError { ExceptionCode::UnknownError, "No backing store object store found"_s };

    outCount = objectStore->countForKeyRange(indexIdentifier, range);

    return IDBError { };
}

IDBError MemoryIDBBackingStore::generateKeyNumber(const IDBResourceIdentifier& transactionIdentifier, IDBObjectStoreIdentifier objectStoreIdentifier, uint64_t& keyNumber)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::generateKeyNumber");
    ASSERT_UNUSED(transactionIdentifier, m_transactions.contains(transactionIdentifier));
    ASSERT_UNUSED(transactionIdentifier, m_transactions.get(transactionIdentifier)->isWriting());

    RefPtr objectStore = m_objectStoresByIdentifier.get(objectStoreIdentifier);
    RELEASE_ASSERT(objectStore);

    keyNumber = objectStore->currentKeyGeneratorValue();
    if (keyNumber > maxGeneratedKeyValue)
        return IDBError { ExceptionCode::ConstraintError, "Cannot generate new key value over 2^53 for object store operation"_s };

    objectStore->setKeyGeneratorValue(keyNumber + 1);

    return IDBError { };
}

IDBError MemoryIDBBackingStore::revertGeneratedKeyNumber(const IDBResourceIdentifier& transactionIdentifier, IDBObjectStoreIdentifier objectStoreIdentifier, uint64_t keyNumber)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::revertGeneratedKeyNumber");
    ASSERT_UNUSED(transactionIdentifier, m_transactions.contains(transactionIdentifier));
    ASSERT_UNUSED(transactionIdentifier, m_transactions.get(transactionIdentifier)->isWriting());

    RefPtr objectStore = m_objectStoresByIdentifier.get(objectStoreIdentifier);
    RELEASE_ASSERT(objectStore);

    objectStore->setKeyGeneratorValue(keyNumber);

    return IDBError { };
}

IDBError MemoryIDBBackingStore::maybeUpdateKeyGeneratorNumber(const IDBResourceIdentifier& transactionIdentifier, IDBObjectStoreIdentifier objectStoreIdentifier, double newKeyNumber)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::maybeUpdateKeyGeneratorNumber");
    ASSERT_UNUSED(transactionIdentifier, m_transactions.contains(transactionIdentifier));
    ASSERT_UNUSED(transactionIdentifier, m_transactions.get(transactionIdentifier)->isWriting());

    RefPtr objectStore = m_objectStoresByIdentifier.get(objectStoreIdentifier);
    RELEASE_ASSERT(objectStore);

    if (newKeyNumber < objectStore->currentKeyGeneratorValue())
        return IDBError { };

    if (newKeyNumber >= (double)maxGeneratedKeyValue) {
        objectStore->setKeyGeneratorValue(maxGeneratedKeyValue + 1);
        return IDBError { };
    }

    uint64_t newKeyInteger(newKeyNumber);
    if (newKeyInteger <= uint64_t(newKeyNumber))
        ++newKeyInteger;

    ASSERT(newKeyInteger > uint64_t(newKeyNumber));

    objectStore->setKeyGeneratorValue(newKeyInteger);

    return IDBError { };
}

IDBError MemoryIDBBackingStore::openCursor(const IDBResourceIdentifier& transactionIdentifier, const IDBCursorInfo& info, IDBGetResult& outData)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::openCursor");

    RefPtr transaction = m_transactions.get(transactionIdentifier);
    if (!transaction)
        return IDBError { ExceptionCode::UnknownError, "No backing store transaction found in which to open a cursor"_s };

    switch (info.cursorSource()) {
    case IndexedDB::CursorSource::ObjectStore: {
        auto identifier = std::get<IDBObjectStoreIdentifier>(info.sourceIdentifier());
        RefPtr objectStore = m_objectStoresByIdentifier.get(identifier);
        if (!objectStore)
            return IDBError { ExceptionCode::UnknownError, "No backing store object store found"_s };

        RefPtr<MemoryCursor> cursor = objectStore->maybeOpenCursor(info, *transaction);
        if (!cursor)
            return IDBError { ExceptionCode::UnknownError, "Could not create object store cursor in backing store"_s };

        cursor->currentData(outData);
        break;
    }
    case IndexedDB::CursorSource::Index:
        RefPtr objectStore = m_objectStoresByIdentifier.get(info.objectStoreIdentifier());
        if (!objectStore)
            return IDBError { ExceptionCode::UnknownError, "No backing store object store found"_s };

        auto identifier = std::get<IDBIndexIdentifier>(info.sourceIdentifier());
        auto* index = objectStore->indexForIdentifier(identifier);
        if (!index)
            return IDBError { ExceptionCode::UnknownError, "No backing store index found"_s };

        RefPtr<MemoryCursor> cursor = index->maybeOpenCursor(info, *transaction);
        if (!cursor)
            return IDBError { ExceptionCode::UnknownError, "Could not create index cursor in backing store"_s };

        cursor->currentData(outData);
        break;
    }

    return IDBError { };
}

IDBError MemoryIDBBackingStore::iterateCursor(const IDBResourceIdentifier& transactionIdentifier, const IDBResourceIdentifier& cursorIdentifier, const IDBIterateCursorData& data, IDBGetResult& outData)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::iterateCursor");

    RefPtr transaction = m_transactions.get(transactionIdentifier);
    if (!transaction)
        return IDBError { ExceptionCode::UnknownError, "No backing store transaction found in which to iterate cursor"_s };

    RefPtr cursor = transaction->cursor(cursorIdentifier);
    if (!cursor)
        return IDBError { ExceptionCode::UnknownError, "No backing store cursor found in which to iterate cursor"_s };

    cursor->iterate(data.keyData, data.primaryKeyData, data.count, outData);

    return IDBError { };
}

void MemoryIDBBackingStore::registerObjectStore(Ref<MemoryObjectStore>&& objectStore)
{
    RELEASE_ASSERT(!m_objectStoresByIdentifier.contains(objectStore->info().identifier()));
    RELEASE_ASSERT(!m_objectStoresByName.contains(objectStore->info().name()));

    auto identifier = objectStore->info().identifier();
    m_objectStoresByName.set(objectStore->info().name(), &objectStore.get());
    m_objectStoresByIdentifier.set(identifier, WTFMove(objectStore));
}

void MemoryIDBBackingStore::unregisterObjectStore(MemoryObjectStore& objectStore)
{
    ASSERT(m_objectStoresByIdentifier.contains(objectStore.info().identifier()));
    ASSERT(m_objectStoresByName.contains(objectStore.info().name()));

    m_objectStoresByName.remove(objectStore.info().name());
    m_objectStoresByIdentifier.remove(objectStore.info().identifier());
}

RefPtr<MemoryObjectStore> MemoryIDBBackingStore::takeObjectStoreByIdentifier(IDBObjectStoreIdentifier objectStoreIdentifier)
{
    auto objectStoreByIdentifier = m_objectStoresByIdentifier.take(objectStoreIdentifier);
    if (!objectStoreByIdentifier)
        return nullptr;

    auto objectStore = m_objectStoresByName.take(objectStoreByIdentifier->info().name());
    ASSERT_UNUSED(objectStore, objectStore);

    return objectStoreByIdentifier;
}

IDBObjectStoreInfo* MemoryIDBBackingStore::infoForObjectStore(IDBObjectStoreIdentifier objectStoreIdentifier)
{
    ASSERT(m_databaseInfo);
    return m_databaseInfo->infoForExistingObjectStore(objectStoreIdentifier);
}

void MemoryIDBBackingStore::deleteBackingStore()
{
    // The in-memory IDB backing store doesn't need to do any cleanup when it is deleted.
}

void MemoryIDBBackingStore::close()
{
}

IDBError MemoryIDBBackingStore::addIndex(const IDBResourceIdentifier& transactionIdentifier, const IDBIndexInfo& indexInfo)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::createIndex");

    if (!m_databaseInfo)
        return IDBError { ExceptionCode::UnknownError, "Database info is invalid."_s };

    auto* objectStoreInfo = m_databaseInfo->infoForExistingObjectStore(indexInfo.objectStoreIdentifier());
    if (!objectStoreInfo)
        return IDBError { ExceptionCode::ConstraintError, "Object store does not exist in database info."_s };

    RefPtr transaction = m_transactions.get(transactionIdentifier);
    if (!transaction || !transaction->isVersionChange())
        return IDBError { ExceptionCode::UnknownError, "Transaction is not in version change mode."_s };

    RefPtr objectStore = m_objectStoresByIdentifier.get(indexInfo.objectStoreIdentifier());
    if (!objectStore)
        return IDBError { ExceptionCode::ConstraintError, "Object store does not exist in backing store."_s };

    auto error = objectStore->addIndex(*transaction, indexInfo);
    if (error.isNull()) {
        objectStoreInfo->addExistingIndex(indexInfo);
        m_databaseInfo->setMaxIndexID(indexInfo.identifier().toRawValue());
    }

    return error;
}

void MemoryIDBBackingStore::revertAddIndex(const IDBResourceIdentifier& transactionIdentifier, IDBObjectStoreIdentifier objectStoreIdentifier, IDBIndexIdentifier indexIdentifier)
{
    LOG(IndexedDB, "MemoryIDBBackingStore::revertAddIndex");

    ASSERT(m_databaseInfo);
    auto* objectStoreInfo = m_databaseInfo->infoForExistingObjectStore(objectStoreIdentifier);
    if (!objectStoreInfo)
        return;

    auto* indexInfo = objectStoreInfo->infoForExistingIndex(indexIdentifier);
    if (!indexInfo)
        return;

    RefPtr rawTransaction = m_transactions.get(transactionIdentifier);
    if (!rawTransaction || !rawTransaction->isVersionChange())
        return;

    RefPtr objectStore = m_objectStoresByIdentifier.get(objectStoreIdentifier);
    if (objectStore)
        objectStoreInfo->deleteIndex(indexIdentifier);

    objectStore->revertAddIndex(*rawTransaction, indexIdentifier);
}

IDBError MemoryIDBBackingStore::updateIndexRecordsWithIndexKey(const IDBResourceIdentifier& transactionIdentifier, const IDBIndexInfo& indexInfo, const IDBKeyData& key, const IndexKey& indexKey, std::optional<int64_t> recordID)
{
    UNUSED_PARAM(recordID);
    RefPtr transaction = m_transactions.get(transactionIdentifier);
    if (!transaction || !transaction->isVersionChange())
        return IDBError { ExceptionCode::UnknownError, "Transaction is not in version change mode."_s };

    RefPtr objectStore = m_objectStoresByIdentifier.get(indexInfo.objectStoreIdentifier());
    if (!objectStore)
        return IDBError { ExceptionCode::ConstraintError, "Object store does not exist in backing store."_s };

    if (indexKey.isNull())
        return IDBError { };

    return objectStore->updateIndexRecordsWithIndexKey(*transaction, indexInfo, key, indexKey);
}

void MemoryIDBBackingStore::forEachObjectStoreRecord(const IDBResourceIdentifier& transactionIdentifier, IDBObjectStoreIdentifier objectStoreIdentifier, Function<void(RecordOrError&&)>&& apply)
{
    RefPtr transaction = m_transactions.get(transactionIdentifier);
    if (!transaction) {
        IDBError error { ExceptionCode::UnknownError, "Transaction is not active."_s };
        apply(makeUnexpected(WTFMove(error)));
        return;
    }

    RefPtr objectStore = m_objectStoresByIdentifier.get(objectStoreIdentifier);
    if (!objectStore) {
        IDBError error { ExceptionCode::ConstraintError, "Object store does not exist in backing store."_s };
        apply(makeUnexpected(WTFMove(error)));
        return;
    }

    objectStore->forEachRecord([&](auto key, auto value) {
        apply(ObjectStoreRecord { key, value, std::nullopt });
    });
}

MemoryObjectStore* MemoryIDBBackingStore::objectStoreForName(const String& name) const
{
    return m_objectStoresByName.get(name);
}

} // namespace IDBServer
} // namespace WebCore
