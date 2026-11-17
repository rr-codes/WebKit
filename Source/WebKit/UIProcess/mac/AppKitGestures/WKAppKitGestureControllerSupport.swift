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
private import AppKit_Private.NSClickGestureRecognizer_Private
private import AppKit_Private.NSPanGestureRecognizer_Private
private import AppKit_Private.NSPressGestureRecognizer_Private
private import AppKit_Private.NSTouch_Private
private import WebCore_Private

enum ImageAnalysisDeferralOutcome: UInt8 {
    case notApplicable = 0 // Not an image (or the press was abandoned): influence neither deferral.
    case noText = 1 // Image without selectable text: prevent text selection; allow drag / context menu.
    case foundText = 2 // Image with selectable text: allow text selection; prevent drag / context menu.
}

enum ImageAnalysisDeferralState: UInt8 {
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

private let sharedPositionInformationToleranceRadius = 15
let panPositionInformationToleranceRadius = sharedPositionInformationToleranceRadius
let mouseDownPositionInformationToleranceRadius = sharedPositionInformationToleranceRadius

@MainActor
func panTranslation(_ gesture: NSPanGestureRecognizer, in view: WKWebView) -> WebCore.FloatSize {
    let translation = WebCore.toFloatSize(WebCore.FloatPoint(gesture.translation(in: view)))
    gesture.setTranslation(.zero, in: view)
    return translation
}

func toWebEventPhase(_ state: NSGestureRecognizer.State) -> WebKit.WebEventPhase {
    switch state {
    case .possible:
        return WebKit.WebEventPhase.MayBegin
    case .began:
        return WebKit.WebEventPhase.Began
    case .changed:
        return WebKit.WebEventPhase.Changed
    case .ended:
        return WebKit.WebEventPhase.Ended
    case .cancelled, .failed:
        return WebKit.WebEventPhase.Cancelled
    default:
        assertionFailure()
        return WebKit.WebEventPhase.None
    }
}

@MainActor
func isBuiltInScrollViewPanGestureRecognizer(_ recognizer: NSGestureRecognizer?) -> Bool {
    guard let scrollViewPanGestureClass = scrollViewPanGestureClass else {
        return false
    }
    return recognizer?.isKind(of: scrollViewPanGestureClass) ?? false
}

private let scrollViewPanGestureClass: AnyClass? = NSClassFromString("NSScrollViewPanGestureRecognizer")

// Bit sets with only the operations the controller uses.
struct TouchActionSet {
    let rawValue: UInt8

    // True when the set shares a bit with any of `members` (OptionSet's `!isDisjoint(with: [members])`).
    func intersectsAny(of members: TouchActionSet...) -> Bool {
        members.contains { rawValue & $0.rawValue != 0 }
    }

    static let auto = TouchActionSet(rawValue: WebCore.TouchAction.Auto.rawValue)
    static let manipulation = TouchActionSet(rawValue: WebCore.TouchAction.Manipulation.rawValue)
    static let panX = TouchActionSet(rawValue: WebCore.TouchAction.PanX.rawValue)
    static let panY = TouchActionSet(rawValue: WebCore.TouchAction.PanY.rawValue)
    static let pinchZoom = TouchActionSet(rawValue: WebCore.TouchAction.PinchZoom.rawValue)
}

struct PanAxis {
    var rawValue: UInt8

    var isEmpty: Bool { rawValue == 0 }
    func contains(_ member: PanAxis) -> Bool { rawValue & member.rawValue == member.rawValue }
    mutating func insert(_ member: PanAxis) { rawValue |= member.rawValue }

