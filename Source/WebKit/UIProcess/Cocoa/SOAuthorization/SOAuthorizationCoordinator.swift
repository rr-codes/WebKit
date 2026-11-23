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
import os
import wtf

// AppSSO's SPI types the view controller as id on macOS.
#if WTF_PLATFORM_MAC
typealias SOAuthorizationPresentedViewController = Any
#else
typealias SOAuthorizationPresentedViewController = SOAuthorizationViewController
#endif

extension os.Logger {
    static let appSSO = os.Logger(subsystem: "com.apple.WebKit", category: "AppSSO")
}

// An object's address, as the AppSSO log lines print it (%p).
func appSSOLogAddress(_ object: AnyObject?) -> UInt {
    object.map { UInt(bitPattern: ObjectIdentifier($0)) } ?? 0
}

// The address as %p prints it, for a message built as a string.
func appSSOLogAddressText(_ object: AnyObject?) -> String {
    "0x" + String(appSSOLogAddress(object), radix: 16)
}

// The address as %p prints it, for AppSSO's view controller.
func appSSOLogAddressText(viewController: SOAuthorizationPresentedViewController?) -> String {
    appSSOLogAddressText(viewController.map { $0 as AnyObject })
}

// C++ cannot call a main-actor class, so it makes the coordinator through this nonisolated function.
@_expose(Cxx)
func makeSOAuthorizationCoordinatorBlocks() -> WebKit.SOAuthorizationCoordinatorBlocks {
    let coordinator = WKSOAuthorizationCoordinator()
    return WebKit.SOAuthorizationCoordinatorBlocks(
        { navigationAction, page, callback in
            coordinator.tryAuthorize(navigationAction, page: page, callback: callback)
        },
        { configuration, navigationAction, page, newPageCallback, uiClientCallback in
            coordinator.tryAuthorize(
                configuration,
                navigationAction: navigationAction,
                page: page,
                newPageCallback: newPageCallback,
                uiClientCallback: uiClientCallback
            )
        }
    )
}

// Asks AppSSO whether a navigation's URL belongs to a sign-on extension, and hands the navigation to a session if it
// does. The prefix tells it apart from the C++ SOAuthorizationCoordinator, which holds it through its two blocks.
@MainActor
private final class WKSOAuthorizationCoordinator {
    private let hasAppSSO: Bool
    private let delegate: WKSOAuthorizationDelegate?

    // Called from the nonisolated makeSOAuthorizationCoordinatorBlocks().
    nonisolated init() {
        hasAppSSO = WebKit.SOAuthorizationSupport.authorizationClass() != nil
        #if WTF_PLATFORM_MAC
        // In the case of base system, which doesn't have AppSSO.framework.
        guard hasAppSSO else {
            delegate = nil
            return
        }
        #endif
        delegate = WKSOAuthorizationDelegate()
        WebKit.SOAuthorizationSupport.disableAppSSOInURLSession()
    }

    // What a tryAuthorize call does once AppSSO answers canAuthorize.
    private enum Interception {
        case navigation(callback: WebKit.SOAuthorizationNavigationCallback)
        case popUp(
            configuration: API.PageConfiguration,
            newPageCallback: WebKit.SOAuthorizationNewPageCallback,
            uiClientCallback: WebKit.SOAuthorizationUIClientCallback
        )
    }

    // For navigation interception.
    func tryAuthorize(
        _ navigationAction: API.NavigationAction,
        page: WebKit.WebPageProxy,
        callback: WebKit.SOAuthorizationNavigationCallback
    ) {
        log("tryAuthorize")
        tryAuthorize(.navigation(callback: callback), navigationAction: navigationAction, page: page)
    }

    // For pop-up interception.
    func tryAuthorize(
        _ configuration: API.PageConfiguration,
        navigationAction: API.NavigationAction,
        page: WebKit.WebPageProxy,
        newPageCallback: WebKit.SOAuthorizationNewPageCallback,
        uiClientCallback: WebKit.SOAuthorizationUIClientCallback
    ) {
        log("tryAuthorize (2)")
        if let sourceFrame = navigationAction.sourceFrame(), !sourceFrame.isMainFrame() {
            log("tryAuthorize (2): Attempting to perform subframe navigation.", level: .error)
            WebKit.SOAuthorizationSupport.callUIClientCallback(uiClientCallback, navigationAction, newPageCallback)
            return
        }
        guard navigationAction.isProcessingUserGesture() else {
            log("tryAuthorize (2): Attempting to perform auth without a user gesture.", level: .error)
            WebKit.SOAuthorizationSupport.callUIClientCallback(uiClientCallback, navigationAction, newPageCallback)
            return
        }

        tryAuthorize(
            .popUp(configuration: configuration, newPageCallback: newPageCallback, uiClientCallback: uiClientCallback),
            navigationAction: navigationAction,
            page: page
        )
    }

