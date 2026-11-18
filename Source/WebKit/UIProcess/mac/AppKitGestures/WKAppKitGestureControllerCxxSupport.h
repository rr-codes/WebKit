/*
 * Copyright (C) 2026 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#pragma once

#import <wtf/Platform.h>

#if HAVE(APPKIT_GESTURES_SUPPORT)

#import "IdentifierTypes.h"
#import "InteractionInformationAtPosition.h"
#import "InteractionInformationRequest.h"
#import "TransactionID.h"
#import "WebEventPhase.h"
#import <WebCore/ElementContext.h>
#import <WebCore/IntPoint.h>
#import <optional>
#import <wtf/MathExtras.h>
#import <wtf/MonotonicTime.h>

OBJC_CLASS WKAppKitGestureController;

namespace WebKit {

using OptionalInteractionInformationAtPosition = std::optional<InteractionInformationAtPosition>;
using OptionalIntPoint = std::optional<WebCore::IntPoint>;
using OptionalTransactionID = std::optional<TransactionID>;

inline uint64_t appKitGestureTapIdentifierToUInt64(TapIdentifier identifier) { return identifier.toUInt64(); }
inline MonotonicTime appKitGestureMonotonicTimeFromRawSeconds(double seconds) { return MonotonicTime::fromRawSeconds(seconds); }
inline bool appKitGestureMagnificationIsOne(double magnification) { return WTF::areEssentiallyEqual(magnification, 1.0); }

inline bool appKitGestureIsInteractiveModel(const InteractionInformationAtPosition& info)
{
#if ENABLE(MODEL_ELEMENT_STAGE_MODE)
    return info.isInteractiveModel;
#else
    UNUSED_PARAM(info);
    return false;
#endif
}

} // namespace WebKit

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

NS_SWIFT_UI_ACTOR
@interface WKAppKitGestureControllerCxxSupport : NSObject
@property (nonatomic, weak, nullable) WKAppKitGestureController *controller;
- (void)setUpPositionInformation;
- (void)doAfterPositionInformationUpdate:(WebKit::InteractionInformationRequest)request completion:(NS_SWIFT_UI_ACTOR void (^)(WebKit::OptionalInteractionInformationAtPosition info))completion NS_SWIFT_NAME(doAfterPositionInformationUpdate(_:completion:));
- (void)preflightImageAnalysis:(WebKit::InteractionInformationRequest)request completion:(NS_SWIFT_UI_ACTOR void (^)(BOOL foundText, WebCore::ElementContext element))completion;
- (void)invalidatePositionInformation;
- (void)resetPositionInformation;
- (void)abandonPositionInformationRequest;
- (BOOL)positionInformationIsApproximatelyValid:(WebKit::InteractionInformationRequest)request radius:(int)radius;
- (BOOL)hasValidPositionInformation;
- (WebKit::InteractionInformationAtPosition)positionInformation;
- (BOOL)positionInformationIsHoverActivatedByClick;
- (WebKit::OptionalIntPoint)nearbySliderInteractionLocation;
+ (BOOL)isLiveTextAvailableAndEnabled;
- (void)startMomentumAtPosition:(NSPoint)position globalPosition:(NSPoint)globalPosition timestamp:(double)timestamp velocity:(NSSize)velocity fastScrollMultiplier:(double)fastScrollMultiplier;
- (void)interruptMomentum;
- (void)resetMomentum;
- (uint8_t)touchActionsAtPoint:(NSPoint)point;
- (WebKit::OptionalTransactionID)lastCommittedMainFrameLayerTreeTransactionID;
- (void)dispatchTrackedPointerEventWithPhase:(WebKit::WebEventPhase)phase atLocationInWindow:(NSPoint)locationInWindow modifierFlags:(NSEventModifierFlags)modifierFlags completion:(NS_SWIFT_UI_ACTOR void (^)(BOOL wasCanceled))completion NS_SWIFT_NAME(dispatchTrackedPointerEvent(_:atLocationInWindow:modifierFlags:completion:));
- (void)doAfterProcessingAllPendingMouseEvents:(NS_SWIFT_UI_ACTOR void (^)(void))completion NS_SWIFT_NAME(doAfterProcessingAllPendingMouseEvents(_:));
@end

#if !__has_feature(modules)
@interface WKAppKitGestureControllerCxxSupport (PositionInformation)
- (void)positionInformationDidChange:(const WebKit::InteractionInformationAtPosition&)info;
@end
#endif

NS_HEADER_AUDIT_END(nullability, sendability)

#endif // HAVE(APPKIT_GESTURES_SUPPORT)
