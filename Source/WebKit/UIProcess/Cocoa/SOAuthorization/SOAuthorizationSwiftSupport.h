/*
 * Copyright (C) 2019-2026 Apple Inc. All rights reserved.
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

#if HAVE(APP_SSO)

#include "APINavigationAction.h"
#include "APIPageConfiguration.h"
#include "FrameLoadState.h"
#include "PageLoadState.h"
#include "SOAuthorizationCoordinator.h"
#include "SOAuthorizationLoadPolicy.h"
#include "WebFrameProxy.h"
#include "WebPageProxy.h"
#include "WebPreferences.h"
#include "WebViewDidMoveToWindowObserver.h"
#include "WebsiteDataStore.h"
#include <wtf/BlockPtr.h>
#include <wtf/RawPointer.h>
#include <wtf/RefCounted.h>
#include <wtf/StringPrintStream.h>
#include <wtf/URL.h>
#include <wtf/WeakPtr.h>

@protocol SOAuthorizationClassProtocol;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

// Swift cannot import pal/cocoa/AppSSOSoftLink.h, whose AppSSO SPI header is empty in a module build: these are the two
// declarations from it that the Swift uses.
// SOAuthorizationSwiftSupport.mm also includes AppSSOSoftLink.h, so these must match its declarations.
namespace PAL {
extern ::Class _Nullable (* _Nonnull getSOAuthorizationClassSingleton)();
NSErrorDomain get_AppSSO_SOErrorDomainSingleton();
}

namespace WebKit {

// Main-actor blocks: every caller calls them on the main thread.
typedef void (NS_SWIFT_UI_ACTOR ^SOAuthorizationPolicyReply)(SOAuthorizationLoadPolicy);
typedef void (NS_SWIFT_UI_ACTOR ^SOAuthorizationReply)(void);
typedef void (NS_SWIFT_UI_ACTOR ^SOAuthorizationCanAuthorizeReply)(BOOL);

namespace SOAuthorizationSupport {

// nil only on macOS, where AppSSO may be missing.
inline id<SOAuthorizationClassProtocol> _Nullable authorizationClass() { return (id<SOAuthorizationClassProtocol>)PAL::getSOAuthorizationClassSingleton(); }

// Swift 6.4 does not import WeakPtr's constrained constructors, nor the LIFETIME_BOUND references: URL and PageLoadState.
inline WeakPtrWebPageProxy makeWeakPtr(WebPageProxy& page) { return WeakPtrWebPageProxy { &page }; }
inline URL activeURL(WebPageProxy& page) { return page.pageLoadState().activeURL(); }
inline NSURL * _Nullable requestNSURL(const API::NavigationAction& navigationAction) { return navigationAction.request().url().createNSURL().autorelease(); }
inline URL frameURL(const WebFrameProxy& frame) { return frame.url(); }
// Swift cannot import ResourceRequest, so these read the navigation action's request for it.
inline URL requestURL(const API::NavigationAction& navigationAction) { return navigationAction.request().url(); }
inline String navigationReferrer(const API::NavigationAction& navigationAction) { return navigationAction.request().httpReferrer(); }
inline bool isPOST(const API::NavigationAction& navigationAction) { return navigationAction.request().httpMethod() == "POST"_s; }
// Swift cannot compare two C++ references for identity.
inline bool isFrameInPage(const WebFrameProxy& frame, const WebPageProxy& page) { return frame.page() == &page; }

// A C++ object's address as the AppSSO log lines print it, for Swift, which cannot take one; appSSOLogAddressText prints a Swift object's.
inline NSString * logAddressText(const WebPageProxy* _Nullable page) { return WTF::toString(RawPointer(page)).createNSString().autorelease(); }
inline NSString * logAddressText(const API::NavigationAction* _Nullable navigationAction) { return WTF::toString(RawPointer(navigationAction)).createNSString().autorelease(); }
inline NSString * logAddressText(const WebsiteDataStore* _Nullable dataStore) { return WTF::toString(RawPointer(dataStore)).createNSString().autorelease(); }

// Swift calls the coordinator's callbacks through these, not through the RefCountable's pointee.
inline bool hasNavigationCallback(SOAuthorizationNavigationCallback& callback) { return !!*callback; }
inline void callNavigationCallback(SOAuthorizationNavigationCallback& callback, bool value)
{
    RELEASE_ASSERT(*callback);
    (*callback)(value);
}
inline bool hasNewPageCallback(SOAuthorizationNewPageCallback& callback) { return !!*callback; }
inline void callNewPageCallback(SOAuthorizationNewPageCallback& callback, WebPageProxy* _Nullable page)
{
    RELEASE_ASSERT(*callback);
    (*callback)(page);
}
// Swift cannot move the pop-up's new page CompletionHandler into the UI client callback.
inline void callUIClientCallback(SOAuthorizationUIClientCallback& callback, API::NavigationAction& navigationAction, SOAuthorizationNewPageCallback& newPageCallback)
{
    RELEASE_ASSERT(*callback && *newPageCallback);
    std::exchange(*callback, { })(Ref { navigationAction }, std::exchange(*newPageCallback, { }));
}

// Swift cannot make a CompletionHandler: these wrap a block in one.
void decidePolicy(WebPageProxy&, const String& extensionName, SOAuthorizationPolicyReply);
void setCookies(WebPageProxy&, NSArray<NSHTTPCookie *> *, SOAuthorizationReply);
// AppSSO may answer off the main thread; the reply runs on the main run loop.
void canPerformAuthorization(NSURL *, SOAuthorizationCanAuthorizeReply);

// What Swift cannot reach: AuthKit's and CFNetwork's SPI, and WebCore's ContentSecurityPolicy and SecurityOrigin (the
// subframe check is C++).
bool isMainFrameURLFromAppleOwnedDomain(WebPageProxy&);
void disableAppSSOInURLSession();
// Sets xFrameOptionsMessage when the X-Frame-Options header conflicts or is invalid, and refusalMessage when it refuses the
// load; the session logs them.
bool shouldInterruptLoadForCSPFrameAncestorsOrXFrameOptions(WebPageProxy* _Nullable, API::NavigationAction&, const WebCore::ResourceResponse&, String& xFrameOptionsMessage, String& refusalMessage);

// The session's calls into WebCore's request, response and origin types, and its loads. Swift cannot import ResourceRequest,
// SecurityOrigin, SharedBuffer or ResourceResponse::url().
// The target frame comes from the action's frame handle, which Swift cannot call.
WebFrameProxy* _Nullable targetWebFrame(API::NavigationAction&);
// Sets responseURL to the response's URL; the response's cookies if it has the request's origin, nil if not.
NSArray<NSHTTPCookie *> * _Nullable sameOriginCookies(API::NavigationAction&, const WebCore::ResourceResponse&, NSHTTPURLResponse *, URL& responseURL);
// The options need SecurityOrigin, URL::path and AppSSO's option macros, and the visionOS setup comes before the call.
// initiatingAction is AppSSO's SOAuthorizationOptionInitiatingAction value.
void beginAuthorization(WebPageProxy&, API::NavigationAction&, id soAuthorization, NSInteger initiatingAction, bool isSubFrame);
// Reads the response's Location header and loads through a SharedBuffer.
void loadRedirectLocation(WebPageProxy&, API::NavigationAction&, const WebCore::ResourceResponse&);
// Loads the body through a SharedBuffer, as the response's URL.
void loadResponseBody(WebPageProxy&, API::NavigationAction&, const WebCore::ResourceResponse&, NSData *);
// WebFrameProxy::loadData takes a span of the data's bytes, which Swift cannot make.
void loadDataInFrame(WebFrameProxy&, const URL&, NSData *);
#if PLATFORM(IOS_FAMILY)
// The presenting view controller comes from the UI client, a C++ class.
UIViewController * _Nullable presentingViewController(WebPageProxy&);
#endif

} // namespace SOAuthorizationSupport

// Swift cannot subclass a C++ class: these observers call their session back through a main-actor block.
// Swift holds each one as a shared reference; its initializer returns it at RefCounted's count of one, retained.
// Only Swift makes them; the constructors are public for its import. C++ would have to adoptRef a new one, never put one on the stack.
class SOAuthorizationDidMoveToWindowObserver final : public WebViewDidMoveToWindowObserver, public RefCounted<SOAuthorizationDidMoveToWindowObserver> {
public:
    explicit SOAuthorizationDidMoveToWindowObserver(SOAuthorizationReply callback) SWIFT_RETURNS_RETAINED
        : m_callback(makeBlockPtr(callback))
    {
    }

    SWIFT_UNSAFE void ref() const final { RefCounted::ref(); }
    SWIFT_UNSAFE void deref() const final { RefCounted::deref(); }
    void addTo(WebPageProxy& page) SWIFT_NAME(add(to:)) { page.addDidMoveToWindowObserver(*this); }
    void removeFrom(WebPageProxy& page) SWIFT_NAME(remove(from:)) { page.removeDidMoveToWindowObserver(*this); }
private:
    void webViewDidMoveToWindow() final { m_callback(); }
    const BlockPtr<void()> m_callback;
} SWIFT_SHARED_REFERENCE(.ref, .deref);

class SOAuthorizationFrameLoadObserver final : public FrameLoadStateObserver, public RefCounted<SOAuthorizationFrameLoadObserver> {
public:
    explicit SOAuthorizationFrameLoadObserver(SOAuthorizationReply callback) SWIFT_RETURNS_RETAINED
        : m_callback(makeBlockPtr(callback))
    {
    }

    SWIFT_UNSAFE void ref() const final { RefCounted::ref(); }
    SWIFT_UNSAFE void deref() const final { RefCounted::deref(); }
    void addTo(WebFrameProxy& frame) SWIFT_NAME(add(to:)) { frame.frameLoadState().addObserver(*this); }
    void removeFrom(WebFrameProxy& frame) SWIFT_NAME(remove(from:)) { frame.frameLoadState().removeObserver(*this); }
private:
    void didFinishLoad(IsMainFrame, const URL&) final { m_callback(); }
    const BlockPtr<void()> m_callback;
} SWIFT_SHARED_REFERENCE(.ref, .deref);

} // namespace WebKit

NS_HEADER_AUDIT_END(nullability, sendability)

#endif // HAVE(APP_SSO)
