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

#pragma once

#import <wtf/Platform.h>
#import <wtf/Compiler.h>

DECLARE_SYSTEM_HEADER

#if ENABLE(WRITING_TOOLS) && PLATFORM(MAC)

#if USE(APPLE_INTERNAL_SDK)

#import <WritingToolsUI/WritingToolsUI.h>
#import <WritingToolsUI/WritingToolsUI_Private.h>

#else

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
//#import "WritingToolsSPI.h"

typedef NS_ENUM(NSInteger, WTRequestedTool);

@protocol WTWritingToolsDelegate;

@interface _WTTextChunk : NSObject

@property (readonly) NSString *identifier;

- (instancetype)initChunkWithIdentifier:(NSString *)identifier;

@end

@interface _WTTextPreview : NSObject

@property (readonly) CGImageRef previewImage;

@property (readonly) CGPathRef contentPath;

@property (readonly) CGRect presentationFrame;

@property (readonly) CGColorRef backgroundColor;

@property (readonly) CGPathRef clippingPath;

@property (readonly) CGFloat scale;

@property (readonly) NSArray <NSValue *> *candidateRects;

- (instancetype)initWithSnapshotImage:(CGImageRef)snapshotImage
                    presentationFrame:(CGRect)presentationFrame;

- (instancetype)initWithSnapshotImage:(CGImageRef)snapshotImage
                    presentationFrame:(CGRect)presentationFrame
                      backgroundColor:(CGColorRef)backgroundColor
                         clippingPath:(CGPathRef)clippingPath
                                scale:(CGFloat)scale;

- (instancetype)initWithSnapshotImage:(CGImageRef)snapshotImage
                    presentationFrame:(CGRect)presentationFrame
                      backgroundColor:(CGColorRef)backgroundColor
                         clippingPath:(CGPathRef)clippingPath
                                scale:(CGFloat)scale
                       candidateRects:(NSArray <NSValue *> *)candidateRects;

- (instancetype)initWithContentPath:(CGPathRef)contentPath;

- (CALayer *)layerWithContents;

@end

//@protocol _WTTextPreviewSource <NSObject>
//
//- (NSArray <_WTTextPreview *> *)textPreviewsForChunk:(_WTTextChunk *)chunk;
//- (_WTTextPreview *)textPreviewForRect:(CGRect)rect;
//
//- (void)updateIsTextVisible:(BOOL)isTextVisible forChunk:(_WTTextChunk *)chunk;
//
//@end

@protocol _WTTextPreviewAsyncSource <NSObject>

// One or more text previews for a given chunk, broken into lines.
- (void)textPreviewsForChunk:(nonnull _WTTextChunk *)chunk completion:(void (^_Nullable)(NSArray <_WTTextPreview *> * _Nullable previews))completion;
- (void)textPreviewForRect:(CGRect)rect completion:(void (^_Nullable)(_WTTextPreview * _Nullable preview))completion;

// Update the visibility of text for a given chunk.
- (void)updateIsTextVisible:(BOOL)isTextVisible forChunk:(nonnull _WTTextChunk *)chunk completion:(void (^_Nullable)(void))completion;

@end

NS_ASSUME_NONNULL_BEGIN

@class _WTTextEffectView;

@protocol _WTTextEffect <NSObject>
@property (strong) _WTTextChunk *chunk;
@property (strong) _WTTextEffectView *effectView;
@property (strong) NSUUID *identifier;
- (void)updateEffectWith:(NSArray <_WTTextPreview *> *)snapshots;
- (void)updateAnimationForTimeDelta:(NSTimeInterval)timeDelta;
- (void)invalidate:(BOOL)animated;
@optional
- (BOOL)hidesOriginal;
@property (copy, nullable) void (^completion)(void);
@property (copy, nullable) void (^preCompletion)(void);
@end

@interface _WTTextEffect : NSObject <_WTTextEffect>

@property (strong) _WTTextChunk  *chunk;

@property (strong) _WTTextEffectView *effectView;

@property (strong) NSUUID *identifier;

@property BOOL hidesOriginal;

@property (copy, nullable) void (^completion)(void);

@property (copy, nullable) void (^preCompletion)(void);

- (instancetype)initWithChunk:(_WTTextChunk *)chunk effectView:(_WTTextEffectView *)effectView;

- (void)updateEffectWith:(NSArray <_WTTextPreview *> *)snapshots;

- (void)invalidate:(BOOL)animated;

@end

@interface _WTSweepTextEffect : _WTTextEffect

@end

@interface _WTReplaceTextEffect : _WTTextEffect

@property (assign) BOOL animateRemovalWhenDone;

@property BOOL isDestination;

@property BOOL highlightsCandidateRects;

@end

@interface _WTReplaceSourceTextEffect : _WTReplaceTextEffect
@end

@interface _WTReplaceDestinationTextEffect : _WTReplaceSourceTextEffect
@end

NS_ASSUME_NONNULL_END

NS_ASSUME_NONNULL_BEGIN

@interface WTWritingToolsViewController

@property (class, assign, readonly, getter=isAvailable) BOOL available;

@end

NS_ASSUME_NONNULL_END

NS_ASSUME_NONNULL_BEGIN

@interface WTWritingTools : NSObject

+ (instancetype)sharedInstance;

- (void)showTool:(WTRequestedTool)requestedTool
forSelectionRect:(NSRect)selectionRect
          ofView:(NSView *)positioningView
     forDelegate:(NSObject<WTWritingToolsDelegate> *)writingToolsDelegate;

- (void)scheduleShowAffordanceForSelectionRect:(NSRect)selectionRect
                                        ofView:(NSView *)positioningView
                                   forDelegate:(NSObject<WTWritingToolsDelegate> *)writingToolsDelegate;

@end

NS_ASSUME_NONNULL_END

@interface _WTTextEffectView : NSView

//@property (weak) id <_WTTextPreviewSource> source;
@property (weak) id <_WTTextPreviewAsyncSource> asyncSource;

//- (instancetype)initWithSource:(id <_WTTextPreviewSource>)source;
- (instancetype)initWithAsyncSource:(id <_WTTextPreviewAsyncSource>)asyncSource;

- (NSUUID *)addEffect:(_WTTextEffect *)effect; // weird?

- (_WTTextChunk *)removeEffect:(NSUUID *)effectID;
- (_WTTextChunk *)removeEffect:(NSUUID *)effectID animated:(BOOL)animated;

- (void)removeAllEffects;
- (void)removeAllEffectsAnimated:(BOOL)animated;

- (BOOL)hasActiveEffects;
- (BOOL)hasActiveEffect:(NSUUID *)effectID;

- (void)updateSnapshots;
- (void)updateSnapshotForEffectID:(NSUUID *)effectID;

@end

#endif // USE(APPLE_INTERNAL_SDK)

#endif // ENABLE(WRITING_TOOLS) && PLATFORM(MAC)
