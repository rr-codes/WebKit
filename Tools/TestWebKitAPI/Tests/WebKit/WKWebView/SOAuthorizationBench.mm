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

#import "config.h"

#if HAVE(APP_SSO)

#import "ClassMethodSwizzler.h"
#import "Helpers/PlatformUtilities.h"
#import "Helpers/Test.h"
#import "Helpers/cocoa/TestNSBundleExtras.h"
#import "Helpers/cocoa/TestWKWebView.h"
#import "InstanceMethodSwizzler.h"
#import <WebKit/WKNavigationDelegatePrivate.h>
#import <WebKit/WKNavigationPrivate.h>
#import <WebKit/WKPreferencesPrivate.h>
#import <WebKit/WKWebViewPrivate.h>
#import <dlfcn.h>
#import <libproc.h>
#import <malloc/malloc.h>
#import <pal/spi/cocoa/AuthKitSPI.h>
#import <sys/resource.h>
#import <wtf/MonotonicTime.h>
#import <wtf/RetainPtr.h>
#import <wtf/StdLibExtras.h>
#import <wtf/StringPrintStream.h>
#import <wtf/URL.h>
#import <wtf/text/MakeString.h>
#import <wtf/text/WTFString.h>

#import <pal/cocoa/AppSSOSoftLink.h>

// Benchmark of the SOAuthorization code reached through production entry points only: a WKWebView navigation, a
// sub-frame load or window.open, with AppSSO mocked as SOAuthorizationTests.mm mocks it. Each TEST is one shape.
// By default a shape runs one pass and compares the digest of what it observed with the recorded one. With
// WEBKIT_RUN_BENCHMARKS=1 it repeats the pass for a second or more and prints
// "<Shape>: <ms> ms <n> MB/s checksum=<digest> passes=<n>". Nothing asserts on time.

namespace {

// State the mocks and delegates below write; the pass in progress reads and resets it.
struct BenchDigest {
    uint64_t hash { 0xcbf29ce484222325ull };
    size_t bytes { 0 };
    // What each add saw, in order, so that a repeat pass that differs from the first can say where.
    Vector<String> trace;

    void addBytes(std::span<const uint8_t> data)
    {
        for (auto byte : data) {
            hash ^= byte;
            hash *= 0x100000001b3ull;
        }
        bytes += data.size();
        // Separate the fields, so that ("ab", "c") and ("a", "bc") differ.
        hash ^= 0xff;
        hash *= 0x100000001b3ull;
    }
    void add(const String& string)
    {
        auto utf8 = string.utf8();
        addBytes(byteCast<uint8_t>(utf8.span()));
        trace.append(string);
    }
    void add(NSString *string)
    {
        add(String(string));
    }
    void add(uint64_t value)
    {
        for (unsigned shift = 0; shift < 64; shift += 8) {
            hash ^= (value >> shift) & 0xff;
            hash *= 0x100000001b3ull;
        }
        bytes += sizeof(value);
        trace.append(String::number(value));
    }
    // Payload the pass moved through the interception (a response's body, a redirect's Location), which the
    // digest does not hash: it counts toward the pass's bytes, so MB/s is the payload rate.
    void addPayload(size_t size)
    {
        bytes += size;
    }
};

}

static BenchDigest gDigest;
static bool gNavigationCompleted = false;
static bool gAuthorizationPerformed = false;
static bool gNewWindowCreated = false;
static bool gAllMessagesReceived = false;
static bool gCanPerformAnswer = true;
static String gFinalURL;
static SOAuthorization* gBenchAuthorization;
static id<SOAuthorizationDelegate> gBenchDelegate;
static RetainPtr<WKWebView> gBenchNewWindow;

static constexpr auto benchOpenerTemplate =
"<html>"
"<button onclick='clickMe()' style='width:400px;height:400px'>window.open</button>"
"<script>"
"function clickMe()"
"{"
"    window.addEventListener('message', receiveMessage, false);"
"    newWindow = window.open('%s');"
"    if (!newWindow)"
"        return;"
"    const pollTimer = window.setInterval(function() {"
"        if (newWindow.closed) {"
"            window.clearInterval(pollTimer);"
"            window.webkit.messageHandlers.testHandler.postMessage('WindowClosed.');"
"        }"
"    }, 200);"
"}"
"function receiveMessage(event)"
"{"
"    if (event.origin == 'http://www.example.com')"
"        window.webkit.messageHandlers.testHandler.postMessage(event.data);"
"}"
"</script>"
"</html>";

