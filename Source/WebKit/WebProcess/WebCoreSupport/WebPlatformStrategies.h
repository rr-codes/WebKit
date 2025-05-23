/*
 * Copyright (C) 2010-2018 Apple Inc. All rights reserved.
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

#include <WebCore/LoaderStrategy.h>
#include <WebCore/PasteboardStrategy.h>
#include <WebCore/PlatformStrategies.h>
#include <WebCore/PushStrategy.h>

namespace WebKit {

class WebPlatformStrategies :
    public WebCore::PlatformStrategies,
    private WebCore::PasteboardStrategy
#if ENABLE(DECLARATIVE_WEB_PUSH)
    , public WebCore::PushStrategy
#endif
{
    friend NeverDestroyed<WebPlatformStrategies>;
public:
    static void initialize();
    
private:
    WebPlatformStrategies();
    
    // WebCore::PlatformStrategies
    WebCore::LoaderStrategy* createLoaderStrategy() override;
    WebCore::PasteboardStrategy* createPasteboardStrategy() override;
    WebCore::MediaStrategy* createMediaStrategy() override;
    WebCore::BlobRegistry* createBlobRegistry() override;
#if ENABLE(DECLARATIVE_WEB_PUSH)
    WebCore::PushStrategy* createPushStrategy() override;
#endif

    // WebCore::PasteboardStrategy
#if PLATFORM(IOS_FAMILY)
    void writeToPasteboard(const WebCore::PasteboardWebContent&, const String& pasteboardName, const WebCore::PasteboardContext*) override;
    void writeToPasteboard(const WebCore:: PasteboardURL&, const String& pasteboardName, const WebCore::PasteboardContext*) override;
    void writeToPasteboard(const WebCore::PasteboardImage&, const String& pasteboardName, const WebCore::PasteboardContext*) override;
    void writeToPasteboard(const String& pasteboardType, const String&, const String& pasteboardName, const WebCore::PasteboardContext*) override;
    void updateSupportedTypeIdentifiers(const Vector<String>& identifiers, const String& pasteboardName, const WebCore::PasteboardContext*) override;
#endif
#if PLATFORM(COCOA)
    int getNumberOfFiles(const String& pasteboardName, const WebCore::PasteboardContext*) override;
    void getTypes(Vector<String>& types, const String& pasteboardName, const WebCore::PasteboardContext*) override;
    RefPtr<WebCore::SharedBuffer> bufferForType(const String& pasteboardType, const String& pasteboardName, const WebCore::PasteboardContext*) override;
    void getPathnamesForType(Vector<String>& pathnames, const String& pasteboardType, const String& pasteboardName, const WebCore::PasteboardContext*) override;
    String stringForType(const String& pasteboardType, const String& pasteboardName, const WebCore::PasteboardContext*) override;
    Vector<String> allStringsForType(const String& pasteboardType, const String& pasteboardName, const WebCore::PasteboardContext*) override;
    int64_t changeCount(const String& pasteboardName, const WebCore::PasteboardContext*) override;
    WebCore::Color color(const String& pasteboardName, const WebCore::PasteboardContext*) override;
    URL url(const String& pasteboardName, const WebCore::PasteboardContext*) override;

    int64_t addTypes(const Vector<String>& pasteboardTypes, const String& pasteboardName, const WebCore::PasteboardContext*) override;
    int64_t setTypes(const Vector<String>& pasteboardTypes, const String& pasteboardName, const WebCore::PasteboardContext*) override;
    int64_t setBufferForType(WebCore::SharedBuffer*, const String& pasteboardType, const String& pasteboardName, const WebCore::PasteboardContext*) override;
    int64_t setURL(const WebCore::PasteboardURL&, const String& pasteboardName, const WebCore::PasteboardContext*) override;
    int64_t setColor(const WebCore::Color&, const String& pasteboardName, const WebCore::PasteboardContext*) override;
    int64_t setStringForType(const String&, const String& pasteboardType, const String& pasteboardName, const WebCore::PasteboardContext*) override;

    bool containsURLStringSuitableForLoading(const String& pasteboardName, const WebCore::PasteboardContext*) override;
    String urlStringSuitableForLoading(const String& pasteboardName, String& title, const WebCore::PasteboardContext*) override;
#endif
#if PLATFORM(GTK) || PLATFORM(WPE)
    Vector<String> types(const String& pasteboardName) override;
    String readTextFromClipboard(const String& pasteboardName, const String& pasteboardType) override;
    Vector<String> readFilePathsFromClipboard(const String& pasteboardName) override;
    RefPtr<WebCore::SharedBuffer> readBufferFromClipboard(const String& pasteboardName, const String& pasteboardType) override;
    void writeToClipboard(const String& pasteboardName, WebCore::SelectionData&&) override;
    void clearClipboard(const String& pasteboardName) override;
    int64_t changeCount(const String& pasteboardName) override;
#elif USE(LIBWPE)
    void getTypes(Vector<String>& types) override;
    void writeToPasteboard(const WebCore::PasteboardWebContent&) override;
    void writeToPasteboard(const String& pasteboardType, const String&) override;
#endif

    String readStringFromPasteboard(size_t index, const String& pasteboardType, const String& pasteboardName, const WebCore::PasteboardContext*) override;
    RefPtr<WebCore::SharedBuffer> readBufferFromPasteboard(std::optional<size_t> index, const String& pasteboardType, const String& pasteboardName, const WebCore::PasteboardContext*) override;
    URL readURLFromPasteboard(size_t index, const String& pasteboardName, String& title, const WebCore::PasteboardContext*) override;
    int getPasteboardItemsCount(const String& pasteboardName, const WebCore::PasteboardContext*) override;
    std::optional<WebCore::PasteboardItemInfo> informationForItemAtIndex(size_t index, const String& pasteboardName, int64_t changeCount, const WebCore::PasteboardContext*) override;
    std::optional<Vector<WebCore::PasteboardItemInfo>> allPasteboardItemInfo(const String& pasteboardName, int64_t changeCount, const WebCore::PasteboardContext*) override;
    Vector<String> typesSafeForDOMToReadAndWrite(const String& pasteboardName, const String& origin, const WebCore::PasteboardContext*) override;
    int64_t writeCustomData(const Vector<WebCore::PasteboardCustomData>&, const String&, const WebCore::PasteboardContext*) override;
    bool containsStringSafeForDOMToReadForType(const String&, const String& pasteboardName, const WebCore::PasteboardContext*) override;

    // WebCore::PushStrategy
#if ENABLE(DECLARATIVE_WEB_PUSH)
    void windowSubscribeToPushService(const URL& scope, const Vector<uint8_t>& applicationServerKey, SubscribeToPushServiceCallback&&) override;
    void windowUnsubscribeFromPushService(const URL& scope, std::optional<WebCore::PushSubscriptionIdentifier>, UnsubscribeFromPushServiceCallback&&) override;
    void windowGetPushSubscription(const URL& scope, GetPushSubscriptionCallback&&) override;
    void windowGetPushPermissionState(const URL& scope, GetPushPermissionStateCallback&&) override;
#endif
};

} // namespace WebKit