    static let horizontal = PanAxis(rawValue: 1 << 0)
    static let vertical = PanAxis(rawValue: 1 << 1)
}

@MainActor
func isCatchingDeceleratingScroll(_ scrollViewPanGesture: NSGestureRecognizer?) -> Bool {
    guard let scrollView = scrollViewPanGesture?.view as? NSScrollView else {
        return false
    }

    // FIXME: The flag was recently renamed in rdar://185652893, so keep this selector check for a bit.
    guard scrollView.responds(to: #selector(NSScrollView._touchCaughtDeceleration)) else {
        return false
    }

    return scrollView._touchCaughtDeceleration()
}

@MainActor
func isBuiltInScrollViewMagnificationGestureRecognizer(_ gesture: NSGestureRecognizer) -> Bool {
    gesture.isKind(of: NSMagnificationGestureRecognizer.self) && gesture._isScrollGestureRecognizer
}

func isSamePair(_ a: NSGestureRecognizer, _ b: NSGestureRecognizer, _ x: NSGestureRecognizer?, _ y: NSGestureRecognizer?) -> Bool {
    (a === x && b === y) || (b === x && a === y)
}

@MainActor
func startLocationInView(_ gesture: NSPanGestureRecognizer, _ view: NSView) -> NSPoint {
    if gesture.responds(to: #selector(NSPanGestureRecognizer._startLocation(in:))) {
        return gesture._startLocation(in: view)
    }

    return gesture.location(in: view)
}

func representsDraggableElement(_ info: WebKit.InteractionInformationAtPosition) -> Bool {
    info.isLink || info.isImage || info.isAttachment || info.isDHTMLDraggable || info.isColorInput || info.prefersDraggingOverTextSelection
}

func representsSelectableContent(_ info: WebKit.InteractionInformationAtPosition) -> Bool {
    info.isSelectable() || info.isFocusableWithSelectableText()
}

func prefersDirectManipulation(_ info: WebKit.InteractionInformationAtPosition) -> Bool {
    info.isRangeInput || info.isARIASlider || info.hasDirectionalResizeCursor || info.isInResizeControl || info.isCustomSlider
        || WebKit.appKitGestureIsInteractiveModel(info)
}

func representsSecondaryClickableElement(_ info: WebKit.InteractionInformationAtPosition) -> Bool {
    if prefersDirectManipulation(info) {
        return false
    }

    if representsSelectableContent(info) {
        return true
    }

    if info.shouldTreatLongClickAsSecondaryClickQuirk {
        return true
    }

    if info.isImage {
        return true
    }

    return info.isOverVideo && info.selectability != WebKit.InteractionInformationAtPosition.Selectability.UnselectableDueToFocusableElement
}

// Converts like a C++ int cast on arm64: out-of-range values saturate and NaN becomes 0.
func saturatingInt32(fromAllowableMovement value: Double) -> Int32 {
    if value.isNaN {
        return 0
    }
    if value >= 2_147_483_647 {
        return .max
    }
    if value <= -2_147_483_648 {
        return .min
    }
    return Int32(value)
}

// The os_log channel `Logger.viewGestures` writes to (WebKit's ViewGestures channel). A log site asks it whether its
// level is enabled before reading the page or building its message. Keep in step with Logger.viewGestures.
let appKitGestureControllerViewGesturesLog = OSLog(subsystem: "com.apple.WebKit", category: "ViewGestures")

// A flag in a log line, written 1 or 0.
func appKitGestureLogInteger(_ flag: Bool) -> Int {
    flag ? 1 : 0
}

// `value` with two decimals, as "%.2f" writes it: rounded half to even on the exact binary value. Velocities are
// finite and small; the branches above 2^53 keep the output equal to printf's.
func appKitGestureLogFixedTwoDecimals(_ value: Double) -> String {
    let sign = value.sign == .minus ? "-" : ""
    if value.isNaN {
        return "nan"
    }
    let magnitude = value.magnitude
    if magnitude.isInfinite {
        return "\(sign)inf"
    }
    guard magnitude < 0x1p53 else {
        // Integral: the significand times a power of two, in base 10^9 limbs, least significant first.
        let exponent = Int(magnitude.exponent) - Double.significandBitCount
        let significand = UInt64(Double(sign: .plus, exponent: Double.significandBitCount, significand: magnitude.significand))
        var limbs: [UInt64] = [significand % 1_000_000_000, significand / 1_000_000_000]
        for _ in 0..<exponent {
            var carry: UInt64 = 0
            for index in limbs.indices {
                let doubled = limbs[index] * 2 + carry
                limbs[index] = doubled % 1_000_000_000
                carry = doubled / 1_000_000_000
            }
            if carry > 0 {
                limbs.append(carry)
            }
        }
        while limbs.count > 1 && limbs[limbs.count - 1] == 0 {
            limbs.removeLast()
        }
        var digits = "\(limbs[limbs.count - 1])"
        for limb in limbs.dropLast().reversed() {
            let text = "\(limb)"
            digits += String(repeating: "0", count: 9 - text.count) + text
        }
        return "\(sign)\(digits).00"
    }
    let integralPart = magnitude.rounded(.towardZero)
    let fraction = magnitude - integralPart
    var whole = UInt64(integralPart)
    var hundredths: UInt64 = 0
    if fraction > 0 {
        // fraction = scaled / 2^shift exactly; under 2^-61 it rounds to 0 hundredths.
        let shift = fraction.significandWidth - Int(fraction.exponent)
        if shift < 61 {
            let scaled = UInt64(Double(sign: .plus, exponent: shift, significand: fraction))
            let product = scaled * 100
            hundredths = product >> UInt64(shift)
            let remainder = product & ((1 << UInt64(shift)) - 1)
            let half: UInt64 = 1 << UInt64(shift - 1)
            if remainder > half || (remainder == half && hundredths & 1 == 1) {
                hundredths += 1
            }
            if hundredths == 100 {
                whole += 1
                hundredths = 0
            }
        }
    }
    return "\(sign)\(whole).\(hundredths < 10 ? "0" : "")\(hundredths)"
}

#endif // HAVE_APPKIT_GESTURES_SUPPORT
