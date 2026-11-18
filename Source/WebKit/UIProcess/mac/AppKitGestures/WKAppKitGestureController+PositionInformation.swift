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
private import WebCore_Private

private let sharedPositionInformationToleranceRadius: Int32 = 15
private let panPositionInformationToleranceRadius = sharedPositionInformationToleranceRadius
private let mouseDownPositionInformationToleranceRadius = sharedPositionInformationToleranceRadius

private func saturatingInt32(_ value: Double) -> Int32 {
    value.isNaN ? 0 : Int32(min(max(value, Double(Int32.min)), Double(Int32.max)))
}

extension WKAppKitGestureController {
    // MARK: Position Information

    func dragPressShouldBegin(at locationInView: NSPoint) -> Bool {
        guard let webView = view else {
            return false
        }

        let radius = saturatingInt32((dragPressGestureRecognizer?.allowableMovement ?? 0).rounded(.up))

        let information = cxxSupport.positionInformation()

        // FIXME: Migrate to requestDragStart: IPC for an authoritative decision.
        // The heuristic below approximates DragController::draggableElement() by consulting the same element-type and style signals.
        let isDraggable = information.representsDraggableElement
        let requestIsValid = isPositionInformationValid(at: locationInView, radius: radius)
        let shouldDrag = requestIsValid && isDraggable && !information.isHoverActivatedByClick

        if Logger.viewGestures.isEnabled(type: .default), let page = webView._protectedPage().get() {
            Logger.viewGestures.log(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                Drag-press shouldBegin → \(appKitGestureLogInteger(shouldDrag)) \
                (hasInfo=\(appKitGestureLogInteger(self.cxxSupport.hasValidPositionInformation())) \
                link=\(appKitGestureLogInteger(information.isLink)) image=\(appKitGestureLogInteger(information.isImage)) \
                attachment=\(appKitGestureLogInteger(information.isAttachment)) \
                dhtml=\(appKitGestureLogInteger(information.isDHTMLDraggable)) color=\(appKitGestureLogInteger(information.isColorInput)) \
                prefersDrag=\(appKitGestureLogInteger(information.prefersDraggingOverTextSelection)) \
                hoverActivatedByClick=\(appKitGestureLogInteger(information.isHoverActivatedByClick)) radius=\(radius))
                """
            )
        }

        if !requestIsValid {
            cxxSupport.invalidatePositionInformation()
        }

        return shouldDrag
    }

    func panShouldBegin(at locationInView: NSPoint) -> Bool {
        guard let webView = view else {
            return false
        }

        let requestIsValid = isPositionInformationValid(
            at: locationInView,
            radius: panPositionInformationToleranceRadius
        )

        let information = cxxSupport.positionInformation()

        // FIXME: (rdar://181964604) Because of this logic, vertically scrolling over these elements likely will not work.
        let prefersInteraction = information.prefersDirectManipulation
        let usesHoverActivatedByClickBounds = !requestIsValid && isInsideHoverActivatedByClickBounds(at: locationInView)
        let yieldToContent =
            (requestIsValid && (prefersInteraction || information.isHoverActivatedByClick)) || usesHoverActivatedByClickBounds

        if Logger.viewGestures.isEnabled(type: .default), let page = webView._protectedPage().get() {
            Logger.viewGestures.log(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                Pan shouldBegin → \(appKitGestureLogInteger(!yieldToContent)) \
                (hasInfo=\(appKitGestureLogInteger(self.cxxSupport.hasValidPositionInformation())) \
                valid=\(appKitGestureLogInteger(requestIsValid)) prefersInteraction=\(appKitGestureLogInteger(prefersInteraction)) \
                hoverActivatedByClick=\(appKitGestureLogInteger(information.isHoverActivatedByClick)) \
                fallback=\(appKitGestureLogInteger(usesHoverActivatedByClickBounds)))
                """
            )
        }

        return !yieldToContent
    }