static constexpr char benchNewWindowResponse[] =
"<html>"
"<script>"
"window.opener.postMessage('Hello.', '*');"
"window.close();"
"</script>"
"</html>";

static constexpr auto benchParentTemplate =
"<html>"
"<meta name='referrer' content='origin' />"
"<iframe src='%s'></iframe>"
"<script>"
"function receiveMessage(event)"
"{"
"    window.webkit.messageHandlers.testHandler.postMessage(event.origin);"
"    window.webkit.messageHandlers.testHandler.postMessage(event.data);"
"}"
"window.addEventListener('message', receiveMessage, false);"
"</script>"
"</html>";

static constexpr char benchIframeResponse[] =
"<html>"
"<script>"
"parent.postMessage('Hello.', '*');"
"</script>"
"</html>";

@interface TestSOAuthorizationBenchDelegate : NSObject <WKNavigationDelegate, WKUIDelegate>
@end

@implementation TestSOAuthorizationBenchDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    gNavigationCompleted = true;
    // The last path component and the query, not the absolute URL, whose directory is the build products'.
    NSURL *finalURL = navigation._request.URL;
    gFinalURL = makeString(String(finalURL.lastPathComponent), '?', String(finalURL.query));
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    // Empty: a failure is not digested.
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures
{
    gNewWindowCreated = true;
    gBenchNewWindow = adoptNS([[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration]);
    [gBenchNewWindow setNavigationDelegate:self];
    return gBenchNewWindow.get();
}

- (void)_webView:(WKWebView *)webView decidePolicyForSOAuthorizationLoadWithCurrentPolicy:(_WKSOAuthorizationLoadPolicy)policy forExtension:(NSString *)extension completionHandler:(void (^)(_WKSOAuthorizationLoadPolicy policy))completionHandler
{
    gDigest.add(extension);
    gDigest.add(static_cast<uint64_t>(policy));
    completionHandler(_WKSOAuthorizationLoadPolicyAllow);
}

#if PLATFORM(IOS) || PLATFORM(VISION)
- (UIViewController *)_presentingViewControllerForWebView:(WKWebView *)webView
{
    return nil;
}
#endif

@end

@interface TestSOAuthorizationBenchMessageHandler : NSObject <WKScriptMessageHandler>
- (void)expect:(NSUInteger)count;
@end

@implementation TestSOAuthorizationBenchMessageHandler {
    NSUInteger _expectedCount;
    NSUInteger _count;
}

- (void)expect:(NSUInteger)count
{
    _expectedCount = count;
    _count = 0;
    gAllMessagesReceived = false;
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
    gDigest.add((NSString *)message.body);
    if (++_count == _expectedCount)
        gAllMessagesReceived = true;
}

@end

// The AppSSO mock. The URL's host and last path component are digested, never its directory, so the digest is the
// same wherever the tree is checked out.
static void digestURL(NSURL *url)
{
    gDigest.add(url.scheme);
    gDigest.add(url.host);
    gDigest.add(url.lastPathComponent);
    gDigest.add(url.query);
}

static bool benchAnswersYes(NSURL *url)
{
    gDigest.add("canPerform"_s);
    digestURL(url);
    return gCanPerformAnswer && (url.host.length ? [url.host isEqual:@"www.example.com"] : [url.lastPathComponent isEqual:@"simple.html"]);
}

using CanPerformAuthorizationWithURLCallback = void (^)(BOOL);
static void benchOverrideCanPerformAuthorizationWithURLCompletion(id, SEL, NSURL *url, NSInteger, NSString *, BOOL, CanPerformAuthorizationWithURLCallback completion)
{
    completion(benchAnswersYes(url));
}

static bool benchOverrideCanPerformAuthorizationWithURL(id, SEL, NSURL *url, NSInteger)
{
    return benchAnswersYes(url);
}

static void benchOverrideSetDelegate(id self, SEL, id<SOAuthorizationDelegate> delegate)
{
    gBenchAuthorization = self;
    gBenchDelegate = delegate;
}

static void benchOverrideBeginAuthorizationWithURL(id, SEL, NSURL *url, NSDictionary *headers, NSData *body)
{
    gAuthorizationPerformed = true;
    gDigest.add("begin"_s);
    digestURL(url);
    // Header values can carry the checkout's file paths, so only the names are digested.
    RetainPtr sortedNames = [[headers allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in sortedNames.get())
        gDigest.add(name);
    gDigest.add(static_cast<uint64_t>(body.length));
    NSDictionary *options = [gBenchAuthorization authorizationOptions];
    gDigest.add(static_cast<uint64_t>([options[SOAuthorizationOptionUserActionInitiated] boolValue]));
    gDigest.add(options[SOAuthorizationOptionInitiatorOrigin]);
    gDigest.add(static_cast<uint64_t>([options[SOAuthorizationOptionInitiatingAction] intValue]));
}

static void benchOverrideCancelAuthorization(id, SEL)
{
    gDigest.add("cancel"_s);
}

using GetAuthorizationHintsCallback = void (^)(SOAuthorizationHints *authorizationHints, NSError *error);
static void benchOverrideGetAuthorizationHintsWithURL(id, SEL, NSURL *url, NSInteger responseCode, GetAuthorizationHintsCallback completion)
{
    gDigest.add("hints"_s);
    gDigest.add(static_cast<uint64_t>(responseCode));
    RetainPtr soAuthorizationHintsCore = adoptNS([PAL::allocSOAuthorizationHintsCoreInstance() initWithLocalizedExtensionBundleDisplayName:@"Test"]);
    RetainPtr soAuthorizationHints = adoptNS([PAL::allocSOAuthorizationHintsInstance() initWithAuthorizationHintsCore:soAuthorizationHintsCore.get()]);
    completion(soAuthorizationHints.get(), nullptr);
}

static bool benchOverrideIsURLFromAppleOwnedDomain(id, SEL, NSURL *)
{
    return true;
}

static void resetBenchState()
{
    gDigest = { };
    gNavigationCompleted = false;
    gAuthorizationPerformed = false;
    gNewWindowCreated = false;
    gAllMessagesReceived = false;
    gCanPerformAnswer = true;
    gFinalURL = emptyString();
    gBenchAuthorization = nullptr;
    gBenchDelegate = nullptr;
    gBenchNewWindow = nullptr;
}

#define BENCH_SWIZZLE_SOAUTH() \
    ClassMethodSwizzler swizzler0(PAL::getSOAuthorizationClassSingleton(), @selector(canPerformAuthorizationWithURL:responseCode:callerBundleIdentifier:useInternalExtensions:completion:), reinterpret_cast<IMP>(benchOverrideCanPerformAuthorizationWithURLCompletion)); \
    ClassMethodSwizzler swizzler1(PAL::getSOAuthorizationClassSingleton(), @selector(canPerformAuthorizationWithURL:responseCode:), reinterpret_cast<IMP>(benchOverrideCanPerformAuthorizationWithURL)); \
    InstanceMethodSwizzler swizzler2(PAL::getSOAuthorizationClassSingleton(), @selector(setDelegate:), reinterpret_cast<IMP>(benchOverrideSetDelegate)); \
    InstanceMethodSwizzler swizzler3(PAL::getSOAuthorizationClassSingleton(), @selector(beginAuthorizationWithURL:httpHeaders:httpBody:), reinterpret_cast<IMP>(benchOverrideBeginAuthorizationWithURL)); \
    InstanceMethodSwizzler swizzler4(PAL::getSOAuthorizationClassSingleton(), @selector(cancelAuthorization), reinterpret_cast<IMP>(benchOverrideCancelAuthorization)); \
    InstanceMethodSwizzler swizzler5(PAL::getSOAuthorizationClassSingleton(), @selector(getAuthorizationHintsWithURL:responseCode:completion:), reinterpret_cast<IMP>(benchOverrideGetAuthorizationHintsWithURL)); \
    ClassMethodSwizzler swizzler6([AKAuthorizationController class], @selector(isURLFromAppleOwnedDomain:), reinterpret_cast<IMP>(benchOverrideIsURLFromAppleOwnedDomain))

namespace TestWebKitAPI {

static bool shouldRunBenchmarks()
{
    return [NSProcessInfo.processInfo.environment[@"WEBKIT_RUN_BENCHMARKS"] isEqual:@"1"];
}

// WEBKIT_MEMORY_PROBE=<n> runs the memory probe instead of the benchmark: one warm-up pass, then n passes, and a line
// of this process's footprint, which is the UI process, where the interception runs:
//   MEM <shape> passes <n> baseline <bytes> peak-added <bytes> retained <bytes> total-peak-added <bytes>
//       total-retained <bytes> reset <0|1> zone-baseline <bytes> zone-retained <bytes>
// peak-added is the median over the passes of the peak one pass adds, and retained is the total growth divided by n.
// total-peak-added and total-retained are the whole interval's.
// reset is 1 when proc_reset_footprint_interval was found, so each pass's peak is its own; with 0 the peaks are
// cumulative, and peak-added is not a per-call figure. Run one shape per process.
// zone-baseline is the bytes in use in the process's malloc zones after the warm-up, and zone-retained their growth
// to after the last pass: byte-exact, where the footprint moves in pages. libpas reports no bytes (its zone's statistics
// are zeroed), so this leaves out fastMalloc.
static unsigned memoryProbePasses()
{
    return static_cast<unsigned>([NSProcessInfo.processInfo.environment[@"WEBKIT_MEMORY_PROBE"] integerValue]);
}

struct Footprint {
    uint64_t now { 0 };
    uint64_t intervalPeak { 0 };
};

static Footprint currentFootprint()
{
    // Let what the last pass released (the web view's teardown, autoreleased objects) be released.
    Util::runFor(0.5_s);
    Footprint footprint;
    rusage_info_current info { };
    if (proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, reinterpret_cast<rusage_info_t *>(&info)))
        return footprint;
    footprint.now = info.ri_phys_footprint;
    footprint.intervalPeak = info.ri_interval_max_phys_footprint;
    return footprint;
}

static int64_t mallocZonesInUse()
{
    malloc_statistics_t statistics { };
    malloc_zone_statistics(nullptr, &statistics);
    return static_cast<int64_t>(statistics.size_in_use);
}

// Starts a new interval for the peak, so that the warm-up's peak does not stand for the passes'.
static bool resetFootprintInterval()
{
    using ResetFunction = int (*)(int);
    auto reset = reinterpret_cast<ResetFunction>(dlsym(RTLD_DEFAULT, "proc_reset_footprint_interval"));
    if (!reset)
        return false;
    reset(getpid());
    return true;
}

static int64_t medianOf(Vector<int64_t>& values)
{
    std::sort(values.begin(), values.end());
    return values[values.size() / 2];
}

static void reportMismatch(ASCIILiteral shape, const Vector<String>& first, const Vector<String>& repeat)
{
    size_t common = std::min(first.size(), repeat.size());
    size_t index = 0;
    while (index < common && first[index] == repeat[index])
        ++index;
    SAFE_PRINTF("%s: repeat pass differs at entry %zu of %zu (first pass) and %zu (repeat pass)\n", shape, index, first.size(), repeat.size());
    for (size_t i = index > 3 ? index - 3 : 0; i < std::min(index + 3, std::max(first.size(), repeat.size())); ++i) {
        String firstEntry = i < first.size() ? first[i] : "(none)"_s;
        String repeatEntry = i < repeat.size() ? repeat[i] : "(none)"_s;
        SAFE_PRINTF("  [%zu] first=%s repeat=%s\n", i, firstEntry.utf8(), repeatEntry.utf8());
    }
}

// Runs the pass once and compares its digest, or repeats it for a second or more and prints the line a
// benchmark script reads. The digest is of the first pass only; later passes must reproduce it.
// setUp runs before each pass, outside its digest: it makes the pass's web view, and so also destroys the last
// pass's, whose teardown cancels a session the digest would otherwise count.
// A shape whose pass takes long enough that one more or fewer pass in the second moves the work by a tenth runs a fixed
// number of passes (fixedPasses, the first included) instead of passes until a second has gone by.
template<typename SetUp, typename Pass>
static void runShape(ASCIILiteral shape, uint64_t expectedChecksum, SetUp&& setUp, Pass&& pass, unsigned fixedPasses = 0)
{
    auto start = MonotonicTime::now();
    setUp();
    resetBenchState();
    pass();
    if (auto passes = memoryProbePasses()) {
        auto baseline = currentFootprint();
        int64_t zoneBaseline = mallocZonesInUse();
        bool foundReset = false;
        int64_t totalPeakAdded = 0;
        Vector<int64_t> passPeaks;
        auto before = baseline;
        for (unsigned i = 0; i < passes; ++i) {
            foundReset = resetFootprintInterval();
            setUp();
            resetBenchState();
            pass();
            auto after = currentFootprint();
            passPeaks.append(static_cast<int64_t>(std::max(after.intervalPeak, std::max(before.now, after.now))) - static_cast<int64_t>(before.now));
            totalPeakAdded = std::max(totalPeakAdded, static_cast<int64_t>(std::max(after.intervalPeak, baseline.now)) - static_cast<int64_t>(baseline.now));
            before = after;
        }
        int64_t totalRetained = static_cast<int64_t>(before.now) - static_cast<int64_t>(baseline.now);
        int64_t zoneRetained = mallocZonesInUse() - zoneBaseline;
        SAFE_PRINTF("MEM %s passes %u baseline %llu peak-added %lld retained %lld total-peak-added %lld total-retained %lld reset %d zone-baseline %lld zone-retained %lld\n", shape, passes, static_cast<unsigned long long>(baseline.now),
            static_cast<long long>(medianOf(passPeaks)), static_cast<long long>(totalRetained / static_cast<int64_t>(passes)), static_cast<long long>(totalPeakAdded), static_cast<long long>(totalRetained), foundReset ? 1 : 0, static_cast<long long>(zoneBaseline), static_cast<long long>(zoneRetained));
        return;
    }
    uint64_t checksum = gDigest.hash;
    Vector<String> firstTrace = gDigest.trace;
    size_t totalBytes = gDigest.bytes;

    if (shouldRunBenchmarks()) {
        unsigned passCount = 1;
        while (fixedPasses ? passCount < fixedPasses : MonotonicTime::now() - start < 1_s) {
            ++passCount;
            setUp();
            resetBenchState();
            pass();
            if (checksum != gDigest.hash) {
                reportMismatch(shape, firstTrace, gDigest.trace);
                EXPECT_EQ(checksum, gDigest.hash) << shape.characters();
                break;
            }
            totalBytes += gDigest.bytes;
        }
        double seconds = (MonotonicTime::now() - start).seconds();
        SAFE_PRINTF("%s: %.3f ms %.6f MB/s checksum=%016llx passes=%u\n", shape, seconds * 1000, totalBytes / seconds / 1e6, static_cast<unsigned long long>(checksum), passCount);
        return;
    }
    if (expectedChecksum != checksum)
        SAFE_PRINTF("%s: checksum=%016llx\n", shape, static_cast<unsigned long long>(checksum));
    EXPECT_EQ(expectedChecksum, checksum) << shape.characters();
}

static RetainPtr<NSURL> benchURL(NSString *name, unsigned index)
{
    RetainPtr base = [NSBundle.test_resourcesBundle URLForResource:name withExtension:@"html"];
    RetainPtr components = adoptNS([[NSURLComponents alloc] initWithURL:base.get() resolvingAgainstBaseURL:NO]);
    [components setQuery:[NSString stringWithFormat:@"i=%u", index]];
    return [components URL];
}

static RetainPtr<TestWKWebView> makeBenchWebView(TestSOAuthorizationBenchDelegate *delegate, WKWebViewConfiguration *configuration = nil, CGSize size = CGSizeMake(400, 400))
{
    RetainPtr webView = configuration ? adoptNS([[TestWKWebView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height) configuration:configuration]) : adoptNS([[TestWKWebView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)]);
    [webView setNavigationDelegate:delegate];
    [webView setUIDelegate:delegate];
    return webView;
}

// The memory probe keeps one web view for the whole process: a web view's own footprint, which does not return
// to the baseline when it is destroyed, would otherwise stand for the interception's.
static bool needsNewWebView(TestWKWebView *current)
{
    return !current || !memoryProbePasses();
}

static void runNavigation(TestWKWebView *webView, NSURL *url)
{
    gNavigationCompleted = false;
    [webView loadRequest:[NSURLRequest requestWithURL:url]];
}

TEST(SOAuthorizationBench, StartUp)
{
    // Empty: the cost of starting the process and loading the test binary is what this shape measures.
}

// Every navigation consults AppSSO first; here AppSSO declines each one.
TEST(SOAuthorizationBench, NavigationNotHandled)
{
    BENCH_SWIZZLE_SOAUTH();
    RetainPtr delegate = adoptNS([[TestSOAuthorizationBenchDelegate alloc] init]);

    // Each pass makes its own web view, so that every pass starts from the same page, as the first does.
    RetainPtr<TestWKWebView> webView;
    runShape("NavigationNotHandled"_s, 0x731471119725de01, [&] {
        if (needsNewWebView(webView.get()))
            webView = makeBenchWebView(delegate.get());
    }, [&] {
        gCanPerformAnswer = false;
        for (unsigned i = 0; i < 12; ++i) {
            RetainPtr url = benchURL(i % 2 ? @"simple" : @"simple2", i);
            runNavigation(webView.get(), url.get());
            Util::run(&gNavigationCompleted);
            gDigest.add(gFinalURL);
            gDigest.add(static_cast<uint64_t>(gAuthorizationPerformed));
        }
    });
}

// AppSSO takes a navigation and completes it with a 302 to another page.
TEST(SOAuthorizationBench, RedirectCompletes)
{
    BENCH_SWIZZLE_SOAUTH();
    RetainPtr delegate = adoptNS([[TestSOAuthorizationBenchDelegate alloc] init]);

    // Each pass makes its own web view: a view left on the last pass's page starts the next pass's first
    // navigation from a page with an origin, where the first pass's started from none.
    RetainPtr<TestWKWebView> webView;
    runShape("RedirectCompletes"_s, 0xaf398dbada0c0183, [&] {
        if (needsNewWebView(webView.get()))
            webView = makeBenchWebView(delegate.get());
    }, [&] {
        for (unsigned i = 0; i < 6; ++i) {
            gAuthorizationPerformed = false;
            RetainPtr url = benchURL(@"simple", i);
            runNavigation(webView.get(), url.get());
            Util::run(&gAuthorizationPerformed);

            RetainPtr redirectURL = benchURL(@"simple2", i);
            RetainPtr response = adoptNS([[NSHTTPURLResponse alloc] initWithURL:url.get() statusCode:302 HTTPVersion:@"HTTP/1.1" headerFields:@{ @"Location" : [redirectURL absoluteString] }]);
            gDigest.addPayload(redirectURL.get().absoluteString.length);
            [gBenchDelegate authorization:gBenchAuthorization didCompleteWithHTTPResponse:response.get() httpBody:adoptNS([[NSData alloc] init]).get()];
            Util::run(&gNavigationCompleted);
#if PLATFORM(IOS) || PLATFORM(VISION)
            gNavigationCompleted = false;
            Util::run(&gNavigationCompleted);
#endif
            gDigest.add("done"_s);
            gDigest.add(gFinalURL);
        }
    });
}

// A frame whose source AppSSO takes completes with a 200 and an HTML body.
TEST(SOAuthorizationBench, SubFrameCompletes)
{
    BENCH_SWIZZLE_SOAUTH();
    RetainPtr messageHandler = adoptNS([[TestSOAuthorizationBenchMessageHandler alloc] init]);
    RetainPtr delegate = adoptNS([[TestSOAuthorizationBenchDelegate alloc] init]);

    // One configuration, so every pass's web view shares one process pool: a configuration of its own per pass
    // launches the web and network processes again each time, work that varies with the machine's load.
    RetainPtr configuration = adoptNS([[WKWebViewConfiguration alloc] init]);
    [[configuration userContentController] addScriptMessageHandler:messageHandler.get() name:@"testHandler"];
    // The web view is also kept: each pass loads its parent page with no base URL, so it starts from the same state in a
    // view left by the last pass, and a view made and destroyed per pass makes the process pool's process cache decide
    // by timing whether a web process is reused or launched.
    RetainPtr<TestWKWebView> webView;
    runShape("SubFrameCompletes"_s, 0xade036bb037bdb95, [&] {
        if (!webView)
            webView = makeBenchWebView(delegate.get(), configuration.get(), CGSizeMake(320, 500));
    }, [&] {
        for (unsigned i = 0; i < 4; ++i) {
            gAuthorizationPerformed = false;
            URL frameURL { makeString("http://www.example.com/frame"_s, i) };
            StringPrintStream stream;
            SAFE_PRINTSTREAM_PRINTF(stream, benchParentTemplate, frameURL.string().utf8());

            [messageHandler expect:2];
            [webView loadHTMLString:stream.toString().createNSString().get() baseURL:nil];
            Util::run(&gAllMessagesReceived);

            [messageHandler expect:2];
            gDigest.addPayload(sizeof(benchIframeResponse) - 1);
            RetainPtr response = adoptNS([[NSHTTPURLResponse alloc] initWithURL:frameURL.createNSURL().get() statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil]);
            [gBenchDelegate authorization:gBenchAuthorization didCompleteWithHTTPResponse:response.get() httpBody:adoptNS([[NSData alloc] initWithBytes:benchIframeResponse length:sizeof(benchIframeResponse) - 1]).get()];
            Util::run(&gAllMessagesReceived);
        }
    }, 6);
}

// window.open of a URL AppSSO takes, completed with a page that posts to its opener and closes itself.
TEST(SOAuthorizationBench, PopUpCompletes)
{
    BENCH_SWIZZLE_SOAUTH();
    RetainPtr baseURL = [NSBundle.test_resourcesBundle URLForResource:@"simple2" withExtension:@"html"];
    URL popUpURL { "http://www.example.com"_str };
    StringPrintStream stream;
    SAFE_PRINTSTREAM_PRINTF(stream, benchOpenerTemplate, popUpURL.string().utf8());
    String openerHTML = stream.toString();

    RetainPtr<TestSOAuthorizationBenchDelegate> delegate;
    RetainPtr<TestWKWebView> webView;
    runShape("PopUpCompletes"_s, 0x6e73f1e14bc74399, [] { }, [&] {
        for (unsigned i = 0; i < 2; ++i) {
            gAuthorizationPerformed = false;
            gNavigationCompleted = false;
            gNewWindowCreated = false;
            if (needsNewWebView(webView.get())) {
                delegate = adoptNS([[TestSOAuthorizationBenchDelegate alloc] init]);
                webView = makeBenchWebView(delegate.get());
            }

            [webView loadHTMLString:openerHTML.createNSString().get() baseURL:baseURL.get()];
            Util::run(&gNavigationCompleted);

#if PLATFORM(MAC)
            [webView sendClicksAtPoint:NSMakePoint(200, 200) numberOfClicks:1];
#elif PLATFORM(IOS) || PLATFORM(VISION)
            [webView evaluateJavaScript:@"clickMe()" completionHandler:nil];
#endif
            Util::run(&gAuthorizationPerformed);

            RetainPtr response = adoptNS([[NSHTTPURLResponse alloc] initWithURL:popUpURL.createNSURL().get() statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil]);
            gDigest.addPayload(sizeof(benchNewWindowResponse) - 1);
            // The secret WKWebView needs to be destroyed right away.
            @autoreleasepool {
                [gBenchDelegate authorization:gBenchAuthorization didCompleteWithHTTPResponse:response.get() httpBody:adoptNS([[NSData alloc] initWithBytes:benchNewWindowResponse length:sizeof(benchNewWindowResponse) - 1]).get()];
            }
            [webView waitForMessagesUnordered:@[@"Hello.", @"WindowClosed."]];
            gDigest.add("done"_s);
            gDigest.add(static_cast<uint64_t>(gNewWindowCreated));
            gBenchNewWindow = nullptr;
            gBenchDelegate = nullptr;
            gBenchAuthorization = nullptr;
            if (!memoryProbePasses()) {
                webView = nullptr;
                delegate = nullptr;
            }
        }
    });
}

} // namespace TestWebKitAPI

#undef BENCH_SWIZZLE_SOAUTH

#endif