    // Both interceptions share this call, so canAuthorize's completion is compiled once.
    private func tryAuthorize(_ interception: Interception, navigationAction: API.NavigationAction, page: WebKit.WebPageProxy) {
        canAuthorize(WebKit.SOAuthorizationSupport.requestNSURL(navigationAction)) { [delegate] result in
            Self.finishTryAuthorize(interception, canAuthorize: result, navigationAction: navigationAction, page: page, delegate: delegate)
        }
    }

    private static func finishTryAuthorize(
        _ interception: Interception,
        canAuthorize: Bool,
        navigationAction: API.NavigationAction,
        page: WebKit.WebPageProxy,
        delegate: WKSOAuthorizationDelegate?
    ) {
        let kind: SOAuthorizationSession.Kind
        switch interception {
        case .navigation(let callback):
            guard canAuthorize else {
                os.Logger.appSSO.log(
                    "SOAuthorizationCoordinator::tryAuthorize: The requested URL is not registered for AppSSO handling. No further action needed."
                )
                WebKit.SOAuthorizationSupport.callNavigationCallback(callback, false)
                return
            }

            // A subframe session should only be allowed for Apple first parties.
            let isSubframeNavigation = navigationAction.targetFrame().map { !$0.isMainFrame() } ?? false
            if isSubframeNavigation && !WebKit.SOAuthorizationSupport.isMainFrameURLFromAppleOwnedDomain(page) {
                os.Logger.appSSO.error(
                    "SOAuthorizationCoordinator::tryAuthorize: Attempting to perform subframe navigation for non-Apple authorization URL."
                )
                WebKit.SOAuthorizationSupport.callNavigationCallback(callback, false)
                return
            }
            kind = isSubframeNavigation ? .subFrame(callback: callback) : .redirect(callback: callback)
        case .popUp(let configuration, let newPageCallback, let uiClientCallback):
            guard canAuthorize else {
                os.Logger.appSSO.error("SOAuthorizationCoordinator::tryAuthorize (2): Attempting to perform subframe navigation.")
                WebKit.SOAuthorizationSupport.callUIClientCallback(uiClientCallback, navigationAction, newPageCallback)
                return
            }
            kind = .popUp(configuration: configuration, newPageCallback: newPageCallback, uiClientCallback: uiClientCallback)
        }
        // canAuthorize answers true only with AppSSO, and then there is a delegate.
        guard let delegate else {
            return
        }
        delegate.setSession(SOAuthorizationSession(kind, navigationAction: navigationAction, page: page, delegate: delegate))
    }

    private func canAuthorize(_ url: URL?, completion: @escaping @MainActor (Bool) -> Void) {
        guard hasAppSSO else {
            log("canAuthorize: No AppSSO framework")
            completion(false)
            return
        }
        guard let soAuthorizationClass = WebKit.SOAuthorizationSupport.authorizationClass(), let url else {
            completion(false)
            return
        }
        if soAuthorizationClass.responds(
            to: #selector(
                (any SOAuthorizationClassProtocol).canPerformAuthorization(
                    with:
                    responseCode:
                    callerBundleIdentifier:
                    useInternalExtensions:
                    completion:
                )
            )
        ) {
            log("canAuthorize: Calling async canPerformAuthorizationWithURL")
            WebKit.SOAuthorizationSupport.canPerformAuthorization(url) { result in
                os.Logger.appSSO.log(
                    "SOAuthorizationCoordinator::canAuthorize: Async canPerformAuthorizationWithURL completed, result=\(result ? 1 : 0)"
                )
                completion(result)
            }
            return
        }
        completion(soAuthorizationClass.canPerformAuthorization(with: url, responseCode: 0))
    }

    // Out of line, so that the log call is compiled once.
    @inline(never)
    private func log(_ message: String, level: OSLogType = .default) {
        os.Logger.appSSO.log(
            level: level,
            "\(appSSOLogAddress(self), format: .hex(includePrefix: true), privacy: .public) - SOAuthorizationCoordinator::\(message, privacy: .public)"
        )
    }
}

// MARK: WKSOAuthorizationDelegate

// AppSSO's delegate: the current session gets AppSSO's answers for its authorization.
@MainActor
private final class WKSOAuthorizationDelegate: NSObject, @MainActor SOAuthorizationDelegate {
    private static let authenticationErrorDomain = "AKAuthenticationError" // AKAppleIDAuthenticationErrorDomain
    private static let userCanceled = -7003 // AKAuthenticationErrorUserCanceled

