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
import os
private import CxxStdlib
private import AppKit_Private.NSClickGestureRecognizer_Private
private import AppKit_Private.NSPanGestureRecognizer_Private
private import AppKit_Private.NSPressGestureRecognizer_Private
private import AppKit_Private.NSTouch_Private
private import WebCore_Private
import struct Swift.String

#if !ENABLE_MAC_GESTURE_EVENTS || !ENABLE_IMAGE_ANALYSIS || !ENABLE_TWO_PHASE_CLICKS
#error("WKAppKitGestureController assumes MAC_GESTURE_EVENTS, IMAGE_ANALYSIS and TWO_PHASE_CLICKS")
#endif

private func isSamePair(_ a: NSGestureRecognizer, _ b: NSGestureRecognizer, as x: NSGestureRecognizer?, _ y: NSGestureRecognizer?) -> Bool {
    (a === x && b === y) || (b === x && a === y)
}

private let scrollViewPanGestureClass: AnyClass? = NSClassFromString("NSScrollViewPanGestureRecognizer")

@MainActor
private func isBuiltInScrollViewPanGestureRecognizer(_ recognizer: NSGestureRecognizer?) -> Bool {
    guard let scrollViewPanGestureClass else {
        return false
    }
    return recognizer?.isKind(of: scrollViewPanGestureClass) ?? false
}

@MainActor
private func isBuiltInScrollViewMagnificationGestureRecognizer(_ gesture: NSGestureRecognizer) -> Bool {
    gesture is NSMagnificationGestureRecognizer && gesture._isScrollGestureRecognizer
}

@MainActor
private func isCatchingDeceleratingScroll(_ scrollViewPanGesture: NSGestureRecognizer?) -> Bool {
    guard let scrollView = scrollViewPanGesture?.view as? NSScrollView else {
        return false
    }

    // FIXME: The flag was recently renamed in rdar://185652893, so keep this selector check for a bit.
    guard scrollView.responds(to: #selector(NSScrollView._touchCaughtDeceleration)) else {
        return false
    }

    return scrollView._touchCaughtDeceleration()
}

@objc
@implementation
extension WKAppKitGestureController {
    @nonobjc
    private(set) final weak var view: WKWebView?

    @nonobjc
    private(set) final var panGestureRecognizer: NSPanGestureRecognizer?
    @nonobjc
    private final var primaryMouseTrackingGestureRecognizer: WKMouseTrackingGestureRecognizer?
    @nonobjc
    private final var secondaryMouseTrackingGestureRecognizer: WKMouseTrackingGestureRecognizer?

    @nonobjc
    private final var singleClickGestureRecognizer: NSPressGestureRecognizer?
    @nonobjc
    private(set) final var doubleClickGestureRecognizer: NSClickGestureRecognizer?
    @nonobjc
    private final var domDoubleClickGestureRecognizer: NSClickGestureRecognizer?

    // Auxiliary gesture recognizers to support context menus.
    @nonobjc
    private(set) final var secondaryClickGestureRecognizer: NSPressGestureRecognizer?
    @nonobjc
    private final var secondaryClickDeferringGestureRecognizer: WKDeferringGestureRecognizer?

    // Auxiliary gesture recognizers to support drag-and-drop.
    @nonobjc
    private final var textSelectionDragGesture: NSGestureRecognizer?
    @nonobjc
    private final var dragDeferringGestureRecognizer: WKDeferringGestureRecognizer?

    @nonobjc
    private final var enclosingScrollViewPanDeferringGestureRecognizer: WKDeferringGestureRecognizer?

    @nonobjc
    final var isMomentumActive = false
    @nonobjc
    final var lastPanWheelEventWasHandledByViewGestureController = false
    @nonobjc
    final var caughtDeceleratingScroll = false
    @nonobjc
    final var suppressNextPanScrollDelta = false

    @nonobjc
    private(set) final var isSuppressingSingleClickGestureForTextSelection = false

    @nonobjc
    final var layerTreeTransactionIdAtLastInteractionStart: WebKit.TransactionID?
    @nonobjc
    final var latestTapID: UInt64?
    @nonobjc
    private(set) final var clickHighlight: WKClickHighlightController?
    @nonobjc
    final let cxxSupport = WKAppKitGestureControllerCxxSupport()
    @nonobjc
    private final var uidOfTouchThatCaughtDeceleratingScroll: Int?

    // FIXME: Avoid bloat in WKAppKitGestureController by introducing a separate
    // gesture delegate that exclusively manages the mouse tracking recognizers.
    //
    // See mouseTrackingGestureRecognized(_:) where this state is used to transition
    // between tracking gestures when an active gesture's tracking conditions change.
    @nonobjc
    private final weak var activeMouseTrackingGestureRecognizer: WKMouseTrackingGestureRecognizer?
    @nonobjc
    private final var mouseTrackingHasSentMouseDown = false
    @nonobjc
    private final var mouseTrackingSendsMouseMoves = false
    @nonobjc
    private final var mayHaveHoverActivatedByClick = false
    @nonobjc
    private final var mouseTrackingStartLocationInWindow = WebCore.FloatPoint()
    @nonobjc
    private final var mouseTrackingIsSuppressedForTransformGesture = false
    @nonobjc
    private final var contentDeclinedTransformGesture = false
    @nonobjc
    private final var lastTransformGestureDriveTime: TimeInterval?

    @nonobjc
    private(set) final var dragPressGestureRecognizer: WKPressGestureRecognizer?

    @nonobjc
    private final var pointerTrackingGestureRecognizer: WKPointerTrackingGestureRecognizer?
    @nonobjc
    private final var pointerDownDeferringGestureRecognizer: WKDeferringGestureRecognizer?
    @nonobjc
    private final var isTrackingPointer = false
    @nonobjc
    private final var trackedPointerHasMoved = false
    @nonobjc
    private final var trackedPointerStartLocationInWindow = NSPoint.zero
    @nonobjc
    private final var trackedPointerLastLocationInWindow = NSPoint.zero

    @nonobjc
    private final var gestureDraggingSession: NSDraggingSession?
    @nonobjc
    private final var textSelectionDragCompletionHandler: ((NSDraggingSession) -> Void)?
    @nonobjc
    private final var dragGestureHasSentMouseDown = false
    @nonobjc
    private final var dragGestureDidReceiveDragStart = false
    @nonobjc
    private final var dragIdentifier: UInt64 = 0

    @nonobjc
    final var potentialTapIsInProgress = false

    @nonobjc
    private final var imageAnalysisGestureRecognizer: WKPressGestureRecognizer?
    @nonobjc
    private(set) final var imageAnalysisTextSelectionDeferringGestureRecognizer: WKDeferringGestureRecognizer?
    @nonobjc
    private(set) final var imageAnalysisDragAndContextMenuDeferringGestureRecognizer: WKDeferringGestureRecognizer?

    @nonobjc
    private final var lastCompletedImageAnalysis: CompletedImageAnalysis?
    @nonobjc
    final var imageAnalysisDeferralState = ImageAnalysisDeferralState.undecided

    @nonobjc
    final var fastScrollTracker = WKFastScrollTracker()
    @nonobjc
    final var directionalScrollLockTracker = WKDirectionalScrollLockTracker()

    @nonobjc
    private final var magnificationGestureRecognizer: NSMagnificationGestureRecognizer?
    @nonobjc
    private final var rotationGestureRecognizer: NSRotationGestureRecognizer?

    // FIXME: <webkit.org/b/321828> Avoid further bloating this class and instead manage state through a separate/independent entity.
    // Magnification and rotation GRs report their values cumulatively over a gesture.
    // These variables track the last reported value so that we can forward deltas.
    @nonobjc
    private final var lastCumulativeMagnification: Double = 0
    @nonobjc
    private final var lastCumulativeRotation: Double = 0

    @objc
    var webView: WKWebView? { view }
    @objc
    var everMagnifiedDuringCurrentGesture: Bool { hasEverMagnifiedDuringCurrentGesture }
    @nonobjc
    final var hasEverMagnifiedDuringCurrentGesture = false

    init(view: WKWebView) {
        self.view = view
        super.init()
        cxxSupport.controller = self
        clickHighlight = makeClickHighlightController()
    }

    func setUp() {
        guard view != nil else {
            return
        }

        cxxSupport.setUpPositionInformation()

        setUpGestureRecognizers()
        addGesturesToWebView()
        enableGesturesIfNeeded()
        ensureGesturesAreNotArchived()
    }

    func preferencesDidChange() {
        enableGesturesIfNeeded()
        if let panGestureRecognizer {
            configure(forScrolling: panGestureRecognizer)
        }
    }

    func beginSuppressingSingleClickGestureForTextSelection() {
        guard let webView = view else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .default), let page = webView._protectedPage().get() {
            Logger.viewGestures.log(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                Begin suppressing single-click gesture for text selection
                """
            )
        }

        isSuppressingSingleClickGestureForTextSelection = true

        handleTapCancelled()
        webView._protectedPage().get()?.cancelPotentialTap()
    }

    func endSuppressingSingleClickGestureForTextSelection() {
        guard let webView = view else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .default), let page = webView._protectedPage().get() {
            Logger.viewGestures.log(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                End suppressing single-click gesture for text selection
                """
            )
        }

