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

extension SOAuthorizationSession {
    #if WTF_PLATFORM_MAC
    // The sheet that presents AppSSO's view controller, and the observer that dismisses it when the sheet closes.
    struct Sheet {
        let window: NSWindow
        let willCloseObserver: any NSObjectProtocol
    }
    #endif

    // AppSSO's view controller while the session presents it and, on macOS, its sheet and the observers that put off
    // its dismissal.
    struct Presentation {
        fileprivate(set) var viewController: SOAuthorizationPresentedViewController?
        #if WTF_PLATFORM_MAC
        fileprivate(set) var sheet: Sheet?
        fileprivate(set) var presentingWindowDidDeminiaturizeObserver: (any NSObjectProtocol)?
        fileprivate(set) var applicationDidUnhideObserver: (any NSObjectProtocol)?
        #endif
    }

    // Should only be called by SOAuthorizationDelegate methods.
    func present(_ viewController: SOAuthorizationPresentedViewController, completion: (Bool, (any Error)?) -> Void) {
        log(
            "SOAuthorizationSession::presentViewController: m_viewController=\(appSSOLogAddressText(viewController: self.presentation.viewController))"
        )
        #if WTF_PLATFORM_MAC
        log("SOAuthorizationSession::presentViewController: m_sheetWindow=\(appSSOLogAddressText(self.presentation.sheet?.window))")
        #endif
        assert(state == .active)
        // Only expect at most one UI session for the whole authorization session.
        guard let page = page.get(), !page.isClosed(), self.presentation.viewController == nil else {
            log(
                "SOAuthorizationSession::presentViewController: m_page=\(WebKit.SOAuthorizationSupport.logAddressText(self.page.get())), m_page->isClosed=\(self.page.get()?.isClosed() == true ? 1 : 0), m_viewController=\(appSSOLogAddressText(viewController: self.presentation.viewController))"
            )
            completion(false, Self.presentationFailedError)
            return
        }
        self.presentation.viewController = viewController
        #if WTF_PLATFORM_MAC
        assert(presentation.sheet == nil)
        dismissModalSheetIfNecessary()
        // AppSSO gives an NSViewController on macOS.
        // swift-format-ignore: NeverForceUnwrap
        let sheetWindow = NSWindow(contentViewController: viewController as! NSViewController)
        // AppKit posts NSWindow and NSApplication notifications on the main thread.
        let willCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: sheetWindow,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                os.Logger.appSSO.log("presentViewController: Received NSWindowWillCloseNotification. Dismissing the view controller.")
                self.dismissViewController()
            }
        }
        presentation.sheet = Sheet(window: sheetWindow, willCloseObserver: willCloseObserver)
        log(
            "SOAuthorizationSession::presentViewController: Added m_sheetWindowWillCloseObserver (\(appSSOLogAddressText(self.presentation.sheet?.willCloseObserver)))"
        )
        guard let presentingWindow = page.platformWindow() else {
            log("SOAuthorizationSession::presentViewController: No presenting window. Returning early.")
            completion(false, Self.presentationFailedError)
            return
        }
        log(
            "SOAuthorizationSession::presentViewController: Calling beginSheet on \(appSSOLogAddressText(presentingWindow)) for sheet \(appSSOLogAddressText(self.presentation.sheet?.window))."
        )
        presentingWindow.beginSheet(sheetWindow, completionHandler: nil)
        #else
        guard let presentingViewController = WebKit.SOAuthorizationSupport.presentingViewController(page) else {
            completion(false, Self.presentationFailedError)
            return
        }
        presentingViewController.present(viewController, animated: true, completion: nil)
        #endif
        completion(true, nil)
    }

    private static var presentationFailedError: NSError {
        NSError(domain: PAL.get_AppSSO_SOErrorDomainSingleton(), code: Int(kSOErrorAuthorizationPresentationFailed))
    }

    #if WTF_PLATFORM_MAC
    private func dismissModalSheetIfNecessary() {
        guard let sheet = presentation.sheet else {
            return
        }
        if let presentingWindow = sheet.window.sheetParent {
            log(
                "SOAuthorizationSession::dismissModalSheetIfNecessary: Calling endSheet on \(appSSOLogAddressText(presentingWindow)) for sheet \(appSSOLogAddressText(sheet.window))."
            )
            presentingWindow.endSheet(sheet.window)
        }
        self.presentation.sheet = nil
        log(
            "SOAuthorizationSession::dismissModalSheetIfNecessary: Removing m_sheetWindowWillCloseObserver (\(appSSOLogAddressText(sheet.willCloseObserver)))"
        )
        NotificationCenter.default.removeObserver(sheet.willCloseObserver)
    }
    #endif

    func dismissViewController(deferringWhileHidden: Bool = true) {
        log(
            "SOAuthorizationSession::dismissViewController: m_viewController=\(appSSOLogAddressText(viewController: self.presentation.viewController))"
        )
        guard presentation.viewController != nil else {
            log("SOAuthorizationSession::dismissViewController: No view controller, so returning early.")
            return
        }
        #if WTF_PLATFORM_MAC
        guard presentation.sheet != nil else {
            log("SOAuthorizationSession::dismissViewController: No view controller or sheet window, so returning early.")
            return
        }
        // This is a workaround for an AppKit issue: <rdar://problem/59125329>.
        // sheet.window.sheetParent is nil if the parent is minimized or the host app is hidden.
        if deferringWhileHidden, let presentingWindow = page.get()?.platformWindow(), presentingWindow.isMiniaturized {
            log("SOAuthorizationSession::dismissViewController: Page's window is miniaturized. Waiting to dismiss until active.")
            guard presentation.presentingWindowDidDeminiaturizeObserver == nil else {
                log(
                    "SOAuthorizationSession::dismissViewController: [Miniaturized] Already has a deminiaturized observer (\(appSSOLogAddressText(self.presentation.presentingWindowDidDeminiaturizeObserver))). Hidden observer is \(appSSOLogAddressText(self.presentation.applicationDidUnhideObserver))"
                )
                return
            }
            // The observer keeps the session alive until the dismissal completes.
            presentation.presentingWindowDidDeminiaturizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: presentingWindow,
                queue: nil
            ) { _ in
                MainActor.assumeIsolated {
                    self.log("SOAuthorizationSession::dismissViewController: Window has deminiaturized. Completing the dismissal.")
                    self.dismissViewController()
                    if let observer = self.presentation.presentingWindowDidDeminiaturizeObserver.take() {
                        NotificationCenter.default.removeObserver(observer)
                    }
                }
            }
            return
        }
        if deferringWhileHidden && NSApp.isHidden {
            log("SOAuthorizationSession::dismissViewController: Application is hidden. Waiting to dismiss until active.")
            guard presentation.applicationDidUnhideObserver == nil else {
                log(
                    "SOAuthorizationSession::dismissViewController: [Hidden] Already has an Unhide observer (\(appSSOLogAddressText(self.presentation.presentingWindowDidDeminiaturizeObserver))). Deminiaturized observer is \(appSSOLogAddressText(self.presentation.applicationDidUnhideObserver))"
                )
                return
            }
            // The observer keeps the session alive until the dismissal completes.
            presentation.applicationDidUnhideObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didUnhideNotification,
                object: NSApp,
                queue: nil
            ) { _ in
                MainActor.assumeIsolated {
                    self.log("SOAuthorizationSession::dismissViewController: Application is no longer hidden. Completing the dismissal.")
                    self.dismissViewController()
                    if let observer = self.presentation.applicationDidUnhideObserver.take() {
                        NotificationCenter.default.removeObserver(observer)
                    }
                }
            }
            return
        }
        dismissModalSheetIfNecessary()
        log(
            "SOAuthorizationSession::dismissViewController: Finished call with deminiaturized observer (\(appSSOLogAddressText(self.presentation.presentingWindowDidDeminiaturizeObserver))) and Hidden observer (\(appSSOLogAddressText(self.presentation.applicationDidUnhideObserver)))"
        )
        #else
        presentation.viewController?.presentingViewController?.dismiss(animated: true, completion: nil)
        #endif
        presentation.viewController = nil
    }
}

#endif
