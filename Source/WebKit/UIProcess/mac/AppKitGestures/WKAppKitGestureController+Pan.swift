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
    // MARK: Wheel Event Handling

    @nonobjc
    final func prefersUnlockedScroll(_ gesture: NSPanGestureRecognizer) -> Bool {
        gesture.touches.count > 1
    }

    @nonobjc
    final func prefersForwardingToGestureController(_ gesture: NSPanGestureRecognizer) -> Bool {
        gesture.touches.count == 1
    }

    @nonobjc
    final func supportsMomentumScroll(_ gesture: NSPanGestureRecognizer) -> Bool {
        gesture.touches.count == 1
    }

    @nonobjc
    final func panVelocity(in view: NSView?) -> NSPoint {
        guard let panGestureRecognizer = panGestureRecognizer as? WKPanGestureRecognizer else {
            return .zero
        }
        return panGestureRecognizer.wk_velocity(in: view)
    }

    @nonobjc
    final func sendWheelEvent(forGesture gesture: NSPanGestureRecognizer) {
        guard let webView = view else {
            return
        }

        guard let impl = webView._impl() else {
            return
        }

        let rawTimestamp = gesture.timestamp
        let locationInView = WebCore.FloatPoint(gesture.location(in: webView))
        let position = WebCore.IntPoint(locationInView)
        let globalPosition = WebCore.globalPoint(gesture.location(in: nil), impl.window())
        var gestureDelta = panTranslation(gesture, in: webView)

        let suppressedDelta = suppressNextPanScrollDelta
        suppressNextPanScrollDelta = false
        if suppressedDelta {
            gestureDelta = WebCore.FloatSize()
        }

        let page = webView._protectedPage().get()
        if let page, page.delegatesScalingToUIProcess() {
            if impl.moveMagnificationOriginIfMagnifying(locationInView) {
                gestureDelta = WebCore.FloatSize()
            }
        }

        guard let pinnedState = page?.pinnedStateIncludingAncestorsAtPoint(locationInView) else {
            return
        }
        let prefersUnlockedScroll = panGestureRecognizer.map { self.prefersUnlockedScroll($0) } ?? false
        let canScrollHorizontally =
            (panGestureRecognizer?._canPanHorizontally ?? false)
            && !(pinnedState[WebCore.BoxSide.Left] && pinnedState[WebCore.BoxSide.Right])
        let canScrollVertically =
            (panGestureRecognizer?._canPanVertically ?? false) && !(pinnedState[WebCore.BoxSide.Top] && pinnedState[WebCore.BoxSide.Bottom])
        gestureDelta = WebCore.FloatSize(
            directionalScrollLockTracker.update(
                delta: CGSize(width: CGFloat(gestureDelta.width()), height: CGFloat(gestureDelta.height())),
                canScrollHorizontally: canScrollHorizontally,
                canScrollVertically: canScrollVertically,
                prefersUnlocked: prefersUnlockedScroll,
                time: rawTimestamp
            )
        )

        var phase = toWebEventPhase(gesture.state)

        func makeWheelEventInit(_ delta: WebCore.FloatSize) -> WebKit.WebWheelEventInit {
            let wheelTicks = delta.scaled(Float(1.0 / Double(Float(WebCore.Scrollbar.pixelsPerLineStep()))))
            let unacceleratedScrollingDelta = delta

            var event = WebKit.WebEventData()
            event.type = WebKit.WebEventType.Wheel
            event.timestamp = WebKit.appKitGestureMonotonicTimeFromRawSeconds(rawTimestamp)

            var wheel = WebKit.WebWheelEventData()
            wheel.position = position
            wheel.globalPosition = WebCore.IntPoint(globalPosition)
            wheel.delta = delta
            wheel.wheelTicks = wheelTicks
            wheel.granularity = WebKit.WebWheelEventGranularity.ScrollByPixelWheelEvent
            wheel.directionInvertedFromDevice = false
            wheel.phase = phase
            wheel.momentumPhase = WebKit.WebEventPhase.None
            wheel.hasPreciseScrollingDeltas = true
            wheel.scrollCount = 1
            wheel.unacceleratedScrollingDelta = unacceleratedScrollingDelta
            wheel.ioHIDEventTimestamp = WebKit.appKitGestureMonotonicTimeFromRawSeconds(rawTimestamp)
            wheel.momentumEndType = WebKit.WebWheelEventMomentumEndType.Unknown
            wheel.inputSource = WebKit.WebEventInputSource.Touch
            return WebKit.WebWheelEventInit(event: event, wheel: wheel)
        }

        if phase == WebKit.WebEventPhase.Began {
            hasEverMagnifiedDuringCurrentGesture = false
        }
        if !WebKit.appKitGestureMagnificationIsOne(impl.magnification()) {
            hasEverMagnifiedDuringCurrentGesture = true
        }

        let forwardToGestureController = impl.allowsBackForwardNavigationGestures() && prefersForwardingToGestureController(gesture)

        func dispatchWheelEvent(_ delta: WebCore.FloatSize) {
            interruptMomentumForScrollWheelEvent()

            lastPanWheelEventWasHandledByViewGestureController =
                forwardToGestureController
                && impl.handleScrollWheelEventOnViewGestureController(
                    WebKit.NativeWebWheelEvent.create(WebKit.WebWheelEvent.create(consuming: makeWheelEventInit(delta)).get()).get()
                )
            if lastPanWheelEventWasHandledByViewGestureController {
                if let page = webView._protectedPage().get() {
                    Logger.viewGestures.debug(
                        "[pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): View gesture controller handled gesture"
                    )
                }
                return
            }

            webView._protectedPage().get()?
                .handleNativeWheelEvent(
                    consuming: WebKit.NativeWebWheelEvent.create(WebKit.WebWheelEvent.create(consuming: makeWheelEventInit(delta)).get())
                )
        }

        if phase == WebKit.WebEventPhase.Began {
            phase = WebKit.WebEventPhase.MayBegin
            dispatchWheelEvent(WebCore.FloatSize())
            phase = WebKit.WebEventPhase.Began
        }

        dispatchWheelEvent(gestureDelta)
    }

    // MARK: Momentum Handling

    @nonobjc
    final func startMomentumIfNeeded(forGesture gesture: NSPanGestureRecognizer) {
        guard let webView = view else {
            return
        }

        if gesture.state != .ended {
            return
        }

        if !supportsMomentumScroll(gesture) {
            return
        }

        // Momentum started now would scroll out of sight and then show up all at once.
        if isTransformGestureActiveOrEnding() {
            fastScrollTracker.reset()
            return
        }

        // A swipe navigates instead of scrolling, so it has no momentum. Momentum would scroll the page navigated to.
        if lastPanWheelEventWasHandledByViewGestureController {
            fastScrollTracker.reset()
            return
        }

        let unfilteredVelocity = WebCore.toFloatSize(WebCore.FloatPoint(panVelocity(in: webView)))

        // Continue the scroll along the same axis the drag was locked to rather than reintroducing
        // diagonal drift; also keeps fastScrollTracker's velocity heuristics off-axis-clean.
        let velocity = WebCore.FloatSize(
            directionalScrollLockTracker.filterVelocity(
                CGSize(width: CGFloat(unfilteredVelocity.width()), height: CGFloat(unfilteredVelocity.height())),
                prefersUnlocked: prefersUnlockedScroll(gesture)
            )
        )

        let minimumVelocityForSwipe: Float = 20
        let minimumVelocityForMomentum: Float = 250

        func maximumComponentMagnitude(_ vector: WebCore.FloatSize) -> Float {
            let width = abs(vector.width())
            let height = abs(vector.height())
            return width < height ? height : width
        }

        // Advance the swipe chain for every gesture that was fast enough to be a swipe, judged on the
        // unfiltered velocity: the user swiped even if the lock just zeroed the axis they swiped along, and
        // the tracker has to see it to consume its caughtMomentum and advance its endTime. Slower gestures
        // leave the tracker alone.
        var fastScrollMultiplier: Double = 1
        if maximumComponentMagnitude(unfilteredVelocity) >= minimumVelocityForSwipe {
            fastScrollMultiplier = fastScrollTracker.update(
                location: gesture.location(in: nil),
                velocity: CGSize(width: CGFloat(velocity.width()), height: CGFloat(velocity.height())),
                time: gesture.timestamp
            )
        }

        // Suppressing the gesture itself is judged on the filtered velocity, which can only be smaller, so
        // anything reaching this point has already been through the tracker above.
        let velocityMagnitude = maximumComponentMagnitude(velocity)
        if velocityMagnitude < minimumVelocityForMomentum {
            return
        }

        cxxSupport.startMomentum(
            atPosition: gesture.location(in: webView),
            globalPosition: WebCore.globalPoint(gesture.location(in: nil), webView._impl()?.window()),
            timestamp: gesture.timestamp,
            velocity: NSSize(width: CGFloat(velocity.width()), height: CGFloat(velocity.height())),
            fastScrollMultiplier: fastScrollMultiplier
        )
        isMomentumActive = true

        if let page = webView._protectedPage().get() {
            Logger.viewGestures.log(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                Started momentum scrolling with velocity \(velocityMagnitude, format: .fixed(precision: 2)) pts/s
                """
            )
        }
    }

    @nonobjc
    final func interruptMomentumIfNeeded() {
        let wasMomentumActive = isMomentumActive
        isMomentumActive = false
        if !wasMomentumActive {
            return
        }

        guard let webView = view else {
            return
        }

        fastScrollTracker.didCatchMomentum()
        directionalScrollLockTracker.didCatchMomentum()
        caughtDeceleratingScroll = true
        suppressNextPanScrollDelta = true

        cxxSupport.invalidate()

        cxxSupport.interruptMomentum()

        if let page = webView._protectedPage().get() {
            page.interruptSyntheticMomentumScrolling()
            Logger.viewGestures.log("[pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): Interrupted momentum scrolling")
        }
    }

    @nonobjc
    final func resetCaughtDeceleratingScroll() {
        caughtDeceleratingScroll = false
        suppressNextPanScrollDelta = false
    }
}

#endif // HAVE_APPKIT_GESTURES_SUPPORT
