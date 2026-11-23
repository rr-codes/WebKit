// Copyright (C) 2019-2026 Apple Inc. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
// BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
// THE POSSIBILITY OF SUCH DAMAGE.

#if HAVE_APP_SSO

import AppSSO_SPI
import Foundation
import WebKit_Internal
import WebKit_Private
import os
import wtf

// One AppSSO authorization for an intercepted navigation or pop-up, and what to load once it answers.
// A session will only be executed once.
@MainActor
final class SOAuthorizationSession {
    // When the web view, owner of the page, is not in the window, a navigation session (redirect or subframe) will proceed
    // through authorization hints and policy decision, then pause before beginning authorization.
    // It will resume after the web view is moved into the window.
    // FSM: Idle => start() => Active => decidePolicyForSOAuthorizationLoad => isInWindow => beginAuthorization => Completed
    //      Idle => start() => Active => decidePolicyForSOAuthorizationLoad => !isInWindow => Waiting => become isInWindow => beginAuthorization => Completed
    // The pop-up session's FSM: Idle => Active => Completed
    enum State: String {
        case idle = "Idle"
        case active = "Active"
        case waiting = "Waiting"
        case completed = "Completed"
    }

    enum Kind {
        // Main frame navigations: the callback cancels (true) or continues (false) the navigation.
        case redirect(callback: WebKit.SOAuthorizationNavigationCallback, windowWait: WindowWait = WindowWait())
        // Subframe navigations: the callback cancels the frame's navigation, whose loads the session then makes.
        case subFrame(
            callback: WebKit.SOAuthorizationNavigationCallback,
            windowWait: WindowWait = WindowWait(),
            loads: SubFrameLoads = SubFrameLoads()
        )
        // Pop-ups: the opener gets a page from the new page callback, or the UI client opens the window.
        case popUp(
            configuration: API.PageConfiguration,
            newPageCallback: WebKit.SOAuthorizationNewPageCallback,
            uiClientCallback: WebKit.SOAuthorizationUIClientCallback,
            secret: SecretWebView = SecretWebView()
        )

        var windowWait: WindowWait? {
            switch self {
            case .redirect(_, let windowWait), .subFrame(_, let windowWait, _):
                windowWait
            case .popUp:
                nil
            }
        }

        var initiatingActionName: String {
            switch self {
            case .redirect:
                "Redirect"
            case .subFrame:
                "SubFrame"
            case .popUp:
                "PopUp"
            }
        }

        // AppSSO's initiating action option: 0 redirect, 1 pop-up, 2 subframe.
        var initiatingActionValue: Int {
            switch self {
            case .redirect:
                0
            case .popUp:
                1
            case .subFrame:
                2
            }
        }

        var isSubFrame: Bool {
            if case .subFrame = self {
                return true
            }
            return false
        }
    }

    // A navigation session's pause until its web view is in a window: the observer that resumes it, and the page's
    // active URL when it paused.
    final class WindowWait {
        fileprivate struct Pause {
            let observer: WebKit.SOAuthorizationDidMoveToWindowObserver
            let pageActiveURL: WTF.URL
        }

        fileprivate var pause: Pause?
    }

    private let soAuthorization: (any SOAuthorizationProtocol)?
    let navigationAction: API.NavigationAction
    let page: WebKit.WeakPtrWebPageProxy
    let kind: Kind
    private(set) var state = State.idle

    var presentation = Presentation()

    init(_ kind: Kind, navigationAction: API.NavigationAction, page: WebKit.WebPageProxy, delegate: any SOAuthorizationDelegate) {
        soAuthorization = WebKit.SOAuthorizationSupport.authorizationClass()?.makeAuthorization()
        self.navigationAction = navigationAction
        self.page = WebKit.SOAuthorizationSupport.makeWeakPtr(page)
        self.kind = kind
        soAuthorization?.delegate = delegate
        if case .subFrame(_, _, let loads) = kind {
            observeFrameLoads(loads)
        }
    }

