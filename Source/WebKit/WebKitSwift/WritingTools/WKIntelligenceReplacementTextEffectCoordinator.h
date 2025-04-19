/*
 * Copyright (C) 2024 Apple Inc. All rights reserved.
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

#import <Foundation/Foundation.h>
#import <wtf/Platform.h>

#if !TARGET_OS_WATCH && !TARGET_OS_TV && HAVE(WRITING_TOOLS_FRAMEWORK)

#import "WKIntelligenceTextEffectCoordinator.h"
#import <pal/spi/cocoa/WritingToolsSPI.h>

NS_ASSUME_NONNULL_BEGIN

//#ifdef __swift__

//typedef NS_ENUM(NSInteger, WTTextSuggestionState) {
//    WTTextSuggestionStatePending = 0,
//    WTTextSuggestionStateReviewing = 1,
//    WTTextSuggestionStateRejected = 3,
//    WTTextSuggestionStateInvalid = 4,
//};

//#endif


//@interface WTTextSuggestion : NSObject
//
//@property (nonatomic, readonly) NSUUID *uuid;
//
//@property (nonatomic, readonly) NSRange originalRange;
//
//@property (nonatomic, readonly) NSString *replacement;
//
//@property (nonatomic) WTTextSuggestionState state;
//
//- (instancetype)initWithOriginalRange:(NSRange)originalRange replacement:(NSString *)replacement;
//
//@end

NS_SWIFT_UI_ACTOR
@interface WKIntelligenceReplacementTextEffectCoordinator : NSObject <WKIntelligenceTextEffectCoordinating>

@end

@interface WKIntelligenceReplacementTextEffectCoordinator (WTUI)

+ (NSInteger)characterDeltaForReceivedSuggestions:(NSArray<WTTextSuggestion *> *)suggestions;

@end

NS_ASSUME_NONNULL_END

#endif
