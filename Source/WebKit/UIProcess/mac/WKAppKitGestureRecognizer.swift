// Copyright (C) 2026 Apple Inc. All rights reserved.
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

#if HAVE_APPKIT_GESTURES_SUPPORT && compiler(>=6.2)

import Foundation
internal import WebKit_Internal

@objc(NSGestureRecognizerDelegate)
@implementation
extension WKAppKitGestureController {
    @objc(gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:)
    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        guard let page = _page else {
            return false
        }

        Logger.viewGestures.log(
            "[pageProxyID=\(page.logIdentifier())] \(#function) Gesture: \(String(reflecting: gestureRecognizer)), Other gesture: \(String(reflecting: otherGestureRecognizer))"
        )

        if Set([gestureRecognizer, otherGestureRecognizer]) == Set([_singleClickGestureRecognizer, _panGestureRecognizer]) {
            return true
        }

        if gestureRecognizer === _singleClickGestureRecognizer
            && otherGestureRecognizer.isBuiltInScrollViewPanGestureRecognizer
            && otherGestureRecognizer.view is NSScrollView
        {
            return true
        }

        guard let webView = unsafe _viewImpl?.view() else {
            return false
        }

        // Allow the single click GR to be simultaneously recognized with any of those from the text selection manager.

        if let textSelectionManager = webView.textSelectionManager {
            if textSelectionManager.gesturesForFailureRequirements.contains(where: {
                Set([gestureRecognizer, otherGestureRecognizer]) == Set([_singleClickGestureRecognizer, $0])
            }) {
                return true
            }
        }

        return false
    }

    @objc(gestureRecognizer:shouldBeRequiredToFailByGestureRecognizer:)
    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        guard let page = _page else {
            return false
        }

        Logger.viewGestures.log(
            "[pageProxyID=\(page.logIdentifier())] \(#function) Gesture: \(String(reflecting: gestureRecognizer)), Other gesture: \(String(reflecting: otherGestureRecognizer))"
        )

        guard let webView = unsafe _viewImpl?.view() else {
            return false
        }

        // Fail any gestures from the text selection manager if the secondary click GR handles them.

        if let textSelectionManager = webView.textSelectionManager {
            if textSelectionManager.gesturesForFailureRequirements.contains(where: {
                gestureRecognizer === _secondaryClickGestureRecognizer && otherGestureRecognizer === $0
            }) {
                return true
            }
        }

        return false
    }

    @objc(gestureRecognizer:shouldRequireFailureOfGestureRecognizer:)
    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        guard let page = _page else {
            return false
        }

        Logger.viewGestures.log(
            "[pageProxyID=\(page.logIdentifier())] \(#function) Gesture: \(String(reflecting: gestureRecognizer)), Other gesture: \(String(reflecting: otherGestureRecognizer))"
        )

        if gestureRecognizer === _singleClickGestureRecognizer && otherGestureRecognizer === _doubleClickGestureRecognizer {
            return true
        }

        return false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        guard let page = _page else {
            return false
        }

        guard let viewImpl = unsafe _viewImpl else {
            return false
        }

        Logger.viewGestures.log("[pageProxyID=\(page.logIdentifier())] \(#function) Gesture: \(String(reflecting: gestureRecognizer))")

        if gestureRecognizer === _doubleClickGestureRecognizer {
            if unsafe !viewImpl.allowsMagnification() {
                return false
            }
        }

        if gestureRecognizer === _secondaryClickGestureRecognizer {
            // FIXME: Implement logic for determining if the clicked node is not text.
            return false
        }

        return true
    }

    private func isScrollOrZoomGestureRecognizer(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        // FIXME: Should we account for any system pan gesture recognizers?
        gestureRecognizer === _panGestureRecognizer || gestureRecognizer is NSMagnificationGestureRecognizer
    }

    // swift-format-ignore: NoLeadingUnderscores
    @objc(_gestureRecognizer:canPreventGestureRecognizer:)
    func _gestureRecognizer(
        _ preventingGestureRecognizer: NSGestureRecognizer!,
        canPrevent preventedGestureRecognizer: NSGestureRecognizer!
    ) -> Bool {
        let isOurClickGesture =
            preventingGestureRecognizer === _singleClickGestureRecognizer
            || preventingGestureRecognizer === _secondaryClickGestureRecognizer

        return !isOurClickGesture || !isScrollOrZoomGestureRecognizer(preventedGestureRecognizer)
    }
}

extension NSGestureRecognizer {
    fileprivate var isBuiltInScrollViewPanGestureRecognizer: Bool {
        guard let scrollViewPanGestureClass: AnyClass = NSClassFromString("NSScrollViewPanGestureRecognizer") else {
            return false
        }
        return isKind(of: scrollViewPanGestureClass)
    }
}

#endif // HAVE_APPKIT_GESTURES_SUPPORT && compiler(>=6.2)
