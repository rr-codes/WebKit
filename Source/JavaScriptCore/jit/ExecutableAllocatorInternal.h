/*
 * Copyright (C) 2008-2023 Apple Inc. All rights reserved.
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

#include "FastJITPermissions.h"
#include <JavaScriptCore/ExecutableAllocator.h>

namespace JSC {

#if ENABLE(JIT)

WTF_ALLOW_UNSAFE_BUFFER_USAGE_BEGIN

template<RepatchingInfo repatch>
ALWAYS_INLINE void* performJITMemcpy(void *dst, const void *src, size_t n)
{
    static_assert(!(*repatch).contains(RepatchingFlag::Memcpy));
    static_assert(!(*repatch).contains(RepatchingFlag::Flush));
    jitMemcpyChecks(dst, src, n);
    if (isJITPC(dst)) {
#if ENABLE(MPROTECT_RX_TO_RWX)
        auto ret = performJITMemcpyWithMProtect(dst, src, n);
        jitMemcpyCheckForZeros(dst, src, n);
        return ret;
#endif

        if (g_jscConfig.useFastJITPermissions) {
            threadSelfRestrict<MemoryRestriction::kRwxToRw>();
            if constexpr ((*repatch).contains(RepatchingFlag::Atomic))
                memcpyAtomic(dst, src, n);
            else
                memcpyAtomicIfPossible(dst, src, n);
            threadSelfRestrict<MemoryRestriction::kRwxToRx>();
            jitMemcpyCheckForZeros(dst, src, n);
            return dst;
        }

#if ENABLE(SEPARATED_WX_HEAP)
        if (g_jscConfig.jitWriteSeparateHeaps) {
            // Use execute-only write thunk for writes inside the JIT region. This is a variant of
            // memcpy that takes an offset into the JIT region as its destination (first) parameter.
            off_t offset = (off_t)((uintptr_t)dst - startOfFixedExecutableMemoryPool<uintptr_t>());
            retagCodePtr<JITThunkPtrTag, CFunctionPtrTag>(g_jscConfig.jitWriteSeparateHeaps)(offset, src, n);
            RELEASE_ASSERT(!Gigacage::contains(src));
            jitMemcpyCheckForZeros(dst, src, n);
            return dst;
        }
#endif
        memcpyAtomicIfPossible(dst, src, n);
        jitMemcpyCheckForZeros(dst, src, n);
        return dst;
    }

    return memcpyAtomicIfPossible(dst, src, n);
}

WTF_ALLOW_UNSAFE_BUFFER_USAGE_END

#else

inline void* performJITMemcpy(void *dst, const void *src, size_t n)
{
WTF_ALLOW_UNSAFE_BUFFER_USAGE_BEGIN
    return memcpy(dst, src, n);
WTF_ALLOW_UNSAFE_BUFFER_USAGE_END
}

inline bool isJITPC(void*) { return false; }
#endif // ENABLE(JIT)

} // namespace JSC
