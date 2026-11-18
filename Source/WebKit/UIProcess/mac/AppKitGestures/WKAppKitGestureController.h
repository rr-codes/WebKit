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

#import "WKDeferringGestureRecognizer.h"
#import "WKPointerTrackingGestureRecognizer.h"
#import "WKPressGestureRecognizer.h"
#import <AppKit/NSGestureRecognizer.h>
#import <wtf/Forward.h>
#import <wtf/ObjectIdentifier.h>
#import <wtf/Vector.h>

#if !__has_feature(modules)
#import "IdentifierTypes.h"
#endif

namespace WebCore {
class Color;
class CornerRadii;
class FloatQuad;
}

namespace WebKit {
struct InteractionInformationAtPosition;
}

OBJC_CLASS WKAppKitGestureControllerCxxSupport;
OBJC_CLASS WKClickHighlightController;
OBJC_CLASS WKWebView;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

NS_SWIFT_UI_ACTOR
@interface WKAppKitGestureController : NSObject <NSGestureRecognizerDelegate, WKPointerTrackingGestureRecognizerDelegate, WKPressGestureRecognizerDelegate>

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithView:(WKWebView *)view NS_DESIGNATED_INITIALIZER;
- (void)setUp;
- (void)preferencesDidChange;
- (void)beginSuppressingSingleClickGestureForTextSelection;
- (void)endSuppressingSingleClickGestureForTextSelection;
- (nullable NSGestureRecognizer *)activeDragGestureRecognizer;
- (void)didReceiveDragStart;
- (void)setGestureDraggingSession:(nullable NSDraggingSession *)session;
- (void)clearGestureDragState;
- (void)setTextSelectionDragGesture:(NSGestureRecognizer *)gesture completionHandler:(void (^)(NSDraggingSession *))completionHandler;
- (void)didCommitLoadForMainFrame;
- (void)transformGestureWasNotHandledByContent;
- (void)interruptMomentumForScrollWheelEvent;
- (void)cancelClickHighlight;
- (void)reset;

@property (nonatomic, readonly) BOOL everMagnifiedDuringCurrentGesture;

#if ENABLE(TWO_PHASE_CLICKS)
@property (nonatomic, readonly, getter=isPotentialTapInProgress) BOOL potentialTapInProgress;
@property (nonatomic, readonly, nullable) WKClickHighlightController *clickHighlightController;
- (void)commitPotentialTapFailed;
- (void)didCompleteSyntheticClick;
- (void)didHandleTapAsHover;
- (void)disableDoubleTapGesturesDuringTapIfNecessaryForRequest:(uint64_t)requestID;
- (void)didNotHandleTapAsClickAtPoint:(NSPoint)point;
#endif

@property (nonatomic, readonly, nullable) WKWebView *webView;

@end

@interface WKAppKitGestureController (CxxSupport)
- (WKAppKitGestureControllerCxxSupport *)_cxxSupport NS_SWIFT_NAME(cxxSupportForObjectiveC());
- (void)generatedMomentumDidEnd;
@end

@interface WKAppKitGestureController (Internal)
- (WKClickHighlightController *)_makeClickHighlightController NS_SWIFT_NAME(makeClickHighlightController());
@end

#if !__has_feature(modules)
@interface WKAppKitGestureController (WebViewImpl)
- (void)positionInformationDidChange:(const WebKit::InteractionInformationAtPosition&)info;
#if ENABLE(TWO_PHASE_CLICKS)
- (void)didGetTapHighlightForRequest:(WebKit::TapIdentifier)requestID color:(const WebCore::Color&)color quads:(const Vector<WebCore::FloatQuad>&)highlightedQuads cornerRadii:(WebCore::CornerRadii&&)cornerRadii nodeHasBuiltInClickHandling:(BOOL)nodeHasBuiltInClickHandling;
#endif
@end

#endif

@interface WKAppKitGestureController (WKDeferringGestureRecognizerDelegate) <WKDeferringGestureRecognizerDelegate>
@end

NS_HEADER_AUDIT_END(nullability, sendability)

#endif // HAVE(APPKIT_GESTURES_SUPPORT)
