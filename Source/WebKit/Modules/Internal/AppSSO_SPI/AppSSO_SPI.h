/*
 * Copyright (C) 2019-2026 Apple Inc. All rights reserved.
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

// Swift-visible declarations of AppSSO's types, which the public SDKs do not ship (their AppSSO is a link stub).
// The text is the part of the public-SDK branch of Source/WebCore/PAL/pal/spi/cocoa/AppSSOSPI.h that WebKit's Swift calls.
// Only Swift under #if HAVE_APP_SSO imports this module.

#import <Foundation/Foundation.h>

#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
typedef UIViewController * SOAuthorizationViewController;
#elif __has_include(<AppKit/AppKit.h>)
typedef id SOAuthorizationViewController;
#endif

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

#define kSOErrorAuthorizationPresentationFailed -7

@protocol SOAuthorizationHintsProtocol;
@protocol SOAuthorizationDelegate;

// No AppSSO class is declared, so Swift cannot name one before PAL's soft link loads it: each class is seen through a
// protocol of its methods, and the class object through a WebKit accessor that loads AppSSO first.
@protocol SOAuthorizationProtocol <NSObject>
@property (weak) id<SOAuthorizationDelegate> delegate;
- (void)getAuthorizationHintsWithURL:(NSURL *)url responseCode:(NSInteger)responseCode completion:(void (^)(id<SOAuthorizationHintsProtocol> _Nullable_result authorizationHints, NSError * _Nullable error))completion;
- (void)cancelAuthorization;
@end

@protocol SOAuthorizationHintsProtocol <NSObject>
@property (nonatomic, readonly) NSString *localizedExtensionBundleDisplayName;
@end

// SOAuthorization's class methods, as the class object's.
@protocol SOAuthorizationClassProtocol <NSObject>
- (id<SOAuthorizationProtocol>)new NS_SWIFT_NAME(makeAuthorization());
- (BOOL)canPerformAuthorizationWithURL:(NSURL *)url responseCode:(NSInteger)responseCode;
- (void)canPerformAuthorizationWithURL:(NSURL *)url responseCode:(NSInteger)responseCode callerBundleIdentifier:(NSString * _Nullable)callerBundleIdentifier useInternalExtensions:(BOOL)useInternalExtensions completion:(void (^)(BOOL))completion;
@end

@protocol SOAuthorizationDelegate <NSObject>
@optional
- (void)authorizationDidNotHandle:(id<SOAuthorizationProtocol>)authorization;
- (void)authorizationDidCancel:(id<SOAuthorizationProtocol>)authorization;
- (void)authorizationDidComplete:(id<SOAuthorizationProtocol>)authorization;
- (void)authorization:(id<SOAuthorizationProtocol>)authorization didCompleteWithHTTPAuthorizationHeaders:(NSDictionary<NSString *, NSString *> *)httpAuthorizationHeaders;
- (void)authorization:(id<SOAuthorizationProtocol>)authorization didCompleteWithHTTPResponse:(NSHTTPURLResponse *)httpResponse httpBody:(NSData *)httpBody;
- (void)authorization:(id<SOAuthorizationProtocol>)authorization didCompleteWithError:(NSError *)error;
- (void)authorization:(id<SOAuthorizationProtocol>)authorization presentViewController:(nullable SOAuthorizationViewController)viewController withCompletion:(void (^)(BOOL success, NSError * _Nullable error))completion NS_SWIFT_NAME(authorization(_:presentViewController:withCompletion:));
@end

NS_HEADER_AUDIT_END(nullability, sendability)
