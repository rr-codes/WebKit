/*
 * Copyright (C) 2021 Apple Inc. All rights reserved.
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

#pragma once

#include "Connection.h"
#include "FileSystemStorageError.h"
#include <WebCore/FileSystemStorageConnection.h>

namespace IPC {
class Connection;

template<> struct AsyncReplyError<WebKit::FileSystemStorageError> {
    static WebKit::FileSystemStorageError create()
    {
        return WebKit::FileSystemStorageError::Unknown;
    }
};

}

namespace WebCore {
template<typename> class ExceptionOr;
class FileSystemDirectoryHandle;
class FileSystemFileHandle;
}

namespace WebKit {

class WebFileSystemStorageConnection final : public WebCore::FileSystemStorageConnection {
public:
    static Ref<WebFileSystemStorageConnection> create(Ref<IPC::Connection>&&);
    void connectionClosed();
    void didReceiveMessage(IPC::Connection&, IPC::Decoder&);

private:
    explicit WebFileSystemStorageConnection(Ref<IPC::Connection>&&);

    // FileSystemStorageConnection
    void closeHandle(WebCore::FileSystemHandleIdentifier) final;
    void isSameEntry(WebCore::FileSystemHandleIdentifier, WebCore::FileSystemHandleIdentifier, WebCore::FileSystemStorageConnection::SameEntryCallback&&) final;
    void move(WebCore::FileSystemHandleIdentifier, WebCore::FileSystemHandleIdentifier, const String& newName, VoidCallback&&) final;
    void getFileHandle(WebCore::FileSystemHandleIdentifier, const String& name, bool createIfNecessary, WebCore::FileSystemStorageConnection::GetHandleCallback&&) final;
    void getDirectoryHandle(WebCore::FileSystemHandleIdentifier, const String& name, bool createIfNecessary, WebCore::FileSystemStorageConnection::GetHandleCallback&&) final;
    void removeEntry(WebCore::FileSystemHandleIdentifier, const String& name, bool deleteRecursively, WebCore::FileSystemStorageConnection::VoidCallback&&) final;
    void resolve(WebCore::FileSystemHandleIdentifier, WebCore::FileSystemHandleIdentifier, WebCore::FileSystemStorageConnection::ResolveCallback&&) final;
    void getHandleNames(WebCore::FileSystemHandleIdentifier, FileSystemStorageConnection::GetHandleNamesCallback&&) final;
    void getHandle(WebCore::FileSystemHandleIdentifier, const String& name, FileSystemStorageConnection::GetHandleCallback&&) final;
    void getFile(WebCore::FileSystemHandleIdentifier, StringCallback&&) final;

    void createSyncAccessHandle(WebCore::FileSystemHandleIdentifier, WebCore::FileSystemStorageConnection::GetAccessHandleCallback&&) final;
    void closeSyncAccessHandle(WebCore::FileSystemHandleIdentifier, WebCore::FileSystemSyncAccessHandleIdentifier, EmptyCallback&&) final;
    void requestNewCapacityForSyncAccessHandle(WebCore::FileSystemHandleIdentifier, WebCore::FileSystemSyncAccessHandleIdentifier, uint64_t newCapacity, RequestCapacityCallback&& completionHandler) final;
    void registerSyncAccessHandle(WebCore::FileSystemSyncAccessHandleIdentifier, WebCore::ScriptExecutionContextIdentifier) final;
    void unregisterSyncAccessHandle(WebCore::FileSystemSyncAccessHandleIdentifier) final;
    void invalidateAccessHandle(WebCore::FileSystemSyncAccessHandleIdentifier) final;
    void createWritable(WebCore::ScriptExecutionContextIdentifier, WebCore::FileSystemHandleIdentifier, bool keepExistingData, StreamCallback&&) final;
    void closeWritable(WebCore::FileSystemHandleIdentifier, WebCore::FileSystemWritableFileStreamIdentifier, WebCore::FileSystemWriteCloseReason, VoidCallback&&) final;
    void executeCommandForWritable(WebCore::FileSystemHandleIdentifier, WebCore::FileSystemWritableFileStreamIdentifier, WebCore::FileSystemWriteCommandType, std::optional<uint64_t> position, std::optional<uint64_t> size, std::span<const uint8_t> dataBytes, bool hasDataError, VoidCallback&&) final;

    void invalidateWritable(WebCore::FileSystemWritableFileStreamIdentifier);
    void errorWritable(WebCore::ScriptExecutionContextIdentifier, WebCore::FileSystemWritableFileStreamIdentifier);

    HashMap<WebCore::FileSystemSyncAccessHandleIdentifier, WebCore::ScriptExecutionContextIdentifier> m_syncAccessHandles;
    HashMap<WebCore::FileSystemWritableFileStreamIdentifier, WebCore::ScriptExecutionContextIdentifier> m_writableIdentifiers;
    RefPtr<IPC::Connection> m_connection;
};

} // namespace WebKit
