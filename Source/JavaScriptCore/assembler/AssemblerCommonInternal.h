/*
 * Copyright (C) 2012-2023 Apple Inc. All rights reserved.
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

#include "ExecutableAllocatorInternal.h"
#include <JavaScriptCore/AssemblerCommon.h>

namespace JSC {

WTF_ALLOW_UNSAFE_BUFFER_USAGE_BEGIN

template<RepatchingInfo repatch>
ALWAYS_INLINE void* machineCodeCopy(void* dst, const void* src, size_t n)
{
    static_assert(!(*repatch).contains(RepatchingFlag::Flush));
    if constexpr (is32Bit()) {
        // Avoid unaligned accesses.
        if (WTF::isAligned(dst, n))
            return memcpyAtomicIfPossible(dst, src, n);
        return memcpyTearing(dst, src, n);
    }
    if constexpr ((*repatch).contains(RepatchingFlag::Memcpy) && (*repatch).contains(RepatchingFlag::Atomic))
        return memcpyAtomic(dst, src, n);
    else if constexpr ((*repatch).contains(RepatchingFlag::Memcpy))
        return memcpyAtomicIfPossible(dst, src, n);
    else
        return performJITMemcpy<repatch>(dst, src, n);
}

WTF_ALLOW_UNSAFE_BUFFER_USAGE_END

} // namespace JSC.

