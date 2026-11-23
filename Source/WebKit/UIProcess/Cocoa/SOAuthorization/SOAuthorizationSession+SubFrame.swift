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
import os
import wtf

extension SOAuthorizationSession {
    // A load the subframe session makes in its frame: the data to load at the URL, or the URL itself with its referrer.
    struct SubFrameLoad {
        enum Content {
            case data(Data)
            case referrer(WTF.String)
        }

        let url: WTF.URL
        let content: Content
    }

    // The loads a subframe session makes in its frame, one at a time, and the observer that tells it when each finishes.
    final class SubFrameLoads {
        fileprivate var observer: WebKit.SOAuthorizationFrameLoadObserver?
        fileprivate var queue: [SubFrameLoad] = []
    }

    private static let postDidStartMessageToParent = Data("<script>parent.postMessage('SOAuthorizationDidStart', '*');</script>".utf8)
    private static let postDidCancelMessageToParent = Data("<script>parent.postMessage('SOAuthorizationDidCancel', '*');</script>".utf8)
    private static let postDidUserCancelMessageToParent = Data(
        "<script>parent.postMessage('SOAuthorizationDidUserCancel', '*');</script>".utf8
    )

    // Observes the target frame's loads, so that each finished load starts the next one.
    func observeFrameLoads(_ loads: SubFrameLoads) {
        guard let frame = WebKit.SOAuthorizationSupport.targetWebFrame(navigationAction) else {
            return
        }
        let observer = WebKit.SOAuthorizationFrameLoadObserver { [weak self, weak loads] in
            guard let self, let loads else {
                return
            }
            didFinishLoad(loads)
        }
        observer.add(to: frame)
        loads.observer = observer
    }

    func stopObservingFrameLoads(_ loads: SubFrameLoads) {
        if let observer = loads.observer, let frame = WebKit.SOAuthorizationSupport.targetWebFrame(navigationAction) {
            observer.remove(from: frame)
        }
    }

    func prepareSubFrameStart(callback: WebKit.SOAuthorizationNavigationCallback, loads: SubFrameLoads) {
        log("SubFrameSOAuthorizationSession::beforeStart")
        // Cancelled the current load before loading the data to post SOAuthorizationDidStart to the parent frame.
        WebKit.SOAuthorizationSupport.callNavigationCallback(callback, true)
        appendRequestToLoad(
            WebKit.SOAuthorizationSupport.requestURL(navigationAction),
            .data(Self.postDidStartMessageToParent),
            in: loads
        )
    }

    func userCancelSubFrame(_ loads: SubFrameLoads) {
        log(
            "SubFrameSOAuthorizationSession::userCancel: navigationAction=\(WebKit.SOAuthorizationSupport.logAddressText(self.navigationAction))"
        )
        appendMessageAndOriginalRequest(Self.postDidUserCancelMessageToParent, in: loads)
    }

    func fallBackSubFrameToWebPath(_ loads: SubFrameLoads) {
        log(
            "SubFrameSOAuthorizationSession::fallBackToWebPathInternal: navigationAction=\(WebKit.SOAuthorizationSupport.logAddressText(self.navigationAction))"
        )
        appendMessageAndOriginalRequest(Self.postDidCancelMessageToParent, in: loads)
    }

    func completeSubFrame(_ httpResponse: HTTPURLResponse, body: Data, responseURL: WTF.URL, loads: SubFrameLoads) {
        log("SubFrameSOAuthorizationSession::completeInternal: httpState=\(httpResponse.statusCode)")
        guard httpResponse.statusCode == Int(WebCore.httpStatus200OK) else {
            fallBackToWebPathInternal()
            return
        }
        appendRequestToLoad(responseURL, .data(body), in: loads)
    }

    private func appendMessageAndOriginalRequest(_ message: Data, in loads: SubFrameLoads) {
        let url = WebKit.SOAuthorizationSupport.requestURL(navigationAction)
        appendRequestToLoad(url, .data(message), in: loads)
        appendRequestToLoad(url, .referrer(WebKit.SOAuthorizationSupport.navigationReferrer(navigationAction)), in: loads)
    }

    private func appendRequestToLoad(_ url: WTF.URL, _ content: SubFrameLoad.Content, in loads: SubFrameLoads) {
        loads.queue.append(SubFrameLoad(url: url, content: content))
        if loads.queue.count == 1 {
            loadRequestToFrame(loads)
        }
    }

    private func didFinishLoad(_ loads: SubFrameLoads) {
        log("SubFrameSOAuthorizationSession::didFinishLoad")
        let frame = WebKit.SOAuthorizationSupport.targetWebFrame(navigationAction)
        assert(frame != nil)
        guard let frame, let first = loads.queue.first, WebKit.SOAuthorizationSupport.frameURL(frame) == first.url else {
            return
        }
        loads.queue.removeFirst()
        loadRequestToFrame(loads)
    }

    private func loadRequestToFrame(_ loads: SubFrameLoads) {
        log("SubFrameSOAuthorizationSession::loadRequestToFrame")
        guard let page = page.get(), let first = loads.queue.first else {
            return
        }
        let frame = WebKit.SOAuthorizationSupport.targetWebFrame(navigationAction)
        assert(frame.map { WebKit.SOAuthorizationSupport.isFrameInPage($0, page) } ?? true)
        guard let frame, WebKit.SOAuthorizationSupport.isFrameInPage(frame, page) else {
            return
        }
        page.setShouldSuppressSOAuthorizationInNextNavigationPolicyDecision()
        switch first.content {
        case .data(let data):
            WebKit.SOAuthorizationSupport.loadDataInFrame(frame, first.url, data)
        case .referrer(let referrer):
            frame.loadURL(first.url, referrer)
        }
    }

    func shouldInterruptLoadForCSPFrameAncestorsOrXFrameOptions(_ response: WebCore.ResourceResponse) -> Bool {
        var xFrameOptionsMessage = WTF.String()
        var refusalMessage = WTF.String()
        let shouldInterrupt = WebKit.SOAuthorizationSupport.shouldInterruptLoadForCSPFrameAncestorsOrXFrameOptions(
            page.get(),
            navigationAction,
            response,
            &xFrameOptionsMessage,
            &refusalMessage
        )
        if !xFrameOptionsMessage.isNull() {
            log(
                "SubFrameSOAuthorizationSession::shouldInterruptLoadForXFrameOptions: ",
                private: Swift.String(xFrameOptionsMessage.utf8(WTF.LenientConversion).toStdString())
            )
        }
        if !refusalMessage.isNull() {
            log(
                "SubFrameSOAuthorizationSession::shouldInterruptLoadForCSPFrameAncestorsOrXFrameOptions: ",
                private: Swift.String(refusalMessage.utf8(WTF.LenientConversion).toStdString())
            )
        }
        return shouldInterrupt
    }
}

#endif
