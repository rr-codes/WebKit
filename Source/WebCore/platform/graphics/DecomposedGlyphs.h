/*
 * Copyright (C) 2022-2023 Apple Inc. All rights reserved.
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

#pragma once

#include "FloatPoint.h"
#include "GlyphBufferMembers.h"
#include "RenderingResource.h"
#include "TextFlags.h"
#include <wtf/TZoneMalloc.h>

namespace WebCore {

class DecomposedGlyphs final : public RenderingResource {
    WTF_MAKE_TZONE_ALLOCATED(DecomposedGlyphs);
public:
    static WEBCORE_EXPORT Ref<DecomposedGlyphs> create(Vector<GlyphBufferGlyph>&&, Vector<GlyphBufferAdvance>&&, const FloatPoint& localAnchor, FontSmoothingMode, RenderingResourceIdentifier = RenderingResourceIdentifier::generate());
    ~DecomposedGlyphs();

    std::span<const GlyphBufferGlyph> glyphs() const LIFETIME_BOUND { return m_glyphs.span(); }
    std::span<const GlyphBufferAdvance> advances() const LIFETIME_BOUND { return m_advances.span(); }
    const FloatPoint& localAnchor() const { return m_localAnchor; }
    FontSmoothingMode fontSmoothingMode() const { return m_fontSmoothingMode; }
private:
    DecomposedGlyphs(Vector<GlyphBufferGlyph>&&, Vector<GlyphBufferAdvance>&&, const FloatPoint& localAnchor, FontSmoothingMode, RenderingResourceIdentifier);

    bool isDecomposedGlyphs() const final { return true; }

    Vector<GlyphBufferGlyph> m_glyphs;
    Vector<GlyphBufferAdvance> m_advances;
    FloatPoint m_localAnchor;
    FontSmoothingMode m_fontSmoothingMode;
};

} // namespace WebCore

SPECIALIZE_TYPE_TRAITS_BEGIN(WebCore::DecomposedGlyphs)
    static bool isType(const WebCore::RenderingResource& renderingResource) { return renderingResource.isDecomposedGlyphs(); }
SPECIALIZE_TYPE_TRAITS_END()
