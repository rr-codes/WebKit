/*
 * Copyright (C) 2012-2024 Apple Inc. All rights reserved.
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

#if ENABLE(ASSEMBLER) && CPU(ARM64)

#include "ARM64AssemblerInternal.h"
#include <JavaScriptCore/MacroAssemblerARM64.h>

WTF_ALLOW_UNSAFE_BUFFER_USAGE_BEGIN

namespace JSC {

template<PtrTag tag>
ALWAYS_INLINE void MacroAssemblerARM64::linkCall(void* code, Call call, CodePtr<tag> function)
{
    if (!call.isFlagSet(Call::Near))
        Assembler::linkPointer(code, call.m_label.labelAtOffset(REPATCH_OFFSET_CALL_TO_POINTER), function.taggedPtr());
    else if (call.isFlagSet(Call::Tail))
        Assembler::linkJump(code, call.m_label, function.untaggedPtr());
    else
        Assembler::linkCall(code, call.m_label, function.untaggedPtr());
}

template<PtrTag callTag, PtrTag destTag>
ALWAYS_INLINE void MacroAssemblerARM64::repatchCall(CodeLocationCall<callTag> call, CodeLocationLabel<destTag> destination)
{
    Assembler::repatchPointer(call.dataLabelPtrAtOffset(REPATCH_OFFSET_CALL_TO_POINTER).dataLocation(), destination.taggedPtr());
}

template<PtrTag callTag, PtrTag destTag>
ALWAYS_INLINE void MacroAssemblerARM64::repatchCall(CodeLocationCall<callTag> call, CodePtr<destTag> destination)
{
    Assembler::repatchPointer(call.dataLabelPtrAtOffset(REPATCH_OFFSET_CALL_TO_POINTER).dataLocation(), destination.taggedPtr());
}

template<PtrTag tag>
ALWAYS_INLINE void MacroAssemblerARM64::replaceWithVMHalt(CodeLocationLabel<tag> instructionStart)
{
    Assembler::replaceWithVMHalt(instructionStart.dataLocation());
}

template<PtrTag startTag, PtrTag destTag>
ALWAYS_INLINE void MacroAssemblerARM64::replaceWithJump(CodeLocationLabel<startTag> instructionStart, CodeLocationLabel<destTag> destination)
{
    Assembler::replaceWithJump(instructionStart.dataLocation(), destination.dataLocation());
}

template<PtrTag startTag>
ALWAYS_INLINE void MacroAssemblerARM64::replaceWithNops(CodeLocationLabel<startTag> instructionStart, size_t memoryToFillWithNopsInBytes)
{
    Assembler::replaceWithNops(instructionStart.dataLocation(), memoryToFillWithNopsInBytes);
}

} // namespace JSC

WTF_ALLOW_UNSAFE_BUFFER_USAGE_END

#endif // ENABLE(ASSEMBLER) && CPU(ARM64)