    private func isInsideHoverActivatedByClickBounds(at locationInView: NSPoint) -> Bool {
        guard let page = view?._protectedPage().get(), let bounds = page.hoverActivatedByClickBounds().value else {
            return false
        }
        return bounds.contains(WebCore.IntPoint(locationInView))
    }

    func isHoverActivatedByClick(at locationInView: NSPoint) -> Bool {
        if !isPositionInformationValid(at: locationInView, radius: panPositionInformationToleranceRadius) {
            return isInsideHoverActivatedByClickBounds(at: locationInView)
        }

        return cxxSupport.positionInformationIsHoverActivatedByClick()
    }

    func isPointInScrollbar(_ locationInView: NSPoint) -> Bool {
        view?._impl()?.isPointInScrollbar(locationInView) ?? false
    }

    func secondaryClickShouldBegin(at locationInView: NSPoint) -> Bool {
        guard let webView = view else {
            return false
        }

        let radius = saturatingInt32((secondaryClickGestureRecognizer?.allowableMovement ?? 0).rounded(.up))

        let information = cxxSupport.positionInformation()

        let requestIsValid = isPositionInformationValid(at: locationInView, radius: radius)
        let isSecondaryClickable = information.representsSecondaryClickableElement
        let isOverSelectableText = information.isOverSelectableText

        // The secondary click owns points that are not over selectable text (e.g. the page background
        // or a video player). Over a run of selectable text, the text selection manager should win so
        // that a long press selects a word instead of synthesizing a context menu.
        let shouldBegin = requestIsValid && isSecondaryClickable && !isOverSelectableText

        if Logger.viewGestures.isEnabled(type: .default), let page = webView._protectedPage().get() {
            Logger.viewGestures.log(
                """
                [pageProxyID=\(page.logIdentifier())] \(#function, privacy: .private): \
                Secondary click shouldBegin → \(appKitGestureLogInteger(shouldBegin)) \
                (hasInfo=\(appKitGestureLogInteger(self.cxxSupport.hasValidPositionInformation())) \
                requestIsValid=\(appKitGestureLogInteger(requestIsValid)) \
                secondaryClickable=\(appKitGestureLogInteger(isSecondaryClickable)) \
                overSelectableText=\(appKitGestureLogInteger(isOverSelectableText)) selectability=\(information.selectability.rawValue) \
                prefersManipulation=\(appKitGestureLogInteger(information.prefersDirectManipulation)) \
                image=\(appKitGestureLogInteger(information.isImage)) video=\(appKitGestureLogInteger(information.isOverVideo)) \
                longClickQuirk=\(appKitGestureLogInteger(information.shouldTreatLongClickAsSecondaryClickQuirk)) radius=\(radius))
                """
            )
        }

        if !requestIsValid {
            cxxSupport.invalidatePositionInformation()
        }

        return shouldBegin
    }

    func positionInformationRequest(at locationInView: NSPoint) -> WebKit.InteractionInformationRequest {
        var request = WebKit.InteractionInformationRequest(WebCore.IntPoint(locationInView))
        request.inputSource = .Touch
        return request
    }

    private func isPositionInformationValid(at locationInView: NSPoint, radius: Int32) -> Bool {
        let request = positionInformationRequest(at: locationInView)
        return cxxSupport.positionInformationIsApproximatelyValid(request, radius: radius)
    }

    func adjustedMouseDownLocation(inWindow locationInWindow: NSPoint) -> NSPoint {
        guard let webView = view, let adjustedLocationInView = cxxSupport.nearbySliderInteractionLocation().value else {
            return locationInWindow
        }

        let locationInView = webView.convert(locationInWindow, from: nil)
        if !isPositionInformationValid(at: locationInView, radius: mouseDownPositionInformationToleranceRadius) {
            return locationInWindow
        }

        let adjustedLocationInViewCoordinates = CGPoint(adjustedLocationInView)

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