        isSuppressingSingleClickGestureForTextSelection = false
    }

    func didCommitLoadForMainFrame() {
        cxxSupport.invalidatePositionInformation()
        resetDOMDoubleClickGestureRecognizer()
        layerTreeTransactionIdAtLastInteractionStart = nil
        lastCompletedImageAnalysis = nil
        isTrackingPointer = false
    }

    func interruptMomentumForScrollWheelEvent() {
        cxxSupport.interruptMomentum()
    }

    @objc(gestureRecognizer:shouldReceiveTouch:)
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldReceive touch: NSTouch) -> Bool {
        guard let webView = view else {
            return false
        }

        guard let impl = webView._impl(), !impl.ignoresAllEvents() else {
            return false
        }

        interruptMomentumIfNeeded(for: touch)

        if gestureRecognizer === panGestureRecognizer {
            let allowedAxes = touchActionsAllowedPanningAxes(at: touch.location(in: webView))
            panGestureRecognizer?._canPanHorizontally = allowedAxes.contains(.horizontal)
            panGestureRecognizer?._canPanVertically = allowedAxes.contains(.vertical)
        }

        return true
    }

    @objc(gestureRecognizer:shouldAttemptToRecognizeWithEvent:)
    func gestureRecognizer(_ gesture: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        // Every GR we maintain is exclusively direct touch-only, so we can unconditionally return false here.
        // This delegate implementation is only necessary for the magnification and rotation GRs since they
        // can not be configured as a (buttonMask + allowedTouchTypes) pair like the other gestures.

        // FIXME: <rdar://166268811> Migrate towards API (once available) that configures magnification/rotation GRs as touch-only.
        false
    }

    // MARK: Gesture Recognition

    @objc
    private func panGestureRecognized(_ gesture: NSGestureRecognizer) {
        guard let webView = view else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                \(Self.loggingDescription(for: gesture), privacy: .private)
                """
            )
        }

        precondition(panGestureRecognizer === gesture)

        guard let impl = webView._impl(), let panGestureRecognizer else {
            return
        }

        if impl.ignoresAllEvents() {
            if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                Logger.viewGestures.debug("[pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): Ignored gesture")
            }
            return
        }

        if gesture.state == .began {
            cancelPointerTrackingIfNeeded()
            impl.dismissContentRelativeChildWindowsWithAnimation(false)
            fastScrollTracker.didStartGesture(atLocation: gesture.location(in: nil))
            directionalScrollLockTracker.didStartGesture()
        }

        #if HAVE_NSREFRESHCONTROLLER
        impl.updateRefreshControllerForPanGesture(gesture.state, refreshControllerEligibility(panGestureRecognizer))
        #endif

        sendWheelEvent(for: panGestureRecognizer)
        startMomentumIfNeeded(for: panGestureRecognizer)

        switch gesture.state {
        case .ended, .cancelled, .failed:
            // After the wheel and momentum events above, so both still see this gesture's locked axis.
            directionalScrollLockTracker.didEndGesture()
            resetCaughtDeceleratingScroll()
        default:
            break
        }
    }

    @objc
    private func singleClickGestureRecognized(_ gesture: NSGestureRecognizer) {
        guard let webView = view else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                \(Self.loggingDescription(for: gesture), privacy: .private)
                """
            )
        }

        precondition(singleClickGestureRecognizer === gesture)

        guard let impl = webView._impl(), !impl.ignoresAllEvents() else {
            return
        }

        if caughtDeceleratingScroll {
            // This gesture is interrupting a decelerating scroll; it should stop the scroll (and may
            // turn into a pan) but must never perform a click.
            switch gesture.state {
            case .ended, .cancelled, .failed:
                resetCaughtDeceleratingScroll()
                handleTapCancelled()
            default:
                break
            }
            return
        }

        // Clicks aren't delivered to NSButton's built-in click gesture
        // recognizer when a parent view's GR recognizes first, so we
        // forward the click manually.
        if let page = webView._protectedPage().get(), !page.preferences().useAlternatePDFHUD(), gesture.state == .began,
            let hitView = impl.hitTestPDFHUD(WebCore.FloatPoint(gesture.location(in: webView))).get(), impl.isViewVisible(hitView)
        {
            (hitView as? NSButton)?.performClick(nil)
            gesture.state = .cancelled
            return
        }

        switch gesture.state {
        case .began:
            handleTapBegan(gesture)
        case .ended:
            handleTapEnded(gesture)
        case .cancelled, .failed:
            handleTapCancelled()
        default:
            break
        }
    }

    @objc
    private func doubleClickGestureRecognized(_ gesture: NSGestureRecognizer) {
        guard let webView = view else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                \(Self.loggingDescription(for: gesture), privacy: .private)
                """
            )
        }

        precondition(doubleClickGestureRecognizer === gesture)

        guard let impl = webView._impl() else {
            return
        }
        impl.dismissContentRelativeChildWindowsWithAnimation(false)

        let magnificationOrigin = webView.convert(gesture.location(in: nil), from: nil)
        impl.handleSmartMagnificationGestureOnViewGestureController(WebCore.FloatPoint(magnificationOrigin))
    }

    @objc
    private func domDoubleClickGestureRecognized(_ gesture: NSGestureRecognizer) {
        guard let webView = view else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                \(Self.loggingDescription(for: gesture), privacy: .private)
                """
            )
        }

        precondition(domDoubleClickGestureRecognizer === gesture)

        // The single-click gesture may have already committed this click as a double click.
        guard takeCompletedDOMDoubleClick() else {
            return
        }

        guard let impl = webView._impl(), !impl.ignoresAllEvents() else {
            return
        }

        let location = gesture.location(in: webView)

        if layerTreeTransactionIdAtLastInteractionStart == nil {
            updateLayerTreeTransactionIdAtLastInteractionStart()
        }

        guard let layerTreeTransactionIdAtLastInteractionStart else {
            return
        }

        let modifiers = WebKit.WebEventFactory.toWebEventModifierFlags(gesture.modifierFlags)

        webView._protectedPage().get()?
            .handleDoubleTapForDoubleClickAtPoint(
                WebCore.roundedIntPoint(location),
                modifiers,
                layerTreeTransactionIdAtLastInteractionStart,
                .Touch,
                .OneFingerTap
            )
    }

    @objc
    private func secondaryClickGestureRecognized(_ gesture: NSGestureRecognizer) {
        guard let webView = view else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                \(Self.loggingDescription(for: gesture), privacy: .private)
                """
            )
        }

        precondition(secondaryClickGestureRecognizer === gesture)

        guard gesture.state == .began else {
            return
        }

        handleTapCancelled()
        cancelPointerTrackingIfNeeded()

        let modifierFlags = gesture.modifierFlags
        let location = gesture.location(in: nil)
        guard let impl = webView._impl() else {
            return
        }
        let windowNumber = impl.windowNumber()

        let mouseDown = syntheticMouseEvent(
            .rightMouseDown,
            at: location,
            modifierFlags: modifierFlags,
            windowNumber: windowNumber,
            pressure: 1
        )
        impl.mouseDown(mouseDown, .Touch, .Yes)

        let mouseUp = syntheticMouseEvent(
            .rightMouseUp,
            at: location,
            modifierFlags: modifierFlags,
            windowNumber: windowNumber,
            pressure: 0
        )
        impl.mouseUp(mouseUp, .Touch, .Yes)
    }

    func transformGestureWasNotHandledByContent() {
        guard isRecognizingTransformGesture else {
            return
        }

        contentDeclinedTransformGesture = true
        transformGestureDidDrive()
    }

    @objc
    private func mouseTrackingGestureRecognized(_ gesture: NSGestureRecognizer) {
        guard let webView = view else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                \(Self.loggingDescription(for: gesture), privacy: .private)
                """
            )
        }

        let stateAtEntry = gesture.state
        defer {
            if caughtDeceleratingScroll {
                switch stateAtEntry {
                case .ended, .cancelled, .failed:
                    resetCaughtDeceleratingScroll()
                default:
                    break
                }
            }
        }

        if dragGestureHasSentMouseDown {
            if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                Logger.viewGestures.debug(
                    """
                    [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                    Exiting early because _dragGestureHasSentMouseDown is true
                    """
                )
            }
            return
        }

        if isSuppressingSingleClickGestureForTextSelection {
            if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                Logger.viewGestures.debug(
                    """
                    [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                    Exiting early because _isSuppressingSingleClickGestureForTextSelection is true
                    """
                )
            }
            return
        }

        guard let mouseTrackingGesture = gesture as? WKMouseTrackingGestureRecognizer else {
            preconditionFailure("Mouse tracking action from another recognizer")
        }

        guard let impl = webView._impl(), !impl.ignoresAllEvents() else {
            return
        }

        let modifierFlags = gesture.modifierFlags
        let windowNumber = impl.windowNumber()
        let timestamp = GetCurrentEventTime()

        switch gesture.state {
        case .began:
            mouseTrackingIsSuppressedForTransformGesture = false
            activeMouseTrackingGestureRecognizer = mouseTrackingGesture
            if mouseTrackingHasSentMouseDown {
                mouseTrackingGesture.beginTrackingMouseInherited(
                    fromWindowLocation: NSPoint(
                        x: CGFloat(mouseTrackingStartLocationInWindow.x()),
                        y: CGFloat(mouseTrackingStartLocationInWindow.y())
                    )
                )
            } else {
                mouseTrackingGesture.beginTrackingMouse()
            }

        case .changed:
            guard activeMouseTrackingGestureRecognizer === mouseTrackingGesture else {
                break
            }

            if shouldSuppressMouseTrackingForTransformGesture() {
                mouseTrackingIsSuppressedForTransformGesture = true
                break
            }

            if !mouseTrackingHasSentMouseDown && !mouseTrackingSendsMouseMoves {
                // Either the synthetic single-click path or this mouse-tracking path delivers a mouse
                // down for a given interaction, but never both. An event that stays within the single-click
                // gesture's allowable movement is a click: that gesture stays alive and, when it ends, the
                // synthetic click path delivers the mouse down, mouse up, and click.
                // Only once the event moves past that threshold — at which point the single-click gesture
                // cancels and this becomes a drag — does mouse tracking take over event delivery. Sending a
                // mouse down here for a stationary click would deliver a second mouse down to the content,
                // which should be avoided.
                guard movementExceedsClickAllowableMovement(mouseTrackingGesture.movementInWindowSinceStart) else {
                    break
                }

                let isResumingAfterTransformGesture = mouseTrackingIsSuppressedForTransformGesture
                mouseTrackingIsSuppressedForTransformGesture = false
                let mouseDownLocation =
                    isResumingAfterTransformGesture
                    ? mouseTrackingGesture.mouseLocationInWindow
                    : mouseTrackingGesture.startLocationInWindow

                if isResumingAfterTransformGesture {
                    mouseTrackingGesture.beginReportingMovement(fromWindowLocation: mouseDownLocation)
                }

                if isHoverActivatedByClick(at: webView.convert(mouseDownLocation, from: nil)) {
                    mouseTrackingSendsMouseMoves = true
                } else {
                    let mouseDown = syntheticMouseEvent(
                        .leftMouseDown,
                        at: adjustedMouseDownLocation(inWindow: mouseDownLocation),
                        modifierFlags: modifierFlags,
                        timestamp: timestamp,
                        windowNumber: windowNumber,
                        pressure: 1
                    )
                    impl.mouseDown(mouseDown, .Touch, .No)
                    mouseTrackingHasSentMouseDown = true
                }
            }

            if mouseTrackingSendsMouseMoves {
                let locationInWindow = mouseTrackingGesture.mouseLocationInWindow
                let mouseMoved = syntheticMouseEvent(
                    .mouseMoved,
                    at: locationInWindow,
                    modifierFlags: modifierFlags,
                    timestamp: timestamp,
                    windowNumber: windowNumber,
                    clickCount: 0,
                    pressure: 0,
                    reportingMovementFor: mouseTrackingGesture
                )
                impl.mouseMoved(mouseMoved, .Touch)
                break
            }

            let locationInWindow = mouseTrackingGesture.mouseLocationInWindow
            let mouseDragged = syntheticMouseEvent(
                .leftMouseDragged,
                at: locationInWindow,
                modifierFlags: modifierFlags,
                timestamp: timestamp,
                windowNumber: windowNumber,
                pressure: 1,
                reportingMovementFor: mouseTrackingGesture
            )
            impl.mouseDragged(mouseDragged, .Touch, .No)

        case .ended, .cancelled, .failed:
            guard activeMouseTrackingGestureRecognizer === mouseTrackingGesture else {
                break
            }

            activeMouseTrackingGestureRecognizer = nil

            if mouseTrackingSendsMouseMoves {
                mouseTrackingSendsMouseMoves = false
                break
            }

            if mouseTrackingWillBeHandedOff() {
                if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                    Logger.viewGestures.debug(
                        """
                        [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                        Handing off mouse tracking to another gesture
                        """
                    )
                }
                mouseTrackingStartLocationInWindow = WebCore.FloatPoint(mouseTrackingGesture.mouseLocationInWindow)
                break
            }

            if mouseTrackingHasSentMouseDown {
                mouseTrackingHasSentMouseDown = false
                let locationInWindow = mouseTrackingGesture.mouseLocationInWindow
                let mouseUp = syntheticMouseEvent(
                    .leftMouseUp,
                    at: locationInWindow,
                    modifierFlags: modifierFlags,
                    timestamp: timestamp,
                    windowNumber: windowNumber,
                    pressure: 0,
                    reportingMovementFor: mouseTrackingGesture
                )
                impl.mouseUp(mouseUp, .Touch, .No)
            }

        default:
            break
        }
    }

    // MARK: Pointer Tracking

    @objc(pointerTrackingGestureRecognizer:didUpdateTouchWithState:locationInWindow:modifierFlags:)
    func pointerTrackingGestureRecognizer(
        _ gestureRecognizer: WKPointerTrackingGestureRecognizer,
        didUpdateTouchWith state: NSGestureRecognizer.State,
        locationInWindow: NSPoint,
        modifierFlags: NSEvent.ModifierFlags
    ) {
        guard let webView = view else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                \(Self.loggingDescription(for: gestureRecognizer), privacy: .private) touch state \
                \(Int32(truncatingIfNeeded: state.rawValue)) at \(NSStringFromPoint(locationInWindow), privacy: .private)
                """
            )
        }

        switch state {
        case .began:
            cancelPointerTrackingIfNeeded()

            if webView._impl()?.ignoresAllEvents() ?? true {
                break
            }

            let locationInView = webView.convert(locationInWindow, from: nil)
            if !pointerTrackingShouldBegin(at: locationInView, modifierFlags: modifierFlags) {
                // The page must not treat the click that follows as the release of the last tracked touch.
                if isHoverActivatedByClick(at: locationInView) {
                    dispatchTrackedPointerEvent(
                        .Cancelled,
                        atLocationInWindow: locationInWindow,
                        modifierFlags: modifierFlags
                    )
                }
                break
            }

            isTrackingPointer = true
            trackedPointerHasMoved = false
            trackedPointerStartLocationInWindow = locationInWindow
            trackedPointerLastLocationInWindow = locationInWindow
            dispatchTrackedPointerEvent(.Began, atLocationInWindow: locationInWindow, modifierFlags: modifierFlags)

        case .changed:
            guard isTrackingPointer else {
                break
            }

            trackedPointerLastLocationInWindow = locationInWindow

            // Report no movement until the touch has moved too far to be a tap, so that a
            // touch that is held still reads as still.
            if !trackedPointerHasMoved {
                let movementInWindow = NSSize(
                    width: locationInWindow.x - trackedPointerStartLocationInWindow.x,
                    height: locationInWindow.y - trackedPointerStartLocationInWindow.y
                )
                guard movementExceedsClickAllowableMovement(movementInWindow) else {
                    break
                }
                trackedPointerHasMoved = true
            }

            dispatchTrackedPointerEvent(.Changed, atLocationInWindow: locationInWindow, modifierFlags: modifierFlags)

        case .ended:
            guard isTrackingPointer else {
                break
            }
            isTrackingPointer = false

            dispatchTrackedPointerEvent(
                .Ended,
                atLocationInWindow: trackedPointerHasMoved ? locationInWindow : trackedPointerStartLocationInWindow,
                modifierFlags: modifierFlags
            )

        case .cancelled:
            cancelPointerTrackingIfNeeded()

        default:
            break
        }
    }

    @objc
    private func pointerTrackingGestureRecognized(_ gesture: NSGestureRecognizer) {
        guard let webView = view else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                \(Self.loggingDescription(for: gesture), privacy: .private)
                """
            )
        }

        precondition(pointerTrackingGestureRecognizer === gesture)

        switch gesture.state {
        case .cancelled, .failed:
            cancelPointerTrackingIfNeeded()
        default:
            break
        }
    }

    // MARK: Image Analysis

    // Gesture-driven Live Text is arbitrated by three recognizers, plus ImageAnalysisGestureDeferralToken:
    //
    //   1. imageAnalysisGestureRecognizer (the "preflight") -- a settled 0.1s press that kicks off Vision
    //      image analysis. It's a passive observer of the interaction it measures: it recognizes
    //      simultaneously with everything, prevents nothing, and is always allowed to begin.
    //   2. imageAnalysisTextSelectionDeferringGestureRecognizer -- holds the text-selection gestures over an image until
    //      analysis resolves.
    //   3. imageAnalysisDragAndContextMenuDeferringGestureRecognizer -- holds the drag-press and secondary-click
    //      (context menu) recognizers over an image until analysis resolves.
    //
    // The two deferrals resolve to *opposite* booleans (see resolveImageAnalysisDeferrals(with:)):
    // on "text found" we must ALLOW text selection while PREVENTING drag / context menu (Live Text wins),
    // and the reverse on "no text". A single WKDeferringGestureRecognizer can't express that -- its
    // endDeferralShouldPreventGestures(_:) applies one boolean (state = .ended / .failed) to everything it
    // defers -- so the two opposite outcomes require two separate deferrals.
    //
    // iOS needs no fallback deferral because its drag / context menu are UIKit interactions gated by a
    // ProceedWithTextSelectionInImage callback. macOS drag-press / secondary-click are NSGestureRecognizers
    // on independent timers, so they must be *deferred* to keep them from firing before analysis resolves.

    @objc
    private func imageAnalysisGestureRecognized(_ gesture: NSGestureRecognizer) {
        guard let webView = view else {
            return
        }

        precondition(imageAnalysisGestureRecognizer === gesture)

        guard gesture.state == .began else {
            return
        }

        guard let impl = webView._impl(), !impl.ignoresAllEvents() else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .default), let page = webView._protectedPage().get() {
            Logger.viewGestures.log(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                \(Self.loggingDescription(for: gesture), privacy: .private)
                """
            )
        }

        var request = positionInformationRequest(at: gesture.location(in: webView))
        request.includeImageData = true

        // The token keeps the image-analysis deferral open until the async analysis chain finishes (or is
        // abandoned). Capturing it through each stage means the deferral resolves exactly when the last
        // stage completes; dropping it early (e.g. not an image) resolves it as "allow text selection".
        let gestureDeferralToken = ImageAnalysisGestureDeferralToken(controller: self)
        cxxSupport.preflightImageAnalysis(request) { [weak self] foundText, element in
            let outcome: ImageAnalysisDeferralOutcome = foundText ? .foundText : .noText

            gestureDeferralToken.outcome = outcome

            if let self {
                self.lastCompletedImageAnalysis = CompletedImageAnalysis(element: element, outcome: outcome)
            }
        }
    }

    // MARK: WKPressGestureRecognizerDelegate

    func pressGestureRecognizerDidFail(_ gestureRecognizer: WKPressGestureRecognizer) {
        guard gestureRecognizer === imageAnalysisGestureRecognizer else {
            return
        }

        // Similar to iOS's -imageAnalysisGestureDidFail: if the initial gesture fails, resolve our deferrals immediately.
        if imageAnalysisDeferralState != .deferring {
            imageAnalysisDeferralState = .gestureFailed
            return
        }

        if Logger.viewGestures.isEnabled(type: .default), let webView = view, let page = webView._protectedPage().get() {
            Logger.viewGestures.log(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                Image analysis preflight failed; releasing image-analysis deferrals
                """
            )
        }

        resolveImageAnalysisDeferrals(with: .notApplicable)
    }

    // MARK: Drag Handling

    @objc
    private func dragPressGestureRecognized(_ gesture: NSGestureRecognizer) {
        guard let webView = view else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                \(Self.loggingDescription(for: gesture), privacy: .private)
                """
            )
        }

        guard let dragPressGestureRecognizer, dragPressGestureRecognizer === gesture else {
            return
        }

        guard let impl = webView._impl() else {
            return
        }

        if impl.ignoresAllEvents() {
            if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                Logger.viewGestures.debug("[pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): Ignored gesture")
            }
            return
        }

        let modifierFlags = gesture.modifierFlags
        let locationInWindow = gesture.location(in: nil)
        let windowNumber = impl.windowNumber()
        let timestamp = GetCurrentEventTime()

        switch gesture.state {
        case .began:
            handleTapCancelled()
            dragGestureHasSentMouseDown = false
            dragGestureDidReceiveDragStart = false
            dragIdentifier &+= 1

            let mouseDown = syntheticMouseEvent(
                .leftMouseDown,
                at: locationInWindow,
                modifierFlags: modifierFlags,
                timestamp: timestamp,
                windowNumber: windowNumber,
                pressure: 1
            )
            impl.mouseDown(mouseDown, .Touch, .Yes)
            dragGestureHasSentMouseDown = true

            dragPressGestureRecognizer.beginReportingMovement(fromWindowLocation: locationInWindow)

        case .changed:
            guard dragGestureHasSentMouseDown else {
                break
            }
            // Drive WebCore's drag-initiation hysteresis. Once the session exists, AppKit tracks the
            // gesture itself and WebCore is driven by the platform drag callbacks, so we stop feeding it.
            if gestureDraggingSession == nil {
                let mouseDragged = syntheticMouseEvent(
                    .leftMouseDragged,
                    at: locationInWindow,
                    modifierFlags: modifierFlags,
                    timestamp: timestamp,
                    windowNumber: windowNumber,
                    pressure: 1,
                    reportingMovementFor: dragPressGestureRecognizer
                )
                impl.mouseDragged(mouseDragged, .Touch, .Yes)
            }

        case .ended, .cancelled, .failed:
            guard dragGestureHasSentMouseDown else {
                break
            }

            let mouseUp = syntheticMouseEvent(
                .leftMouseUp,
                at: locationInWindow,
                modifierFlags: modifierFlags,
                timestamp: timestamp,
                windowNumber: windowNumber,
                pressure: 0,
                reportingMovementFor: dragPressGestureRecognizer
            )
            impl.mouseUp(mouseUp, .Touch, .Yes)

            // Normally, drag state is cleared in draggingSessionEnded: (normal completion) or in startDrag() when
            // beginDraggingSessionWithItems:gesture: returns nil (gesture ended before session started).
            // But, if the page prevents dragstart, we won't get startDrag(), so clear the state ourselves.
            cxxSupport.doAfterProcessingAllPendingMouseEvents { [weak self, dragIdentifier = self.dragIdentifier] in
                guard let self, self.dragIdentifier == dragIdentifier else {
                    return
                }
                if !self.dragGestureHasSentMouseDown || self.dragGestureDidReceiveDragStart || self.gestureDraggingSession != nil {
                    return
                }
                self.dragGestureHasSentMouseDown = false
            }

        default:
            break
        }
    }

    // MARK: Two-Phase Click Response Handlers

    @objc(potentialTapInProgress)
    var isPotentialTapInProgress: Bool {
        @objc(isPotentialTapInProgress)
        get { potentialTapIsInProgress }
    }

    var clickHighlightController: WKClickHighlightController? { clickHighlight }

    func commitPotentialTapFailed() {
        guard let webView = view else {
            return
        }

        handleTapCancelled()

        if Logger.viewGestures.isEnabled(type: .error), let page = webView._protectedPage().get() {
            Logger.viewGestures.error("[pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): Commit potential tap failed")
        }
    }

    func didCompleteSyntheticClick() {
        guard let webView = view else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .default), let page = webView._protectedPage().get() {
            Logger.viewGestures.log("[pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): Synthetic click completed")
        }

        let hasHoverActivatedByClick = webView._protectedPage().get()?.hoverActivatedByClickBounds().has_value() ?? false
        let hadHoverActivatedByClick = mayHaveHoverActivatedByClick
        mayHaveHoverActivatedByClick = hasHoverActivatedByClick
        if hadHoverActivatedByClick || hasHoverActivatedByClick {
            cxxSupport.invalidatePositionInformation()
        }
    }

    func didHandleTapAsHover() {
        guard let webView = view else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .default), let page = webView._protectedPage().get() {
            Logger.viewGestures.log("[pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): Tap was handled as hover")
        }

        mayHaveHoverActivatedByClick = true
        cxxSupport.invalidatePositionInformation()
    }

    func disableDoubleTapGesturesDuringTapIfNecessary(forRequest requestID: UInt64) {
        guard latestTapID == requestID else {
            return
        }

        setDoubleTapGesturesEnabled(false)
    }

    @objc(didNotHandleTapAsClickAtPoint:)
    func didNotHandleTapAsClick(at point: NSPoint) {
        guard let webView = view else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .default), let page = webView._protectedPage().get() {
            Logger.viewGestures.log(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                Tap at (\(Int32(point.x)), \(Int32(point.y))) was not handled as click
                """
            )
        }

        // FIXME: Consider smart magnification here if a double tap is pending and the point hasn't moved significantly.
    }

    // MARK: Magnification and Rotation

    @objc
    private func magnificationGestureRecognized(_ gesture: NSMagnificationGestureRecognizer) {
        guard let webView = view else {
            return
        }

        let phase = WebKit.WebEventPhase(gesture.state)
        let magnification = currentMagnification(gesture.magnification, atPhase: phase)

        if phase == .Began || phase == .Changed {
            transformGestureDidDrive()
        } else {
            transformGestureDidEnd()
        }

        let initValue = WebKit.NativeWebGestureEvent.Init(
            kind: .Magnification,
            phase: phase,
            locationInWindow: gestureCentroidInWindow(for: gesture),
            gestureScale: Float(magnification),
            gestureRotation: 0,
            timestamp: WebKit.appKitGestureMonotonicTimeFromRawSeconds(GetCurrentEventTime()),
            allowsNativeZoom: magnificationGestureRecognizerCanZoom,
            inputSource: .Touch
        )
        let webEvent = WebKit.NativeWebGestureEvent.create(initValue, webView).get()

        guard let viewImpl = webView._impl() else {
            return
        }

        if !viewImpl.allowsMagnification() {
            if let webEvent {
                webView._protectedPage().get()?.handleGestureEvent(consuming: .init(webEvent))
            }
            return
        }

        if phase == .Began {
            viewImpl.dismissContentRelativeChildWindowsWithAnimation(false)
        }

        let origin = webEvent.map { WebCore.FloatPoint($0.position()) } ?? WebCore.FloatPoint()
        if viewImpl.handleMagnificationGestureIfMagnifying(magnification, phase, origin, .Touch) {
            return
        }

        if let webEvent {
            webView._protectedPage().get()?.handleGestureEvent(consuming: .init(webEvent))
        }
    }

    @objc
    private func rotationGestureRecognized(_ gesture: NSRotationGestureRecognizer) {
        guard let webView = view else {
            return
        }

        let phase = WebKit.WebEventPhase(gesture.state)

        if phase == .Began || phase == .Changed {
            transformGestureDidDrive()
        } else {
            transformGestureDidEnd()
        }

        let initValue = WebKit.NativeWebGestureEvent.Init(
            kind: .Rotation,
            phase: phase,
            locationInWindow: gestureCentroidInWindow(for: gesture),
            gestureScale: 0,
            gestureRotation: Float(currentRotation(gesture.rotationInDegrees, atPhase: phase)),
            timestamp: WebKit.appKitGestureMonotonicTimeFromRawSeconds(GetCurrentEventTime()),
            allowsNativeZoom: true,
            inputSource: .Touch
        )
        if let event = WebKit.NativeWebGestureEvent.create(initValue, webView).get() {
            webView._protectedPage().get()?.handleGestureEvent(consuming: .init(event))
        }
    }

    // MARK: Drag Gesture State

    func activeDragGestureRecognizer() -> NSGestureRecognizer? {
        if let textSelectionDragGesture {
            return textSelectionDragGesture
        }
        if dragGestureHasSentMouseDown {
            return dragPressGestureRecognizer
        }
        return nil
    }

    func setTextSelectionDragGesture(_ gesture: NSGestureRecognizer, completionHandler: @escaping (NSDraggingSession) -> Void) {
        if let textSelectionDragGesture {
            if Logger.viewGestures.isEnabled(type: .error), let view, let page = view._protectedPage().get() {
                Logger.viewGestures.error(
                    """
                    [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                    Replacing prior text-selection drag gesture \
                    \(Self.loggingDescription(for: textSelectionDragGesture), privacy: .private) (completion handler set: \
                    \(appKitGestureLogInteger(self.textSelectionDragCompletionHandler != nil))); prior drag never reached \
                    setGestureDraggingSession:
                    """
                )
            }
            assertionFailure("A text selection drag gesture is already set")
        }

        textSelectionDragGesture = gesture
        textSelectionDragCompletionHandler = completionHandler
    }

    func didReceiveDragStart() {
        dragGestureDidReceiveDragStart = true
    }

    func setGestureDraggingSession(_ session: NSDraggingSession?) {
        gestureDraggingSession = session
        guard let session else {
            return
        }

        cancelPointerTrackingIfNeeded()

        if Logger.viewGestures.isEnabled(type: .default), let view, let page = view._protectedPage().get() {
            Logger.viewGestures.log("[pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): Drag session began")
        }

        if let handler = textSelectionDragCompletionHandler.take() {
            handler(session)
        }
    }

    func clearGestureDragState() {
        gestureDraggingSession = nil
        textSelectionDragGesture = nil
        textSelectionDragCompletionHandler = nil
        dragGestureHasSentMouseDown = false
        dragGestureDidReceiveDragStart = false
    }

    func cancelClickHighlight() {
        clickHighlight?.cancel()
    }

    func reset() {
        clearGestureDragState()
        handleTapCancelled()
        cancelPointerTrackingIfNeeded()
        activeMouseTrackingGestureRecognizer = nil
        mouseTrackingHasSentMouseDown = false
        mouseTrackingIsSuppressedForTransformGesture = false
        contentDeclinedTransformGesture = false
        lastTransformGestureDriveTime = nil
        cxxSupport.resetMomentum()
        mouseTrackingSendsMouseMoves = false
        mayHaveHoverActivatedByClick = false
        isMomentumActive = false
        resetCaughtDeceleratingScroll()
        resetDOMDoubleClickGestureRecognizer()
        fastScrollTracker.reset()
        directionalScrollLockTracker.reset()
        isSuppressingSingleClickGestureForTextSelection = false
        latestTapID = nil
        layerTreeTransactionIdAtLastInteractionStart = nil
        lastCompletedImageAnalysis = nil
        cxxSupport.resetPositionInformation()
    }

    // MARK: NSGestureRecognizerDelegate

    @objc(gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:)
    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        guard let webView = view else {
            return false
        }

        if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                Gesture: \(Self.loggingDescription(for: gestureRecognizer), privacy: .private), Other gesture: \
                \(Self.loggingDescription(for: otherGestureRecognizer), privacy: .private)
                """
            )
        }

        if isSamePair(gestureRecognizer, otherGestureRecognizer, as: singleClickGestureRecognizer, panGestureRecognizer) {
            return true
        }

        if isSamePair(gestureRecognizer, otherGestureRecognizer, as: magnificationGestureRecognizer, panGestureRecognizer) {
            return true
        }

        if isSamePair(gestureRecognizer, otherGestureRecognizer, as: rotationGestureRecognizer, panGestureRecognizer) {
            return true
        }

        if isSamePair(gestureRecognizer, otherGestureRecognizer, as: magnificationGestureRecognizer, rotationGestureRecognizer) {
            return true
        }

        if gestureRecognizer is WKDeferringGestureRecognizer || otherGestureRecognizer is WKDeferringGestureRecognizer {
            return true
        }

        // Live Text (see the Image Analysis design note): the preflight is a passive observer, so it
        // recognizes simultaneously with everything -- it must never block, or be blocked by, the
        // interaction it measures.
        if gestureRecognizer === imageAnalysisGestureRecognizer || otherGestureRecognizer === imageAnalysisGestureRecognizer {
            return true
        }

        if gestureRecognizer === pointerTrackingGestureRecognizer || otherGestureRecognizer === pointerTrackingGestureRecognizer {
            return true
        }

        if gestureRecognizer === domDoubleClickGestureRecognizer || otherGestureRecognizer === domDoubleClickGestureRecognizer {
            return true
        }

        if isMouseTrackingGestureRecognizer(gestureRecognizer)
            && shouldRecognizeSimultaneouslyWithMouseTrackingGesture(otherGestureRecognizer)
        {
            return true
        }

        if isMouseTrackingGestureRecognizer(otherGestureRecognizer)
            && shouldRecognizeSimultaneouslyWithMouseTrackingGesture(gestureRecognizer)
        {
            return true
        }

        if isSamePair(gestureRecognizer, otherGestureRecognizer, as: dragPressGestureRecognizer, singleClickGestureRecognizer) {
            return true
        }

        if gestureRecognizer === singleClickGestureRecognizer
            && isBuiltInScrollViewPanGestureRecognizer(otherGestureRecognizer)
            && otherGestureRecognizer.view is NSScrollView
            && !isCatchingDeceleratingScroll(otherGestureRecognizer)
        {
            return true
        }

        // Allow the single click GR to be simultaneously recognized with any of those from the text
        // selection manager.
        if gestureRecognizer === singleClickGestureRecognizer {
            return Self.isTextSelectionGesture(otherGestureRecognizer, of: webView)
        }

        if otherGestureRecognizer === singleClickGestureRecognizer {
            return Self.isTextSelectionGesture(gestureRecognizer, of: webView)
        }

        return false
    }

    @objc(gestureRecognizer:shouldBeRequiredToFailByGestureRecognizer:)
    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        guard let webView = view else {
            return false
        }

        if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                Gesture: \(Self.loggingDescription(for: gestureRecognizer), privacy: .private), Other gesture: \
                \(Self.loggingDescription(for: otherGestureRecognizer), privacy: .private)
                """
            )
        }

        if let deferringGestureRecognizer = gestureRecognizer as? WKDeferringGestureRecognizer {
            return deferringGestureRecognizer.shouldDefer(otherGestureRecognizer)
        }

        // Fail any gestures from the text selection manager if the secondary click GR handles them.
        return gestureRecognizer === secondaryClickGestureRecognizer && Self.isTextSelectionGesture(otherGestureRecognizer, of: webView)
    }

    @objc(gestureRecognizer:shouldRequireFailureOfGestureRecognizer:)
    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        guard let webView = view else {
            return false
        }

        if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                Gesture: \(Self.loggingDescription(for: gestureRecognizer), privacy: .private), Other gesture: \
                \(Self.loggingDescription(for: otherGestureRecognizer), privacy: .private)
                """
            )
        }

        if gestureRecognizer === singleClickGestureRecognizer && otherGestureRecognizer === doubleClickGestureRecognizer {
            return true
        }

        if isMouseTrackingGestureRecognizer(gestureRecognizer) && otherGestureRecognizer === panGestureRecognizer {
            let panCanScroll = panGestureRecognizerCanScroll
            if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                Logger.viewGestures.debug(
                    """
                    [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                    Mouse tracking requires pan to fail: \(appKitGestureLogInteger(panCanScroll))
                    """
                )
            }
            return panCanScroll
        }

        return false
    }

    @objc(gestureRecognizerShouldBegin:)
    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        guard let webView = view else {
            return false
        }

        if gestureRecognizer === pointerTrackingGestureRecognizer {
            return pointerTrackingShouldBegin(
                at: gestureRecognizer.location(in: webView),
                modifierFlags: gestureRecognizer.modifierFlags
            )
        }

        if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                Gesture: \(Self.loggingDescription(for: gestureRecognizer), privacy: .private)
                """
            )
        }

        let locationInViewCoordinates =
            if let panGestureRecognizer, gestureRecognizer === panGestureRecognizer {
                panGestureRecognizer.startLocation(in: webView)
            } else {
                gestureRecognizer.location(in: webView)
            }

        if gestureRecognizer is WKDeferringGestureRecognizer {
            return true
        }

        // While catching a decelerating scroll, only select gestures are allowed to begin:
        // - single click, so it can reset the interruption state
        // - mouse tracking or pan, so they can continue with successive scrolls (scrollbar drag for the former)
        // - magnification or rotation, so they can continue with simultaneous manipulation gestures
        if caughtDeceleratingScroll {
            if gestureRecognizer === singleClickGestureRecognizer {
                return true
            }
            if isMouseTrackingGestureRecognizer(gestureRecognizer) && isPointInScrollbar(locationInViewCoordinates) {
                return true
            }
            if !isOurManipulationGestureRecognizer(gestureRecognizer) {
                return false
            }
        }

        // An event over a scrollbar is a scrollbar interaction; only a mouse-tracking gesture (which drives
        // `Scrollbar::mouseDown` -> thumb drag) should handle it. The AppKit text-selection/context-menu gestures
        // are handled separately in the deferral delegate.
        if isPointInScrollbar(locationInViewCoordinates) && !isMouseTrackingGestureRecognizer(gestureRecognizer) {
            if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                Logger.viewGestures.debug(
                    """
                    [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                    Denying gesture over scrollbar: \(Self.loggingDescription(for: gestureRecognizer), privacy: .private)
                    """
                )
            }
            return false
        }

        if gestureRecognizer === doubleClickGestureRecognizer {
            return webView._impl()?.allowsMagnification() ?? false
        }

        // Live Text (see the Image Analysis design note): the preflight is a passive observer and is only
        // enabled when Live Text is available, so it's always allowed to begin to measure the press.
        if gestureRecognizer === imageAnalysisGestureRecognizer {
            return true
        }

        if gestureRecognizer === domDoubleClickGestureRecognizer {
            return true
        }

        if gestureRecognizer === secondaryClickGestureRecognizer {
            return secondaryClickShouldBegin(at: locationInViewCoordinates)
        }

        if gestureRecognizer === dragPressGestureRecognizer {
            return dragPressShouldBegin(at: locationInViewCoordinates)
        }

        if gestureRecognizer === panGestureRecognizer {
            return panShouldBegin(at: locationInViewCoordinates)
        }

        if gestureRecognizer === singleClickGestureRecognizer {
            guard let impl = webView._impl() else {
                return false
            }
            return !impl.isTextSelectedAtPoint(locationInViewCoordinates)
        }

        if let mouseTrackingGesture = gestureRecognizer as? WKMouseTrackingGestureRecognizer {
            if !mouseTrackingGestureRecognizerCanTrack(mouseTrackingGesture) {
                if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                    Logger.viewGestures.debug(
                        """
                        [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                        Denying mouse tracking gesture: \(Self.loggingDescription(for: gestureRecognizer), privacy: .private)
                        """
                    )
                }
                return false
            }
            guard let impl = webView._impl() else {
                return false
            }
            return !impl.isTextSelectedAtPoint(locationInViewCoordinates)
        }

        return true
    }

    @objc(_gestureRecognizer:canPreventGestureRecognizer:)
    private func gestureRecognizer(
        _ preventingGestureRecognizer: NSGestureRecognizer,
        canPrevent preventedGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        guard let webView = view else {
            return false
        }

        if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                Preventing gesture: \(Self.loggingDescription(for: preventingGestureRecognizer), privacy: .private), Prevented gesture: \
                \(Self.loggingDescription(for: preventedGestureRecognizer), privacy: .private)
                """
            )
        }

        // None of our gesture recognizers may prevent an enclosing scroll view's pan (or any other
        // scroll/zoom) gesture, so that a scroll can always be handed off to the enclosing scroll view
        // e.g. a scroll over a draggable <img> in a non-scrollable web view.
        if isSomeManipulationGestureRecognizer(preventedGestureRecognizer) {
            return false
        }

        // Live Text (see the Image Analysis design note): the preflight is a passive observer, so it prevents
        // nothing.
        if preventingGestureRecognizer === imageAnalysisGestureRecognizer {
            return false
        }

        if preventingGestureRecognizer === pointerTrackingGestureRecognizer
            || preventedGestureRecognizer === pointerTrackingGestureRecognizer
        {
            return false
        }

        if preventingGestureRecognizer === domDoubleClickGestureRecognizer || preventedGestureRecognizer === domDoubleClickGestureRecognizer
        {
            return false
        }

        // Live Text: when the fallback deferral recognizes to block drag / context menu (text found), it must
        // only affect the drag-press and secondary-click recognizers it defers -- never the text-selection
        // gestures, which Live Text needs to proceed. (Its hold over drag-press / secondary-click is enforced
        // by the deferral failure-requirement, not by this prevention hook.)
        if preventingGestureRecognizer === imageAnalysisDragAndContextMenuDeferringGestureRecognizer {
            return preventedGestureRecognizer === dragPressGestureRecognizer
                || preventedGestureRecognizer === secondaryClickGestureRecognizer
        }

        let isOurClickGesture =
            preventingGestureRecognizer === singleClickGestureRecognizer
            || preventingGestureRecognizer === secondaryClickGestureRecognizer
            || isMouseTrackingGestureRecognizer(preventingGestureRecognizer)
            || preventingGestureRecognizer === dragPressGestureRecognizer

        if !isOurClickGesture {
            return true
        }

        // Don't let other click gestures prevent the secondary click GR; it must be allowed to fire its
        // press timer (0.72s) without being short-circuited by gestures that recognize earlier
        // (e.g. single click and mouse-tracking, which both transition to Began at mouse-down).
        if preventedGestureRecognizer === secondaryClickGestureRecognizer {
            return false
        }

        // Don't let our click gestures prevent text selection manager gestures;
        // they should be allowed to recognize simultaneously (per shouldRecognizeSimultaneouslyWithGestureRecognizer:).
        if Self.isTextSelectionGesture(preventedGestureRecognizer, of: webView) {
            return false
        }

        return true
    }
}

extension WKAppKitGestureController {
    private static func loggingDescription(for gestureRecognizer: NSGestureRecognizer?) -> String {
        guard let gestureRecognizer else {
            return "nil"
        }

        var parts: [String] = []
        parts.append("\(type(of: gestureRecognizer)): \(UInt(bitPattern: ObjectIdentifier(gestureRecognizer)))")

        if let name = gestureRecognizer.name {
            parts.append("name = \(name)")
        }

        parts.append("state = \(gestureRecognizer.state.name)")

        return "<\(parts.joined(separator: "; "))>"
    }

    private func setUpGestureRecognizers() {
        setUpPanGestureRecognizer()
        setUpPointerTrackingGestureRecognizer()
        setUpPointerDownDeferringGestureRecognizer()
        setUpMouseTrackingGestureRecognizers()
        setUpSingleClickGestureRecognizer()
        setUpDoubleClickGestureRecognizer()
        setUpDOMDoubleClickGestureRecognizer()

        setUpSecondaryClickGestureRecognizer()
        setUpSecondaryClickDeferringGestureRecognizer()

        setUpDragPressGestureRecognizer()
        setUpDragDeferringGestureRecognizer()

        setUpEnclosingScrollViewPanDeferringGestureRecognizer()

        setUpImageAnalysisGestureRecognizer()
        setUpImageAnalysisDeferringGestureRecognizers()

        setUpMagnificationGestureRecognizer()
        setUpRotationGestureRecognizer()
    }

    private func setUpPanGestureRecognizer() {
        guard let webView = view else {
            return
        }

        let panGestureRecognizer = WKPanGestureRecognizer(webView: webView, target: self, action: #selector(panGestureRecognized))
        configure(forScrolling: panGestureRecognizer)

        panGestureRecognizer.delegate = self
        panGestureRecognizer.name = "WKPanGesture"

        self.panGestureRecognizer = panGestureRecognizer
    }

    private func setUpMouseTrackingGestureRecognizers() {
        primaryMouseTrackingGestureRecognizer = makeMouseTrackingGestureRecognizer(at: 0)
        secondaryMouseTrackingGestureRecognizer = makeMouseTrackingGestureRecognizer(at: 1)
    }

    private func makeMouseTrackingGestureRecognizer(at index: Int) -> WKMouseTrackingGestureRecognizer {
        let recognizer = WKMouseTrackingGestureRecognizer.make(target: self, action: #selector(mouseTrackingGestureRecognized))
        configure(forMouseTracking: recognizer, at: index)
        recognizer.delegate = self
        recognizer.name = nameForMouseTrackingGesture(recognizer)
        return recognizer
    }

    private func setUpPointerTrackingGestureRecognizer() {
        let recognizer = WKPointerTrackingGestureRecognizer.make(
            target: self,
            action: #selector(pointerTrackingGestureRecognized)
        )
        pointerTrackingGestureRecognizer = recognizer
        configure(forPointerTracking: recognizer)
        recognizer.refusesToBeFailureRequirement = true
        recognizer.pointerTrackingDelegate = self
        recognizer.delegate = self
        recognizer.name = "WKPointerTrackingGesture"
    }

    private func setUpPointerDownDeferringGestureRecognizer() {
        let recognizer = WKDeferringGestureRecognizer(deferringGestureDelegate: self)
        pointerDownDeferringGestureRecognizer = recognizer
        configure(forPointerDownDeferral: recognizer)
        recognizer.delegate = self
        recognizer.name = "WKPointerDownDeferringGesture"
    }

    private func setUpSingleClickGestureRecognizer() {
        let recognizer = WKPressGestureRecognizer.make(target: self, action: #selector(singleClickGestureRecognized))
        singleClickGestureRecognizer = recognizer
        configure(forSingleClick: recognizer)
        recognizer.delegate = self
        recognizer.name = "WKSingleClickGesture"
    }

    private func setUpDoubleClickGestureRecognizer() {
        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(doubleClickGestureRecognized))
        doubleClickGestureRecognizer = recognizer
        configure(forDoubleClick: recognizer)
        recognizer.delegate = self
        recognizer.name = "WKDoubleClickGesture"
    }

    private func setUpDOMDoubleClickGestureRecognizer() {
        let recognizer = WKDOMDoubleClickGestureRecognizer(target: self, action: #selector(domDoubleClickGestureRecognized))
        configure(forDOMDoubleClick: recognizer)

        recognizer.delegate = self
        recognizer.name = "WKDOMDoubleClickGesture"

        domDoubleClickGestureRecognizer = recognizer
    }

    // `domDoubleClickGestureRecognizer` is always created as a `WKDOMDoubleClickGestureRecognizer`.
    private var typedDOMDoubleClickGestureRecognizer: WKDOMDoubleClickGestureRecognizer? {
        guard let recognizer = domDoubleClickGestureRecognizer else {
            return nil
        }

        guard let recognizer = recognizer as? WKDOMDoubleClickGestureRecognizer else {
            assertionFailure("DOM double click gesture recognizer was unexpectedly of type \(type(of: recognizer)).")
            return nil
        }

        return recognizer
    }

    private func resetDOMDoubleClickGestureRecognizer() {
        typedDOMDoubleClickGestureRecognizer?.resetClick()
    }

    func takeCompletedDOMDoubleClick() -> Bool {
        typedDOMDoubleClickGestureRecognizer?.takeCompletedDoubleClick() ?? false
    }

    private func setUpSecondaryClickGestureRecognizer() {
        let recognizer = WKPressGestureRecognizer.make(target: self, action: #selector(secondaryClickGestureRecognized))
        secondaryClickGestureRecognizer = recognizer
        configure(forSecondaryClick: recognizer)
        recognizer.cancelPastAllowableMovement = true
        recognizer.delegate = self
        recognizer.name = "WKSecondaryClickGesture"
    }

    private func setUpSecondaryClickDeferringGestureRecognizer() {
        let recognizer = WKDeferringGestureRecognizer(deferringGestureDelegate: self)
        secondaryClickDeferringGestureRecognizer = recognizer
        configure(forSecondaryClickDeferral: recognizer)
        recognizer.delegate = self
        recognizer.name = "WKSecondaryClickDeferringGesture"
    }

    private func setUpDragPressGestureRecognizer() {
        let recognizer = WKPressGestureRecognizer.make(target: self, action: #selector(dragPressGestureRecognized))
        dragPressGestureRecognizer = recognizer
        configure(forDragPress: recognizer)
        recognizer.delegate = self
        recognizer.name = "WKDragPressGesture"
    }

    private func setUpDragDeferringGestureRecognizer() {
        let recognizer = WKDeferringGestureRecognizer(deferringGestureDelegate: self)
        dragDeferringGestureRecognizer = recognizer
        configure(forDragDeferral: recognizer)
        recognizer.delegate = self
        recognizer.name = "WKDragDeferringGesture"
    }

    private func setUpEnclosingScrollViewPanDeferringGestureRecognizer() {
        let recognizer = WKDeferringGestureRecognizer(deferringGestureDelegate: self)
        enclosingScrollViewPanDeferringGestureRecognizer = recognizer
        recognizer.allowedTouchTypes = .direct
        recognizer.delegate = self
        recognizer.name = "WKEnclosingScrollViewPanDeferringGesture"
    }

    private func setUpImageAnalysisGestureRecognizer() {
        let recognizer = WKPressGestureRecognizer.make(target: self, action: #selector(imageAnalysisGestureRecognized))
        imageAnalysisGestureRecognizer = recognizer
        configure(forImageAnalysis: recognizer)
        recognizer.refusesToBeFailureRequirement = true
        recognizer.delegate = self
        recognizer.pressDelegate = self
        recognizer.name = "WKImageAnalysisGesture"
    }

    private func setUpImageAnalysisDeferringGestureRecognizers() {
        // One deferral holds text selection over an image until analysis resolves; the other holds the
        // drag-press / secondary-click recognizers. See the Image Analysis design note for why both exist
        // and why they resolve to opposite outcomes.
        imageAnalysisTextSelectionDeferringGestureRecognizer = makeImageAnalysisDeferringGestureRecognizer(
            withName: "WKImageAnalysisTextSelectionDeferringGesture"
        )
        imageAnalysisDragAndContextMenuDeferringGestureRecognizer = makeImageAnalysisDeferringGestureRecognizer(
            withName: "WKImageAnalysisDragAndContextMenuDeferringGesture"
        )
    }

    private func setUpMagnificationGestureRecognizer() {
        let recognizer = NSMagnificationGestureRecognizer(target: self, action: #selector(magnificationGestureRecognized))
        magnificationGestureRecognizer = recognizer
        configure(forMagnification: recognizer)
        recognizer.delegate = self
        recognizer.name = "WKMagnificationGesture"
    }

    private func setUpRotationGestureRecognizer() {
        let recognizer = NSRotationGestureRecognizer(target: self, action: #selector(rotationGestureRecognized))
        rotationGestureRecognizer = recognizer
        configure(forRotation: recognizer)
        recognizer.delegate = self
        recognizer.name = "WKRotationGesture"
    }

    private var installedGestureRecognizers: [NSGestureRecognizer] {
        let recognizers: [NSGestureRecognizer?] = [
            panGestureRecognizer,
            pointerTrackingGestureRecognizer,
            pointerDownDeferringGestureRecognizer,
            primaryMouseTrackingGestureRecognizer,
            secondaryMouseTrackingGestureRecognizer,
            singleClickGestureRecognizer,
            doubleClickGestureRecognizer,
            domDoubleClickGestureRecognizer,
            secondaryClickGestureRecognizer,
            secondaryClickDeferringGestureRecognizer,
            dragPressGestureRecognizer,
            dragDeferringGestureRecognizer,
            enclosingScrollViewPanDeferringGestureRecognizer,
            imageAnalysisGestureRecognizer,
            imageAnalysisTextSelectionDeferringGestureRecognizer,
            imageAnalysisDragAndContextMenuDeferringGestureRecognizer,
            magnificationGestureRecognizer,
            rotationGestureRecognizer,
        ]
        return recognizers.compactMap { $0 }
    }

    private func addGesturesToWebView() {
        guard let webView = view else {
            return
        }

        for recognizer in installedGestureRecognizers {
            webView.addGestureRecognizer(recognizer)
        }
    }

    private func enableGesturesIfNeeded() {
        enableGestureIfNeeded(panGestureRecognizer)
        enableGestureIfNeeded(pointerTrackingGestureRecognizer)
        enableGestureIfNeeded(primaryMouseTrackingGestureRecognizer)
        enableGestureIfNeeded(secondaryMouseTrackingGestureRecognizer)
        enableGestureIfNeeded(singleClickGestureRecognizer)
        enableGestureIfNeeded(doubleClickGestureRecognizer)
        enableGestureIfNeeded(domDoubleClickGestureRecognizer)
        enableGestureIfNeeded(secondaryClickGestureRecognizer)
        enableGestureIfNeeded(dragPressGestureRecognizer)
        enableGestureIfNeeded(imageAnalysisGestureRecognizer)
        enableGestureIfNeeded(magnificationGestureRecognizer)
        enableGestureIfNeeded(rotationGestureRecognizer)

        // The deferring gesture recognizers are intentionally not enabled.
    }

    private func ensureGesturesAreNotArchived() {
        // The set of gestures managed by WKAppKitGestureController are configured
        // and installed freshly for every web view initialization, and as such we
        // want to avoid duplicate sets when views are decoded.

        for recognizer in installedGestureRecognizers {
            recognizer.shouldBeArchived = false
        }
    }

    private func enableGestureIfNeeded(_ gesture: NSGestureRecognizer?) {
        guard let webView = view else {
            return
        }

        let gestureEnabled =
            gesture !== imageAnalysisGestureRecognizer || WKAppKitGestureControllerCxxSupport.isLiveTextAvailableAndEnabled()

        if Logger.viewGestures.isEnabled(type: .default), let page = webView._protectedPage().get() {
            Logger.viewGestures.log(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                \(Self.loggingDescription(for: gesture), privacy: .private) setEnabled:\(appKitGestureLogInteger(gestureEnabled))
                """
            )
        }
        gesture?.isEnabled = gestureEnabled
    }

    private func syntheticMouseEvent(
        _ type: NSEvent.EventType,
        at location: NSPoint,
        modifierFlags: NSEvent.ModifierFlags,
        timestamp: TimeInterval = GetCurrentEventTime(),
        windowNumber: Int,
        clickCount: Int = 1,
        pressure: Float,
        reportingMovementFor recognizer: WKPressGestureRecognizer? = nil
    ) -> NSEvent? {
        let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: modifierFlags,
            timestamp: timestamp,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: pressure
        )
        guard let event, let recognizer else {
            return event
        }
        return recognizer.eventReportingMovement(event, atWindowLocation: location)
    }

    private func touchActions(at point: NSPoint) -> TouchActions {
        TouchActions(rawValue: cxxSupport.touchActions(at: point))
    }

    private func touchActionsAllowedPanningAxes(at point: NSPoint) -> PanAxes {
        let touchActions = touchActions(at: point)
        let canPanHorizontally = !touchActions.isDisjoint(with: [.auto, .manipulation, .panX])
        let canPanVertically = !touchActions.isDisjoint(with: [.auto, .manipulation, .panY])

        var allowedAxes: PanAxes = []
        if canPanHorizontally {
            allowedAxes.insert(.horizontal)
        }
        if canPanVertically {
            allowedAxes.insert(.vertical)
        }

        return allowedAxes
    }

    private func touchActionsAllowPanning(at point: NSPoint) -> Bool {
        !touchActionsAllowedPanningAxes(at: point).isEmpty
    }

    private var panGestureRecognizerCanScroll: Bool {
        guard let webView = view else {
            return false
        }

        return touchActionsAllowPanning(at: panGestureRecognizer?.location(in: webView) ?? .zero)
    }

    private var magnificationGestureRecognizerCanZoom: Bool {
        guard let webView = view else {
            return false
        }

        let touchActions = touchActions(at: magnificationGestureRecognizer?.location(in: webView) ?? .zero)
        return !touchActions.isDisjoint(with: [.auto, .manipulation, .pinchZoom])
    }

    private func refreshControllerEligibility(_ gesture: NSPanGestureRecognizer) -> WebKit.RefreshControllerEligibility {
        gesture.touches.count == 1 ? .Eligible : .Ineligible
    }

    private func nameForMouseTrackingGesture(_ gesture: NSPressGestureRecognizer) -> String {
        if gesture.numberOfTouchesRequired == 1 {
            return "WKMouseTrackingGestureSingle"
        }
        if gesture.numberOfTouchesRequired > 1 {
            return "WKMouseTrackingGestureMultiple"
        }

        assertionFailure("A mouse tracking gesture recognizer requires at least one touch")
        return "WKMouseTrackingGestureUnknown"
    }

    private func mouseTrackingGestureRecognizerCanTrack(_ gesture: NSPressGestureRecognizer) -> Bool {
        guard let webView = view else {
            return false
        }

        if gesture.numberOfTouchesRequired <= 1 {
            return true
        }

        // If the web content permits panning, the pan GR will win.
        // This multi-touch tracking recognizer covers the remaining case, where
        // the content has opted out of panning. Web apps typically depend on
        // touch/pointer/mousemove events for a notion of "translation" in this
        // case, such as on maps.apple.com. As such, we complement the logic here
        // with the predicate in panGestureRecognizerCanScroll.
        return !touchActionsAllowPanning(at: gesture.location(in: webView))
    }

    // FIXME: rdar://185815023 (-[NSRotationGestureRecognizer locationInView:] should reflect live centroid of the gesture)
    // The rotation GR's -locationInView: does not reflect its live centroid over
    // the course of a twist, so we compute it directly and use it to feed our
    // gesture machinery. Otherwise, the rotation and magnification locations stomp
    // over each other in ViewGestureController.
    private func gestureCentroidInWindow(for gesture: NSGestureRecognizer) -> WebCore.FloatPoint {
        let touches: [NSTouch]
        if let magnificationGesture = gesture as? NSMagnificationGestureRecognizer {
            touches = magnificationGesture.touches
        } else if let rotationGesture = gesture as? NSRotationGestureRecognizer {
            touches = rotationGesture.touches
        } else {
            touches = []
        }

        let count = touches.count

        if count == 0 {
            return WebCore.FloatPoint(gesture.location(in: nil))
        }

        var centroidX: Float = 0
        var centroidY: Float = 0
        for touch in touches {
            let locationInWindow = touch.location(in: nil)
            centroidX = Float(Double(centroidX) + locationInWindow.x)
            centroidY = Float(Double(centroidY) + locationInWindow.y)
        }
        return WebCore.FloatPoint(centroidX, centroidY).scaled(Float(1.0 / Double(count)))
    }

    private func isOnlyTouchDown(_ touch: NSTouch) -> Bool {
        guard let webView = view else {
            return false
        }

        guard let event = NSApp.currentEvent, event.type == .directTouch else {
            return false
        }

        let touches = event.touches(matching: .touching, in: webView)
        return touches.count == 1 && touches.first?._uid == touch._uid
    }

    private func interruptMomentumIfNeeded(for touch: NSTouch) {
        // Other callers of resetCaughtDeceleratingScroll() can miss the end of a gesture
        // (e.g. a pan over content that disallows scrolling, which then neither scrolls, clicks, nor tracks the mouse).
        // We can't let that leak into the next interaction, or it would keep refusing gestures.
        // We only consider this a new interaction if 1) this is the only touch down,
        // and 2) isn't the touch that caught the scroll.
        if caughtDeceleratingScroll, uidOfTouchThatCaughtDeceleratingScroll != touch._uid, isOnlyTouchDown(touch) {
            if Logger.viewGestures.isEnabled(type: .default), let view, let page = view._protectedPage().get() {
                Logger.viewGestures.log(
                    """
                    [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                    Resetting stale caught decelerating scroll state from a previous interaction
                    """
                )
            }
            resetCaughtDeceleratingScroll()
        }

        let wasMomentumActive = isMomentumActive
        interruptMomentumIfNeeded()

        if wasMomentumActive && caughtDeceleratingScroll {
            uidOfTouchThatCaughtDeceleratingScroll = touch._uid
        }
    }

    private func configure(forScrolling gesture: NSPanGestureRecognizer) {
        // FIXME: Strictly, this should be `2` when allowsMagnification == YES and the min/max zoom
        // scales are different, c.f. -[UIScrollView _updatePanGestureConfiguration] for prior art.
        gesture.maximumNumberOfTouches = 2
        gesture.allowedTouchTypes = .direct
        gesture.buttonMask = 0
    }

    private func configure(forSingleClick gesture: NSPressGestureRecognizer) {
        gesture.minimumPressDuration = 0
        gesture.cancelPastAllowableMovement = true
        gesture.allowedTouchTypes = .direct
        gesture.buttonMask = 0
        gesture.numberOfTouchesRequired = 1
    }

    private func configure(forDoubleClick gesture: NSClickGestureRecognizer) {
        gesture.allowedTouchTypes = .direct
        gesture.buttonMask = 0
        gesture.numberOfTouchesRequired = 2
        gesture.numberOfClicksRequired = 2
    }

    private func configure(forDOMDoubleClick gesture: NSClickGestureRecognizer) {
        gesture.allowedTouchTypes = .direct
        gesture.buttonMask = 0
        gesture.numberOfTouchesRequired = 1
        // Intentionally set to `1` and not `2`, see WKDOMDoubleClickGestureRecognizer.swift.
        // FIXME: rdar://184563102 (An NSClickGestureRecognizer with numberOfClicksRequired=2 results in other GRs being neglected for some gestures)
        gesture.numberOfClicksRequired = 1
    }

    private func configure(forSecondaryClick gesture: NSPressGestureRecognizer) {
        gesture.allowedTouchTypes = .direct
        gesture.buttonMask = 0
    }

    private func configure(forMouseTracking gesture: NSPressGestureRecognizer, at index: Int) {
        gesture.minimumPressDuration = 0
        gesture.cancelPastAllowableMovement = false
        gesture.allowedTouchTypes = .direct
        gesture.buttonMask = 0
        gesture.numberOfTouchesRequired = index + 1
    }

    private func configure(forPointerTracking gesture: NSPressGestureRecognizer) {
        gesture.minimumPressDuration = 0
        gesture.allowableMovement = CGFloat.greatestFiniteMagnitude
        gesture.cancelPastAllowableMovement = false
        gesture.allowedTouchTypes = .direct
        gesture.buttonMask = 0
        // FIXME: Tracking more than one touch needs a pointer per touch.
        gesture.numberOfTouchesRequired = 1
    }

    private func configure(forPointerDownDeferral gesture: WKDeferringGestureRecognizer) {
        gesture.allowedTouchTypes = .direct
    }

    private func configure(forDragPress gesture: NSPressGestureRecognizer) {
        // Matching _UIDragInteractionDefaultLiftDelay.
        let dragPressMinimumDuration: TimeInterval = 0.325
        gesture.minimumPressDuration = dragPressMinimumDuration
        gesture.cancelPastAllowableMovement = false
        gesture.allowedTouchTypes = .direct
        gesture.buttonMask = 0
        gesture.numberOfTouchesRequired = 1
    }

    private func configure(forDragDeferral gesture: WKDeferringGestureRecognizer) {
        gesture.allowedTouchTypes = .direct
    }

    private func configure(forSecondaryClickDeferral gesture: WKDeferringGestureRecognizer) {
        gesture.allowedTouchTypes = .direct
    }

    private func configure(forImageAnalysis gesture: NSPressGestureRecognizer) {
        // Mirrors the iOS WKImageAnalysisGestureRecognizer: a short, stationary long-press that starts
        // preflighting Live Text as soon as a press settles on an image. Movement cancels it, so a
        // scroll or drag over an image does not trigger analysis.
        gesture.minimumPressDuration = 0.1
        gesture.allowableMovement = 0
        gesture.cancelPastAllowableMovement = true
        gesture.allowedTouchTypes = .direct
        gesture.buttonMask = 0
        gesture.numberOfTouchesRequired = 1
    }

    func configure(forImageAnalysisDeferral gesture: WKDeferringGestureRecognizer) {
        gesture.allowedTouchTypes = .direct
    }

    private func configure(forMagnification gesture: NSMagnificationGestureRecognizer) {
        gesture.allowedTouchTypes = .direct
    }

    private func configure(forRotation gesture: NSRotationGestureRecognizer) {
        gesture.allowedTouchTypes = .direct
    }

    // MARK: Gesture Recognition

    private func movementExceedsClickAllowableMovement(_ movementInWindow: NSSize) -> Bool {
        let allowableMovement = singleClickGestureRecognizer?.allowableMovement ?? 0
        return abs(movementInWindow.width) > allowableMovement || abs(movementInWindow.height) > allowableMovement
    }

    private func isMouseTrackingGestureRecognizer(_ gesture: NSGestureRecognizer) -> Bool {
        gesture is WKMouseTrackingGestureRecognizer
    }

    private func mouseTrackingWillBeHandedOff() -> Bool {
        guard mouseTrackingHasSentMouseDown else {
            return false
        }

        return [primaryMouseTrackingGestureRecognizer, secondaryMouseTrackingGestureRecognizer]
            .contains {
                $0?.state == .began || $0?.state == .changed
            }
    }

    private var isRecognizingTransformGesture: Bool {
        func isRecognizing(_ gesture: NSGestureRecognizer?) -> Bool {
            switch gesture?.state {
            case .began, .changed:
                true
            default:
                false
            }
        }

        return isRecognizing(magnificationGestureRecognizer) || isRecognizing(rotationGestureRecognizer)
    }

    var isTransformGestureActiveOrEnding: Bool {
        func isActiveOrEnding(_ gesture: NSGestureRecognizer?) -> Bool {
            switch gesture?.state {
            case .began, .changed, .ended:
                true
            default:
                false
            }
        }

        return isActiveOrEnding(magnificationGestureRecognizer) || isActiveOrEnding(rotationGestureRecognizer)
    }

    private func shouldSuppressMouseTrackingForTransformGesture() -> Bool {
        let transformGestureDriveTimeout: TimeInterval = 0.050

        guard contentDeclinedTransformGesture, isRecognizingTransformGesture, let lastTransformGestureDriveTime else {
            return false
        }

        return ProcessInfo.processInfo.systemUptime - lastTransformGestureDriveTime < transformGestureDriveTimeout
    }

    private func transformGestureDidEnd() {
        guard !isRecognizingTransformGesture else {
            return
        }

        contentDeclinedTransformGesture = false
        resetCaughtDeceleratingScroll()
    }

    private func transformGestureDidDrive() {
        lastTransformGestureDriveTime = ProcessInfo.processInfo.systemUptime

        guard contentDeclinedTransformGesture, mouseTrackingHasSentMouseDown, let impl = view?._impl(), !impl.ignoresAllEvents() else {
            return
        }

        let activeMouseTrackingGesture = activeMouseTrackingGestureRecognizer
        let modifierFlags = activeMouseTrackingGesture?.modifierFlags ?? []
        let locationInWindow =
            activeMouseTrackingGesture?.mouseLocationInWindow
            ?? NSPoint(x: CGFloat(mouseTrackingStartLocationInWindow.x()), y: CGFloat(mouseTrackingStartLocationInWindow.y()))

        let mouseUp = syntheticMouseEvent(
            .leftMouseUp,
            at: locationInWindow,
            modifierFlags: modifierFlags,
            windowNumber: impl.windowNumber(),
            pressure: 0,
            reportingMovementFor: activeMouseTrackingGesture
        )
        impl.mouseUp(mouseUp, .Touch, .No)

        mouseTrackingHasSentMouseDown = false
        mouseTrackingIsSuppressedForTransformGesture = true
    }

    // MARK: Pointer Tracking

    private func dispatchTrackedPointerEvent(
        _ phase: WebKit.WebEventPhase,
        atLocationInWindow locationInWindow: NSPoint,
        modifierFlags: NSEvent.ModifierFlags
    ) {
        cxxSupport.dispatchTrackedPointerEvent(phase, atLocationInWindow: locationInWindow, modifierFlags: modifierFlags) {
            [weak self] wasCanceled in
            self?.didDispatchPointerDown(wasCanceled: wasCanceled)
        }
    }

    private func didDispatchPointerDown(wasCanceled: Bool) {
        guard let pointerDownDeferringGestureRecognizer, pointerDownDeferringGestureRecognizer.state == .possible else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .debug), let webView = view, let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                deferral resolved: pointerdown canceled=\(appKitGestureLogInteger(wasCanceled))
                """
            )
        }

        pointerDownDeferringGestureRecognizer.endDeferralShouldPreventGestures(wasCanceled)
    }

    private func pointerTrackingShouldBegin(at locationInView: NSPoint, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard let webView = view, pointerTrackingGestureRecognizer?.isEnabled ?? false else {
            return false
        }

        if !(webView._impl()?.window()?.isKeyWindow ?? false) && !modifierFlags.contains(.command) {
            return false
        }

        // A pan here is delivered as mouse moves with no button held, so the page must not see a pressed pointer.
        if isHoverActivatedByClick(at: locationInView) {
            return false
        }

        return !isPointInScrollbar(locationInView)
    }

    private func cancelPointerTrackingIfNeeded() {
        guard isTrackingPointer else {
            return
        }
        isTrackingPointer = false

        if Logger.viewGestures.isEnabled(type: .debug), let webView = view, let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                "[pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): Canceling the tracked pointer"
            )
        }

        dispatchTrackedPointerEvent(.Cancelled, atLocationInWindow: trackedPointerLastLocationInWindow, modifierFlags: [])
    }

    // MARK: Magnification and Rotation

    private func currentMagnification(_ magnification: Double, atPhase phase: WebKit.WebEventPhase) -> Double {
        if phase == .Began {
            lastCumulativeMagnification = 0
        }
        let currentMagnification = (1 + magnification) / (1 + lastCumulativeMagnification) - 1
        lastCumulativeMagnification = magnification
        return currentMagnification
    }

    private func currentRotation(_ rotation: Double, atPhase phase: WebKit.WebEventPhase) -> Double {
        if phase == .Began {
            lastCumulativeRotation = 0
        }
        let currentRotation = rotation - lastCumulativeRotation
        lastCumulativeRotation = rotation
        return currentRotation
    }

    // MARK: NSGestureRecognizerDelegate

    // The text selection manager's gestures, read as the NSArray AppKit returns: the tests below are identity
    // tests, so no element is bridged or class-checked.
    private static func textSelectionGestures(of webView: WKWebView) -> NSArray? {
        webView.textSelectionManager?.gesturesForFailureRequirements as NSArray?
    }

    private static func isTextSelectionGesture(_ gesture: NSGestureRecognizer, of webView: WKWebView) -> Bool {
        guard let gestures = textSelectionGestures(of: webView) else {
            return false
        }
        return gestures.indexOfObjectIdentical(to: gesture) != NSNotFound
    }

    private func shouldRecognizeSimultaneouslyWithMouseTrackingGesture(_ gesture: NSGestureRecognizer) -> Bool {
        guard let webView = view else {
            return false
        }

        if isMouseTrackingGestureRecognizer(gesture) || isOurManipulationGestureRecognizer(gesture) {
            return true
        }

        if gesture === doubleClickGestureRecognizer || gesture === singleClickGestureRecognizer || gesture === dragPressGestureRecognizer {
            return true
        }

        if gesture.name == "NSThemeFrame.panTouchGestureRecognizer" {
            return true
        }

        if Self.isTextSelectionGesture(gesture, of: webView) {
            return true
        }

        // An enclosing scroll view pan can report that it "began" even while being deferred,
        // so let mouse tracking recognize simultaneously until we have a deferral decision.
        return isEnclosingScrollViewPanHeldByDeferral(gesture)
    }

    private func isEnclosingScrollViewPanHeldByDeferral(_ gesture: NSGestureRecognizer) -> Bool {
        guard let enclosingScrollViewPanDeferringGestureRecognizer else {
            return false
        }

        let deferralState = enclosingScrollViewPanDeferringGestureRecognizer.state
        return (deferralState == .possible || deferralState == .ended)
            && deferringGestureRecognizer(enclosingScrollViewPanDeferringGestureRecognizer, shouldDeferOtherGestureRecognizer: gesture)
    }

    private func shouldPreventGestures(
        deferredBy deferringGestureRecognizer: WKDeferringGestureRecognizer,
        info: WebKit.InteractionInformationAtPosition,
        isInScrollbar: Bool,
        webView: WKWebView
    ) -> Bool? {
        let overLiveTextImage = WKAppKitGestureControllerCxxSupport.isLiveTextAvailableAndEnabled() && info.isImage

        // Over a scrollbar: drive the scrollbar, not text selection -- prevent the deferred gestures
        // so the mouse-tracking -> `Scrollbar::mouseDown` path wins.
        if isInScrollbar {
            if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                Logger.viewGestures.debug(
                    """
                    [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                    deferral resolved: over scrollbar; preventing text-selection gestures
                    """
                )
            }
            return true
        }

        if deferringGestureRecognizer === imageAnalysisTextSelectionDeferringGestureRecognizer
            || deferringGestureRecognizer === imageAnalysisDragAndContextMenuDeferringGestureRecognizer
        {
            // Image-analysis deferrals (see the Image Analysis design note): over an image with Live
            // Text available, keep deferring (nil) until the preflight's analysis token resolves both
            // deferrals (see resolveImageAnalysisDeferrals(with:)); otherwise this deferral has no
            // opinion, so release. We only have basic hit-test info here (this request does not fetch
            // image data), so key off info.isImage; the preflight does the full analyzability check.
            if overLiveTextImage {
                if let reusableOutcome = lastCompletedImageAnalysis?.outcome(for: info.hostImageOrVideoElementContext.value) {
                    let prevent = shouldPreventGestures(deferredBy: deferringGestureRecognizer, for: reusableOutcome)
                    if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                        Logger.viewGestures.debug(
                            """
                            [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                            deferral resolved: reusing completed image analysis outcome \
                            (prevent=\(appKitGestureLogInteger(prevent)))
                            """
                        )
                    }
                    return prevent
                }

                if imageAnalysisDeferralState == .gestureFailed {
                    if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                        Logger.viewGestures.debug(
                            """
                            [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                            deferral resolved: image analysis preflight failed; not preventing
                            """
                        )
                    }
                    return false
                }

                imageAnalysisDeferralState = .deferring
                return nil
            }

            return false
        }

        if deferringGestureRecognizer === dragDeferringGestureRecognizer {
            let isDraggable = info.representsDraggableElement

            if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                Logger.viewGestures.debug(
                    """
                    [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                    deferral resolved: isDraggable=\(appKitGestureLogInteger(isDraggable)) \
                    (link=\(appKitGestureLogInteger(info.isLink)) image=\(appKitGestureLogInteger(info.isImage)) \
                    attachment=\(appKitGestureLogInteger(info.isAttachment)) \
                    dhtml=\(appKitGestureLogInteger(info.isDHTMLDraggable)) color=\(appKitGestureLogInteger(info.isColorInput)) \
                    prefersDrag=\(appKitGestureLogInteger(info.prefersDraggingOverTextSelection)))
                    """
                )
            }

            return isDraggable && !overLiveTextImage
        }

        if deferringGestureRecognizer === secondaryClickDeferringGestureRecognizer {
            let isSelectable = info.representsSelectableContent
            let prefersManipulation = info.prefersDirectManipulation

            if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                Logger.viewGestures.debug(
                    """
                    [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                    Resolved deferral: isSelectable=\(appKitGestureLogInteger(isSelectable)) \
                    prefersDirectManipulation=\(appKitGestureLogInteger(prefersManipulation)) \
                    (selectability=\(info.selectability.rawValue) \
                    overEditableContent=\(appKitGestureLogInteger(info.isOverEditableContent)))
                    """
                )
            }

            return (!isSelectable || prefersManipulation) && !overLiveTextImage
        }

        if deferringGestureRecognizer === enclosingScrollViewPanDeferringGestureRecognizer {
            let prefersManipulation = info.prefersDirectManipulation

            if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                Logger.viewGestures.debug(
                    """
                    [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                    deferral resolved: enclosing scroll view pan yields to content=\(appKitGestureLogInteger(prefersManipulation))
                    """
                )
            }

            return prefersManipulation
        }

        preconditionFailure("Unexpected deferring gesture recognizer")
    }

    private func isOurManipulationGestureRecognizer(_ gesture: NSGestureRecognizer) -> Bool {
        gesture === panGestureRecognizer || gesture === magnificationGestureRecognizer || gesture === rotationGestureRecognizer
    }

    private func isSomeManipulationGestureRecognizer(_ gesture: NSGestureRecognizer) -> Bool {
        isOurManipulationGestureRecognizer(gesture)
            || isBuiltInScrollViewPanGestureRecognizer(gesture)
            || isBuiltInScrollViewMagnificationGestureRecognizer(gesture)
    }
}

@objc(CxxSupport)
@implementation
extension WKAppKitGestureController {
    @objc(_cxxSupport)
    func cxxSupportForObjectiveC() -> WKAppKitGestureControllerCxxSupport {
        cxxSupport
    }

    func generatedMomentumDidEnd() {
        isMomentumActive = false

        // Only the delta suppression is tied to momentum: once it has stopped, continuing to
        // zero deltas stops top scroll stretching from engaging.
        //
        // Whether the interaction caught a decelerating scroll is a property of the gesture
        // (and not the momentum). Clearing it here lets the scroll interrupt click through.
        // Instead, we should let the gesture end paths own/reset it instead.
        suppressNextPanScrollDelta = false
    }
}

// MARK: WKDeferringGestureRecognizerDelegate

@objc(WKDeferringGestureRecognizerDelegate)
@implementation
extension WKAppKitGestureController {
    @objc(deferringGestureRecognizer:shouldDeferOtherGestureRecognizer:)
    func deferringGestureRecognizer(
        _ deferringGestureRecognizer: WKDeferringGestureRecognizer,
        shouldDeferOtherGestureRecognizer gestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        guard let webView = view else {
            return false
        }

        // Live Text (see the Image Analysis design note): the fallback deferral holds the drag-press /
        // secondary-click recognizers -- not text selection -- until analysis resolves, so a slow analysis
        // can't let drag-press fire and drag the image before Live Text has a chance to win.
        if deferringGestureRecognizer === imageAnalysisDragAndContextMenuDeferringGestureRecognizer {
            return gestureRecognizer === dragPressGestureRecognizer || gestureRecognizer === secondaryClickGestureRecognizer
        }

        // Defer panning any scroll view that encloses the web view so that we can delegate to direct-manipulation elements if needed.
        if deferringGestureRecognizer === enclosingScrollViewPanDeferringGestureRecognizer {
            if !isBuiltInScrollViewPanGestureRecognizer(gestureRecognizer) {
                return false
            }

            guard let scrollView = gestureRecognizer.view as? NSScrollView else {
                return false
            }
            return webView.isDescendant(of: scrollView)
        }

        return Self.isTextSelectionGesture(gestureRecognizer, of: webView)
    }

    @objc(deferringGestureRecognizer:shouldDeferGesturesForEventThatWillBeginTouches:)
    func deferringGestureRecognizer(
        _ deferringGestureRecognizer: WKDeferringGestureRecognizer,
        shouldDeferGesturesForEventThatWillBeginTouches event: NSEvent
    ) -> Bool {
        guard let webView = view else {
            return false
        }

        if deferringGestureRecognizer === imageAnalysisTextSelectionDeferringGestureRecognizer
            || deferringGestureRecognizer === imageAnalysisDragAndContextMenuDeferringGestureRecognizer
        {
            imageAnalysisDeferralState = .undecided
        }

        if deferringGestureRecognizer === enclosingScrollViewPanDeferringGestureRecognizer {
            if webView.enclosingScrollView == nil || !(webView._protectedPage().get()?.hasRunningProcess() ?? false) {
                return false
            }

            if caughtDeceleratingScroll {
                return false
            }
        }

        // An event that catches a decelerating scroll only stops the scroll (and may continue it as a new pan),
        // so it must never begin a text selection or any other deferred gesture, no matter how long it's held
        // before moving.
        if caughtDeceleratingScroll {
            if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                Logger.viewGestures.debug(
                    """
                    [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                    deferral resolved: event caught a decelerating scroll; preventing deferred gestures
                    """
                )
            }
            deferringGestureRecognizer.endDeferralShouldPreventGestures(true)
            return true
        }

        let locationInView = webView.convert(event.locationInWindow, from: nil)

        let isInScrollbar = isPointInScrollbar(locationInView)

        if !isInScrollbar && (webView._impl()?.isTextSelectedAtPoint(locationInView) ?? false) {
            if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                Logger.viewGestures.debug(
                    """
                    [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                    deferral: not deferring; text already selected at \(NSStringFromPoint(locationInView), privacy: .private)
                    """
                )
            }
            return false
        }

        // This deferral waits on the page's reply to the pointerdown and not on position
        // information, so there is only something to wait for if pointer tracking will begin.
        if deferringGestureRecognizer === pointerDownDeferringGestureRecognizer {
            return pointerTrackingShouldBegin(at: locationInView, modifierFlags: event.modifierFlags)
        }

        if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
            Logger.viewGestures.debug(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                deferral: deferring; awaiting position info at \(NSStringFromPoint(locationInView), privacy: .private)
                """
            )
        }

        let request = positionInformationRequest(at: locationInView)
        cxxSupport.doAfterPositionInformationUpdate(request) { [weak self, weak deferringGestureRecognizer] info in
            guard let self, let deferringGestureRecognizer else {
                return
            }

            guard let info = info.value else {
                if deferringGestureRecognizer === self.enclosingScrollViewPanDeferringGestureRecognizer
                    && deferringGestureRecognizer.state == .possible
                {
                    deferringGestureRecognizer.endDeferralShouldPreventGestures(false)
                }
                return
            }

            guard let webView = self.view else {
                return
            }

            let deferralState = deferringGestureRecognizer.state
            if deferralState != .possible {
                if Logger.viewGestures.isEnabled(type: .debug), let page = webView._protectedPage().get() {
                    Logger.viewGestures.debug(
                        """
                        [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                        deferral: position info arrived after deferring gesture exited Possible (state=\(deferralState.rawValue)); \
                        skipping resolution
                        """
                    )
                }
                return
            }

            let shouldPreventGestures = self.shouldPreventGestures(
                deferredBy: deferringGestureRecognizer,
                info: info,
                isInScrollbar: isInScrollbar,
                webView: webView
            )

            if let shouldPreventGestures {
                deferringGestureRecognizer.endDeferralShouldPreventGestures(shouldPreventGestures)
            }
        }

        return true
    }

    @objc(deferringGestureRecognizer:didEndTouchesWithEvent:)
    func deferringGestureRecognizer(_ deferringGestureRecognizer: WKDeferringGestureRecognizer, didEndTouchesWith event: NSEvent) {
        guard deferringGestureRecognizer.state == .possible else {
            return
        }

        if Logger.viewGestures.isEnabled(type: .default), let webView = view, let page = webView._protectedPage().get() {
            Logger.viewGestures.log(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                deferral: touch ended before position info arrived; unblocking text selection
                """
            )
        }

        if deferringGestureRecognizer !== pointerDownDeferringGestureRecognizer {
            cxxSupport.abandonPositionInformationRequest()
        }

        deferringGestureRecognizer.endDeferralShouldPreventGestures(false)
    }

    @objc(deferringGestureRecognizer:didTransitionToState:)
    func deferringGestureRecognizer(
        _ deferringGestureRecognizer: WKDeferringGestureRecognizer,
        didTransitionTo state: NSGestureRecognizer.State
    ) {
    }
}

extension NSGestureRecognizer.State {
    fileprivate var name: String {
        switch self {
        case .possible: "Possible"
        case .began: "Began"
        case .changed: "Changed"
        case .ended: "Ended"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        @unknown default:
            preconditionFailure("Unknown gesture recognizer state")
        }
    }
}

#endif // HAVE_APPKIT_GESTURES_SUPPORT
