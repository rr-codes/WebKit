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

#import "config.h"
#import "SOAuthorizationSwiftSupport.h"

#if HAVE(APP_SSO)

#import "APIFrameHandle.h"
#import "APIHTTPCookieStore.h"
#import "APIUIClient.h"
#import "UIKitUtilities.h"
#import "WKUIDelegatePrivate.h"
#import "WKWebViewInternal.h"
#import <WebCore/ContentSecurityPolicy.h>
#import <WebCore/Cookie.h>
#import <WebCore/HTTPParsers.h>
#import <WebCore/ResourceResponse.h>
#import <WebCore/SecurityOrigin.h>
#import <WebCore/SharedBuffer.h>
#import <pal/spi/cf/CFNetworkSPI.h>
#import <pal/spi/cocoa/AuthKitSPI.h>
#import <wtf/Borrow.h>
#import <wtf/cocoa/RuntimeApplicationChecksCocoa.h>
#import <wtf/cocoa/SpanCocoa.h>
#import <wtf/text/MakeString.h>

#import <pal/cocoa/AppSSOSoftLink.h>

static_assert(kSOErrorAuthorizationPresentationFailed == -7, "AppSSO_SPI.h declares the same value for Swift");

namespace WebKit {
using namespace WebCore;

void SOAuthorizationSupport::decidePolicy(WebPageProxy& page, const String& extensionName, SOAuthorizationPolicyReply reply)
{
    page.decidePolicyForSOAuthorizationLoad(extensionName, [reply = makeBlockPtr(reply)](SOAuthorizationLoadPolicy policy) {
        reply(policy);
    });
}

void SOAuthorizationSupport::setCookies(WebPageProxy& page, NSArray<NSHTTPCookie *> *cookies, SOAuthorizationReply reply)
{
    Vector<Cookie> cookieVector(cookies.count, [cookies](size_t i) {
        return Cookie { cookies[i] };
    });
    protect(protect(page.websiteDataStore())->cookieStore())->setCookies(WTF::move(cookieVector), [reply = makeBlockPtr(reply)] {
        reply();
    });
}

void SOAuthorizationSupport::canPerformAuthorization(NSURL *url, SOAuthorizationCanAuthorizeReply reply)
{
    [PAL::getSOAuthorizationClassSingleton() canPerformAuthorizationWithURL:url responseCode:0 callerBundleIdentifier:nil useInternalExtensions:YES completion:makeBlockPtr([callback = makeBlockPtr(reply)](BOOL result) mutable {
        ensureOnMainRunLoop([callback = WTF::move(callback), result] {
            callback(result);
        });
    }).get()];
}

bool SOAuthorizationSupport::isMainFrameURLFromAppleOwnedDomain(WebPageProxy& page)
{
    RefPtr mainFrame = page.mainFrame();
    return mainFrame && [AKAuthorizationController isURLFromAppleOwnedDomain:mainFrame->url().createNSURL().get()];
}

void SOAuthorizationSupport::disableAppSSOInURLSession()
{
    [NSURLSession _disableAppSSO];
}

static bool shouldInterruptLoadForXFrameOptions(Vector<Ref<SecurityOrigin>>&& frameAncestorOrigins, const String& xFrameOptions, const URL& url, String& xFrameOptionsMessage)
{
    switch (parseXFrameOptionsHeader(xFrameOptions)) {
    case XFrameOptionsDisposition::None:
    case XFrameOptionsDisposition::AllowAll:
        return false;
    case XFrameOptionsDisposition::Deny:
        return true;
    case XFrameOptionsDisposition::SameOrigin: {
        auto origin = SecurityOrigin::create(url);
        for (auto& ancestorOrigin : borrow(frameAncestorOrigins)) {
            if (!origin->isSameSchemeHostPort(ancestorOrigin))
                return true;
        }
        return false;
    }
    case XFrameOptionsDisposition::Conflict: {
        xFrameOptionsMessage = makeString("Multiple 'X-Frame-Options' headers with conflicting values ('"_s, xFrameOptions, "') encountered. Falling back to 'DENY'."_s);
        return true;
    }
    case XFrameOptionsDisposition::Invalid: {
        xFrameOptionsMessage = makeString("Invalid 'X-Frame-Options' header encountered: '"_s, xFrameOptions, "' is not a recognized directive. The header will be ignored."_s);
        return false;
    }
    }
    ASSERT_NOT_REACHED();
    return false;
}

bool SOAuthorizationSupport::shouldInterruptLoadForCSPFrameAncestorsOrXFrameOptions(WebPageProxy* page, API::NavigationAction& navigationAction, const ResourceResponse& response, String& xFrameOptionsMessage, String& refusalMessage)
{
    if (page && protect(page->preferences())->ignoreIframeEmbeddingProtectionsEnabled())
        return false;

    Vector<Ref<SecurityOrigin>> frameAncestorOrigins;
    if (RefPtr targetFrame = navigationAction.targetFrame()) {
        if (auto parentFrameHandle = targetFrame->parentFrameHandle()) {
            for (RefPtr parent = WebFrameProxy::webFrame(parentFrameHandle->frameID()); parent; parent = parent->parentFrame())
                frameAncestorOrigins.append(SecurityOrigin::create(parent->url()));
        }
    }

    auto url = response.url();
    auto contentSecurityPolicy = makeUnique<ContentSecurityPolicy>(URL { url }, nullptr, nullptr);
    contentSecurityPolicy->didReceiveHeaders(ContentSecurityPolicyResponseHeaders { response }, navigationAction.request().httpReferrer());
    if (!contentSecurityPolicy->allowFrameAncestors(frameAncestorOrigins, url))
        return true;

    if (!contentSecurityPolicy->overridesXFrameOptions()) {
        String xFrameOptions = response.httpHeaderField(HTTPHeaderName::XFrameOptions);
        if (!xFrameOptions.isNull() && shouldInterruptLoadForXFrameOptions(WTF::move(frameAncestorOrigins), xFrameOptions, response.url(), xFrameOptionsMessage)) {
            refusalMessage = makeString("Refused to display '"_s, response.url().stringCenterEllipsizedToLength(), "' in a frame because it set 'X-Frame-Options' to '"_s, xFrameOptions, "'."_s);
            return true;
        }
    }

    return false;
}

WebFrameProxy* SOAuthorizationSupport::targetWebFrame(API::NavigationAction& navigationAction)
{
    RefPtr targetFrame = navigationAction.targetFrame();
    return targetFrame ? WebFrameProxy::webFrame(targetFrame->handle()->frameID()) : nullptr;
}

NSArray<NSHTTPCookie *> *SOAuthorizationSupport::sameOriginCookies(API::NavigationAction& navigationAction, const ResourceResponse& response, NSHTTPURLResponse *httpResponse, URL& responseURL)
{
    responseURL = response.url();
    Ref requestOrigin = SecurityOrigin::create(navigationAction.request().url());
    if (!requestOrigin->isSameOriginAs(SecurityOrigin::create(responseURL).get()))
        return nil;
    return [NSHTTPCookie cookiesWithResponseHeaderFields:retainPtr(httpResponse.allHeaderFields).get() forURL:responseURL.createNSURL().get()];
}

void SOAuthorizationSupport::beginAuthorization(WebPageProxy& page, API::NavigationAction& navigationAction, id soAuthorization, NSInteger initiatingAction, bool isSubFrame)
{
    auto initiatorOrigin = emptyString();
    String initiatingPath = emptyString();
    if (RefPtr mainFrame = page.mainFrame()) {
        Ref mainFrameOrigin = SecurityOrigin::create(mainFrame->url());
        if (isSubFrame || !mainFrameOrigin->isOpaque())
            initiatorOrigin = mainFrameOrigin->toString();
        initiatingPath = mainFrame->url().path().toString();
    }
    RetainPtr<NSDictionary> authorizationOptions = @{
        SOAuthorizationOptionUserActionInitiated: @(navigationAction.isProcessingUserGesture()),
        SOAuthorizationOptionInitiatorOrigin: initiatorOrigin.createNSString().get(),
        SOAuthorizationOptionInitiatingAction: @(initiatingAction),
        kSOAuthorizationOptionInitiatingPath: initiatingPath.createNSString().get()
    };
#if PLATFORM(IOS_FAMILY)
    RetainPtr<WKWebView> webView = page.cocoaView();
    id webViewUIDelegate = [webView UIDelegate];
    if ([webViewUIDelegate respondsToSelector:@selector(_hostSceneIdentifierForWebView:)]) {
        NSString *callerSceneID = [webViewUIDelegate _hostSceneIdentifierForWebView:webView.get()];
        if (callerSceneID) {
            RetainPtr mutableAuthorizationOptions = adoptNS([authorizationOptions mutableCopy]);
            mutableAuthorizationOptions.get()[@"callerSceneIdentifier"] = callerSceneID;
            authorizationOptions = WTF::move(mutableAuthorizationOptions);
        }
    }
#endif
    [soAuthorization setAuthorizationOptions:authorizationOptions.get()];
#if PLATFORM(VISION)
    // rdar://130904577 - Investigate supporting embedded authorization view controller on visionOS.
    if (![[page.cocoaView() UIDelegate] respondsToSelector:@selector(_presentingViewControllerForWebView:)] || WTF::IOSApplication::isSafariViewService())
        [soAuthorization setEnableEmbeddedAuthorizationViewController:NO];
    page.dispatchWillPresentModalUI();
#endif
    RetainPtr nsRequest = navigationAction.request().nsURLRequest(HTTPBodyUpdatePolicy::UpdateHTTPBody);
    [soAuthorization beginAuthorizationWithURL:retainPtr(nsRequest.get().URL).get() httpHeaders:retainPtr(nsRequest.get().allHTTPHeaderFields).get() httpBody:retainPtr(nsRequest.get().HTTPBody).get()];
}

void SOAuthorizationSupport::loadRedirectLocation(WebPageProxy& page, API::NavigationAction& navigationAction, const ResourceResponse& response)
{
#if PLATFORM(IOS) || PLATFORM(VISION)
    // MobileSafari has a WBSURLSpoofingMitigator, which will not display the provisional URL for navigations without user gestures.
    // For slow loads that are initiated from the MobileSafari Favorites screen, the aforementioned behavior will create a period
    // after authentication completion where the new request to the application site loads with a blank URL and blank page. To
    // work around this issue, we load a page that does a client side redirection to the application site on behalf of the
    // request URL, instead of directly loading a new request. This local page should be super fast to load and therefore will not
    // show an empty URL or a blank page. These changes ensure a relevant URL bar and useful page content during the load.
    if (!navigationAction.isProcessingUserGesture()) {
        page.setShouldSuppressSOAuthorizationInNextNavigationPolicyDecision();
        auto html = makeString("<script>location = '"_s, response.httpHeaderFields().get(HTTPHeaderName::Location), "'</script>"_s).utf8();
        page.loadData(SharedBuffer::create(html.span()), "text/html"_s, "UTF-8"_s, navigationAction.request().url().string(), nullptr, navigationAction.shouldOpenExternalURLsPolicy());
        return;
    }
#else
    UNUSED_PARAM(navigationAction);
#endif
    page.loadRequest(ResourceRequest(response.httpHeaderFields().get(HTTPHeaderName::Location)));
}

void SOAuthorizationSupport::loadResponseBody(WebPageProxy& page, API::NavigationAction& navigationAction, const ResourceResponse& response, NSData *data)
{
    page.setShouldSuppressSOAuthorizationInNextNavigationPolicyDecision();
    page.loadData(SharedBuffer::create(data), "text/html"_s, "UTF-8"_s, response.url().string(), nullptr, navigationAction.shouldOpenExternalURLsPolicy());
}

void SOAuthorizationSupport::loadDataInFrame(WebFrameProxy& frame, const URL& url, NSData *data)
{
    frame.loadData(span(data), "text/html"_s, "UTF-8"_s, url);
}

#if PLATFORM(IOS_FAMILY)
UIViewController *SOAuthorizationSupport::presentingViewController(WebPageProxy& page)
{
    // FIXME: When in element fullscreen, UIClient::presentingViewController() may not return the
    // WKFullScreenViewController even though that is the presenting view controller of the WKWebView.
    // We should call PageClientImpl::presentingViewController() instead.
    RetainPtr presentingViewController = page.uiClient().presentingViewController();
#if PLATFORM(VISION)
    page.dispatchWillPresentModalUI();
#else
    if (!presentingViewController)
        presentingViewController = [page.cocoaView() _wk_viewControllerForFullScreenPresentation];
#endif
    return presentingViewController.autorelease();
}
#endif

} // namespace WebKit

#endif // HAVE(APP_SSO)
