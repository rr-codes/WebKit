/*
 * Copyright (C) 2017 Apple Inc. All rights reserved.
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

#import "config.h"

#if ENABLE(MEDIA_STREAM) && PLATFORM(MAC)

#import "DeprecatedGlobalValues.h"
#import "PlatformUtilities.h"
#import "Test.h"
#import "TestWKWebView.h"
#import <WebKit/WKPreferencesPrivate.h>
#import <WebKit/WKUIDelegatePrivate.h>
#import <WebKit/WKWebView.h>
#import <WebKit/WKWebViewConfiguration.h>
#import <WebKit/WKWebViewConfigurationPrivate.h>
#import <WebKit/WKWebViewPrivateForTesting.h>

static bool shouldDeny = false;
static bool systemCanPromptForCapture = false;

@interface GetDisplayMediaMessageHandler : NSObject <WKScriptMessageHandler>
@end

@implementation GetDisplayMediaMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
    lastScriptMessage = message;
    receivedScriptMessage = true;
}
@end

@interface GetDisplayMediaUIDelegate : NSObject<WKUIDelegate>

- (void)_webView:(WKWebView *)webView requestDisplayCapturePermissionForOrigin:(WKSecurityOrigin *)securityOrigin initiatedByFrame:(WKFrameInfo *)frame withSystemAudio:(BOOL)withSystemAudio decisionHandler:(void (^)(WKDisplayCapturePermissionDecision decision))decisionHandler;
- (void)_webView:(WKWebView *)webView checkUserMediaPermissionForURL:(NSURL *)url mainFrameURL:(NSURL *)mainFrameURL frameIdentifier:(NSUInteger)frameIdentifier decisionHandler:(void (^)(NSString *salt, BOOL authorized))decisionHandler;
@end

@implementation GetDisplayMediaUIDelegate
- (void)_webView:(WKWebView *)webView requestDisplayCapturePermissionForOrigin:(WKSecurityOrigin *)securityOrigin initiatedByFrame:(WKFrameInfo *)frame withSystemAudio:(BOOL)withSystemAudio decisionHandler:(void (^)(WKDisplayCapturePermissionDecision decision))decisionHandler
{
    wasPrompted = true;

    if (shouldDeny) {
        decisionHandler(WKDisplayCapturePermissionDecisionDeny);
        return;
    }

    decisionHandler(WKDisplayCapturePermissionDecisionScreenPrompt);
}

- (void)_webView:(WKWebView *)webView checkUserMediaPermissionForURL:(NSURL *)url mainFrameURL:(NSURL *)mainFrameURL frameIdentifier:(NSUInteger)frameIdentifier decisionHandler:(void (^)(NSString *salt, BOOL authorized))decisionHandler
{
    decisionHandler(@"0x987654321", YES);
}
@end

@interface MediaCaptureUIDelegate : NSObject<WKUIDelegate>
- (void)webView:(WKWebView *)webView requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin initiatedByFrame:(WKFrameInfo *)frame type:(WKMediaCaptureType)type decisionHandler:(WK_SWIFT_UI_ACTOR void (^)(WKPermissionDecision decision))decisionHandler;
@end
@implementation MediaCaptureUIDelegate
- (void)webView:(WKWebView *)webView requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin initiatedByFrame:(WKFrameInfo *)frame type:(WKMediaCaptureType)type decisionHandler:(WK_SWIFT_UI_ACTOR void (^)(WKPermissionDecision decision))decisionHandler
{
    decisionHandler(WKPermissionDecisionDeny);
}
@end

namespace TestWebKitAPI {

class GetDisplayMediaTest : public testing::Test {
public:
    enum class UseGetDisplayMediaUIDelegate : bool { No, Yes };

    virtual void SetUp() { SetUpInternal(UseGetDisplayMediaUIDelegate::Yes); }

    bool haveStream(bool expected)
    {
        int retryCount = 10;
        while (retryCount--) {
            auto result = [m_webView stringByEvaluatingJavaScript:@"haveStream()"];
            if (result.boolValue == expected)
                return YES;

            TestWebKitAPI::Util::spinRunLoop(10);
        }

        return NO;
    }

    void promptForCapture(NSString* constraints, bool shouldSucceed)
    {
        auto constraintString = [constraints UTF8String];

        [m_webView _setSystemCanPromptForGetDisplayMediaForTesting:systemCanPromptForCapture];

        [m_webView stringByEvaluatingJavaScript:@"stop()"];
        EXPECT_TRUE(haveStream(false)) << " with contraint " << constraintString;

        wasPrompted = false;
        receivedScriptMessage = false;

        NSString *script = [NSString stringWithFormat:@"promptForCapture(%@)", constraints];
        [m_webView stringByEvaluatingJavaScript:script];

        TestWebKitAPI::Util::run(&receivedScriptMessage);
        auto getDisplayMediaResult = [(NSString *)[lastScriptMessage body] UTF8String];
        if (shouldSucceed) {
            EXPECT_STREQ(getDisplayMediaResult, "allowed") << " with contraint " << constraintString;
            EXPECT_TRUE(haveStream(true)) << " with contraint " << constraintString;
            if (!systemCanPromptForCapture)
                EXPECT_EQ(wasPrompted, hasDisplayCaptureDelegate()) << " with contraint " << constraintString;
            else
                EXPECT_FALSE(wasPrompted) << " with contraint " << constraintString;
        } else {
            EXPECT_STREQ(getDisplayMediaResult, "denied") << " with contraint " << constraintString;
            EXPECT_TRUE(haveStream(false)) << " with contraint " << constraintString;
            if (shouldDeny && !systemCanPromptForCapture)
                EXPECT_EQ(wasPrompted, hasDisplayCaptureDelegate()) << " with contraint " << constraintString;
            else
                EXPECT_FALSE(wasPrompted) << " with contraint " << constraintString;
        }
    }

protected:
    void SetUpInternal(UseGetDisplayMediaUIDelegate useGetDisplayMediaUIDelegate)
    {
        m_configuration = adoptNS([[WKWebViewConfiguration alloc] init]);
        auto context = adoptWK(TestWebKitAPI::Util::createContextForInjectedBundleTest("InternalsInjectedBundleTest"));
        m_configuration.get().processPool = (WKProcessPool *)context.get();

        auto handler = adoptNS([[GetDisplayMediaMessageHandler alloc] init]);
        [[m_configuration userContentController] addScriptMessageHandler:handler.get() name:@"testHandler"];

        auto preferences = [m_configuration preferences];
        preferences._mediaCaptureRequiresSecureConnection = NO;
        m_configuration.get()._mediaCaptureEnabled = YES;
        preferences._mockCaptureDevicesEnabled = YES;
        preferences._screenCaptureEnabled = YES;

        m_webView = adoptNS([[TestWKWebView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600) configuration:m_configuration.get() addToWindow:YES]);

        if (useGetDisplayMediaUIDelegate == UseGetDisplayMediaUIDelegate::Yes) {
            m_uiDelegate = adoptNS([[GetDisplayMediaUIDelegate alloc] init]);
            m_webView.get().UIDelegate = m_uiDelegate.get();
        } else {
            m_mediaCaptureUIDelegate = adoptNS([[MediaCaptureUIDelegate alloc] init]);
            m_webView.get().UIDelegate = m_mediaCaptureUIDelegate.get();
        }
        [m_webView focus];

        [m_webView synchronouslyLoadTestPageNamed:@"getDisplayMedia"];
    }

private:
    bool hasDisplayCaptureDelegate() const { return m_uiDelegate.get(); }

    RetainPtr<WKWebViewConfiguration> m_configuration;
    RetainPtr<GetDisplayMediaUIDelegate> m_uiDelegate;
    RetainPtr<MediaCaptureUIDelegate> m_mediaCaptureUIDelegate;
    RetainPtr<TestWKWebView> m_webView;
};

class GetDisplayMediaTestWithMediaCaptureDelegate : public GetDisplayMediaTest {
public:
    void SetUp() override { SetUpInternal(UseGetDisplayMediaUIDelegate::No); }
};

TEST_F(GetDisplayMediaTest, BasicPrompt)
{
    promptForCapture(@"{ audio: true, video: true }", true);
    promptForCapture(@"{ audio: true, video: false }", false);
    promptForCapture(@"{ audio: false, video: true }", true);
    promptForCapture(@"{ audio: false, video: false }", false);
}

TEST_F(GetDisplayMediaTest, Constraints)
{
    promptForCapture(@"{ video: {width: 640} }", true);
    promptForCapture(@"{ video: true, audio: { volume: 0.5 } }", true);
    promptForCapture(@"{ video: {height: 480}, audio: true }", true);
    promptForCapture(@"{ video: {width: { exact: 640} } }", false);
}

TEST_F(GetDisplayMediaTest, PromptOnceAfterDenial)
{
    promptForCapture(@"{ video: true }", true);
    shouldDeny = true;
    promptForCapture(@"{ video: true }", false);
    shouldDeny = false;
    promptForCapture(@"{ video: true }", true);
}

TEST_F(GetDisplayMediaTest, SystemCanPrompt)
{
    systemCanPromptForCapture = true;
    promptForCapture(@"{ audio: true, video: true }", true);
    promptForCapture(@"{ audio: true, video: false }", false);
    promptForCapture(@"{ audio: false, video: true }", true);
    promptForCapture(@"{ audio: false, video: false }", false);
    systemCanPromptForCapture = false;
}

TEST_F(GetDisplayMediaTestWithMediaCaptureDelegate, BasicPrompt)
{
    promptForCapture(@"{ audio: true, video: true }", true);
    promptForCapture(@"{ audio: true, video: false }", false);
    promptForCapture(@"{ audio: false, video: true }", true);
    promptForCapture(@"{ audio: false, video: false }", false);
}

} // namespace TestWebKitAPI

#endif // ENABLE(MEDIA_STREAM) && PLATFORM(MAC)
