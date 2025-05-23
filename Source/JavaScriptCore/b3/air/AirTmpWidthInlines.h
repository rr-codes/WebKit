/*
 * Copyright (C) 2015-2017 Apple Inc. All rights reserved.
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

#if ENABLE(B3_JIT)

#include "AirTmpInlines.h"
#include "AirTmpWidth.h"

namespace JSC { namespace B3 { namespace Air {

inline TmpWidth::Widths& TmpWidth::widths(Tmp tmp)
{
    if (tmp.isGP()) {
        unsigned index = AbsoluteTmpMapper<GP>::absoluteIndex(tmp);
        ASSERT(index < m_widthGP.size());
        return m_widthGP[index];
    }
    unsigned index = AbsoluteTmpMapper<FP>::absoluteIndex(tmp);
    ASSERT(index < m_widthFP.size());
    return m_widthFP[index];
}

const TmpWidth::Widths& TmpWidth::widths(Tmp tmp) const
{
    return const_cast<TmpWidth*>(this)->widths(tmp);
}

Width TmpWidth::width(Tmp tmp) const
{
    Widths tmpWidths = widths(tmp);
    return std::min(tmpWidths.use, tmpWidths.def);
}

void TmpWidth::addWidths(Tmp tmp, Widths tmpWidths)
{
    widths(tmp) = tmpWidths;
}

Width TmpWidth::requiredWidth(Tmp tmp)
{
    Widths tmpWidths = widths(tmp);
    return std::max(tmpWidths.use, tmpWidths.def);
}

Width TmpWidth::defWidth(Tmp tmp) const
{
    return widths(tmp).def;
}

Width TmpWidth::useWidth(Tmp tmp) const
{
    return widths(tmp).use;
}

} } } // namespace JSC::B3::Air

#endif // ENABLE(B3_JIT)
