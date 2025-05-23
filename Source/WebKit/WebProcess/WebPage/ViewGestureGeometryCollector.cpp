/*
 * Copyright (C) 2013, 2014 Apple Inc. All rights reserved.
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
#include "ViewGestureGeometryCollector.h"

#include "Logging.h"
#include "MessageSenderInlines.h"
#include "PluginView.h"
#include "ViewGestureGeometryCollectorMessages.h"
#include "WebFrame.h"
#include "WebPage.h"
#include "WebProcess.h"
#include <WebCore/FontCascade.h>
#include <WebCore/HTMLImageElement.h>
#include <WebCore/HTMLTextFormControlElement.h>
#include <WebCore/HitTestResult.h>
#include <WebCore/ImageDocument.h>
#include <WebCore/LocalFrame.h>
#include <WebCore/LocalFrameView.h>
#include <WebCore/Range.h>
#include <WebCore/RenderView.h>
#include <WebCore/TextIterator.h>
#include <ranges>
#include <wtf/HashCountedSet.h>
#include <wtf/TZoneMallocInlines.h>

#if PLATFORM(IOS_FAMILY)
#include "SmartMagnificationControllerMessages.h"
#else
#include "ViewGestureControllerMessages.h"
#endif

namespace WebKit {
using namespace WebCore;

#if PLATFORM(IOS_FAMILY)
static const double minimumScaleDifferenceForZooming = 0.3;
#endif

WTF_MAKE_TZONE_ALLOCATED_IMPL(ViewGestureGeometryCollector);

ViewGestureGeometryCollector::ViewGestureGeometryCollector(WebPage& webPage)
    : m_webPage(webPage)
    , m_webPageIdentifier(webPage.identifier())
#if !PLATFORM(IOS_FAMILY)
    , m_renderTreeSizeNotificationThreshold(0)
#endif
{
    WebProcess::singleton().addMessageReceiver(Messages::ViewGestureGeometryCollector::messageReceiverName(), m_webPageIdentifier, *this);
}

ViewGestureGeometryCollector::~ViewGestureGeometryCollector()
{
    WebProcess::singleton().removeMessageReceiver(Messages::ViewGestureGeometryCollector::messageReceiverName(), m_webPageIdentifier);
}

void ViewGestureGeometryCollector::dispatchDidCollectGeometryForSmartMagnificationGesture(FloatPoint origin, FloatRect absoluteTargetRect, FloatRect visibleContentRect, bool fitEntireRect, double viewportMinimumScale, double viewportMaximumScale)
{
    RefPtr webPage = m_webPage.get();
    if (!webPage)
        return;

#if PLATFORM(MAC)
    webPage->send(Messages::ViewGestureController::DidCollectGeometryForSmartMagnificationGesture(origin, absoluteTargetRect, visibleContentRect, fitEntireRect, viewportMinimumScale, viewportMaximumScale));
#endif
#if PLATFORM(IOS_FAMILY)
    webPage->send(Messages::SmartMagnificationController::DidCollectGeometryForSmartMagnificationGesture(origin, absoluteTargetRect, visibleContentRect, fitEntireRect, viewportMinimumScale, viewportMaximumScale));
#endif
}

void ViewGestureGeometryCollector::collectGeometryForSmartMagnificationGesture(FloatPoint gestureLocationInViewCoordinates)
{
    RefPtr webPage = m_webPage.get();
    if (!webPage)
        return;

    RefPtr frameView = webPage->localMainFrameView();
    if (!frameView)
        return;

    FloatRect visibleContentRect = frameView->unobscuredContentRectIncludingScrollbars();

    if (webPage->handlesPageScaleGesture())
        return;

    double viewportMinimumScale;
    double viewportMaximumScale;

#if PLATFORM(IOS_FAMILY)
    if (webPage->platformPrefersTextLegibilityBasedZoomScaling()) {
        auto textLegibilityScales = computeTextLegibilityScales(viewportMinimumScale, viewportMaximumScale);
        if (!textLegibilityScales) {
            dispatchDidCollectGeometryForSmartMagnificationGesture({ }, { }, { }, false, 0, 0);
            return;
        }

        float targetScale = webPage->viewportConfiguration().initialScale();
        float currentScale = webPage->pageScaleFactor();
        if (currentScale < textLegibilityScales->first - minimumScaleDifferenceForZooming)
            targetScale = textLegibilityScales->first;
        else if (currentScale < textLegibilityScales->second - minimumScaleDifferenceForZooming)
            targetScale = textLegibilityScales->second;

        FloatRect targetRectInContentCoordinates { gestureLocationInViewCoordinates, FloatSize() };
        targetRectInContentCoordinates.inflate(webPage->viewportConfiguration().viewLayoutSize() / (2 * targetScale));

        dispatchDidCollectGeometryForSmartMagnificationGesture(gestureLocationInViewCoordinates, targetRectInContentCoordinates, visibleContentRect, true, viewportMinimumScale, viewportMaximumScale);
        return;
    }
#endif // PLATFORM(IOS_FAMILY)

    IntPoint originInContentsSpace = frameView->windowToContents(roundedIntPoint(gestureLocationInViewCoordinates));
    HitTestResult hitTestResult = HitTestResult(originInContentsSpace);

    if (RefPtr mainFrame = dynamicDowncast<WebCore::LocalFrame>(webPage->mainFrame()))
        mainFrame->protectedDocument()->hitTest(HitTestRequest(), hitTestResult);

    RefPtr node = hitTestResult.innerNode();
    if (!node) {
        dispatchDidCollectGeometryForSmartMagnificationGesture(FloatPoint(), FloatRect(), FloatRect(), false, 0, 0);
        return;
    }

    bool isReplaced;
    FloatRect absoluteBoundingRect;

    computeZoomInformationForNode(*node, gestureLocationInViewCoordinates, absoluteBoundingRect, isReplaced, viewportMinimumScale, viewportMaximumScale);
    dispatchDidCollectGeometryForSmartMagnificationGesture(gestureLocationInViewCoordinates, absoluteBoundingRect, visibleContentRect, isReplaced, viewportMinimumScale, viewportMaximumScale);
}

#if PLATFORM(IOS_FAMILY)

std::optional<std::pair<double, double>> ViewGestureGeometryCollector::computeTextLegibilityScales(double& viewportMinimumScale, double& viewportMaximumScale)
{
    struct FontSizeAndCount {
        unsigned fontSize { 0 };
        unsigned count { 0 };
    };
    using FontSizeCounter = HashCountedSet<unsigned>;

    static const unsigned fontSizeBinningInterval = 2;
    static const double maximumNumberOfTextRunsToConsider = 200;

    static const double targetLegibilityFontSize = 12;
    static const double textLegibilityScaleRatio = 0.1;
    static const double defaultTextLegibilityZoomScale = 1;

    computeMinimumAndMaximumViewportScales(viewportMinimumScale, viewportMaximumScale);
    if (m_cachedTextLegibilityScales)
        return m_cachedTextLegibilityScales;

    RefPtr webPage = m_webPage.get();
    if (!webPage)
        return std::nullopt;
    RefPtr localMainFrame = dynamicDowncast<WebCore::LocalFrame>(m_webPage->mainFrame());
    if (!localMainFrame)
        return std::nullopt;
    RefPtr document = localMainFrame->document();
    if (!document)
        return std::nullopt;

    document->updateLayout(LayoutOptions::IgnorePendingStylesheets);

    HashSet<Ref<Node>> allTextNodes;
    FontSizeCounter fontSizeCounter;
    unsigned numberOfIterations = 0;
    unsigned totalSampledTextLength = 0;

    for (TextIterator documentTextIterator { makeRangeSelectingNodeContents(*document), TextIteratorBehavior::EntersTextControls }; !documentTextIterator.atEnd(); documentTextIterator.advance()) {
        if (++numberOfIterations >= maximumNumberOfTextRunsToConsider)
            break;

        if (!is<Text>(documentTextIterator.node()))
            continue;

        auto& textNode = downcast<Text>(*documentTextIterator.node());
        auto textLength = textNode.length();
        if (!textLength || !textNode.renderer() || allTextNodes.contains(textNode))
            continue;

        unsigned fontSizeBin = fontSizeBinningInterval * round(textNode.renderer()->style().fontCascade().size() / fontSizeBinningInterval);
        if (!FontSizeCounter::isValidValue(fontSizeBin))
            continue;

        allTextNodes.add(textNode);

        fontSizeCounter.add(fontSizeBin, textLength);
        totalSampledTextLength += textLength;
    }

    auto sortedFontSizesAndCounts = WTF::map(fontSizeCounter, [](auto& entry) {
        return FontSizeAndCount { entry.key, entry.value };
    });

    std::ranges::sort(sortedFontSizesAndCounts, { }, &FontSizeAndCount::fontSize);

    double defaultScale = clampTo<double>(defaultTextLegibilityZoomScale, viewportMinimumScale, viewportMaximumScale);
    double textLegibilityScale = defaultScale;
    double currentSampledTextLength = 0;
    for (auto& fontSizeAndCount : sortedFontSizesAndCounts) {
        currentSampledTextLength += fontSizeAndCount.count;
        double ratioOfTextUnderCurrentFontSize = currentSampledTextLength / totalSampledTextLength;
        if (ratioOfTextUnderCurrentFontSize >= textLegibilityScaleRatio) {
            textLegibilityScale = clampTo<double>(targetLegibilityFontSize / fontSizeAndCount.fontSize, viewportMinimumScale, viewportMaximumScale);
            break;
        }
    }

    auto firstTextLegibilityScale = std::min<double>(textLegibilityScale, defaultScale);
    auto secondTextLegibilityScale = std::max<double>(textLegibilityScale, defaultScale);
    if (secondTextLegibilityScale - firstTextLegibilityScale < minimumScaleDifferenceForZooming)
        firstTextLegibilityScale = secondTextLegibilityScale;

    m_cachedTextLegibilityScales.emplace(std::pair<double, double> { firstTextLegibilityScale, secondTextLegibilityScale });
    return m_cachedTextLegibilityScales;
}

#endif // PLATFORM(IOS_FAMILY)

void ViewGestureGeometryCollector::computeZoomInformationForNode(Node& node, FloatPoint& origin, FloatRect& absoluteBoundingRect, bool& isReplaced, double& viewportMinimumScale, double& viewportMaximumScale)
{
    absoluteBoundingRect = node.absoluteBoundingRect(&isReplaced);
    if (node.document().isImageDocument()) {
        if (RefPtr imageElement = downcast<ImageDocument>(node.document()).imageElement()) {
            if (&node != imageElement.get()) {
                absoluteBoundingRect = imageElement->absoluteBoundingRect(&isReplaced);
                FloatPoint newOrigin = origin;
                if (origin.x() < absoluteBoundingRect.x() || origin.x() > absoluteBoundingRect.maxX())
                    newOrigin.setX(absoluteBoundingRect.x() + absoluteBoundingRect.width() / 2);
                if (origin.y() < absoluteBoundingRect.y() || origin.y() > absoluteBoundingRect.maxY())
                    newOrigin.setY(absoluteBoundingRect.y() + absoluteBoundingRect.height() / 2);
                origin = newOrigin;
            }
            isReplaced = true;
        }
    }  else {
#if ENABLE(PDF_PLUGIN)
        if (RefPtr pluginView = m_webPage->mainFramePlugIn()) {
            absoluteBoundingRect = pluginView->absoluteBoundingRectForSmartMagnificationAtPoint(origin);
            isReplaced = false;
        }
#endif
    }

    computeMinimumAndMaximumViewportScales(viewportMinimumScale, viewportMaximumScale);
}

void ViewGestureGeometryCollector::computeMinimumAndMaximumViewportScales(double& viewportMinimumScale, double& viewportMaximumScale) const
{
#if PLATFORM(IOS_FAMILY)
    RefPtr webPage = m_webPage.get();
    if (!webPage)
        return;

    viewportMinimumScale = m_webPage->minimumPageScaleFactor();
    viewportMaximumScale = m_webPage->maximumPageScaleFactor();
#else
    viewportMinimumScale = 0;
    viewportMaximumScale = std::numeric_limits<double>::max();
#endif
}

#if !PLATFORM(IOS_FAMILY)
void ViewGestureGeometryCollector::collectGeometryForMagnificationGesture()
{
    RefPtr webPage = m_webPage.get();
    if (!webPage)
        return;

    RefPtr frameView = webPage->localMainFrameView();
    if (!frameView)
        return;

    FloatRect visibleContentRect = frameView->unobscuredContentRectIncludingScrollbars();
    bool frameHandlesMagnificationGesture = webPage->handlesPageScaleGesture();
    webPage->send(Messages::ViewGestureController::DidCollectGeometryForMagnificationGesture(visibleContentRect, frameHandlesMagnificationGesture));
}

void ViewGestureGeometryCollector::setRenderTreeSizeNotificationThreshold(uint64_t size)
{
    m_renderTreeSizeNotificationThreshold = size;
    sendDidHitRenderTreeSizeThresholdIfNeeded();
}

void ViewGestureGeometryCollector::sendDidHitRenderTreeSizeThresholdIfNeeded()
{
    RefPtr webPage = m_webPage.get();
    if (!webPage)
        return;

    if (m_renderTreeSizeNotificationThreshold && webPage->renderTreeSize() >= m_renderTreeSizeNotificationThreshold) {
        webPage->send(Messages::ViewGestureController::DidHitRenderTreeSizeThreshold());
        m_renderTreeSizeNotificationThreshold = 0;
    }
}
#endif

void ViewGestureGeometryCollector::mainFrameDidLayout()
{
#if PLATFORM(IOS_FAMILY)
    m_cachedTextLegibilityScales.reset();
#else
    sendDidHitRenderTreeSizeThresholdIfNeeded();
#endif
}

} // namespace WebKit

