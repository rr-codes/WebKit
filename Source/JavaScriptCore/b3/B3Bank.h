/*
 * Copyright (C) 2017-2019 Apple Inc. All rights reserved.
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

#if ENABLE(B3_JIT)

#include "B3Type.h"
#include "Reg.h"

namespace JSC { namespace B3 {

enum Bank : int8_t {
    GP,
    FP
};

static constexpr unsigned numBanks = 2;

template<typename Func>
void forEachBank(const Func& func)
{
    func(GP);
    func(FP);
}

inline Bank bankForType(Type type)
{
    switch (type.kind()) {
    case Void:
    case Tuple:
        ASSERT_NOT_REACHED();
        return GP;
    case Int32:
    case Int64:
        return GP;
    case Float:
    case Double:
    case V128:
        return FP;
    }
    ASSERT_NOT_REACHED();
    return GP;
}

inline Bank bankForReg(Reg reg)
{
    return reg.isFPR() ? FP : GP;
}

inline Width minimumWidth(Bank bank)
{
    return bank == GP ? Width8 : Width32;
}

ALWAYS_INLINE constexpr Width conservativeWidthWithoutVectors(Bank bank)
{
    return bank == FP ? Width64 : widthForBytes(sizeof(CPURegister));
}

ALWAYS_INLINE constexpr Width conservativeWidth(Bank bank)
{
    return bank == FP ? Width128 : widthForBytes(sizeof(CPURegister));
}

ALWAYS_INLINE constexpr unsigned conservativeRegisterBytes(Bank bank)
{
    return bytesForWidth(conservativeWidth(bank));
}

ALWAYS_INLINE constexpr unsigned conservativeRegisterBytesWithoutVectors(Bank bank)
{
    return bytesForWidth(conservativeWidthWithoutVectors(bank));
}

} } // namespace JSC::B3

namespace WTF {

class PrintStream;

void printInternal(PrintStream&, JSC::B3::Bank);

} // namespace WTF

#endif // ENABLE(B3_JIT)

