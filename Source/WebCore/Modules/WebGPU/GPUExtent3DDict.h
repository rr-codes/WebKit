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

#include "GPUIntegralTypes.h"
#include "WebGPUExtent3D.h"
#include <wtf/Vector.h>

namespace WebCore {

struct GPUExtent3DDict {
    WebGPU::Extent3DDict convertToBacking() const
    {
        return {
            width,
            height,
            depthOrArrayLayers,
        };
    }

    GPUIntegerCoordinate width { 0 };
    GPUIntegerCoordinate height { 0 };
    GPUIntegerCoordinate depthOrArrayLayers { 0 };
};

using GPUExtent3D = Variant<Vector<GPUIntegerCoordinate>, GPUExtent3DDict>;

inline WebGPU::Extent3D convertToBacking(const GPUExtent3D& extent3D)
{
    return WTF::switchOn(extent3D, [](const Vector<GPUIntegerCoordinate>& vector) -> WebGPU::Extent3D {
        return vector;
    }, [](const GPUExtent3DDict& extent3D) -> WebGPU::Extent3D {
        return extent3D.convertToBacking();
    });
}

}
