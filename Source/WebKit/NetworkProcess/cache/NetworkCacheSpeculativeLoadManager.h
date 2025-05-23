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

#pragma once

#include "NetworkCache.h"
#include "NetworkCacheStorage.h"
#include <WebCore/ResourceRequest.h>
#include <wtf/CheckedPtr.h>
#include <wtf/HashMap.h>
#include <wtf/TZoneMalloc.h>
#include <wtf/Vector.h>
#include <wtf/WeakPtr.h>

namespace WebKit {
namespace NetworkCache {
class SpeculativeLoadManager;
}
}

namespace WebCore {
enum class AdvancedPrivacyProtections : uint16_t;
}

namespace WebKit {

namespace NetworkCache {

class Entry;
class SpeculativeLoad;
class SubresourceInfo;
class SubresourcesEntry;

class SpeculativeLoadManager final : public CanMakeWeakPtr<SpeculativeLoadManager>, public CanMakeCheckedPtr<SpeculativeLoadManager> {
    WTF_MAKE_TZONE_ALLOCATED(SpeculativeLoadManager);
    WTF_OVERRIDE_DELETE_FOR_CHECKED_PTR(SpeculativeLoadManager);
public:
    explicit SpeculativeLoadManager(Cache&, Storage&);
    ~SpeculativeLoadManager();

    void registerLoad(GlobalFrameID, const WebCore::ResourceRequest&, const Key& resourceKey, std::optional<NavigatingToAppBoundDomain>, bool allowPrivacyProxy, OptionSet<WebCore::AdvancedPrivacyProtections>);
    void registerMainResourceLoadResponse(const GlobalFrameID&, const WebCore::ResourceRequest&, const WebCore::ResourceResponse&);

    typedef Function<void (std::unique_ptr<Entry>)> RetrieveCompletionHandler;

    bool canRetrieve(const Key& storageKey, const WebCore::ResourceRequest&, const GlobalFrameID&) const;
    void retrieve(const Key& storageKey, RetrieveCompletionHandler&&);

private:
    class PreloadedEntry;

    static bool shouldRegisterLoad(const WebCore::ResourceRequest&);
    void addPreloadedEntry(std::unique_ptr<Entry>, const GlobalFrameID&, std::optional<WebCore::ResourceRequest>&& revalidationRequest = std::nullopt);
    void preloadEntry(const Key&, const SubresourceInfo&, const GlobalFrameID&, std::optional<NavigatingToAppBoundDomain>, bool allowPrivacyProxy, OptionSet<WebCore::AdvancedPrivacyProtections>);
    void retrieveEntryFromStorage(const SubresourceInfo&, RetrieveCompletionHandler&&);
    void revalidateSubresource(const SubresourceInfo&, std::unique_ptr<Entry>, const GlobalFrameID&, std::optional<NavigatingToAppBoundDomain>, bool allowPrivacyProxy, OptionSet<WebCore::AdvancedPrivacyProtections>);
    void preconnectForSubresource(const SubresourceInfo&, Entry*, const GlobalFrameID&, std::optional<NavigatingToAppBoundDomain>);
    bool satisfyPendingRequests(const Key&, Entry*);
    void retrieveSubresourcesEntry(const Key& storageKey, WTF::Function<void (std::unique_ptr<SubresourcesEntry>)>&&);
    void startSpeculativeRevalidation(const GlobalFrameID&, SubresourcesEntry&, bool, std::optional<NavigatingToAppBoundDomain>, bool allowPrivacyProxy, OptionSet<WebCore::AdvancedPrivacyProtections>);

    static bool canUsePreloadedEntry(const PreloadedEntry&, const WebCore::ResourceRequest& actualRequest);
    static bool canUsePendingPreload(const SpeculativeLoad&, const WebCore::ResourceRequest& actualRequest);

    Ref<Storage> protectedStorage() const;
    Ref<Cache> protectedCache() const;

    const WeakRef<Cache> m_cache;
    ThreadSafeWeakPtr<Storage> m_storage; // Not expected to be null.

    class PendingFrameLoad;
    HashMap<GlobalFrameID, RefPtr<PendingFrameLoad>> m_pendingFrameLoads;

    HashMap<Key, std::unique_ptr<SpeculativeLoad>> m_pendingPreloads;
    HashMap<Key, std::unique_ptr<Vector<RetrieveCompletionHandler>>> m_pendingRetrieveRequests;

    HashMap<Key, std::unique_ptr<PreloadedEntry>> m_preloadedEntries;

    class ExpiringEntry;
    HashMap<Key, std::unique_ptr<ExpiringEntry>> m_notPreloadedEntries; // For logging.
};

} // namespace NetworkCache

} // namespace WebKit