    isolated deinit {
        switch kind {
        case .redirect(let callback, let windowWait):
            finishNavigation(callback, windowWait: windowWait)
        case .subFrame(let callback, let windowWait, let loads):
            stopObservingFrameLoads(loads)
            finishNavigation(callback, windowWait: windowWait)
        case .popUp(_, let newPageCallback, _, _):
            assert(state != .waiting)
            if WebKit.SOAuthorizationSupport.hasNewPageCallback(newPageCallback) {
                WebKit.SOAuthorizationSupport.callNewPageCallback(newPageCallback, nil)
            }
        }

        log(
            "SOAuthorizationSession::~SOAuthorizationSession: m_viewController=\(appSSOLogAddressText(viewController: self.presentation.viewController))"
        )
        #if WTF_PLATFORM_MAC
        log("SOAuthorizationSession::~SOAuthorizationSession: m_sheetWindow=\(appSSOLogAddressText(self.presentation.sheet?.window))")
        #endif
        if state == .active {
            soAuthorization?.cancelAuthorization()
        }
        if state != .idle && state != .completed {
            becomeCompleted(deferringWhileHidden: false)
        } else {
            dismissViewController(deferringWhileHidden: false)
        }
    }

    private func finishNavigation(_ callback: WebKit.SOAuthorizationNavigationCallback, windowWait: WindowWait) {
        if WebKit.SOAuthorizationSupport.hasNavigationCallback(callback) {
            WebKit.SOAuthorizationSupport.callNavigationCallback(callback, true)
        }
        if state == .waiting, let observer = windowWait.pause?.observer, let page = page.get() {
            observer.remove(from: page)
        }
    }

    func isForAuthorization(_ authorization: any SOAuthorizationProtocol) -> Bool {
        soAuthorization === authorization
    }

    // Out of line, so that the log call is compiled once.
    @inline(never)
    func log(_ message: String) {
        os.Logger.appSSO.log(
            "\(appSSOLogAddress(self), format: .hex(includePrefix: true), privacy: .public) - [InitiatingAction=\(self.kind.initiatingActionName)][State=\(self.state.rawValue)] \(message, privacy: .public)"
        )
    }

    @inline(never)
    func log(_ message: String, private value: String) {
        os.Logger.appSSO.log(
            "\(appSSOLogAddress(self), format: .hex(includePrefix: true), privacy: .public) - [InitiatingAction=\(self.kind.initiatingActionName)][State=\(self.state.rawValue)] \(message, privacy: .public)\(value, privacy: .private)"
        )
    }

    private func becomeCompleted(deferringWhileHidden: Bool = true) {
        log(
            "SOAuthorizationSession::becomeCompleted: m_viewController=\(appSSOLogAddressText(viewController: self.presentation.viewController))"
        )
        assert(state == .active || state == .waiting)
        state = .completed
        dismissViewController(deferringWhileHidden: deferringWhileHidden)
    }

    // Probably not start immediately.
    func shouldStart() {
        log("SOAuthorizationSession::shouldStart: m_page=\(WebKit.SOAuthorizationSupport.logAddressText(self.page.get()))")
        assert(state == .idle)
        guard page.get() != nil else {
            return
        }
        switch kind {
        case .redirect:
            log(
                "NavigationSOAuthorizationSession::shouldStartInternal: m_page=\(WebKit.SOAuthorizationSupport.logAddressText(self.page.get()))"
            )
            log("RedirectSOAuthorizationSession::beforeStart")
        case .subFrame(let callback, _, let loads):
            log(
                "NavigationSOAuthorizationSession::shouldStartInternal: m_page=\(WebKit.SOAuthorizationSupport.logAddressText(self.page.get()))"
            )
            prepareSubFrameStart(callback: callback, loads: loads)
        case .popUp:
            log("PopUpSOAuthorizationSession::shouldStartInternal: m_page=\(WebKit.SOAuthorizationSupport.logAddressText(self.page.get()))")
            assert(page.get()?.isInWindow() == true)
        }
        start()
    }

    private func start() {
        log("SOAuthorizationSession::start: navigationAction=\(WebKit.SOAuthorizationSupport.logAddressText(self.navigationAction))")
        assert(state == .idle || state == .waiting)
        state = .active
        log("SOAuthorizationSession::start: Moving m_state to Active.")
        // canAuthorize answered for this URL, so it has one.
        guard let url = WebKit.SOAuthorizationSupport.requestNSURL(navigationAction) else {
            return
        }
        soAuthorization?
            .getAuthorizationHints(with: url, responseCode: 0) { [weak self] authorizationHints, error in
                // AppSSO may answer on another queue; the session continues on the main thread.
                let errorCode = (error as NSError?)?.code
                let hasHints = authorizationHints != nil
                let extensionName = authorizationHints?.localizedExtensionBundleDisplayName
                let continuation: @MainActor @Sendable () -> Void = {
                    guard let self else {
                        os.Logger.appSSO.error(
                            "SOAuthorizationSession::start (getAuthorizationHintsWithURL completion handler): Returning early because weakThis is now null."
                        )
                        return
                    }
                    self.didGetAuthorizationHints(errorCode: errorCode, hasHints: hasHints, extensionName: extensionName)
                }
                if Thread.isMainThread {
                    MainActor.assumeIsolated(continuation)
                } else {
                    DispatchQueue.main.async {
                        continuation()
                    }
                }
            }
    }

