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

#if PLATFORM(IOS_FAMILY) && !PLATFORM(MACCATALYST)

#import "PlatformUtilities.h"
#import "Test.h"
#import "TestCocoa.h"
#import "TestNavigationDelegate.h"
#import "TestWKWebView.h"
#import "TestWKWebViewController.h"
#import "UIKitSPIForTesting.h"
#import "UIKitUtilities.h"
#import "UserInterfaceSwizzler.h"
#import "WKWebViewConfigurationExtras.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <WebKit/WKUIDelegatePrivate.h>
#import <WebKit/WKWebViewPrivateForTesting.h>
#import <WebKit/_WKActivatedElementInfo.h>
#import <WebKit/_WKElementAction.h>
#import <wtf/BlockPtr.h>
#import <wtf/RetainPtr.h>
#import <wtf/SoftLinking.h>

@interface ActionSheetObserver : NSObject<WKUIDelegatePrivate>
@property (nonatomic) BlockPtr<NSArray *(_WKActivatedElementInfo *, NSArray *)> presentationHandler;
@property (nonatomic) BlockPtr<NSDictionary *(void)> dataDetectionContextHandler;
@end

@implementation ActionSheetObserver

- (NSArray *)_webView:(WKWebView *)webView actionsForElement:(_WKActivatedElementInfo *)element defaultActions:(NSArray<_WKElementAction *> *)defaultActions
{
    return _presentationHandler ? _presentationHandler(element, defaultActions) : defaultActions;
}

- (NSDictionary *)_dataDetectionContextForWebView:(WKWebView *)WebView
{
    return _dataDetectionContextHandler ? _dataDetectionContextHandler() : @{ };
}

@end

#if ENABLE(ACCESSIBILITY_ANIMATION_CONTROL)
@interface TestWKWebViewForAnimationControls : TestWKWebView
- (BOOL)_allowAnimationControls;
@end

@implementation TestWKWebViewForAnimationControls
- (BOOL)_allowAnimationControls
{
    return YES;
}
@end
#endif // ENABLE(ACCESSIBILITY_ANIMATION_CONTROL)

