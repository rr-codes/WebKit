/*
 * Copyright (C) 2021-2023 Apple Inc. All rights reserved.
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

#include "GPUObjectDescriptorBase.h"
#include "GPUPredefinedColorSpace.h"
#include "HTMLVideoElement.h"
#include "WebCodecsVideoFrame.h"
#include "WebGPUExternalTextureDescriptor.h"
#include <wtf/RefPtr.h>

#if PLATFORM(COCOA)
typedef struct CF_BRIDGED_TYPE(id) __CVBuffer* CVPixelBufferRef;
#endif

namespace WebCore {

class HTMLVideoElement;
#if ENABLE(WEB_CODECS)
using GPUVideoSource = Variant<RefPtr<HTMLVideoElement>, RefPtr<WebCodecsVideoFrame>>;
#else
using GPUVideoSource = RefPtr<HTMLVideoElement>;
#endif

struct GPUExternalTextureDescriptor : public GPUObjectDescriptorBase {

#if ENABLE(VIDEO)
    static WebGPU::VideoSourceIdentifier mediaIdentifierForSource(const GPUVideoSource& videoSource)
    {
#if ENABLE(WEB_CODECS)
        return WTF::switchOn(videoSource, [&](const RefPtr<HTMLVideoElement> videoElement) -> WebGPU::VideoSourceIdentifier {
            if (auto playerIdentifier = videoElement->playerIdentifier())
                return playerIdentifier;
            RefPtr<WebCore::VideoFrame> result;
            if (videoElement->player())
                result = videoElement->protectedPlayer()->videoFrameForCurrentTime();
            return result;
        }
        , [&](const RefPtr<WebCodecsVideoFrame> videoFrame) -> WebGPU::VideoSourceIdentifier {
            return videoFrame->internalFrame();
        });
#else
        return videoSource->playerIdentifier();
#endif
    }

    std::optional<WebCore::MediaPlayerIdentifier> mediaIdentifier() const
    {
#if ENABLE(WEB_CODECS)
        return WTF::switchOn(source, [&](const RefPtr<HTMLVideoElement> videoElement) -> std::optional<WebCore::MediaPlayerIdentifier> {
            return videoElement->playerIdentifier();
        }
        , [&](const RefPtr<WebCodecsVideoFrame>) -> std::optional<WebCore::MediaPlayerIdentifier> {
            return std::nullopt;
        });
#else
        return source->playerIdentifier();
#endif
    }
#endif

    WebGPU::ExternalTextureDescriptor convertToBacking() const
    {
        return {
            { label },
#if ENABLE(VIDEO)
            mediaIdentifierForSource(source),
#else
            { },
#endif
            WebCore::convertToBacking(colorSpace),
        };
    }

#if ENABLE(VIDEO)
    GPUVideoSource source;
#endif
    GPUPredefinedColorSpace colorSpace { GPUPredefinedColorSpace::SRGB };
};

}
