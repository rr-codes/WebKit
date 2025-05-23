/*
 * Copyright (C) 2021 Apple Inc. All rights reserved.
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

#include "config.h"

#include "GraphicsTestUtilities.h"
#include "Test.h"
#include "WebCoreTestUtilities.h"
#include <WebCore/Color.h>
#include <WebCore/GraphicsContext.h>
#include <WebCore/ImageBuffer.h>
#include <WebCore/NativeImage.h>
#include <WebCore/PixelBuffer.h>
#include <cmath>
#include <type_traits>
#include <wtf/MemoryFootprint.h>

namespace TestWebKitAPI {
using namespace WebCore;

namespace {
struct TestPattern {
    FloatRect unitRect;
    Color color;
};

}
static TestPattern g_testPattern[] = {
    { { 0.0f, 0.0f, 0.5f, 0.5f }, Color::magenta },
    { { 0.5f, 0.0f, 0.5f, 0.5f }, Color::yellow },
    { { 0.0f, 0.5f, 0.5f, 0.5f }, Color::lightGray },
    { { 0.5f, 0.5f, 0.5f, 0.5f }, Color::transparentBlack },
};

static ::testing::AssertionResult hasTestPattern(ImageBuffer& buffer, int seed)
{
    // Test pattern draws fractional pixels when deviceScaleFactor is < 1.
    // For now, account this by sampling somewhere where the fractional pixels
    // are guaranteed to not exist (4 logical pixels inwards of the pattern
    // borders).
    static constexpr float fuzz = 4.0f;
    constexpr auto patternCount = std::extent_v<decltype(g_testPattern)>;
    for (size_t i = 0; i < patternCount; ++i) {
        auto& pattern = g_testPattern[(i + seed) % patternCount];
        auto rect = pattern.unitRect;
        rect.scale(buffer.logicalSize());
        rect = enclosingIntRect(rect);
        auto p1 = rect.minXMinYCorner();
        p1.move(fuzz, fuzz);
        auto result = imageBufferPixelIs(pattern.color, buffer, p1);
        if (!result)
            return result;
        p1 = rect.maxXMaxYCorner();
        p1.move(-fuzz, -fuzz);
        result = imageBufferPixelIs(pattern.color, buffer, p1 + FloatPoint(-1, -1));
        if (!result)
            return result;
    }
    return ::testing::AssertionSuccess();
}

static void drawTestPattern(ImageBuffer& buffer, int seed)
{
    auto& context = buffer.context();
    bool savedShouldAntialias = context.shouldAntialias();
    context.setShouldAntialias(false);
    constexpr auto patternCount = std::extent_v<decltype(g_testPattern)>;
    for (size_t i = 0; i < patternCount; ++i) {
        auto& pattern = g_testPattern[(i + seed) % patternCount];
        auto rect = pattern.unitRect;
        rect.scale(buffer.logicalSize());
        rect = enclosingIntRect(rect);
        context.fillRect(rect, pattern.color);
    }
    context.setShouldAntialias(savedShouldAntialias);
}

static RefPtr<PixelBuffer> createPixelBufferTestPattern(IntSize size, AlphaPremultiplication alphaFormat, int seed)
{
    auto pattern = ImageBuffer::create(size, RenderingMode::Unaccelerated, RenderingPurpose::Unspecified, 1.0f, DestinationColorSpace::SRGB(), ImageBufferPixelFormat::BGRA8);
    if (!pattern)
        return nullptr;
    drawTestPattern(*pattern, 1);
    EXPECT_TRUE(hasTestPattern(*pattern, 1));
    if (!hasTestPattern(*pattern, 1)) {
        ASSERT_NOT_REACHED();
        return nullptr;
    }
    PixelBufferFormat testFormat { alphaFormat, PixelFormat::BGRA8, DestinationColorSpace::SRGB() };
    return pattern->getPixelBuffer(testFormat, { { }, size }); 
}

// Tests that the specialized image buffer constructors construct the expected type of object.
// Test passes if the test compiles, there was a bug where the code wouldn't compile.
TEST(ImageBufferTests, ImageBufferSubTypeCreateCreatesSubtypes)
{
    auto colorSpace = DestinationColorSpace::SRGB();
    auto pixelFormat = ImageBufferPixelFormat::BGRA8;
    FloatSize size { 1.f, 1.f };
    float scale = 1.f;
    RefPtr<ImageBuffer> unaccelerated = ImageBuffer::create(size, RenderingMode::Unaccelerated, RenderingPurpose::Unspecified, scale, colorSpace, pixelFormat);
    RefPtr<ImageBuffer> accelerated = ImageBuffer::create(size, RenderingMode::Accelerated, RenderingPurpose::Unspecified, scale, colorSpace, pixelFormat);

    EXPECT_NE(nullptr, accelerated);
    EXPECT_NE(nullptr, unaccelerated);
}

TEST(ImageBufferTests, ImageBufferSubPixelDrawing)
{
    auto colorSpace = DestinationColorSpace::SRGB();
    auto pixelFormat = ImageBufferPixelFormat::BGRA8;
    FloatSize logicalSize { 392, 44 };
    float scale = 1.91326535;
    auto frontImageBuffer = ImageBuffer::create(logicalSize, RenderingMode::Accelerated, RenderingPurpose::Unspecified, scale, colorSpace, pixelFormat);
    auto backImageBuffer = ImageBuffer::create(logicalSize, RenderingMode::Accelerated, RenderingPurpose::Unspecified, scale, colorSpace, pixelFormat);

    auto strokeRect = FloatRect { { }, logicalSize };
    strokeRect.inflate(-0.5);
    auto fillRect = strokeRect;
    fillRect.inflate(-1);

    auto& frontContext = frontImageBuffer->context();
    auto& backContext = backImageBuffer->context();

    frontContext.setShouldAntialias(false);
    backContext.setShouldAntialias(false);

    frontContext.setStrokeColor(Color::red);
    frontContext.strokeRect(strokeRect, 1);

    frontContext.fillRect(fillRect, Color::green);

    for (int i = 0; i < 1000; ++i) {
        backContext.drawImageBuffer(*frontImageBuffer, WebCore::FloatPoint { }, { WebCore::CompositeOperator::Copy });
        frontContext.drawImageBuffer(*backImageBuffer, WebCore::FloatPoint { }, { WebCore::CompositeOperator::Copy });
    }

    EXPECT_TRUE(imageBufferPixelIs(Color::green, *frontImageBuffer, fillRect.minXMinYCorner() + FloatPoint(1, 1)));
    EXPECT_TRUE(imageBufferPixelIs(Color::green, *frontImageBuffer, fillRect.maxXMinYCorner() + FloatPoint(-1, 1)));
    EXPECT_TRUE(imageBufferPixelIs(Color::green, *frontImageBuffer, fillRect.minXMaxYCorner() + FloatPoint(1, -1)));
    EXPECT_TRUE(imageBufferPixelIs(Color::green, *frontImageBuffer, fillRect.maxXMaxYCorner() + FloatPoint(-1, -1)));

    EXPECT_TRUE(imageBufferPixelIs(Color::green, *backImageBuffer, fillRect.minXMinYCorner() + FloatPoint(1, 1)));
    EXPECT_TRUE(imageBufferPixelIs(Color::green, *backImageBuffer, fillRect.maxXMinYCorner() + FloatPoint(-1, 1)));
    EXPECT_TRUE(imageBufferPixelIs(Color::green, *backImageBuffer, fillRect.minXMaxYCorner() + FloatPoint(1, -1)));
    EXPECT_TRUE(imageBufferPixelIs(Color::green, *backImageBuffer, fillRect.maxXMaxYCorner() + FloatPoint(-1, -1)));
}

// Test that drawing an accelerated ImageBuffer to an unaccelerated does not store extra
// memory to the accelerated ImageBuffer.
// FIXME: The test is disabled as it appears that WTF::memoryFootprint() is not exact enough to
// test that GraphicsContext::drawImageBitmap() does not keep extra memory around.
// However, if the test is paused at the memory measurement location and the process is inspected
// manually with the memory tools, the footprint is as expected, e.g. drawBitmapImage does not
// persist additional memory.
TEST(ImageBufferTests, DISABLED_DrawImageBufferDoesNotReferenceExtraMemory)
{
    auto colorSpace = DestinationColorSpace::SRGB();
    auto pixelFormat = ImageBufferPixelFormat::BGRA8;
    FloatSize logicalSize { 4096, 4096 };
    float scale = 1;
    size_t footprintError = 1024 * 1024;
    size_t logicalSizeBytes = logicalSize.width() * logicalSize.height() * 4;
    // FIXME: Logically this fuzz amount  should not exist.
    // WTF::memoryFootprint() does not return the same amount of memory as
    // the `footprint` command or the leak tools.
    // At the time of writing, the bug case would report drawImageBitmap footprint
    // as ~130mb, and fixed case would report ~67mb.
    size_t drawImageBitmapUnaccountedFootprint = logicalSizeBytes + 3 * 1024 * 1024;

    {
        // Make potential accelerated drawing backend instantiate roughly the global structures needed for this test.
        auto accelerated = ImageBuffer::create(logicalSize, RenderingMode::Accelerated, RenderingPurpose::Unspecified, scale, colorSpace, pixelFormat);
        auto fillRect = FloatRect { { }, logicalSize };
        accelerated->context().fillRect(fillRect, Color::green);
        EXPECT_TRUE(imageBufferPixelIs(Color::green, *accelerated, fillRect.maxXMaxYCorner() + FloatPoint(-1, -1)));
    }
    WTF::releaseFastMallocFreeMemory();
    auto initialFootprint = memoryFootprint();
    auto lastFootprint = initialFootprint;
    EXPECT_GT(lastFootprint, 0u);

    auto accelerated = ImageBuffer::create(logicalSize, RenderingMode::Accelerated, RenderingPurpose::Unspecified, scale, colorSpace, pixelFormat);
    auto fillRect = FloatRect { { }, logicalSize };
    accelerated->context().fillRect(fillRect, Color::green);
    accelerated->flushDrawingContext();
    EXPECT_TRUE(memoryFootprintChangedBy(lastFootprint, logicalSizeBytes, footprintError));

    auto unaccelerated = ImageBuffer::create(logicalSize, RenderingMode::Unaccelerated, RenderingPurpose::Unspecified, scale, colorSpace, pixelFormat);
    unaccelerated->context().fillRect(fillRect, Color::yellow);
    EXPECT_TRUE(imageBufferPixelIs(Color::yellow, *unaccelerated, fillRect.maxXMaxYCorner() + FloatPoint(-1, -1)));
    EXPECT_TRUE(memoryFootprintChangedBy(lastFootprint, logicalSizeBytes, footprintError));

    // The purpose of the whole test is to test that drawImageBuffer does not increase
    // memory footprint.
    unaccelerated->context().drawImageBuffer(*accelerated, FloatRect { { }, logicalSize }, FloatRect { { }, logicalSize }, { WebCore::CompositeOperator::Copy });
    EXPECT_TRUE(imageBufferPixelIs(Color::green, *unaccelerated, fillRect.maxXMaxYCorner() + FloatPoint(-1, -1)));
    EXPECT_TRUE(memoryFootprintChangedBy(lastFootprint, 0 + drawImageBitmapUnaccountedFootprint, footprintError));
    // sleep(10000); // Enable this to inspect the process manually.
    accelerated = nullptr;
    unaccelerated = nullptr;
    lastFootprint = initialFootprint;
    EXPECT_TRUE(memoryFootprintChangedBy(lastFootprint, 0, footprintError));
}

enum class TestPreserveResolution : bool { No, Yes };

void PrintTo(TestPreserveResolution value, ::std::ostream* o)
{
    if (value == TestPreserveResolution::No)
        *o << "PreserveResolution_No";
    else if (value == TestPreserveResolution::Yes)
        *o << "PreserveResolution_Yes";
    else
        *o << "Unknown";
}

// ImageBuffer test fixture for tests that are variant to the image buffer device scale factor and options
class AnyScaleTest : public testing::TestWithParam<std::tuple<float, RenderingMode>> {
public:
    float deviceScaleFactor() const { return std::get<0>(GetParam()); }
    RenderingMode renderingMode() const { return std::get<1>(GetParam()); }
};

// Test that ImageBuffer::sinkIntoNativeImage() returns NativeImage that contains the ImageBuffer contents and
// that the returned NativeImage is of expected size (native image size * image buffer scale factor).
TEST_P(AnyScaleTest, SinkIntoNativeImageWorks)
{
    FloatSize testSize { 50, 57 };
    auto buffer = ImageBuffer::create(testSize, renderingMode(), RenderingPurpose::Unspecified, deviceScaleFactor(), DestinationColorSpace::SRGB(), ImageBufferPixelFormat::BGRA8);
    ASSERT_NE(buffer, nullptr);
    auto verifyBuffer = ImageBuffer::create(buffer->logicalSize(), RenderingMode::Unaccelerated, RenderingPurpose::Unspecified, 1.f, DestinationColorSpace::SRGB(), ImageBufferPixelFormat::BGRA8);
    ASSERT_NE(verifyBuffer, nullptr);
    drawTestPattern(*buffer, 0);

    auto image = ImageBuffer::sinkIntoNativeImage(WTFMove(buffer));
    ASSERT_NE(image, nullptr);

    EXPECT_EQ(image->size(), expandedIntSize(testSize.scaled(deviceScaleFactor())));
    verifyBuffer->context().drawNativeImage(*image, FloatRect { { }, verifyBuffer->logicalSize() }, { { }, image->size() }, { CompositeOperator::Copy });
    EXPECT_TRUE(hasTestPattern(*verifyBuffer, 0));
}

// Test that ImageBuffer::getPixelBuffer() returns PixelBuffer that is sized to the ImageBuffer::logicalSize() * ImageBuffer::resolutionScale().
TEST_P(AnyScaleTest, GetPixelBufferDimensionsContainScale)
{
    IntSize testSize { 50, 57 };
    auto buffer = ImageBuffer::create(testSize, renderingMode(), RenderingPurpose::Unspecified, deviceScaleFactor(), DestinationColorSpace::SRGB(), ImageBufferPixelFormat::BGRA8);
    ASSERT_NE(buffer, nullptr);
    drawTestPattern(*buffer, 0);

    // Test that ImageBuffer::getPixelBuffer() returns pixel buffer with dimensions that are scaled to resolutionScale() of the source.
    PixelBufferFormat testFormat { AlphaPremultiplication::Premultiplied, PixelFormat::BGRA8, DestinationColorSpace::SRGB() };
    auto pixelBuffer = buffer->getPixelBuffer(testFormat, { { }, testSize });
    IntSize expectedSize = testSize;
    expectedSize.scale(deviceScaleFactor());
    EXPECT_EQ(expectedSize, pixelBuffer->size());

    // Test that the contents of the pixel buffer was as expected.
    auto verifyBuffer = ImageBuffer::create(pixelBuffer->size(), RenderingMode::Unaccelerated, RenderingPurpose::Unspecified, 1.f, DestinationColorSpace::SRGB(), ImageBufferPixelFormat::BGRA8);
    ASSERT_NE(verifyBuffer, nullptr);
    verifyBuffer->putPixelBuffer(*pixelBuffer, { { }, pixelBuffer->size() });
    EXPECT_TRUE(hasTestPattern(*verifyBuffer, 0));
}

// ImageBuffer test fixture for tests that are variant to two image buffer options. Mostly useful
// for example source - destination tests
class AnyTwoImageBufferOptionsTest : public testing::TestWithParam<std::tuple<RenderingMode, RenderingMode>> {
public:
    RenderingMode renderingMode0() const { return std::get<0>(GetParam()); }
    RenderingMode renderingMode1() const { return std::get<1>(GetParam()); }
};

TEST_P(AnyTwoImageBufferOptionsTest, PutPixelBufferAffectsDrawOutput)
{
    IntSize testSize { 50, 57 };
    auto source = ImageBuffer::create(testSize, renderingMode0(), RenderingPurpose::Unspecified, 1.0f, DestinationColorSpace::SRGB(), ImageBufferPixelFormat::BGRA8);
    ASSERT_NE(source, nullptr);
    auto destination = ImageBuffer::create(testSize, renderingMode1(), RenderingPurpose::Unspecified, 1.0f, DestinationColorSpace::SRGB(), ImageBufferPixelFormat::BGRA8);
    ASSERT_NE(destination, nullptr);
    auto pattern1Buffer = createPixelBufferTestPattern(testSize, AlphaPremultiplication::Unpremultiplied, 1);
    ASSERT_NE(pattern1Buffer, nullptr);

    drawTestPattern(*source, 0);
    EXPECT_TRUE(hasTestPattern(*source, 0));
    destination->context().drawImageBuffer(*source, FloatRect { { }, testSize }, FloatRect { { }, testSize }, { WebCore::CompositeOperator::Copy });
    EXPECT_TRUE(hasTestPattern(*destination, 0));
    source->putPixelBuffer(*pattern1Buffer, { { }, pattern1Buffer->size() });
    destination->context().drawImageBuffer(*source, FloatRect { { }, testSize }, FloatRect { { }, testSize }, { WebCore::CompositeOperator::Copy });
    EXPECT_TRUE(hasTestPattern(*destination, 1));
}

INSTANTIATE_TEST_SUITE_P(ImageBufferTests,
    AnyScaleTest,
    testing::Combine(
        testing::Values(0.5f, 1.f, 2.f, 5.f),
        testing::Values(RenderingMode::Unaccelerated, RenderingMode::Accelerated)),
    TestParametersToStringFormatter());

INSTANTIATE_TEST_SUITE_P(ImageBufferTests,
    AnyTwoImageBufferOptionsTest,
    testing::Combine(
        testing::Values(RenderingMode::Unaccelerated, RenderingMode::Accelerated),
        testing::Values(RenderingMode::Unaccelerated, RenderingMode::Accelerated)),
    TestParametersToStringFormatter());

}