    private func didGetAuthorizationHints(errorCode: Int?, hasHints: Bool, extensionName: String?) {
        log("SOAuthorizationSession::start: Receive SOAuthorizationHints (error=\(errorCode ?? 0))")
        guard errorCode == nil && hasHints else {
            log(
                "SOAuthorizationSession::start (getAuthorizationHintsWithURL completion handler): Falling back to web path due to error or lack of hints."
            )
            fallBackToWebPath()
            return
        }
        log("SOAuthorizationSession::start (getAuthorizationHintsWithURL completion handler): Receive SOAuthorizationHints.")
        continueStartAfterGetAuthorizationHints(extensionName)
    }

    private func continueStartAfterGetAuthorizationHints(_ extensionName: String?) {
        // The extension's name keeps the default privacy.
        os.Logger.appSSO.log(
            "\(appSSOLogAddress(self), format: .hex(includePrefix: true), privacy: .public) - [InitiatingAction=\(self.kind.initiatingActionName)][State=\(self.state.rawValue)] SOAuthorizationSession::continueStartAfterGetAuthorizationHints: (hints=\(extensionName ?? ""))"
        )
        assert(state == .active)
        guard let page = page.get() else {
            log("SOAuthorizationSession::continueStartAfterGetAuthorizationHints: Early return due to null m_page")
            return
        }
        log("SOAuthorizationSession::continueStartAfterGetAuthorizationHints: Checking page for policy choice.")
        WebKit.SOAuthorizationSupport.decidePolicy(page, extensionName.map { WTF.String($0 as CFString) } ?? WTF.String()) {
            [weak self] policy in
            self?.continueStartAfterDecidePolicy(policy)
        }
    }

    private func continueStartAfterDecidePolicy(_ policy: WebKit.SOAuthorizationLoadPolicy) {
        guard policy != .Ignore else {
            log(
                "SOAuthorizationSession::continueStartAfterDecidePolicy: Receive SOAuthorizationLoadPolicy::Ignore. Falling back to web path."
            )
            fallBackToWebPath()
            return
        }
        log("SOAuthorizationSession::continueStartAfterDecidePolicy: Receive SOAuthorizationLoadPolicy::Allow")
        switch kind {
        case .redirect(_, let windowWait), .subFrame(_, let windowWait, _):
            beginNavigationAuthorizationIfReady(windowWait)
        case .popUp:
            beginAuthorizationIfReady()
        }
    }

    private func beginNavigationAuthorizationIfReady(_ windowWait: WindowWait) {
        log(
            "NavigationSOAuthorizationSession::beginAuthorizationIfReady: m_page=\(WebKit.SOAuthorizationSupport.logAddressText(self.page.get()))"
        )
        guard let page = page.get() else {
            return
        }
        guard page.isInWindow() else {
            log(
                "NavigationSOAuthorizationSession::beginAuthorizationIfReady: Web view is not attached to a window. Pausing authorization until a window is attached."
            )
            state = .waiting
            let observer = WebKit.SOAuthorizationDidMoveToWindowObserver { [weak self] in
                self?.webViewDidMoveToWindow()
            }
            observer.add(to: page)
            assert(page.mainFrame() != nil)
            windowWait.pause = WindowWait.Pause(observer: observer, pageActiveURL: WebKit.SOAuthorizationSupport.activeURL(page))
            return
        }
        beginAuthorizationIfReady()
    }

    private func webViewDidMoveToWindow() {
        log("NavigationSOAuthorizationSession::webViewDidMoveToWindow")
        guard state == .waiting, let page = page.get(), page.isInWindow(), let pause = kind.windowWait?.pause else {
            return
        }
        log("NavigationSOAuthorizationSession::pageActiveURLDidChangeDuringWaiting")
        // FIXME: (rdar://170847912) Use the `!=` operator instead when possible.
        if !(WebKit.SOAuthorizationSupport.activeURL(page) == pause.pageActiveURL) {
            abort()
            pause.observer.remove(from: page)
            return
        }
        pause.observer.remove(from: page)
        state = .active
        beginAuthorizationIfReady()
    }

