/*
 * Copyright (C) 2015 Apple Inc. All rights reserved.
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
#include "NetworkCacheSubresourcesEntry.h"

#include "Logging.h"
#include "NetworkCacheCoders.h"
#include <WebCore/RegistrableDomain.h>
#include <wtf/TZoneMallocInlines.h>
#include <wtf/persistence/PersistentEncoder.h>

namespace WebKit {
namespace NetworkCache {

WTF_MAKE_TZONE_ALLOCATED_IMPL(SubresourceInfo);
WTF_MAKE_TZONE_ALLOCATED_IMPL(SubresourceLoad);
WTF_MAKE_TZONE_ALLOCATED_IMPL(SubresourcesEntry);

bool SubresourceInfo::isFirstParty() const
{
    WebCore::RegistrableDomain firstPartyDomain { m_firstPartyForCookies };
    return firstPartyDomain.matches(URL(URL(), key().identifier()));
}

Storage::Record SubresourcesEntry::encodeAsStorageRecord() const
{
    WTF::Persistence::Encoder encoder;
    encoder << m_subresources;

    encoder.encodeChecksum();

    return { m_key, m_timeStamp, encoder.span(), { }, { } };
}

std::unique_ptr<SubresourcesEntry> SubresourcesEntry::decodeStorageRecord(const Storage::Record& storageEntry)
{
    auto entry = makeUnique<SubresourcesEntry>(storageEntry);

    WTF::Persistence::Decoder decoder(storageEntry.header.span());
    std::optional<Vector<SubresourceInfo>> subresources;
    decoder >> subresources;
    if (!subresources)
        return nullptr;
    entry->m_subresources = WTFMove(*subresources);

    if (!decoder.verifyChecksum()) {
        LOG(NetworkCache, "(NetworkProcess) checksum verification failure\n");
        return nullptr;
    }

    return entry;
}

SubresourcesEntry::SubresourcesEntry(const Storage::Record& storageEntry)
    : m_key(storageEntry.key)
    , m_timeStamp(storageEntry.timeStamp)
{
    ASSERT(m_key.type() == "SubResources"_s);
}

SubresourceInfo::SubresourceInfo(const Key& key, const WebCore::ResourceRequest& request, const SubresourceInfo* previousInfo)
    : m_key(key)
    , m_lastSeen(WallTime::now())
    , m_firstSeen(previousInfo ? previousInfo->firstSeen() : m_lastSeen)
    , m_isTransient(!previousInfo)
    , m_isSameSite(request.isSameSite())
    , m_isAppInitiated(request.isAppInitiated())
    , m_firstPartyForCookies(request.firstPartyForCookies())
    , m_requestHeaders(request.httpHeaderFields())
    , m_priority(request.priority())
{
}

static Vector<SubresourceInfo> makeSubresourceInfoVector(const Vector<std::unique_ptr<SubresourceLoad>>& subresourceLoads, Vector<SubresourceInfo>* previousSubresources)
{
    Vector<SubresourceInfo> result;
    result.reserveInitialCapacity(subresourceLoads.size());
    
    HashMap<Key, unsigned> previousMap;
    if (previousSubresources) {
        for (unsigned i = 0; i < previousSubresources->size(); ++i)
            previousMap.add(previousSubresources->at(i).key(), i);
    }

    HashSet<Key> deduplicationSet;
    for (auto& load : subresourceLoads) {
        if (!deduplicationSet.add(load->key).isNewEntry)
            continue;
        
        SubresourceInfo* previousInfo = nullptr;
        if (previousSubresources) {
            auto it = previousMap.find(load->key);
            if (it != previousMap.end())
                previousInfo = &(*previousSubresources)[it->value];
        }
        
        result.append({ load->key, load->request, previousInfo });
        
        // FIXME: We should really consider all resources seen for the first time transient.
        if (!previousSubresources)
            result.last().setNonTransient();
    }

    return result;
}

SubresourcesEntry::SubresourcesEntry(Key&& key, const Vector<std::unique_ptr<SubresourceLoad>>& subresourceLoads)
    : m_key(WTFMove(key))
    , m_timeStamp(WallTime::now())
    , m_subresources(makeSubresourceInfoVector(subresourceLoads, nullptr))
{
    ASSERT(m_key.type() == "SubResources"_s);
}
    
void SubresourcesEntry::updateSubresourceLoads(const Vector<std::unique_ptr<SubresourceLoad>>& subresourceLoads)
{
    m_subresources = makeSubresourceInfoVector(subresourceLoads, &m_subresources);
}

} // namespace WebKit
} // namespace NetworkCache