    private var session: SOAuthorizationSession?

    nonisolated override init() {
        super.init()
    }

    func setSession(_ session: SOAuthorizationSession) {
        log("setSession: (existing session = \(appSSOLogAddressText(self.session)), new session = \(appSSOLogAddressText(session)))")
        self.session = session
        session.shouldStart()
    }

    func authorization(
        _ authorization: any SOAuthorizationProtocol,
        presentViewController viewController: SOAuthorizationPresentedViewController?,
        withCompletion completion: @escaping @Sendable (Bool, (any Error)?) -> Void
    ) {
        guard
            let session = session(
                for: authorization,
                method: "authorization",
                callLineSuffix: "",
                outcome: "completing with NO as success state"
            )
        else {
            completion(false, nil)
            return
        }
        guard let viewController else {
            log("authorization: No view controller to present, so completing with NO as success state.")
            completion(false, nil)
            return
        }
        log("authorization: presentingViewController \(appSSOLogAddressText(viewController: viewController))")
        session.present(viewController, completion: completion)
    }

    func authorizationDidNotHandle(_ authorization: any SOAuthorizationProtocol) {
        guard let session = session(for: authorization, method: "authorizationDidNotHandle") else {
            return
        }
        log("authorizationDidNotHandle: Falling back to web path.")
        session.fallBackToWebPath()
    }

    func authorizationDidCancel(_ authorization: any SOAuthorizationProtocol) {
        guard let session = session(for: authorization, method: "authorizationDidCancel") else {
            return
        }
        log("authorizationDidCancel: Aborting session.")
        session.abort()
    }

    func authorizationDidComplete(_ authorization: any SOAuthorizationProtocol) {
        guard let session = session(for: authorization, method: "authorizationDidComplete") else {
            return
        }
        log("authorizationDidComplete: Falling back to web path.")
        session.fallBackToWebPath()
    }

    func authorization(
        _ authorization: any SOAuthorizationProtocol,
        didCompleteWithHTTPAuthorizationHeaders httpAuthorizationHeaders: [String: String]
    ) {
        guard let session = session(for: authorization, method: "authorization:didCompleteWithHTTPAuthorizationHeaders") else {
            return
        }
        log("authorization:didCompleteWithHTTPAuthorizationHeaders: Falling back to web path.")
        session.fallBackToWebPath()
    }

    func authorization(
        _ authorization: any SOAuthorizationProtocol,
        didCompleteWithHTTPResponse httpResponse: HTTPURLResponse,
        httpBody: Data
    ) {
        guard let session = session(for: authorization, method: "authorization:didCompleteWithHTTPResponse") else {
            return
        }
        log("authorization:didCompleteWithHTTPResponse: Completing.")
        session.complete(httpResponse, body: httpBody)
    }

    func authorization(_ authorization: any SOAuthorizationProtocol, didCompleteWithError error: any Error) {
        guard let session = session(for: authorization, method: "authorization:didCompleteWithError") else {
            return
        }
        let nsError = error as NSError
        if nsError.domain == Self.authenticationErrorDomain && nsError.code == Self.userCanceled {
            log("authorization:didCompleteWithError: User cancelled")
            session.fallBackToWebPath(userCancel: true)
            return
        }
        log("authorization:didCompleteWithError: Falling back to web path.")
        session.fallBackToWebPath()
    }

    // Logs the delegate call (the presentation handler's call line has no colon), then returns the current session if
    // AppSSO's answer is for its authorization.
    private func session(
        for authorization: any SOAuthorizationProtocol,
        method: String,
        callLineSuffix: String = ":",
        outcome: String = "returning early"
    ) -> SOAuthorizationSession? {
        log(
            "\(method)\(callLineSuffix) (authorization = \(appSSOLogAddressText(authorization)), _session = \(appSSOLogAddressText(self.session)))"
        )
        guard let session else {
            log("\(method): No session, so \(outcome).")
            assertionFailure("AppSSO called the delegate with no session")
            return nil
        }
        guard session.isForAuthorization(authorization) else {
            log("\(method): Authorization does not belong to the current session, so \(outcome).")
            return nil
        }
        return session
    }

    // Out of line, so that the log call is compiled once.
    @inline(never)
    private func log(_ message: String) {
        os.Logger.appSSO.log(
            "\(appSSOLogAddress(self), format: .hex(includePrefix: true), privacy: .public) - WKSOAuthorizationDelegate::\(message, privacy: .public)"
        )
    }
}

#endif
