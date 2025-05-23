/*
 * Copyright (C) 2022-2023 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1.  Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 * 2.  Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE AND ITS CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL APPLE OR ITS CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "config.h"
#include "ColorInterpolationMethod.h"

#include <wtf/text/StringBuilder.h>
#include <wtf/text/TextStream.h>

namespace WebCore {

void serializationForCSS(StringBuilder& builder, ColorInterpolationColorSpace interpolationColorSpace)
{
    builder.append(serializationForCSS(interpolationColorSpace));
}

void serializationForCSS(StringBuilder& builder, HueInterpolationMethod hueInterpolationMethod)
{
    switch (hueInterpolationMethod) {
    case HueInterpolationMethod::Shorter:
        break;
    case HueInterpolationMethod::Longer:
        builder.append(" longer hue"_s);
        break;
    case HueInterpolationMethod::Increasing:
        builder.append(" increasing hue"_s);
        break;
    case HueInterpolationMethod::Decreasing:
        builder.append(" decreasing hue"_s);
        break;
    }
}

void serializationForCSS(StringBuilder& builder, const ColorInterpolationMethod& method)
{
    WTF::switchOn(method.colorSpace,
        [&]<typename MethodColorSpace> (const MethodColorSpace& type) {
            serializationForCSS(builder, type.interpolationColorSpace);
            if constexpr (hasHueInterpolationMethod<MethodColorSpace>)
                serializationForCSS(builder, type.hueInterpolationMethod);
        }
    );
}

String serializationForCSS(const ColorInterpolationMethod& method)
{
    StringBuilder builder;
    serializationForCSS(builder, method);
    return builder.toString();
}

TextStream& operator<<(TextStream& ts, ColorInterpolationColorSpace interpolationColorSpace)
{
    switch (interpolationColorSpace) {
    case ColorInterpolationColorSpace::HSL:
        ts << "HSL"_s;
        break;
    case ColorInterpolationColorSpace::HWB:
        ts << "HWB"_s;
        break;
    case ColorInterpolationColorSpace::LCH:
        ts << "LCH"_s;
        break;
    case ColorInterpolationColorSpace::Lab:
        ts << "Lab"_s;
        break;
    case ColorInterpolationColorSpace::OKLCH:
        ts << "OKLCH"_s;
        break;
    case ColorInterpolationColorSpace::OKLab:
        ts << "OKLab"_s;
        break;
    case ColorInterpolationColorSpace::SRGB:
        ts << "sRGB"_s;
        break;
    case ColorInterpolationColorSpace::SRGBLinear:
        ts << "sRGB linear"_s;
        break;
    case ColorInterpolationColorSpace::DisplayP3:
        ts << "Display P3"_s;
        break;
    case ColorInterpolationColorSpace::A98RGB:
        ts << "A98 RGB"_s;
        break;
    case ColorInterpolationColorSpace::ProPhotoRGB:
        ts << "ProPhoto RGB"_s;
        break;
    case ColorInterpolationColorSpace::Rec2020:
        ts << "Rec2020"_s;
        break;
    case ColorInterpolationColorSpace::XYZD50:
        ts << "XYZ D50"_s;
        break;
    case ColorInterpolationColorSpace::XYZD65:
        ts << "XYZ D65"_s;
        break;
    }
    return ts;
}

TextStream& operator<<(TextStream& ts, HueInterpolationMethod hueInterpolationMethod)
{
    switch (hueInterpolationMethod) {
    case HueInterpolationMethod::Shorter:
        ts << "shorter"_s;
        break;
    case HueInterpolationMethod::Longer:
        ts << "longer"_s;
        break;
    case HueInterpolationMethod::Increasing:
        ts << "increasing"_s;
        break;
    case HueInterpolationMethod::Decreasing:
        ts << "decreasing"_s;
        break;
    }
    return ts;
}

TextStream& operator<<(TextStream& ts, const ColorInterpolationMethod& method)
{
    WTF::switchOn(method.colorSpace,
        [&]<typename ColorSpace> (const ColorSpace& type) {
            ts << type.interpolationColorSpace;
            if constexpr (hasHueInterpolationMethod<ColorSpace>)
                ts << ' ' << type.hueInterpolationMethod;
            ts << ' ' << method.alphaPremultiplication;
        }
    );
    return ts;
}

} // namespace WebCore