    private func beginAuthorizationIfReady() {
        guard let soAuthorization, let page = page.get() else {
            log(
                "SOAuthorizationSession::beginAuthorizationIfReady: Early return m_soAuthorization=\(self.soAuthorization != nil ? 1 : 0), m_page=\(WebKit.SOAuthorizationSupport.logAddressText(self.page.get())), navigationAction=\(WebKit.SOAuthorizationSupport.logAddressText(self.navigationAction))."
            )
            return
        }
        log("SOAuthorizationSession::beginAuthorizationIfReady: Beginning authorization with AppSSO.")
        WebKit.SOAuthorizationSupport.beginAuthorization(
            page,
            navigationAction,
            soAuthorization,
            kind.initiatingActionValue,
            kind.isSubFrame
        )
    }

    func fallBackToWebPathInternal() {
        switch kind {
        case .redirect(let callback, _):
            log(
                "RedirectSOAuthorizationSession::fallBackToWebPathInternal: navigationAction=\(WebKit.SOAuthorizationSupport.logAddressText(self.navigationAction))"
            )
            WebKit.SOAuthorizationSupport.callNavigationCallback(callback, false)
        case .subFrame(_, _, let loads):
            fallBackSubFrameToWebPath(loads)
        case .popUp(_, let newPageCallback, let uiClientCallback, _):
            log("PopUpSOAuthorizationSession::fallBackToWebPathInternal")
            WebKit.SOAuthorizationSupport.callUIClientCallback(uiClientCallback, navigationAction, newPageCallback)
        }
    }

    // The following should only be called by SOAuthorizationDelegate methods.
    func fallBackToWebPath(userCancel: Bool = false) {
        log("SOAuthorizationSession::fallBackToWebPath")
        guard state == .active else {
            log("SOAuthorizationSession::fallBackToWebPath: Returning early since not active.")
            dismissViewController()
            return
        }
        becomeCompleted()
        if userCancel, case .subFrame(_, _, let loads) = kind {
            userCancelSubFrame(loads)
            return
        }
        fallBackToWebPathInternal()
    }

    func abort() {
        log("SOAuthorizationSession::abort: m_viewController=\(appSSOLogAddressText(viewController: self.presentation.viewController))")
        #if WTF_PLATFORM_MAC
        log("SOAuthorizationSession::abort: m_sheetWindow=\(appSSOLogAddressText(self.presentation.sheet?.window))")
        #endif
        guard state != .idle && state != .completed else {
            log("SOAuthorizationSession::abort: Returning early since idle or already completed.")
            dismissViewController()
            return
        }
        becomeCompleted()
        switch kind {
        case .redirect(let callback, _):
            log("RedirectSOAuthorizationSession::abortInternal")
            WebKit.SOAuthorizationSupport.callNavigationCallback(callback, true)
        case .subFrame:
            log("SubFrameSOAuthorizationSession::abortInternal")
            fallBackToWebPathInternal()
        case .popUp(let configuration, let newPageCallback, _, let secret):
            abortPopUp(configuration: configuration, newPageCallback: newPageCallback, secret: secret)
        }
    }

    // Only responses that meet all of the following requirements will be processed:
    // 1) it has the same origin as the request;
    // 2) it has a status code of 200, 302, 307 (POST only), or 401 (with non-empty body).
    // Otherwise, it falls back to the web path.
    // Only the following HTTP headers will be processed:
    // { Set-Cookie, Location }.
    func complete(_ httpResponse: HTTPURLResponse, body: Data) {
        log(
            "SOAuthorizationSession::complete: httpState=\(httpResponse.statusCode), m_viewController=\(appSSOLogAddressText(viewController: self.presentation.viewController))"
        )
        #if WTF_PLATFORM_MAC
        log("SOAuthorizationSession::complete: m_sheetWindow=\(appSSOLogAddressText(self.presentation.sheet?.window))")
        #endif
        guard state == .active else {
            log("SOAuthorizationSession::complete: Returning early since not active.")
            dismissViewController()
            return
        }
        becomeCompleted()
        let response = WebCore.ResourceResponse(httpResponse)
        if case .subFrame = kind, shouldInterruptLoadForCSPFrameAncestorsOrXFrameOptions(response) {
            log("SOAuthorizationSession::complete: CSP failed. Falling back to web path.")
            fallBackToWebPathInternal()
            return
        }
        var responseURL = WTF.URL()
        guard let cookies = WebKit.SOAuthorizationSupport.sameOriginCookies(navigationAction, response, httpResponse, &responseURL) else {
            log("SOAuthorizationSession::complete:  Origins don't match. Falling back to web path.")
            fallBackToWebPathInternal()
            return
        }
        log(
            "SOAuthorizationSession::complete: (httpStatusCode=\(httpResponse.statusCode), hasCookies=\(cookies.isEmpty ? 0 : 1), hasData=\(body.isEmpty ? 0 : 1))"
        )
        guard !cookies.isEmpty else {
            log("SOAuthorizationSession::complete:  No cookies to set. Completing (internal).")
            completeInternal(httpResponse, response: response, body: body, responseURL: responseURL)
            return
        }
        guard let page = page.get() else {
            log("SOAuthorizationSession::complete:  Returning early because m_page is null.")
            return
        }
        // https://bugs.webkit.org/show_bug.cgi?id=299083
        log(
            "SOAuthorizationSession::complete: Setting \(cookies.count) cookies with total header size ~\(cookies.reduce(0) { $0 + $1.name.utf16.count + $1.value.utf16.count + 1 }) bytes in data store \(WebKit.SOAuthorizationSupport.logAddressText(page.websiteDataStore()))"
        )
        WebKit.SOAuthorizationSupport.setCookies(page, cookies) { [weak self, response, responseURL] in
            guard let self else {
                return
            }
            log("SOAuthorizationSession::complete: Cookies are set.")
            completeInternal(httpResponse, response: response, body: body, responseURL: responseURL)
        }
    }