namespace TestWebKitAPI {

static RetainPtr<UIViewController> gOverrideViewControllerForFullscreenPresentation;
static void setOverrideViewControllerForFullscreenPresentation(UIViewController *viewController)
{
    gOverrideViewControllerForFullscreenPresentation = viewController;
}

static UIViewController *overrideViewControllerForFullscreenPresentation()
{
    return gOverrideViewControllerForFullscreenPresentation.get();
}

TEST(ActionSheetTests, DISABLED_DismissingActionSheetShouldNotDismissPresentingViewController)
{
    IPadUserInterfaceSwizzler iPadUserInterface;
    TestWebKitAPI::Util::instantiateUIApplicationIfNeeded();

    auto navigationDelegate = adoptNS([[TestNavigationDelegate alloc] init]);
    auto window = adoptNS([[TestWKWebViewControllerWindow alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)]);
    auto rootViewController = adoptNS([[UIViewController alloc] init]);
    auto navigationController = adoptNS([[UINavigationController alloc] initWithRootViewController:rootViewController.get()]);
    auto observer = adoptNS([[ActionSheetObserver alloc] init]);
    [window setRootViewController:navigationController.get()];
    [window makeKeyAndVisible];

    auto webViewController = adoptNS([[TestWKWebViewController alloc] initWithFrame:CGRectMake(0, 0, 1024, 768) configuration:nil]);
    TestWKWebView *webView = [webViewController webView];
    webView.UIDelegate = observer.get();
    [webView synchronouslyLoadTestPageNamed:@"link-and-input"];
    [webView setNavigationDelegate:navigationDelegate.get()];
    [rootViewController presentViewController:webViewController.get() animated:NO completion:nil];

    // Since TestWebKitAPI is not a UI application, -[UIView _wk_viewControllerForFullScreenPresentation]
    // returns nil. To ensure that we actually present the action sheet from the web view controller, we mock this for the
    // time being until https://webkit.org/b/175204 is fixed.
    setOverrideViewControllerForFullscreenPresentation(webViewController.get());
    InstanceMethodSwizzler swizzler([UIView class], @selector(_wk_viewControllerForFullScreenPresentation), reinterpret_cast<IMP>(overrideViewControllerForFullscreenPresentation));

    [observer setPresentationHandler:^(_WKActivatedElementInfo *, NSArray *actions) {
        // Killing the web content process should dismiss the action sheet.
        // This should not tell the web view controller to dismiss in the process.
        [webView _killWebContentProcess];
        return actions;
    }];

    __block bool done = false;
    [navigationDelegate setWebContentProcessDidTerminate:^(WKWebView *, _WKProcessTerminationReason) {
        dispatch_async(dispatch_get_main_queue(), ^{
            done = true;
        });
    }];

    __block bool didDismissWebViewController = false;
    [webViewController setDismissalHandler:^{
        didDismissWebViewController = true;
    }];

    [webView _simulateLongPressActionAtLocation:CGPointMake(100, 100)];
    TestWebKitAPI::Util::run(&done);

    EXPECT_FALSE(didDismissWebViewController);
    EXPECT_NULL([webViewController presentedViewController]);
    EXPECT_NOT_NULL([webViewController presentingViewController]);
}

TEST(ActionSheetTests, ImageMapDoesNotDestroySelection)
{
    IPadUserInterfaceSwizzler iPadUserInterface;

    auto webView = adoptNS([[TestWKWebView alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)]);
    auto observer = adoptNS([[ActionSheetObserver alloc] init]);
    [webView setUIDelegate:observer.get()];
    [webView synchronouslyLoadTestPageNamed:@"image-map"];
    [webView stringByEvaluatingJavaScript:@"selectTextNode(h1.childNodes[0])"];

    EXPECT_WK_STREQ("Hello world", [webView stringByEvaluatingJavaScript:@"getSelection().toString()"]);

    __block bool done = false;
    [observer setPresentationHandler:^(_WKActivatedElementInfo *element, NSArray *actions) {
        done = true;
        return actions;
    }];
    [webView _simulateLongPressActionAtLocation:CGPointMake(200, 200)];
    TestWebKitAPI::Util::run(&done);

    EXPECT_WK_STREQ("Hello world", [webView stringByEvaluatingJavaScript:@"getSelection().toString()"]);
}

static UIView *swizzledResizableSnapshotViewFromRect(id, SEL, CGRect rect, BOOL, UIEdgeInsets)
{
    return adoptNS([[UIView alloc] initWithFrame:CGRectMake(0, 0, rect.size.width, rect.size.height)]).autorelease();
}

TEST(ActionSheetTests, DataDetectorsLinkIsNotPresentedAsALink)
{
    IPadUserInterfaceSwizzler iPadUserInterface;
    InstanceMethodSwizzler snapshotViewSwizzler {
        UIView.class,
        @selector(resizableSnapshotViewFromRect:afterScreenUpdates:withCapInsets:),
        reinterpret_cast<IMP>(swizzledResizableSnapshotViewFromRect)
    };

    auto webView = adoptNS([[TestWKWebView alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)]);
    auto observer = adoptNS([[ActionSheetObserver alloc] init]);
    [webView setUIDelegate:observer.get()];

    auto runTest = ^(NSString *phoneNumber) {
        [webView synchronouslyLoadHTMLString:[NSString stringWithFormat:@"<a style='position: absolute; top: 0; left: 0;' href='tel:%@'>telephone number</a>", phoneNumber]];

        __block bool done = false;
        __block bool succeeded = true;

        // We shouldn't present a normal action sheet, but instead a data detectors sheet.
        [observer setDataDetectionContextHandler:^{
            done = true;
            return @{ @"unused" : [NSUUID UUID] };
        }];
        [observer setPresentationHandler:^(_WKActivatedElementInfo *, NSArray *) {
            done = true;
            succeeded = false;
            return @[ ];
        }];
        [webView _simulateLongPressActionAtLocation:CGPointMake(5, 5)];
        TestWebKitAPI::Util::run(&done);

        return succeeded;
    };

    EXPECT_TRUE(runTest(@"4089961010"));
    EXPECT_TRUE(runTest(@"408 996 1010"));
    EXPECT_TRUE(runTest(@"1-866-MY-APPLE"));
    EXPECT_TRUE(runTest(@"(123) 456 - 7890"));
    EXPECT_TRUE(runTest(@"01 23 45 67 00"));
    EXPECT_TRUE(runTest(@"+33 (0)1 23 34 45 56"));
    EXPECT_TRUE(runTest(@"(0)1 12 23 34 56"));
    EXPECT_TRUE(runTest(@"010-1-800-MY-APPLE"));
    EXPECT_TRUE(runTest(@"+1-408-1234567"));
    EXPECT_TRUE(runTest(@"０８０８０８０８０８０"));
}

#if !PLATFORM(WATCHOS) && !PLATFORM(APPLETV)

static void presentActionSheetAndChooseAction(WKWebView *webView, ActionSheetObserver *observer, CGPoint location, _WKElementActionType actionType)
{
    __block RetainPtr<_WKElementAction> copyAction;
    __block RetainPtr<_WKActivatedElementInfo> copyElement;
    __block bool done = false;
    [observer setPresentationHandler:^(_WKActivatedElementInfo *element, NSArray *actions) {
        copyElement = element;
        for (_WKElementAction *action in actions) {
            if (action.type == actionType)
                copyAction = action;
        }
        done = true;
        return @[ copyAction.get() ];
    }];
    [webView _simulateLongPressActionAtLocation:location];
    TestWebKitAPI::Util::run(&done);

    EXPECT_TRUE(!!copyAction);
    EXPECT_TRUE(!!copyElement);
    [copyAction runActionWithElementInfo:copyElement.get()];
}

TEST(ActionSheetTests, CopyImageElementWithHREFAndTitle)
{
    TestWebKitAPI::Util::instantiateUIApplicationIfNeeded();
    [UIPasteboard generalPasteboard].items = @[ ];

    auto webView = adoptNS([[TestWKWebView alloc] initWithFrame:CGRectMake(0, 0, 320, 500)]);
    auto observer = adoptNS([[ActionSheetObserver alloc] init]);
    [webView setUIDelegate:observer.get()];
    [webView synchronouslyLoadTestPageNamed:@"image-in-link-and-input"];
    [webView stringByEvaluatingJavaScript:@"document.querySelector('a').setAttribute('title', 'hello world')"];

    presentActionSheetAndChooseAction(webView.get(), observer.get(), CGPointMake(100, 50), _WKElementActionTypeCopy);

    __block bool done = false;
    __block RetainPtr<NSItemProvider> itemProvider;
    [webView _doAfterNextPresentationUpdate:^() {
        NSArray <NSString *> *pasteboardTypes = [[UIPasteboard generalPasteboard] pasteboardTypes];
        EXPECT_EQ(2UL, pasteboardTypes.count);
        EXPECT_WK_STREQ((__bridge NSString *)kUTTypePNG, pasteboardTypes.firstObject);
        EXPECT_WK_STREQ((__bridge NSString *)kUTTypeURL, pasteboardTypes.lastObject);
        NSArray <NSItemProvider *> *itemProviders = [[UIPasteboard generalPasteboard] itemProviders];
        EXPECT_EQ(1UL, itemProviders.count);
        itemProvider = itemProviders.firstObject;
        EXPECT_EQ(2UL, [itemProvider registeredTypeIdentifiers].count);
        EXPECT_WK_STREQ((__bridge NSString *)kUTTypePNG, [itemProvider registeredTypeIdentifiers].firstObject);
        EXPECT_WK_STREQ((__bridge NSString *)kUTTypeURL, [itemProvider registeredTypeIdentifiers].lastObject);
        done = true;
    }];
    TestWebKitAPI::Util::run(&done);

    __block bool doneLoading = false;
    [itemProvider loadObjectOfClass:[NSURL class] completionHandler:^(id <NSItemProviderReading> result, NSError *) {
        EXPECT_TRUE([result isKindOfClass:[NSURL class]]);
        NSURL *url = (NSURL *)result;
        EXPECT_WK_STREQ("https://www.apple.com/", url.absoluteString);
        EXPECT_WK_STREQ("hello world", url._title);
        doneLoading = true;
    }];
    TestWebKitAPI::Util::run(&doneLoading);
}

TEST(ActionSheetTests, CopyImageElementWithHREF)
{
    TestWebKitAPI::Util::instantiateUIApplicationIfNeeded();
    [UIPasteboard generalPasteboard].items = @[ ];

    auto webView = adoptNS([[TestWKWebView alloc] initWithFrame:CGRectMake(0, 0, 320, 500)]);
    auto observer = adoptNS([[ActionSheetObserver alloc] init]);
    [webView setUIDelegate:observer.get()];
    [webView synchronouslyLoadTestPageNamed:@"image-in-link-and-input"];

    presentActionSheetAndChooseAction(webView.get(), observer.get(), CGPointMake(100, 50), _WKElementActionTypeCopy);

    __block bool done = false;
    __block RetainPtr<NSItemProvider> itemProvider;
    [webView _doAfterNextPresentationUpdate:^() {
        NSArray <NSString *> *pasteboardTypes = [[UIPasteboard generalPasteboard] pasteboardTypes];
        EXPECT_EQ(2UL, pasteboardTypes.count);
        EXPECT_WK_STREQ((__bridge NSString *)kUTTypePNG, pasteboardTypes.firstObject);
        EXPECT_WK_STREQ((__bridge NSString *)kUTTypeURL, pasteboardTypes.lastObject);
        NSArray <NSItemProvider *> *itemProviders = [[UIPasteboard generalPasteboard] itemProviders];
        EXPECT_EQ(1UL, itemProviders.count);
        itemProvider = itemProviders.firstObject;
        EXPECT_EQ(2UL, [itemProvider registeredTypeIdentifiers].count);
        EXPECT_WK_STREQ((__bridge NSString *)kUTTypePNG, [itemProvider registeredTypeIdentifiers].firstObject);
        EXPECT_WK_STREQ((__bridge NSString *)kUTTypeURL, [itemProvider registeredTypeIdentifiers].lastObject);
        done = true;
    }];
    TestWebKitAPI::Util::run(&done);

    __block bool doneLoading = false;
    [itemProvider loadObjectOfClass:[NSURL class] completionHandler:^(id <NSItemProviderReading> result, NSError *) {
        EXPECT_TRUE([result isKindOfClass:[NSURL class]]);
        NSURL *url = (NSURL *)result;
        EXPECT_WK_STREQ("https://www.apple.com/", url.absoluteString);
        EXPECT_WK_STREQ("https://www.apple.com/", url._title);
        doneLoading = true;
    }];
    TestWebKitAPI::Util::run(&doneLoading);
}

TEST(ActionSheetTests, CopyImageElementWithoutHREF)
{
    TestWebKitAPI::Util::instantiateUIApplicationIfNeeded();
    [UIPasteboard generalPasteboard].items = @[ ];

    auto webView = adoptNS([[TestWKWebView alloc] initWithFrame:CGRectMake(0, 0, 320, 500)]);
    auto observer = adoptNS([[ActionSheetObserver alloc] init]);
    [webView setUIDelegate:observer.get()];
    [webView synchronouslyLoadTestPageNamed:@"image-and-contenteditable"];

    presentActionSheetAndChooseAction(webView.get(), observer.get(), CGPointMake(100, 100), _WKElementActionTypeCopy);

    __block bool done = false;
    [webView _doAfterNextPresentationUpdate:^() {
        NSArray <NSString *> *pasteboardTypes = [[UIPasteboard generalPasteboard] pasteboardTypes];
        EXPECT_EQ(1UL, pasteboardTypes.count);
        EXPECT_WK_STREQ((__bridge NSString *)kUTTypePNG, pasteboardTypes.firstObject);
        NSArray <NSItemProvider *> *itemProviders = [[UIPasteboard generalPasteboard] itemProviders];
        EXPECT_EQ(1UL, itemProviders.count);
        NSItemProvider *itemProvider = itemProviders.firstObject;
        EXPECT_EQ(1UL, itemProvider.registeredTypeIdentifiers.count);
        EXPECT_WK_STREQ((__bridge NSString *)kUTTypePNG, itemProvider.registeredTypeIdentifiers.firstObject);
        done = true;
    }];
    TestWebKitAPI::Util::run(&done);
}

TEST(ActionSheetTests, CopyLinkWritesURLAndPlainText)
{
    TestWebKitAPI::Util::instantiateUIApplicationIfNeeded();
    [UIPasteboard generalPasteboard].items = @[ ];

    auto webView = adoptNS([[TestWKWebView alloc] initWithFrame:CGRectMake(0, 0, 320, 500)]);
    auto observer = adoptNS([[ActionSheetObserver alloc] init]);
    [webView setUIDelegate:observer.get()];
    [webView synchronouslyLoadTestPageNamed:@"link-and-input"];

    presentActionSheetAndChooseAction(webView.get(), observer.get(), CGPointMake(100, 100), _WKElementActionTypeCopy);

    [webView synchronouslyLoadTestPageNamed:@"DataTransfer"];
    [webView paste:nil];

    EXPECT_WK_STREQ("text/uri-list, text/plain", [webView stringByEvaluatingJavaScript:@"types.textContent"]);
    EXPECT_WK_STREQ("(STRING, text/uri-list), (STRING, text/plain)", [webView stringByEvaluatingJavaScript:@"items.textContent"]);
    EXPECT_WK_STREQ("", [webView stringByEvaluatingJavaScript:@"files.textContent"]);
    EXPECT_WK_STREQ("https://www.apple.com/", [webView stringByEvaluatingJavaScript:@"textData.textContent"]);
    EXPECT_WK_STREQ("https://www.apple.com/", [webView stringByEvaluatingJavaScript:@"urlData.textContent"]);
    EXPECT_WK_STREQ("", [webView stringByEvaluatingJavaScript:@"htmlData.textContent"]);
    EXPECT_WK_STREQ("", [webView stringByEvaluatingJavaScript:@"rawHTMLData.textContent"]);
}

#endif // !PLATFORM(WATCHOS) && !PLATFORM(APPLETV)

#if ENABLE(ACCESSIBILITY_ANIMATION_CONTROL)
static void performLongPressAction(WKWebView *webView, ActionSheetObserver *observer, CGPoint originalLocation, _WKElementActionType actionType)
{
    // This function spins until it finds the specified action type.
    // To avoid hitting InteractionInformationAtPosition caches, use a slightly different long-press location each attempt.
    bool shouldAlterPressLocation = false;
    __block RetainPtr<_WKElementAction> copyAction;
    __block RetainPtr<_WKActivatedElementInfo> copyElement;
    while (!copyAction) {
        // First reset interaction state (simulating real behavior in a long-press, dismiss sheet, long-press cycle).
        [webView _resetInteraction];

        CGPoint location = shouldAlterPressLocation ? CGPointMake(originalLocation.x, originalLocation.y - 1) : originalLocation;
        shouldAlterPressLocation = !shouldAlterPressLocation;

        __block bool done = false;
        [observer setPresentationHandler:^(_WKActivatedElementInfo *element, NSArray *actions) {
            copyElement = element;
            for (_WKElementAction *action in actions) {
                if (action.type == actionType)
                    copyAction = action;
            }
            done = true;
            return actions;
        }];
        [webView _simulateLongPressActionAtLocation:location];
        TestWebKitAPI::Util::run(&done);

        // Spin a bit to allow underlying data structures to update, hopefully resulting in our expected action appearing next long-press.
        if (!copyAction)
            TestWebKitAPI::Util::runFor(0.1_s);
    }

    EXPECT_TRUE(!!copyElement);
    [copyAction runActionWithElementInfo:copyElement.get()];
}

static void playPauseAnimationTest(NSString *testFilename)
{
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration _test_configurationWithTestPlugInClassName:@"WebProcessPlugInWithInternals" configureJSCForTesting:YES];
    auto webView = adoptNS([[TestWKWebViewForAnimationControls alloc] initWithFrame:CGRectMake(0, 0, 320, 500) configuration:configuration addToWindow:YES]);
    auto observer = adoptNS([[ActionSheetObserver alloc] init]);
    [webView setUIDelegate:observer.get()];
    [webView synchronouslyLoadTestPageNamed:testFilename];
    [webView stringByEvaluatingJavaScript:@"window.internals.settings.setImageAnimationControlEnabled(true)"];
    // Pause animations globally to establish a known state.
    [webView stringByEvaluatingJavaScript:@"window.internals.setImageAnimationEnabled(false)"];

