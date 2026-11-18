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
private import AppKit_Private.NSPanGestureRecognizer_Private
private import WebCore_Private

extension WKAppKitGestureController {
    // MARK: Wheel Event Handling

    private func prefersUnlockedScroll(_ gesture: NSPanGestureRecognizer) -> Bool {
        gesture.touches.count > 1
    }

    private func prefersForwardingToGestureController(_ gesture: NSPanGestureRecognizer) -> Bool {
        gesture.touches.count == 1
    }

    private func supportsMomentumScroll(_ gesture: NSPanGestureRecognizer) -> Bool {
        gesture.touches.count == 1
    }

    private func panVelocity(in view: NSView?) -> NSPoint {
        guard let panGestureRecognizer = panGestureRecognizer as? WKPanGestureRecognizer else {
            return .zero
        }
        return panGestureRecognizer.wk_velocity(in: view)
    }

    func sendWheelEvent(for gesture: NSPanGestureRecognizer) {
        guard let webView = view, let impl = webView._impl() else {
            return
        }

        let timestamp = WebKit.appKitGestureMonotonicTimeFromRawSeconds(gesture.timestamp)
        let locationInView = WebCore.FloatPoint(gesture.location(in: webView))
        let position = WebCore.IntPoint(locationInView)
        let globalPosition = WebCore.globalPoint(gesture.location(in: nil), impl.window())
        var gestureDelta = gesture.takeTranslation(in: webView)

        if suppressNextPanScrollDelta {
            suppressNextPanScrollDelta = false
            gestureDelta = WebCore.FloatSize()
        }

        guard let page = webView._protectedPage().get() else {
            return
        }

        if page.delegatesScalingToUIProcess(), impl.moveMagnificationOriginIfMagnifying(locationInView) {
            gestureDelta = WebCore.FloatSize()
        }

        let pinnedState = page.pinnedStateIncludingAncestorsAtPoint(locationInView)
        let canScrollHorizontally = gesture._canPanHorizontally && !(pinnedState[.Left] && pinnedState[.Right])
        let canScrollVertically = gesture._canPanVertically && !(pinnedState[.Top] && pinnedState[.Bottom])
        gestureDelta = WebCore.FloatSize(
            directionalScrollLockTracker.update(
                delta: CGSize(gestureDelta),
                canScrollHorizontally: canScrollHorizontally,
                canScrollVertically: canScrollVertically,
                prefersUnlocked: prefersUnlockedScroll(gesture),
                time: gesture.timestamp
            )
        )

        func makeWheelEventInit(_ delta: WebCore.FloatSize, phase: WebKit.WebEventPhase) -> WebKit.WebWheelEventInit {
            var event = WebKit.WebEventData()
            event.type = .Wheel
            event.timestamp = timestamp

            var wheel = WebKit.WebWheelEventData()
            wheel.position = position
            wheel.globalPosition = WebCore.IntPoint(globalPosition)
            wheel.delta = delta
            wheel.wheelTicks = delta.scaled(1 / Float(WebCore.Scrollbar.pixelsPerLineStep()))
            wheel.granularity = .ScrollByPixelWheelEvent
            wheel.directionInvertedFromDevice = false
            wheel.phase = phase
            wheel.momentumPhase = .None
            wheel.hasPreciseScrollingDeltas = true
            wheel.scrollCount = 1
            wheel.unacceleratedScrollingDelta = delta
            wheel.ioHIDEventTimestamp = timestamp
            wheel.momentumEndType = .Unknown
            wheel.inputSource = .Touch
            return WebKit.WebWheelEventInit(event: event, wheel: wheel)
        }

        let phase = WebKit.WebEventPhase(gesture.state)
        if phase == .Began {
            hasEverMagnifiedDuringCurrentGesture = false
        }
        if !WebKit.appKitGestureMagnificationIsOne(impl.magnification()) {
            hasEverMagnifiedDuringCurrentGesture = true
        }

        let forwardToGestureController = impl.allowsBackForwardNavigationGestures() && prefersForwardingToGestureController(gesture)

        func dispatchWheelEvent(_ delta: WebCore.FloatSize, phase: WebKit.WebEventPhase) {
            interruptMomentumForScrollWheelEvent()

            lastPanWheelEventWasHandledByViewGestureController =
                forwardToGestureController
                && impl.handleScrollWheelEventOnViewGestureController(
                    WebKit.NativeWebWheelEvent.create(WebKit.WebWheelEvent.create(consuming: makeWheelEventInit(delta, phase: phase)).get())
                        .get()
                )
            if lastPanWheelEventWasHandledByViewGestureController {
                Logger.viewGestures.debug(
                    "[pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): View gesture controller handled gesture"
                )
                return
            }

            page.handleNativeWheelEvent(
                consuming: WebKit.NativeWebWheelEvent.create(
                    WebKit.WebWheelEvent.create(consuming: makeWheelEventInit(delta, phase: phase)).get()
                )
            )
        }

        if phase == .Began {
            dispatchWheelEvent(WebCore.FloatSize(), phase: .MayBegin)
        }

        dispatchWheelEvent(gestureDelta, phase: phase)
    }

