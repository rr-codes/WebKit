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
private import WebCore_Private
import struct Swift.String

extension WKAppKitGestureController {
    func makeImageAnalysisDeferringGestureRecognizer(withName name: String) -> WKDeferringGestureRecognizer {
        let deferringGestureRecognizer = WKDeferringGestureRecognizer(deferringGestureDelegate: self)
        configure(forImageAnalysisDeferral: deferringGestureRecognizer)
        deferringGestureRecognizer.name = name
        deferringGestureRecognizer.delegate = self
        deferringGestureRecognizer.immediatelyFailsAfterTouchEnd = true
        return deferringGestureRecognizer
    }

    func resolveImageAnalysisDeferrals(with outcome: ImageAnalysisDeferralOutcome) {
        if imageAnalysisDeferralState == .deferring {
            imageAnalysisDeferralState = .undecided
        }

        let preventTextSelection = shouldPreventGestures(deferredBy: imageAnalysisTextSelectionDeferringGestureRecognizer, for: outcome)
        let preventDragAndContextMenu = shouldPreventGestures(
            deferredBy: imageAnalysisDragAndContextMenuDeferringGestureRecognizer,
            for: outcome
        )

        // Only resolve a deferral that's still deferring. A deferral may already be resolved by the time the
        // analysis token drops -- e.g. it failed on lift (immediatelyFailsAfterTouchEnd) before slow
        // analysis finished -- and re-setting an already-terminal gesture state would be a no-op at best.
        endDeferralIfStillDeferring(imageAnalysisTextSelectionDeferringGestureRecognizer, preventingGestures: preventTextSelection)
        endDeferralIfStillDeferring(
            imageAnalysisDragAndContextMenuDeferringGestureRecognizer,
            preventingGestures: preventDragAndContextMenu
        )
    }

    func shouldPreventGestures(
        deferredBy deferringGestureRecognizer: NSGestureRecognizer?,
        for outcome: ImageAnalysisDeferralOutcome
    ) -> Bool {
        // Text found -> Live Text wins: allow the deferred text selection, prevent the drag / context-menu
        // fallback. No text -> the reverse.
        if deferringGestureRecognizer === imageAnalysisTextSelectionDeferringGestureRecognizer {
            return outcome == .noText
        }

        if deferringGestureRecognizer === imageAnalysisDragAndContextMenuDeferringGestureRecognizer {
            return outcome == .foundText
        }

        assertionFailure("Unexpected image analysis deferring gesture recognizer")
        return false
    }

    private func endDeferralIfStillDeferring(_ recognizer: WKDeferringGestureRecognizer?, preventingGestures: Bool) {
        guard let recognizer, recognizer.state == .possible else {
            return
        }
        recognizer.endDeferralShouldPreventGestures(preventingGestures)
    }
}

#endif // HAVE_APPKIT_GESTURES_SUPPORT
