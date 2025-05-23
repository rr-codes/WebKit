/*
 * Copyright (C) Research In Motion Limited 2010. All rights reserved.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public License
 * along with this library; see the file COPYING.LIB.  If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 */

#pragma once

#include "Color.h"
#include "FloatRect.h"
#include "LegacyRenderSVGResource.h"
#include <wtf/TZoneMalloc.h>

namespace WebCore {

class RenderObject;

class LegacyRenderSVGResourceSolidColor final : public LegacyRenderSVGResource {
    WTF_MAKE_TZONE_ALLOCATED(LegacyRenderSVGResourceSolidColor);
public:
    LegacyRenderSVGResourceSolidColor();
    virtual ~LegacyRenderSVGResourceSolidColor();

    void removeAllClientsFromCache() override { }
    void removeAllClientsFromCacheAndMarkForInvalidationIfNeeded(bool, SingleThreadWeakHashSet<RenderObject>*) override { }
    void removeClientFromCache(RenderElement&) override { }
    void removeClientFromCacheAndMarkForInvalidation(RenderElement&, bool = true) override { }

    OptionSet<ApplyResult> applyResource(RenderElement&, const RenderStyle&, GraphicsContext*&, OptionSet<RenderSVGResourceMode>) override;
    void postApplyResource(RenderElement&, GraphicsContext*&, OptionSet<RenderSVGResourceMode>, const Path*, const RenderElement*) override;
    FloatRect resourceBoundingBox(const RenderObject&, RepaintRectCalculation) override { return FloatRect(); }

    RenderSVGResourceType resourceType() const override { return SolidColorResourceType; }

    const Color& color() const { return m_color; }
    void setColor(const Color& color) { m_color = color; }

private:
    Color m_color;
};

} // namespace WebCore

SPECIALIZE_TYPE_TRAITS_LEGACY_RENDER_SVG_RESOURCE(LegacyRenderSVGResourceSolidColor, SolidColorResourceType)
