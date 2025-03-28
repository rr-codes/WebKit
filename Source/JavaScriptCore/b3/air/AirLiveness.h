/*
 * Copyright (C) 2015-2024 Apple Inc. All rights reserved.
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

#include "AirLivenessAdapter.h"
#include "CompilerTimingScope.h"
#include "SuperSampler.h"
#include <wtf/Liveness.h>
#include <wtf/SequesteredMalloc.h>
#include <wtf/TZoneMalloc.h>

namespace JSC { namespace B3 { namespace Air {

template<typename Adapter>
class Liveness : public WTF::Liveness<Adapter> {
    WTF_MAKE_SEQUESTERED_ARENA_ALLOCATED_TEMPLATE(Liveness);
public:
    Liveness(Code& code)
        : WTF::Liveness<Adapter>(code.cfg(), code)
    {
        SuperSamplerScope samplingScope(false);
        CompilerTimingScope timingScope("Air"_s, "Liveness"_s);
        WTF::Liveness<Adapter>::compute();
    }
};

WTF_MAKE_SEQUESTERED_ARENA_ALLOCATED_TEMPLATE_IMPL(template<typename Adapter>, Liveness<Adapter>);

template<Bank bank, Arg::Temperature minimumTemperature = Arg::Cold>
using TmpLiveness = Liveness<TmpLivenessAdapter<bank, minimumTemperature>>;

typedef Liveness<TmpLivenessAdapter<GP>> GPLiveness;
typedef Liveness<TmpLivenessAdapter<FP>> FPLiveness;
typedef Liveness<UnifiedTmpLivenessAdapter> UnifiedTmpLiveness;
typedef Liveness<StackSlotLivenessAdapter> StackSlotLiveness;

} } } // namespace JSC::B3::Air

#endif // ENABLE(B3_JIT)