    private func completeInternal(_ httpResponse: HTTPURLResponse, response: WebCore.ResourceResponse, body: Data, responseURL: WTF.URL) {
        switch kind {
        case .redirect(let callback, _):
            completeRedirect(httpResponse, response: response, body: body, callback: callback)
        case .subFrame(_, _, let loads):
            completeSubFrame(httpResponse, body: body, responseURL: responseURL, loads: loads)
        case .popUp(let configuration, let newPageCallback, _, let secret):
            completePopUp(httpResponse, body: body, configuration: configuration, newPageCallback: newPageCallback, secret: secret)
        }
    }

    private func completeRedirect(
        _ httpResponse: HTTPURLResponse,
        response: WebCore.ResourceResponse,
        body: Data,
        callback: WebKit.SOAuthorizationNavigationCallback
    ) {
        log(
            "RedirectSOAuthorizationSession::completeInternal: httpState=\(httpResponse.statusCode), navigationAction=\(WebKit.SOAuthorizationSupport.logAddressText(self.navigationAction))"
        )
        guard let page = page.get() else {
            log(
                "RedirectSOAuthorizationSession::completeInternal: httpState=\(httpResponse.statusCode) page=0, so falling back to web path."
            )
            fallBackToWebPathInternal()
            return
        }
        switch httpResponse.statusCode {
        case Int(WebCore.httpStatus302Found):
            WebKit.SOAuthorizationSupport.callNavigationCallback(callback, true)
            WebKit.SOAuthorizationSupport.loadRedirectLocation(page, navigationAction, response)
        case Int(WebCore.httpStatus200OK):
            WebKit.SOAuthorizationSupport.callNavigationCallback(callback, true)
            WebKit.SOAuthorizationSupport.loadResponseBody(page, navigationAction, response, body)
        case Int(WebCore.httpStatus307TemporaryRedirect) where WebKit.SOAuthorizationSupport.isPOST(navigationAction):
            // FIXME: Enable the useRedirectionForCurrentNavigation code path for all redirections.
            // useRedirectionForCurrentNavigation() asserts isRedirection(), which reads the status code without filling it in.
            _ = response.httpStatusCode()
            page.useRedirectionForCurrentNavigation(response)
            WebKit.SOAuthorizationSupport.callNavigationCallback(callback, false)
        case Int(WebCore.httpStatus401Unauthorized) where !body.isEmpty:
            // When the SSO extension completes with a 401 response and non-empty body data,
            // load the response body so the page can continue the authentication flow.
            // The extension chose didCompleteWithHTTPResponse: over authorizationDidNotHandle:,
            // indicating it has meaningful content for the browser to render. rdar://145336725
            log("RedirectSOAuthorizationSession::completeInternal: loading 401 response body (\(body.count) bytes)")
            WebKit.SOAuthorizationSupport.callNavigationCallback(callback, true)
            WebKit.SOAuthorizationSupport.loadResponseBody(page, navigationAction, response, body)
        default:
            log("RedirectSOAuthorizationSession::completeInternal: httpState=\(httpResponse.statusCode), so falling back to web path.")
            fallBackToWebPathInternal()
        }
    }
}

#endif
