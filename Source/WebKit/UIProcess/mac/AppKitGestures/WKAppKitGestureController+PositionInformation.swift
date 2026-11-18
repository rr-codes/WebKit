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
    // MARK: Position Information

    @nonobjc
    final func dragPressShouldBegin(atLocation locationInViewCoordinates: NSPoint) -> Bool {
        guard let webView = view else {
            return false
        }

        let radius = saturatingInt32((dragPressGestureRecognizer?.allowableMovement ?? 0).rounded(.up))

        let information = cxxSupport.currentInformation()

        // FIXME: Migrate to requestDragStart: IPC for an authoritative decision.
        // The heuristic below approximates DragController::draggableElement() by consulting the same element-type and style signals.
        let isDraggable = representsDraggableElement(information)
        let requestIsValid = positionInformationRequestIsValid(atLocation: locationInViewCoordinates, withRadius: radius)
        let shouldDrag = requestIsValid && isDraggable && !information.isHoverActivatedByClick

        if let page = webView._protectedPage().get() {
            Logger.viewGestures.log(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                Drag-press shouldBegin \u{2192} \(appKitGestureLogInteger(shouldDrag)) \
                (hasInfo=\(appKitGestureLogInteger(self.cxxSupport.hasValidCurrentInformation())) \
                link=\(appKitGestureLogInteger(information.isLink)) image=\(appKitGestureLogInteger(information.isImage)) \
                attachment=\(appKitGestureLogInteger(information.isAttachment)) \
                dhtml=\(appKitGestureLogInteger(information.isDHTMLDraggable)) color=\(appKitGestureLogInteger(information.isColorInput)) \
                prefersDrag=\(appKitGestureLogInteger(information.prefersDraggingOverTextSelection)) \
                hoverActivatedByClick=\(appKitGestureLogInteger(information.isHoverActivatedByClick)) radius=\(radius))
                """
            )
        }

        if !requestIsValid {
            cxxSupport.invalidate()
        }

        return shouldDrag
    }

    @nonobjc
    final func panShouldBegin(atLocation locationInViewCoordinates: NSPoint) -> Bool {
        guard let webView = view else {
            return false
        }

        let requestIsValid = positionInformationRequestIsValid(
            atLocation: locationInViewCoordinates,
            withRadius: panPositionInformationToleranceRadius
        )

        let information = cxxSupport.currentInformation()

        // FIXME: (rdar://181964604) Because of this logic, vertically scrolling over these elements likely will not work.
        let prefersInteraction = prefersDirectManipulation(information)
        let usesHoverActivatedByClickBounds = !requestIsValid && isInsideHoverActivatedByClickBounds(atLocation: locationInViewCoordinates)
        let yieldToContent =
            (requestIsValid && (prefersInteraction || information.isHoverActivatedByClick)) || usesHoverActivatedByClickBounds

        if let page = webView._protectedPage().get() {
            Logger.viewGestures.log(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                Pan shouldBegin \u{2192} \(appKitGestureLogInteger(!yieldToContent)) \
                (hasInfo=\(appKitGestureLogInteger(self.cxxSupport.hasValidCurrentInformation())) \
                valid=\(appKitGestureLogInteger(requestIsValid)) prefersInteraction=\(appKitGestureLogInteger(prefersInteraction)) \
                hoverActivatedByClick=\(appKitGestureLogInteger(information.isHoverActivatedByClick)) \
                fallback=\(appKitGestureLogInteger(usesHoverActivatedByClickBounds)))
                """
            )
        }

        return !yieldToContent
    }

    @nonobjc
    final func isInsideHoverActivatedByClickBounds(atLocation locationInViewCoordinates: NSPoint) -> Bool {
        guard let webView = view, let page = webView._protectedPage().get() else {
            return false
        }

        guard let bounds = page.hoverActivatedByClickBounds().value else {
            return false
        }
        return bounds.contains(WebCore.IntPoint(locationInViewCoordinates))
    }

    @nonobjc
    final func isHoverActivatedByClick(atLocation locationInView: NSPoint) -> Bool {
        if !positionInformationRequestIsValid(atLocation: locationInView, withRadius: panPositionInformationToleranceRadius) {
            return isInsideHoverActivatedByClickBounds(atLocation: locationInView)
        }

        return cxxSupport.currentInformationIsHoverActivatedByClick()
    }

    @nonobjc
    final func isPointInScrollbar(_ locationInView: NSPoint) -> Bool {
        guard let webView = view, let impl = webView._impl() else {
            return false
        }

        return impl.isPointInScrollbar(locationInView)
    }

    @nonobjc
    final func secondaryClickShouldBegin(atLocation locationInViewCoordinates: NSPoint) -> Bool {
        guard let webView = view else {
            return false
        }

        let radius = saturatingInt32((secondaryClickGestureRecognizer?.allowableMovement ?? 0).rounded(.up))

        let information = cxxSupport.currentInformation()

        let requestIsValid = positionInformationRequestIsValid(atLocation: locationInViewCoordinates, withRadius: radius)
        let isSecondaryClickable = representsSecondaryClickableElement(information)
        let isOverSelectableText = information.isOverSelectableText

        // The secondary click owns points that are not over selectable text (e.g. the page background
        // or a video player). Over a run of selectable text, the text selection manager should win so
        // that a long press selects a word instead of synthesizing a context menu.
        let shouldBegin = requestIsValid && isSecondaryClickable && !isOverSelectableText

        if let page = webView._protectedPage().get() {
            Logger.viewGestures.log(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                Secondary click shouldBegin \u{2192} \(appKitGestureLogInteger(shouldBegin)) \
                (hasInfo=\(appKitGestureLogInteger(self.cxxSupport.hasValidCurrentInformation())) \
                requestIsValid=\(appKitGestureLogInteger(requestIsValid)) \
                secondaryClickable=\(appKitGestureLogInteger(isSecondaryClickable)) \
                overSelectableText=\(appKitGestureLogInteger(isOverSelectableText)) selectability=\(information.selectability.rawValue) \
                prefersManipulation=\(appKitGestureLogInteger(prefersDirectManipulation(information))) \
                image=\(appKitGestureLogInteger(information.isImage)) video=\(appKitGestureLogInteger(information.isOverVideo)) \
                longClickQuirk=\(appKitGestureLogInteger(information.shouldTreatLongClickAsSecondaryClickQuirk)) radius=\(radius))
                """
            )
        }

        if !requestIsValid {
            cxxSupport.invalidate()
        }

        return shouldBegin
    }

    @nonobjc
    final func positionInformationRequest(atLocation locationInViewCoordinates: NSPoint) -> WebKit.InteractionInformationRequest {
        var request = WebKit.InteractionInformationRequest(WebCore.IntPoint(locationInViewCoordinates))
        request.inputSource = WebKit.WebEventInputSource.Touch
        return request
    }

    @nonobjc
    final func positionInformationRequestIsValid(atLocation locationInViewCoordinates: NSPoint, withRadius radius: Int32) -> Bool {
        let request = positionInformationRequest(atLocation: locationInViewCoordinates)
        return cxxSupport.currentIsApproximatelyValid(request, radius: radius)
    }

    @nonobjc
    final func adjustedMouseDownLocation(inWindow locationInWindow: NSPoint) -> NSPoint {
        guard let webView = view else {
            return locationInWindow
        }

        guard let adjustedLocationInView = cxxSupport.currentNearbySliderInteractionLocation().value else {
            return locationInWindow
        }

        let locationInView = webView.convert(locationInWindow, from: nil)
        if !positionInformationRequestIsValid(atLocation: locationInView, withRadius: mouseDownPositionInformationToleranceRadius) {
            return locationInWindow
        }

        let adjustedLocationInViewCoordinates = NSPoint(x: CGFloat(adjustedLocationInView.x()), y: CGFloat(adjustedLocationInView.y()))

        let maximumInteractionAdjustmentDistance: CGFloat = 48
        if abs(adjustedLocationInViewCoordinates.x - locationInView.x) > maximumInteractionAdjustmentDistance
            || abs(adjustedLocationInViewCoordinates.y - locationInView.y) > maximumInteractionAdjustmentDistance
        {
            return locationInWindow
        }

        if !NSPointInRect(adjustedLocationInViewCoordinates, webView.bounds) {
            return locationInWindow
        }

        return webView.convert(adjustedLocationInViewCoordinates, to: nil)
    }
}

#endif // HAVE_APPKIT_GESTURES_SUPPORT
