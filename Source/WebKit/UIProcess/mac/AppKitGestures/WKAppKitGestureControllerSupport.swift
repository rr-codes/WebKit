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
import WebKit_Internal
private import AppKit_Private.NSPanGestureRecognizer_Private
private import WebCore_Private

// The outcome of the image-analysis preflight, used to resolve the two image-analysis deferring
// gestures. Over an image we defer both text selection and the drag / context-menu fallback until
// analysis finishes, then resolve them oppositely.
enum ImageAnalysisDeferralOutcome {
    case notApplicable // Not an image (or the press was abandoned): influence neither deferral.
    case noText // Image without selectable text: prevent text selection; allow drag / context menu.
    case foundText // Image with selectable text: allow text selection; prevent drag / context menu.
}

enum ImageAnalysisDeferralState {
    case undecided
    case deferring
    case gestureFailed
}

struct CompletedImageAnalysis {
    var element: WebCore.ElementContext
    var outcome: ImageAnalysisDeferralOutcome

    func outcome(for hostElement: WebCore.ElementContext?) -> ImageAnalysisDeferralOutcome? {
        guard let hostElement, element.isSameElement(hostElement) else {
            return nil
        }
        return outcome
    }
}

// Keeps the image-analysis deferrals open for the lifetime of an in-flight analysis. When the last
// reference is dropped (analysis finished or abandoned), it resolves both deferrals on the main run
// loop according to the recorded outcome. Mirrors the iOS ImageAnalysisGestureDeferralToken.
@MainActor
final class ImageAnalysisGestureDeferralToken {
    private weak var controller: WKAppKitGestureController?
    var outcome: ImageAnalysisDeferralOutcome = .notApplicable

    init(controller: WKAppKitGestureController) {
        self.controller = controller
    }

    isolated deinit {
        controller?.resolveImageAnalysisDeferrals(with: outcome)
    }
}

struct TouchActions: OptionSet {
    let rawValue: UInt8

    static let auto = Self(rawValue: WebCore.TouchAction.Auto.rawValue)
    static let manipulation = Self(rawValue: WebCore.TouchAction.Manipulation.rawValue)
    static let panX = Self(rawValue: WebCore.TouchAction.PanX.rawValue)
    static let panY = Self(rawValue: WebCore.TouchAction.PanY.rawValue)
    static let pinchZoom = Self(rawValue: WebCore.TouchAction.PinchZoom.rawValue)
}

struct PanAxes: OptionSet {
    let rawValue: UInt8

    static let horizontal = Self(rawValue: 1 << 0)
    static let vertical = Self(rawValue: 1 << 1)
}

extension WebKit.WebEventPhase {
    init(_ state: NSGestureRecognizer.State) {
        switch state {
        case .possible:
            self = .MayBegin
        case .began:
            self = .Began
        case .changed:
            self = .Changed
        case .ended:
            self = .Ended
        case .cancelled, .failed:
            self = .Cancelled
        default:
            assertionFailure("Unknown gesture recognizer state")
            self = .None
        }
    }
}

extension WebKit.InteractionInformationAtPosition {
    var representsDraggableElement: Bool {
        isLink || isImage || isAttachment || isDHTMLDraggable || isColorInput || prefersDraggingOverTextSelection
    }

    var representsSelectableContent: Bool {
        isSelectable() || isFocusableWithSelectableText()
    }

    var prefersDirectManipulation: Bool {
        isRangeInput || isARIASlider || hasDirectionalResizeCursor || isInResizeControl || isCustomSlider
            || WebKit.appKitGestureIsInteractiveModel(self)
    }

    var representsSecondaryClickableElement: Bool {
        if prefersDirectManipulation {
            return false
        }

        if representsSelectableContent {
            return true
        }

        if shouldTreatLongClickAsSecondaryClickQuirk {
            return true
        }

        if isImage {
            return true
        }

        return isOverVideo && selectability != .UnselectableDueToFocusableElement
    }
}

extension NSPanGestureRecognizer {
    func startLocation(in view: NSView) -> NSPoint {
        if responds(to: #selector(NSPanGestureRecognizer._startLocation(in:))) {
            return _startLocation(in: view)
        }

        return location(in: view)
    }

    func takeTranslation(in view: NSView) -> WebCore.FloatSize {
        let translation = WebCore.toFloatSize(WebCore.FloatPoint(self.translation(in: view)))
        setTranslation(.zero, in: view)
        return translation
    }
}

extension CGSize {
    init(_ size: WebCore.FloatSize) {
        self.init(width: CGFloat(size.width()), height: CGFloat(size.height()))
    }
}

extension CGPoint {
    init(_ point: WebCore.IntPoint) {
        self.init(x: CGFloat(point.x()), y: CGFloat(point.y()))
    }
}

func appKitGestureLogInteger(_ flag: Bool) -> Int {
    flag ? 1 : 0
}

#endif // HAVE_APPKIT_GESTURES_SUPPORT