    // MARK: Momentum Handling

    func startMomentumIfNeeded(for gesture: NSPanGestureRecognizer) {
        guard let webView = view else {
            return
        }

        guard gesture.state == .ended, supportsMomentumScroll(gesture) else {
            return
        }

        // Momentum started now would scroll out of sight and then show up all at once.
        if isTransformGestureActiveOrEnding {
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
                CGSize(unfilteredVelocity),
                prefersUnlocked: prefersUnlockedScroll(gesture)
            )
        )

        let minimumVelocityForSwipe: Float = 20
        let minimumVelocityForMomentum: Float = 250

        func maximumComponentMagnitude(_ vector: WebCore.FloatSize) -> Float {
            max(abs(vector.width()), abs(vector.height()))
        }

        // Advance the swipe chain for every gesture that was fast enough to be a swipe, judged on the
        // unfiltered velocity: the user swiped even if the lock just zeroed the axis they swiped along, and
        // the tracker has to see it to consume its caughtMomentum and advance its endTime. Slower gestures
        // leave the tracker alone.
        let fastScrollMultiplier =
            maximumComponentMagnitude(unfilteredVelocity) >= minimumVelocityForSwipe
            ? fastScrollTracker.update(location: gesture.location(in: nil), velocity: CGSize(velocity), time: gesture.timestamp) : 1

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
            velocity: CGSize(velocity),
            fastScrollMultiplier: fastScrollMultiplier
        )
        isMomentumActive = true

        if Logger.viewGestures.isEnabled(type: .default), let page = webView._protectedPage().get() {
            Logger.viewGestures.log(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                Started momentum scrolling with velocity \(velocityMagnitude, format: .fixed(precision: 2)) pts/s
                """
            )
        }
    }

    func interruptMomentumIfNeeded() {
        guard isMomentumActive else {
            return
        }
        isMomentumActive = false

        guard let webView = view else {
            return
        }

        fastScrollTracker.didCatchMomentum()
        directionalScrollLockTracker.didCatchMomentum()
        caughtDeceleratingScroll = true
        suppressNextPanScrollDelta = true

        cxxSupport.invalidatePositionInformation()

        cxxSupport.interruptMomentum()

        if let page = webView._protectedPage().get() {
            page.interruptSyntheticMomentumScrolling()
            Logger.viewGestures.log("[pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): Interrupted momentum scrolling")
        }
    }

    func resetCaughtDeceleratingScroll() {
        caughtDeceleratingScroll = false
        suppressNextPanScrollDelta = false
    }
}

#endif // HAVE_APPKIT_GESTURES_SUPPORT
