/*
 * Copyright (C) 2023 Apple Inc. All rights reserved.
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
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "config.h"
#include "DisplayListItem.h"

#include "DisplayListItems.h"
#include "DisplayListResourceHeap.h"
#include "FilterResults.h"
#include "GraphicsContext.h"
#include <wtf/text/TextStream.h>

namespace WebCore {
namespace DisplayList {

template<typename, typename = void> inline constexpr bool HasIsValid = false;
template<typename T> inline constexpr bool HasIsValid<T, std::void_t<decltype(std::declval<T>().isValid())>> = true;

bool isValid(const Item& item)
{
    return WTF::switchOn(item, [&]<typename T> (const T& item) {
        if constexpr (HasIsValid<T>)
            return item.isValid();
        else {
            UNUSED_PARAM(item);
            return true;
        }
    });
}

template<class T>
inline static std::optional<RenderingResourceIdentifier> applyFilteredImageBufferItem(GraphicsContext& context, const ResourceHeap& resourceHeap, const T& item, OptionSet<ReplayOption> options)
{
    auto resourceIdentifier = item.sourceImageIdentifier();
    RefPtr sourceImage = resourceIdentifier ? resourceHeap.getImageBuffer(*resourceIdentifier, options) : nullptr;
    if (UNLIKELY(!sourceImage && resourceIdentifier))
        return resourceIdentifier;

    FilterResults results;
    item.apply(context, sourceImage.get(), results);
    return std::nullopt;
}

template<class T>
inline static std::optional<RenderingResourceIdentifier> applyImageBufferItem(GraphicsContext& context, const ResourceHeap& resourceHeap, const T& item, OptionSet<ReplayOption> options)
{
    auto resourceIdentifier = item.imageBufferIdentifier();
    if (RefPtr imageBuffer = resourceHeap.getImageBuffer(resourceIdentifier, options)) {
        item.apply(context, *imageBuffer);
        return std::nullopt;
    }
    return resourceIdentifier;
}

template<class T>
inline static std::optional<RenderingResourceIdentifier> applyNativeImageItem(GraphicsContext& context, const ResourceHeap& resourceHeap, const T& item, OptionSet<ReplayOption> options)
{
    auto resourceIdentifier = item.imageIdentifier();
    if (RefPtr image = resourceHeap.getNativeImage(resourceIdentifier, options)) {
        item.apply(context, *image);
        return std::nullopt;
    }
    return resourceIdentifier;
}

template<class T>
inline static std::optional<RenderingResourceIdentifier> applySourceImageItem(GraphicsContext& context, const ResourceHeap& resourceHeap, const T& item, OptionSet<ReplayOption> options)
{
    auto resourceIdentifier = item.imageIdentifier();
    if (auto sourceImage = resourceHeap.getSourceImage(resourceIdentifier, options)) {
        item.apply(context, *sourceImage);
        return std::nullopt;
    }
    return resourceIdentifier;
}

inline static std::optional<RenderingResourceIdentifier> applySetStateItem(GraphicsContext& context, const ResourceHeap& resourceHeap, const SetState& item, OptionSet<ReplayOption> options)
{
    auto fixPatternTileImage = [&](Pattern* pattern) -> std::optional<RenderingResourceIdentifier> {
        if (!pattern)
            return std::nullopt;

        auto imageIdentifier = pattern->tileImage().imageIdentifier();
        auto sourceImage = resourceHeap.getSourceImage(imageIdentifier, options);
        if (!sourceImage)
            return imageIdentifier;

        pattern->setTileImage(WTFMove(*sourceImage));
        return std::nullopt;
    };

    if (auto imageIdentifier = fixPatternTileImage(item.state().strokeBrush().pattern()))
        return *imageIdentifier;

    if (auto imageIdentifier = fixPatternTileImage(item.state().fillBrush().pattern()))
        return *imageIdentifier;

    item.apply(context);
    return std::nullopt;
}

ApplyItemResult applyItem(GraphicsContext& context, const ResourceHeap& resourceHeap, ControlFactory& controlFactory, const Item& item, OptionSet<ReplayOption> options)
{
    if (!isValid(item))
        return { StopReplayReason::InvalidItemOrExtent, std::nullopt };

    return WTF::switchOn(item,
        [&](const ClipToImageBuffer& item) -> ApplyItemResult {
            if (auto missingCachedResourceIdentifier = applyImageBufferItem(context, resourceHeap, item, options))
                return { StopReplayReason::MissingCachedResource, WTFMove(missingCachedResourceIdentifier) };
            return { };
        }, [&](const DrawControlPart& item) -> ApplyItemResult {
            item.apply(context, controlFactory);
            return { };
        }, [&](const DrawGlyphs& item) -> ApplyItemResult {
            item.apply(context);
            return { };
        }, [&](const DrawDecomposedGlyphs& item) -> ApplyItemResult {
            item.apply(context);
            return { };
        }, [&](const DrawFilteredImageBuffer& item) -> ApplyItemResult {
            if (auto missingCachedResourceIdentifier = applyFilteredImageBufferItem(context, resourceHeap, item, options))
                return { StopReplayReason::MissingCachedResource, WTFMove(missingCachedResourceIdentifier) };
            return { };
        }, [&](const DrawImageBuffer& item) -> ApplyItemResult {
            if (auto missingCachedResourceIdentifier = applyImageBufferItem(context, resourceHeap, item, options))
                return { StopReplayReason::MissingCachedResource, WTFMove(missingCachedResourceIdentifier) };
            return { };
        }, [&](const DrawNativeImage& item) -> ApplyItemResult {
            if (auto missingCachedResourceIdentifier = applyNativeImageItem<DrawNativeImage>(context, resourceHeap, item, options))
                return { StopReplayReason::MissingCachedResource, WTFMove(missingCachedResourceIdentifier) };
            return { };
        }, [&](const DrawPattern& item) -> ApplyItemResult {
            if (auto missingCachedResourceIdentifier = applySourceImageItem<DrawPattern>(context, resourceHeap, item, options))
                return { StopReplayReason::MissingCachedResource, WTFMove(missingCachedResourceIdentifier) };
            return { };
        }, [&](const SetState& item) -> ApplyItemResult {
            if (auto missingCachedResourceIdentifier = applySetStateItem(context, resourceHeap, item, options))
                return { StopReplayReason::MissingCachedResource, WTFMove(missingCachedResourceIdentifier) };
            return { };
        }, [&](const auto& item) -> ApplyItemResult {
            item.apply(context);
            return { };
        }
    );
}

bool shouldDumpItem(const Item& item, OptionSet<AsTextFlag> flags)
{
    return WTF::switchOn(item,
        [&](const SetState& item) -> bool {
            if (!flags.contains(AsTextFlag::IncludePlatformOperations))
                return true;
            // FIXME: for now, only drop the item if the only state-change flags are platform-specific.
            return item.state().changes() != GraphicsContextState::Change::ShouldSubpixelQuantizeFonts;
#if USE(CG)
        }, [&](const ApplyFillPattern&) -> bool {
            return !flags.contains(AsTextFlag::IncludePlatformOperations);
        }, [&](const ApplyStrokePattern&) -> bool {
            return !flags.contains(AsTextFlag::IncludePlatformOperations);
#endif
        }, [&](const auto&) -> bool {
            return true;
        }
    );
}

void dumpItem(TextStream& ts, const Item& item, OptionSet<AsTextFlag> flags)
{
    WTF::switchOn(item, [&]<typename ItemType> (const ItemType& item) {
        ts << ItemType::name;
        item.dump(ts, flags);
    });
}

TextStream& operator<<(TextStream& ts, const Item& item)
{
    dumpItem(ts, item, { AsTextFlag::IncludePlatformOperations, AsTextFlag::IncludeResourceIdentifiers });
    return ts;
}

TextStream& operator<<(TextStream& ts, StopReplayReason reason)
{
    switch (reason) {
    case StopReplayReason::ReplayedAllItems: ts << "ReplayedAllItems"_s; break;
    case StopReplayReason::MissingCachedResource: ts << "MissingCachedResource"_s; break;
    case StopReplayReason::InvalidItemOrExtent: ts << "InvalidItemOrExtent"_s; break;
    case StopReplayReason::OutOfMemory: ts << "OutOfMemory"_s; break;
    }
    return ts;
}

} // namespace DisplayList
} // namespace WebCore