    // Start the animation.
    performLongPressAction(webView.get(), observer.get(), CGPointMake(100, 100), _WKElementActionPlayAnimation);

    // After the animation begins playing again, expect to have "Pause Animation" in the action sheet.
    performLongPressAction(webView.get(), observer.get(), CGPointMake(100, 100), _WKElementActionPauseAnimation);

    // Wait until we have "Play Animation" again (indicating the animation was successfully paused).
    performLongPressAction(webView.get(), observer.get(), CGPointMake(100, 100), _WKElementActionPlayAnimation);
}

TEST(ActionSheetTests, PlayPauseAnimationInsideLink)
{
    playPauseAnimationTest(@"img-animation-in-anchor");
}

TEST(ActionSheetTests, PlayPauseAnimationCoveredByLink)
{
    playPauseAnimationTest(@"img-animation-covered-by-link");
}

TEST(ActionSheetTests, PlayPauseAnimationSheetActionsNotPresentByDefault)
{
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration _test_configurationWithTestPlugInClassName:@"WebProcessPlugInWithInternals" configureJSCForTesting:YES];
    // Note that this is a TestWKWebView, not a TestWKWebViewForAnimationControls, which has the necessary testing only override.
    // Without the testing override, the only way "Play Animation" and "Pause Animation" should appear is when a system setting is in a non-default state.
    // So this test ensures these actions are not available by default.
    auto webView = adoptNS([[TestWKWebView alloc] initWithFrame:CGRectMake(0, 0, 320, 500) configuration:configuration addToWindow:YES]);
    auto observer = adoptNS([[ActionSheetObserver alloc] init]);
    [webView setUIDelegate:observer.get()];
    [webView synchronouslyLoadTestPageNamed:@"img-animation-in-anchor"];
    [webView stringByEvaluatingJavaScript:@"window.internals.settings.setImageAnimationControlEnabled(true)"];

    __block bool done = false;
    [observer setPresentationHandler:^(_WKActivatedElementInfo *element, NSArray *actions) {
        for (_WKElementAction *action in actions) {
            EXPECT_FALSE(action.type == _WKElementActionPlayAnimation);
            EXPECT_FALSE(action.type == _WKElementActionPauseAnimation);
        }
        done = true;
        return @[ ];
    }];
    [webView _simulateLongPressActionAtLocation:CGPointMake(100, 100)];
    TestWebKitAPI::Util::run(&done);
}
#endif // ENABLE(ACCESSIBILITY_ANIMATION_CONTROL)

} // namespace TestWebKitAPI

#endif // PLATFORM(IOS_FAMILY) && !PLATFORM(MACCATALYST)
