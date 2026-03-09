/*
 * Copyright (C) 2025 Apple Inc. All rights reserved.
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

#import <AppKit/NSGestureRecognizer_Private.h>
#import <wtf/Forward.h>
#import <wtf/ObjectIdentifier.h>
#import <wtf/Vector.h>

namespace WebCore {
class Color;
class FloatQuad;
class IntPoint;
class IntSize;
}

namespace WebKit {
class WebPageProxy;
class WebViewImpl;
}

OBJC_CLASS NSPanGestureRecognizer;

#if __has_include(<WebKitAdditions/WKAppKitGestureControllerAdditionsBefore.mm>)
#import <WebKitAdditions/WKAppKitGestureControllerAdditionsBefore.mm>
#endif

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

// MARK: WKAppKitGestureController

NS_SWIFT_UI_ACTOR
@interface WKAppKitGestureController : NSObject

- (instancetype)initWithPage:(std::reference_wrapper<WebKit::WebPageProxy>)page viewImpl:(std::reference_wrapper<WebKit::WebViewImpl>)viewImpl;
- (void)enableGesturesIfNeeded;

#if ENABLE(TWO_PHASE_CLICKS)

@property (nonatomic, readonly, getter=isPotentialClickInProgress) BOOL potentialClickInProgress;

- (void)didGetClickHighlightForRequest:(WebKit::ClickIdentifier)requestID color:(const WebCore::Color&)color quads:(const Vector<WebCore::FloatQuad>&)highlightedQuads topLeftRadius:(const WebCore::IntSize&)topLeftRadius topRightRadius:(const WebCore::IntSize&)topRightRadius bottomLeftRadius:(const WebCore::IntSize&)bottomLeftRadius bottomRightRadius:(const WebCore::IntSize&)bottomRightRadius nodeHasBuiltInClickHandling:(BOOL)nodeHasBuiltInClickHandling;
- (void)disableDoubleClickGesturesDuringClickIfNecessary:(WebKit::ClickIdentifier)requestID;
- (void)commitPotentialClickFailed;
- (void)didCompleteSyntheticClick;
- (void)didHandleClickAsHover;
- (void)didNotHandleClickAsClick:(const WebCore::IntPoint&)point;

#endif // ENABLE(TWO_PHASE_CLICKS)

@end

// MARK: WKAppKitGestureController + Internal

@interface WKAppKitGestureController (Internal)

@property (nonatomic, readonly) NSPanGestureRecognizer *_panGestureRecognizer;

@property (nonatomic, readonly) NSPressGestureRecognizer *_singleClickGestureRecognizer;

@property (nonatomic, readonly) NSClickGestureRecognizer *_doubleClickGestureRecognizer;

@property (nonatomic, readonly) NSPressGestureRecognizer *_secondaryClickGestureRecognizer;

@property (nonatomic, readonly, nullable) WebKit::WebViewImpl *_viewImpl;

@property (nonatomic, readonly, nullable) WebKit::WebPageProxy *_page;

@end

// MARK: WKAppKitGestureController + Click Handling

@interface WKAppKitGestureController (ClickHandling)

- (void)_handleClickBegan:(NSGestureRecognizer *)gesture;

- (void)_handleClickEnded:(NSGestureRecognizer *)gesture;

- (void)_handleClickCancelled;

- (void)_endPotentialClickAndEnableDoubleClickGesturesIfNecessary;

- (void)_setDoubleClickGesturesEnabled:(BOOL)enabled;

@end

// MARK: WKAppKitGestureController + Wheel Event Handling

@interface WKAppKitGestureController (WheelEventHandling)

- (void)sendWheelEventForGesture:(NSPanGestureRecognizer *)gesture;

@end

// MARK: WKAppKitGestureController + Momentum Handling

@interface WKAppKitGestureController (MomentumHandling)

- (void)startMomentumIfNeededForGesture:(NSPanGestureRecognizer *)gesture;

- (void)interruptMomentumIfNeeded;

@end

// MARK: WKAppKitGestureController + Gesture Recognition

@interface WKAppKitGestureController (GestureRecognition)

- (void)panGestureRecognized:(NSGestureRecognizer *)gesture;

- (void)singleClickGestureRecognized:(NSGestureRecognizer *)gesture;

- (void)doubleClickGestureRecognized:(NSGestureRecognizer *)gesture;

- (void)secondaryClickGestureRecognized:(NSGestureRecognizer *)gesture;

@end

// MARK: WKAppKitGestureController + NSGestureRecognizerDelegatePrivate

@interface WKAppKitGestureController (NSGestureRecognizerDelegate) <NSGestureRecognizerDelegatePrivate>

@end

NS_HEADER_AUDIT_END(nullability, sendability)

#endif // HAVE(APPKIT_GESTURES_SUPPORT)
