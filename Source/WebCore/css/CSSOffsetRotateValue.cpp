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
#include "CSSOffsetRotateValue.h"

#include "CSSValuePool.h"

namespace WebCore {

String CSSOffsetRotateValue::customCSSText(const CSS::SerializationContext& context) const
{
    StringBuilder builder;

    if (m_modifier)
        builder.append(m_modifier->cssText(context));

    if (m_angle) {
        if (!builder.isEmpty())
            builder.append(' ');

        builder.append(m_angle->cssText(context));
    }

    return builder.toString();
}

bool CSSOffsetRotateValue::isInitialValue() const
{
    return m_modifier && m_modifier->valueID() == CSSValueAuto
        && (!m_angle || m_angle->isZero().value_or(false));
}

bool CSSOffsetRotateValue::equals(const CSSOffsetRotateValue& o) const
{
    return compareCSSValuePtr(m_modifier, o.m_modifier)
        && compareCSSValuePtr(m_angle, o.m_angle);
}

} // namespace WebCore
