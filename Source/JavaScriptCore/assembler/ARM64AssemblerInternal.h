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

#include <wtf/Platform.h>

#if ENABLE(ASSEMBLER) && CPU(ARM64)

#include "AssemblerCommonInternal.h"
#include "ExecutableAllocatorInternal.h"
#include <JavaScriptCore/ARM64Assembler.h>

WTF_ALLOW_UNSAFE_BUFFER_USAGE_BEGIN

namespace JSC {

ALWAYS_INLINE void ARM64Assembler::linkPointer(void* code, AssemblerLabel where, void* valuePtr)
{
    linkPointer<jitMemcpyRepatch>(addressOf(code, where), valuePtr);
}

inline void ARM64Assembler::replaceWithVMHalt(void *where)
{
    // This should try to write to null which should always Segfault.
    int insn = dataCacheZeroVirtualAddress(ARM64Registers::zr);
    RELEASE_ASSERT(roundUpToMultipleOf<instructionSize>(where) == where);
    performJITMemcpy<jitMemcpyRepatchAtomic>(where, &insn, sizeof(int));
    cacheFlush(where, sizeof(int));
}

inline void ARM64Assembler::replaceWithJump(void* where, void* to)
{
    intptr_t offset = (reinterpret_cast<intptr_t>(to) - reinterpret_cast<intptr_t>(where)) >> 2;
    ASSERT(static_cast<int>(offset) == offset);

#if ENABLE(JUMP_ISLANDS)
    if (!isInt<26>(offset)) {
        to = ExecutableAllocator::singleton().getJumpIslandToUsingJITMemcpy(where, to);
        offset = (std::bit_cast<intptr_t>(to) - std::bit_cast<intptr_t>(where)) >> 2;
        RELEASE_ASSERT(isInt<26>(offset));
    }
#endif

    int insn = unconditionalBranchImmediate(false, static_cast<int>(offset));
    RELEASE_ASSERT(roundUpToMultipleOf<instructionSize>(where) == where);
    performJITMemcpy<jitMemcpyRepatchAtomic>(where, &insn, sizeof(int));
    cacheFlush(where, sizeof(int));
}

ALWAYS_INLINE void ARM64Assembler::replaceWithNops(void* where, size_t memoryToFillWithNopsInBytes)
{
    fillNops<jitMemcpyRepatch>(where, memoryToFillWithNopsInBytes);
    cacheFlush(where, memoryToFillWithNopsInBytes);
}

template<RepatchingInfo repatch>
ALWAYS_INLINE void ARM64Assembler::fillNops(void* base, size_t size)
{
    static_assert(!(*repatch).contains(RepatchingFlag::Flush));
    RELEASE_ASSERT(!(size % sizeof(int32_t)));
    size_t n = size / sizeof(int32_t);
    int32_t* ptr = static_cast<int32_t*>(base);
    RELEASE_ASSERT(roundUpToMultipleOf<instructionSize>(ptr) == ptr);
    for (; n--;) {
        int insn = nopPseudo();
        machineCodeCopy<repatch>(ptr++, &insn, sizeof(int));
    }
}

template<RepatchingInfo repatch>
ALWAYS_INLINE void ARM64Assembler::fillNearTailCall(void* from, void* to)
{
    static_assert((*repatch).contains(RepatchingFlag::Flush));
    RELEASE_ASSERT(roundUpToMultipleOf<instructionSize>(from) == from);
    intptr_t offset = (std::bit_cast<intptr_t>(to) - std::bit_cast<intptr_t>(from)) >> 2;
    ASSERT(static_cast<int>(offset) == offset);
    ASSERT(isInt<26>(offset));
    constexpr bool isCall = false;
    int insn = unconditionalBranchImmediate(isCall, static_cast<int>(offset));
    machineCodeCopy<noFlush(repatch)>(from, &insn, sizeof(int));
    cacheFlush(from, sizeof(int));
}

ALWAYS_INLINE void ARM64Assembler::repatchPointer(void* where, void* valuePtr)
{
    linkPointer<jitMemcpyRepatchFlush>(static_cast<int*>(where), valuePtr);
}

template<RepatchingInfo repatch>
ALWAYS_INLINE void ARM64Assembler::setPointer(int* address, void* valuePtr, RegisterID rd)
{
    uintptr_t value = reinterpret_cast<uintptr_t>(valuePtr);
    int buffer[NUMBER_OF_ADDRESS_ENCODING_INSTRUCTIONS];
    buffer[0] = moveWideImediate(Datasize_64, MoveWideOp_Z, 0, getHalfword(value, 0), rd);
    buffer[1] = moveWideImediate(Datasize_64, MoveWideOp_K, 1, getHalfword(value, 1), rd);
    if constexpr (NUMBER_OF_ADDRESS_ENCODING_INSTRUCTIONS > 2)
        buffer[2] = moveWideImediate(Datasize_64, MoveWideOp_K, 2, getHalfword(value, 2), rd);
    if constexpr (NUMBER_OF_ADDRESS_ENCODING_INSTRUCTIONS > 3)
        buffer[3] = moveWideImediate(Datasize_64, MoveWideOp_K, 3, getHalfword(value, 3), rd);
    RELEASE_ASSERT(roundUpToMultipleOf<instructionSize>(address) == address);
    performJITMemcpy<noFlush(repatch)>(address, buffer, sizeof(int) * NUMBER_OF_ADDRESS_ENCODING_INSTRUCTIONS);

    if constexpr ((*repatch).contains(RepatchingFlag::Flush))
        cacheFlush(address, sizeof(int) * NUMBER_OF_ADDRESS_ENCODING_INSTRUCTIONS);
}

template<ARM64Assembler::BranchTargetType type, RepatchingInfo repatch>
ALWAYS_INLINE void ARM64Assembler::linkCompareAndBranch(Condition condition, bool is64Bit, RegisterID rt, int* from, const int* fromInstruction, void* to)
{
    RELEASE_ASSERT(roundUpToMultipleOf<instructionSize>(from) == from);
    ASSERT(!(reinterpret_cast<intptr_t>(from) & 3));
    ASSERT(!(reinterpret_cast<intptr_t>(to) & 3));
    intptr_t offset = (reinterpret_cast<intptr_t>(to) - reinterpret_cast<intptr_t>(fromInstruction)) >> 2;

    bool useDirect = isInt<19>(offset);
    ASSERT(type == IndirectBranch || useDirect);

    if (useDirect || type == DirectBranch) {
        ASSERT(isInt<19>(offset));
        int insn = compareAndBranchImmediate(is64Bit ? Datasize_64 : Datasize_32, condition == ConditionNE, static_cast<int>(offset), rt);
        machineCodeCopy<repatch>(from, &insn, sizeof(int));
        if (type == IndirectBranch) {
            insn = nopPseudo();
            machineCodeCopy<repatch>(from + 1, &insn, sizeof(int));
        }
    } else {
        int insn = compareAndBranchImmediate(is64Bit ? Datasize_64 : Datasize_32, invert(condition) == ConditionNE, 2, rt);
        machineCodeCopy<repatch>(from, &insn, sizeof(int));
        linkJumpOrCall<BranchType_JMP, repatch>(from + 1, fromInstruction + 1, to);
    }
}

template<ARM64Assembler::BranchTargetType type, RepatchingInfo repatch>
ALWAYS_INLINE void ARM64Assembler::linkConditionalBranch(Condition condition, int* from, const int* fromInstruction, void* to)
{
    RELEASE_ASSERT(roundUpToMultipleOf<instructionSize>(from) == from);
    ASSERT(!(reinterpret_cast<intptr_t>(from) & 3));
    ASSERT(!(reinterpret_cast<intptr_t>(to) & 3));
    intptr_t offset = (reinterpret_cast<intptr_t>(to) - reinterpret_cast<intptr_t>(fromInstruction)) >> 2;

    bool useDirect = isInt<19>(offset);
    ASSERT(type == IndirectBranch || useDirect);

    if (useDirect || type == DirectBranch) {
        ASSERT(isInt<19>(offset));
        int insn = conditionalBranchImmediate(static_cast<int>(offset), condition);
        machineCodeCopy<repatch>(from, &insn, sizeof(int));
        if (type == IndirectBranch) {
            insn = nopPseudo();
            machineCodeCopy<repatch>(from + 1, &insn, sizeof(int));
        }
    } else {
        int insn = conditionalBranchImmediate(2, invert(condition));
        machineCodeCopy<repatch>(from, &insn, sizeof(int));
        linkJumpOrCall<BranchType_JMP, repatch>(from + 1, fromInstruction + 1, to);
    }
}

template<ARM64Assembler::BranchTargetType type, RepatchingInfo repatch>
ALWAYS_INLINE void ARM64Assembler::linkTestAndBranch(Condition condition, unsigned bitNumber, RegisterID rt, int* from, const int* fromInstruction, void* to)
{
    RELEASE_ASSERT(roundUpToMultipleOf<instructionSize>(from) == from);
    ASSERT(!(reinterpret_cast<intptr_t>(from) & 3));
    ASSERT(!(reinterpret_cast<intptr_t>(to) & 3));
    intptr_t offset = (reinterpret_cast<intptr_t>(to) - reinterpret_cast<intptr_t>(fromInstruction)) >> 2;
    ASSERT(static_cast<int>(offset) == offset);

    bool useDirect = isInt<14>(offset);
    ASSERT(type == IndirectBranch || useDirect);

    if (useDirect || type == DirectBranch) {
        ASSERT(isInt<14>(offset));
        int insn = testAndBranchImmediate(condition == ConditionNE, static_cast<int>(bitNumber), static_cast<int>(offset), rt);
        machineCodeCopy<repatch>(from, &insn, sizeof(int));
        if (type == IndirectBranch) {
            insn = nopPseudo();
            machineCodeCopy<repatch>(from + 1, &insn, sizeof(int));
        }
    } else {
        int insn = testAndBranchImmediate(invert(condition) == ConditionNE, static_cast<int>(bitNumber), 2, rt);
        machineCodeCopy<repatch>(from, &insn, sizeof(int));
        linkJumpOrCall<BranchType_JMP, repatch>(from + 1, fromInstruction + 1, to);
    }
}

template<RepatchingInfo repatch>
ALWAYS_INLINE void ARM64Assembler::linkPointer(int* address, void* valuePtr)
{
    Datasize sf;
    MoveWideOp opc;
    int hw;
    uint16_t imm16;
    RegisterID rd;
    bool expected = disassembleMoveWideImediate(address, sf, opc, hw, imm16, rd);
    ASSERT_UNUSED(expected, expected && sf && opc == MoveWideOp_Z && !hw);
    ASSERT(checkMovk<Datasize_64>(address[1], 1, rd));
    if constexpr (NUMBER_OF_ADDRESS_ENCODING_INSTRUCTIONS > 2)
        ASSERT(checkMovk<Datasize_64>(address[2], 2, rd));
    if constexpr (NUMBER_OF_ADDRESS_ENCODING_INSTRUCTIONS > 3)
        ASSERT(checkMovk<Datasize_64>(address[3], 3, rd));

    setPointer<repatch>(address, valuePtr, rd);
}

template<ARM64Assembler::BranchType type, RepatchingInfo repatch>
ALWAYS_INLINE void ARM64Assembler::linkJumpOrCall(int* from, const int* fromInstruction, void* to)
{
    static_assert(type == BranchType_JMP || type == BranchType_CALL);

    bool link;
    int imm26;
    bool isUnconditionalBranchImmediateOrNop = disassembleUnconditionalBranchImmediate(from, link, imm26) || disassembleNop(from);

    ASSERT_UNUSED(isUnconditionalBranchImmediateOrNop, isUnconditionalBranchImmediateOrNop);
    constexpr bool isCall = (type == BranchType_CALL);
    ASSERT_UNUSED(isCall, (link == isCall) || disassembleNop(from));
    ASSERT(!(reinterpret_cast<intptr_t>(from) & 3));
    ASSERT(!(reinterpret_cast<intptr_t>(to) & 3));
    assertIsNotTagged(to);
    assertIsNotTagged(fromInstruction);
    intptr_t offset = (std::bit_cast<intptr_t>(to) - std::bit_cast<intptr_t>(fromInstruction)) >> 2;
    ASSERT(static_cast<int>(offset) == offset);

#if ENABLE(JUMP_ISLANDS)
    if (!isInt<26>(offset)) {
        if constexpr (!(*repatch).contains(RepatchingFlag::Memcpy))
            to = ExecutableAllocator::singleton().getJumpIslandToUsingJITMemcpy(std::bit_cast<void*>(fromInstruction), to);
        else
            to = ExecutableAllocator::singleton().getJumpIslandToUsingMemcpy(std::bit_cast<void*>(fromInstruction), to);
        offset = (std::bit_cast<intptr_t>(to) - std::bit_cast<intptr_t>(fromInstruction)) >> 2;
        RELEASE_ASSERT(isInt<26>(offset));
    }
#endif

    int insn = unconditionalBranchImmediate(isCall, static_cast<int>(offset));
    RELEASE_ASSERT(roundUpToMultipleOf<instructionSize>(from) == from);
    machineCodeCopy<repatch>(from, &insn, sizeof(int));
}

} // namespace JSC

WTF_ALLOW_UNSAFE_BUFFER_USAGE_END

#endif // ENABLE(ASSEMBLER) && CPU(ARM64)
