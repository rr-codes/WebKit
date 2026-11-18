// Copyright (C) 2025 Apple Inc. All rights reserved.
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

#if HAVE_APPKIT_GESTURES_SUPPORT

import AppKit
import Foundation
import WebKit_Internal
import os
private import CxxStdlib
private import AppKit_Private.NSClickGestureRecognizer_Private
private import AppKit_Private.NSPanGestureRecognizer_Private
private import AppKit_Private.NSPressGestureRecognizer_Private
private import AppKit_Private.NSTouch_Private
private import WebCore_Private
import struct Swift.String

extension WKAppKitGestureController {
    // MARK: Click Handling

    @nonobjc
    final func updateLayerTreeTransactionIdAtLastInteractionStart() {
        if let transactionID = cxxSupport.lastCommittedMainFrameLayerTreeTransactionID().value {
            layerTreeTransactionIdAtLastInteractionStart = transactionID
        }
    }

    @nonobjc
    final func handleTapCancelled() {
        clickHighlight?.cancel()

        if !potentialTapIsInProgress {
            return
        }

        potentialTapIsInProgress = false

        if let webView = view {
            webView._protectedPage().get()?.cancelPotentialTap()
        }
    }

    @nonobjc
    final func handleTapBegan(_ gesture: NSGestureRecognizer) {
        guard let webView = view else {
            return
        }

        // Equivalent to acceptsFirstMouse, but here because potential taps are asynchronous, which
        // means that the window can get focus from this tap before we complete the click.
        let commandKeyIsDown = gesture.modifierFlags.contains(.command)
        if !(webView._impl()?.window()?.isKeyWindow ?? false) && !commandKeyIsDown {
            if Logger.viewGestures.isEnabled(type: .default), let page = webView._protectedPage().get() {
                Logger.viewGestures.log(
                    "[pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): Tap began in an inactive window; suppressing"
                )
            }
            return
        }

        if isSuppressingSingleClickGestureForTextSelection {
            return
        }

        let position = WebCore.FloatPoint(gesture.location(in: webView))

        updateLayerTreeTransactionIdAtLastInteractionStart()

        let tapID = WebKit.TapIdentifier.generate()
        latestTapID = WebKit.appKitGestureTapIdentifierToUInt64(tapID)
        potentialTapIsInProgress = true

        clickHighlight?.beginRequest(tapID, expectsFastCommit: true)

        webView._protectedPage().get()?.potentialTapAtPosition(.init(), position, false, tapID, WebKit.WebEventInputSource.Touch)
    }

    @nonobjc
    final func handleTapEnded(_ gesture: NSGestureRecognizer) {
        guard let webView = view else {
            return
        }

        if !potentialTapIsInProgress {
            return
        }

        endPotentialTapAndEnableDoubleTapGesturesIfNecessary()

        guard let layerTreeTransactionIdAtLastInteractionStart else {
            handleTapCancelled()
            return
        }

        // If this tap completes a double tap, the web process delivers it as a double click when there is a listener
        // for one, instead of the DOM double-click gesture also sending it.
        let completesDoubleClick = takeCompletedDOMDoubleClick() ? WebKit.CompletesDoubleClick.Yes : WebKit.CompletesDoubleClick.No

        clickHighlight?.showPendingHighlightForCommittedClick()

        let modifiers = WebKit.WebEventFactory.toWebEventModifierFlags(gesture.modifierFlags)
        webView._protectedPage().get()?
            .commitPotentialTap(
                .init(),
                modifiers,
                layerTreeTransactionIdAtLastInteractionStart,
                WebCore.mousePointerID,
                completesDoubleClick
            )

        clickHighlight?.fadeUnlessAwaitingHighlight()
    }

    @nonobjc
    final func endPotentialTapAndEnableDoubleTapGesturesIfNecessary() {
        potentialTapIsInProgress = false
        setDoubleTapGesturesEnabled(true)
    }

    @nonobjc
    final func setDoubleTapGesturesEnabled(_ enabled: Bool) {
        doubleClickGestureRecognizer?.isEnabled = enabled
    }
}

#endif // HAVE_APPKIT_GESTURES_SUPPORT
