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

import Foundation
import WebKit_Internal
import WebKit_Private
import WebKit_Private.WKNavigationDelegatePrivate

extension SOAuthorizationSession {
    // The pop-up session's hidden web view, which loads the response for the opener, and its delegate.
    final class SecretWebView {
        fileprivate var webView: WKWebView?
        fileprivate var delegate: SOAuthorizationSecretDelegate?
    }

    private func createSecretWebView(_ pageConfiguration: API.PageConfiguration, in secret: SecretWebView) {
        log("PopUpSOAuthorizationSession::initSecretWebView")
        // swift-format-ignore: NeverForceUnwrap
        let configuration = pageConfiguration.wrapper() as! WKWebViewConfiguration
        // swift-format-ignore: NeverForceUnwrap
        let secretViewPreferences = configuration.preferences.copy() as! WKPreferences
        secretViewPreferences._isExtensibleSSOEnabled = false
        configuration.preferences = secretViewPreferences
        let secretWebView = WKWebView(frame: .zero, configuration: configuration)
        let secretDelegate = SOAuthorizationSecretDelegate(session: self)
        secretWebView.uiDelegate = secretDelegate
        secretWebView.navigationDelegate = secretDelegate
        precondition(secretWebView._protectedPage().get()?.preferences().isExtensibleSSOEnabled() == false)
        secret.webView = secretWebView
        secret.delegate = secretDelegate
        log("PopUpSOAuthorizationSession::SecretWebView is created.")
    }

    // Creates the secret web view and, if there is one, gives its page to the opener.
    private func openSecretWebView(
        _ configuration: API.PageConfiguration,
        newPageCallback: WebKit.SOAuthorizationNewPageCallback,
        in secret: SecretWebView
    ) -> WKWebView? {
        createSecretWebView(configuration, in: secret)
        guard let secretWebView = secret.webView else {
            return nil
        }
        WebKit.SOAuthorizationSupport.callNewPageCallback(newPageCallback, secretWebView._protectedPage().get())
        return secretWebView
    }

    func abortPopUp(configuration: API.PageConfiguration, newPageCallback: WebKit.SOAuthorizationNewPageCallback, secret: SecretWebView) {
        log("PopUpSOAuthorizationSession::abortInternal: m_page=\(WebKit.SOAuthorizationSupport.logAddressText(self.page.get()))")
        guard let page = page.get(), !page.isClosed() else {
            WebKit.SOAuthorizationSupport.callNewPageCallback(newPageCallback, nil)
            return
        }
        guard let secretWebView = openSecretWebView(configuration, newPageCallback: newPageCallback, in: secret) else {
            WebKit.SOAuthorizationSupport.callNewPageCallback(newPageCallback, nil)
            return
        }
        secretWebView.evaluateJavaScript("window.close()", completionHandler: nil)
    }

    func completePopUp(
        _ httpResponse: HTTPURLResponse,
        body: Data,
        configuration: API.PageConfiguration,
        newPageCallback: WebKit.SOAuthorizationNewPageCallback,
        secret: SecretWebView
    ) {
        log("PopUpSOAuthorizationSession::completeInternal: httpState=\(httpResponse.statusCode)")
        // A response of the request's origin has a URL.
        guard httpResponse.statusCode == Int(WebCore.httpStatus200OK), let page = page.get(), !page.isClosed(),
            let baseURL = httpResponse.url
        else {
            fallBackToWebPathInternal()
            return
        }
        guard let secretWebView = openSecretWebView(configuration, newPageCallback: newPageCallback, in: secret) else {
            fallBackToWebPathInternal()
            return
        }
        secretWebView.load(body, mimeType: "text/html", characterEncodingName: "UTF-8", baseURL: baseURL)
    }

    fileprivate func close(_ webView: WKWebView) {
        log("PopUpSOAuthorizationSession::close")
        guard case .popUp(_, _, _, let secret) = kind, let secretWebView = secret.webView else {
            return
        }
        guard state == .completed, webView === secretWebView else {
            assertionFailure("A secret web view closed out of order")
            return
        }
        secret.webView = nil
        log("PopUpSOAuthorizationSession::SecretWebView is cleaned.")
    }
}

// MARK: SOAuthorizationSecretDelegate

// The pop-up's secret web view's delegate: cancels the first navigation and allows the rest, and tells the session
// when the page closes or finishes loading.
@MainActor
private final class SOAuthorizationSecretDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    private weak var session: SOAuthorizationSession?
    private var isFirstNavigation = true

    init(session: SOAuthorizationSession) {
        self.session = session
    }

    func webViewDidClose(_ webView: WKWebView) {
        session?.close(webView)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        // FIXME<rdar://problem/48787839>: We should restrict the load to only substitute data.
        // Use the following heuristic as a workaround right now.
        // Ignore the first load in the secret window, which navigates to the authentication URL.
        if isFirstNavigation {
            isFirstNavigation = false
            decisionHandler(.cancel)
            return
        }
        decisionHandler(_WKNavigationActionPolicyAllowWithoutTryingAppLink)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        session?.close(webView)
    }
}

#endif
