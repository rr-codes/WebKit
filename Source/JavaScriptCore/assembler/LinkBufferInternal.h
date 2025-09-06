/*
 * Copyright (C) 2009-2023 Apple Inc. All rights reserved.
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

#include <wtf/Platform.h>

#if ENABLE(ASSEMBLER)

#include "AbstractMacroAssemblerInternal.h"
#include "MacroAssemblerARM64Internal.h"
#include <JavaScriptCore/LinkBuffer.h>

WTF_ALLOW_UNSAFE_BUFFER_USAGE_BEGIN

namespace JSC {

template<PtrTag tag, typename Func, typename>
ALWAYS_INLINE void LinkBuffer::link(Call call, Func funcName)
{
    CodePtr<tag> function(funcName);
    link(call, function);
}

template<PtrTag tag>
ALWAYS_INLINE void LinkBuffer::link(Call call, CodePtr<tag> function)
{
    ASSERT(call.isFlagSet(Call::Linkable));
    call.m_label = applyOffset(call.m_label);
    MacroAssembler::linkCall(code(), call, function);
}

template<PtrTag tag>
ALWAYS_INLINE void LinkBuffer::link(Call call, CodeLocationLabel<tag> label)
{
    link(call, CodePtr<tag>(label));
}

template<PtrTag tag>
ALWAYS_INLINE void LinkBuffer::link(Jump jump, CodeLocationLabel<tag> label)
{
    jump.m_label = applyOffset(jump.m_label);
    MacroAssembler::linkJump(code(), jump, label);
}

template<PtrTag tag>
ALWAYS_INLINE void LinkBuffer::link(const JumpList& list, CodeLocationLabel<tag> label)
{
    for (const Jump& jump : list.jumps())
        link(jump, label);
}

ALWAYS_INLINE void LinkBuffer::patch(DataLabelPtr label, void* value)
{
    AssemblerLabel target = applyOffset(label.m_label);
    MacroAssembler::linkPointer(code(), target, value);
}

template<PtrTag tag>
ALWAYS_INLINE void LinkBuffer::patch(DataLabelPtr label, CodeLocationLabel<tag> value)
{
    AssemblerLabel target = applyOffset(label.m_label);
    MacroAssembler::linkPointer(code(), target, value);
}


} // namespace JSC

WTF_ALLOW_UNSAFE_BUFFER_USAGE_END

#endif // ENABLE(ASSEMBLER)
