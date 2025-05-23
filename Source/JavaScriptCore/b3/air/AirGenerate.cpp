/*
 * Copyright (C) 2015-2021 Apple Inc. All rights reserved.
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

#include "config.h"
#include "AirGenerate.h"

#if ENABLE(B3_JIT)

#include "AirAllocateRegistersAndStackAndGenerateCode.h"
#include "AirAllocateRegistersAndStackByLinearScan.h"
#include "AirAllocateRegistersByGraphColoring.h"
#include "AirAllocateRegistersByGreedy.h"
#include "AirAllocateStackByGraphColoring.h"
#include "AirCode.h"
#include "AirEliminateDeadCode.h"
#include "AirFixObviousSpills.h"
#include "AirFixPartialRegisterStalls.h"
#include "AirGenerationContext.h"
#include "AirLogRegisterPressure.h"
#include "AirLowerAfterRegAlloc.h"
#include "AirLowerEntrySwitch.h"
#include "AirLowerMacros.h"
#include "AirLowerStackArgs.h"
#include "AirOpcodeUtils.h"
#include "AirOptimizeBlockOrder.h"
#include "AirOptimizePairedLoadStore.h"
#include "AirReportUsedRegisters.h"
#include "AirSimplifyCFG.h"
#include "AirValidate.h"
#include "B3Common.h"
#include "B3Procedure.h"
#include "CCallHelpers.h"
#include "CompilerTimingScope.h"
#include "DisallowMacroScratchRegisterUsage.h"
#include <wtf/IndexMap.h>

namespace JSC { namespace B3 { namespace Air {

void prepareForGeneration(Code& code)
{
    CompilerTimingScope timingScope("Total Air"_s, "prepareForGeneration"_s);
    
    // If we're doing super verbose dumping, the phase scope of any phase will already do a dump.
    if (shouldDumpIR(code.proc(), AirMode) && !shouldDumpIRAtEachPhase(AirMode)) {
        dataLog(tierName, "Initial air:\n");
        dataLog(code);
    }
    
    // We don't expect the incoming code to have predecessors computed.
    code.resetReachability();
    
    if (shouldValidateIR())
        validate(code);

    if (!code.optLevel()) {
        lowerMacros(code);

        // FIXME: The name of this phase doesn't make much sense in O0 since we do this before
        // register allocation.
        lowerAfterRegAlloc(code);

        // Actually create entrypoints.
        lowerEntrySwitch(code);
        
        // This sorts the basic blocks in Code to achieve an ordering that maximizes the likelihood that a high
        // frequency successor is also the fall-through target.
        optimizeBlockOrder(code);

        if (shouldValidateIR())
            validate(code);

        if (shouldDumpIR(code.proc(), AirMode)) {
            dataLog("Air after ", code.lastPhaseName(), ", before generation:\n");
            dataLog(code);
        }

        code.m_generateAndAllocateRegisters = makeUniqueWithoutFastMallocCheck<GenerateAndAllocateRegisters>(code);
        code.m_generateAndAllocateRegisters->prepareForGeneration();

        return;
    }

    simplifyCFG(code);

    lowerMacros(code);

    // This is where we run our optimizations and transformations.
    // FIXME: Add Air optimizations.
    // https://bugs.webkit.org/show_bug.cgi?id=150456

    eliminateDeadCode(code);

    auto useLinearScan = [](Code& code) -> bool {
        if (code.usesSIMD())
            return false;
        if (Options::airUseGreedyRegAlloc())
            return false;
        unsigned numTmps = code.numTmps(Bank::GP) + code.numTmps(Bank::FP);
        return code.optLevel() == 1 || numTmps > Options::maximumTmpsForGraphColoring();
    };

    if (useLinearScan(code)) {
        // When we're compiling quickly, we do register and stack allocation in one linear scan
        // phase. It's fast because it computes liveness only once.
        allocateRegistersAndStackByLinearScan(code);

        if (Options::logAirRegisterPressure()) {
            dataLog("Register pressure after register allocation:\n");
            logRegisterPressure(code);
        }

        // We may still need to do post-allocation lowering. Doing it after both register and
        // stack allocation is less optimal, but it works fine.
        lowerAfterRegAlloc(code);
    } else {
        // NOTE: B3 -O2 generates code that runs 1.5x-2x faster than code generated by -O1.
        // Most of this performance benefit is from -O2's register allocation
        // and stack allocation pipeline, which you see below.

        // Register allocation for all the Tmps that do not have a corresponding machine
        // register. After this phase, every Tmp has a reg.
        if (Options::airUseGreedyRegAlloc())
            allocateRegistersByGreedy(code);
        else
            allocateRegistersByGraphColoring(code);

        if (Options::logAirRegisterPressure()) {
            dataLog("Register pressure after register allocation:\n");
            logRegisterPressure(code);
        }

        // This replaces uses of spill slots with registers or constants if possible. It
        // does this by minimizing the amount that we perturb the already-chosen register
        // allocation. It may extend the live ranges of registers though.
        fixObviousSpills(code);

        lowerAfterRegAlloc(code);

        // This does first-fit allocation of stack slots using an interference graph plus a
        // bunch of other optimizations.
        allocateStackByGraphColoring(code);
    }

    // This turns all Stack and CallArg Args into Addr args that use the frame pointer.
    lowerStackArgs(code);

    // If we coalesced moves then we can unbreak critical edges. This is the main reason for this
    // phase.
    simplifyCFG(code);

    // This is needed to satisfy a requirement of B3::StackmapValue. This also removes dead
    // code. We can avoid running this when certain optimizations are disabled.
    if (code.optLevel() >= 2 || code.needsUsedRegisters())
        reportUsedRegisters(code);

    // Attempt to remove false dependencies between instructions created by partial register changes.
    // This must be executed as late as possible as it depends on the instructions order and register
    // use. We _must_ run this after reportUsedRegisters(), since that kills variable assignments
    // that seem dead. Luckily, this phase does not change register liveness, so that's OK.
    fixPartialRegisterStalls(code);
    
    // Actually create entrypoints.
    lowerEntrySwitch(code);
    
    // The control flow graph can be simplified further after we have lowered EntrySwitch.
    simplifyCFG(code);

    // We do this optimization at the very end of Air generation pipeline since it can be beneficial after
    // spills are lowered to load/store with the frame pointer or the stack pointer. And this is block-local
    // optimization, so this is more effective after simplifyCFG.
#if CPU(ARM64)
    if (Options::useAirOptimizePairedLoadStore())
        optimizePairedLoadStore(code);
#endif

    // This sorts the basic blocks in Code to achieve an ordering that maximizes the likelihood that a high
    // frequency successor is also the fall-through target.
    optimizeBlockOrder(code);

    if (shouldValidateIR())
        validate(code);

    // Do a final dump of Air. Note that we have to do this even if we are doing per-phase dumping,
    // since the final generation is not a phase.
    if (shouldDumpIR(code.proc(), AirMode)) {
        dataLog("Air after ", code.lastPhaseName(), ", before generation:\n");
        dataLog(code);
    }
}

static void generateWithAlreadyAllocatedRegisters(Code& code, CCallHelpers& jit)
{
    CompilerTimingScope timingScope("Air"_s, "generateWithAlreadyAllocatedRegisters"_s);

#if !CPU(ARM)
    DisallowMacroScratchRegisterUsage disallowScratch(jit);
#endif

    // And now, we generate code.
    GenerationContext context;
    context.code = &code;
    context.blockLabels.resize(code.size());
    for (BasicBlock* block : code)
        context.blockLabels[block] = Box<CCallHelpers::Label>::create();
    IndexMap<BasicBlock*, CCallHelpers::JumpList> blockJumps(code.size());

    auto link = [&] (CCallHelpers::Jump jump, BasicBlock* target) {
        if (context.blockLabels[target]->isSet()) {
            jump.linkTo(*context.blockLabels[target], &jit);
            return;
        }

        blockJumps[target].append(jump);
    };

    PCToOriginMap& pcToOriginMap = code.proc().pcToOriginMap();
    auto addItem = [&] (Inst& inst) {
        if (!code.shouldPreserveB3Origins())
            return;
        if (inst.origin)
            pcToOriginMap.appendItem(jit.labelIgnoringWatchpoints(), inst.origin->origin());
        else
            pcToOriginMap.appendItem(jit.labelIgnoringWatchpoints(), Origin());
    };

    Disassembler* disassembler = code.disassembler();

    for (BasicBlock* block : code) {
        context.currentBlock = block;
        context.indexInBlock = UINT_MAX;
        blockJumps[block].link(&jit);
        CCallHelpers::Label label = jit.label();
        *context.blockLabels[block] = label;

        if (disassembler)
            disassembler->startBlock(block, jit); 

        if (std::optional<unsigned> entrypointIndex = code.entrypointIndex(block)) {
            ASSERT(code.isEntrypoint(block));

            if (disassembler)
                disassembler->startEntrypoint(jit); 

            code.prologueGeneratorForEntrypoint(*entrypointIndex)->run(jit, code);

            if (disassembler)
                disassembler->endEntrypoint(jit); 
        } else
            ASSERT(!code.isEntrypoint(block));
        
        ASSERT(block->size() >= 1);
        for (unsigned i = 0; i < block->size() - 1; ++i) {
            context.indexInBlock = i;
            Inst& inst = block->at(i);
            addItem(inst);
            auto start = jit.labelIgnoringWatchpoints();
            CCallHelpers::Jump jump = inst.generate(jit, context);
            ASSERT_UNUSED(jump, !jump.isSet());
            auto end = jit.labelIgnoringWatchpoints();
            if (disassembler)
                disassembler->addInst(&inst, start, end);
        }

        context.indexInBlock = block->size() - 1;
        
        if (block->last().kind.opcode == Jump
            && block->successorBlock(0) == code.findNextBlock(block))
            continue;

        addItem(block->last());

        if (isReturn(block->last().kind.opcode)) {
            // We currently don't represent the full prologue/epilogue in Air, so we need to
            // have this override.
            auto start = jit.labelIgnoringWatchpoints();
            code.emitEpilogue(jit);
            addItem(block->last());
            auto end = jit.labelIgnoringWatchpoints();
            if (disassembler)
                disassembler->addInst(&block->last(), start, end);
            continue;
        }

        auto start = jit.labelIgnoringWatchpoints();
        CCallHelpers::Jump jump = block->last().generate(jit, context);
        auto end = jit.labelIgnoringWatchpoints();
        if (disassembler)
            disassembler->addInst(&block->last(), start, end);

        // The jump won't be set for patchpoints. It won't be set for Oops because then it won't have
        // any successors.
        if (jump.isSet()) {
            switch (block->numSuccessors()) {
            case 1:
                link(jump, block->successorBlock(0));
                break;
            case 2:
                link(jump, block->successorBlock(0));
                if (block->successorBlock(1) != code.findNextBlock(block))
                    link(jit.jump(), block->successorBlock(1));
                break;
            default:
                RELEASE_ASSERT_NOT_REACHED();
                break;
            }
        }
        addItem(block->last());
    }
    
    context.currentBlock = nullptr;
    context.indexInBlock = UINT_MAX;
    
    Vector<CCallHelpers::Label> entrypointLabels(code.numEntrypoints());
    for (unsigned i = code.numEntrypoints(); i--;)
        entrypointLabels[i] = *context.blockLabels[code.entrypoint(i).block()];
    code.setEntrypointLabels(WTFMove(entrypointLabels));

    pcToOriginMap.appendItem(jit.label(), Origin());
    // FIXME: Make late paths have Origins: https://bugs.webkit.org/show_bug.cgi?id=153689
    if (disassembler)
        disassembler->startLatePath(jit);

    for (auto& latePath : context.latePaths)
        latePath->run(jit, context);

    if (disassembler)
        disassembler->endLatePath(jit);
    pcToOriginMap.appendItem(jit.labelIgnoringWatchpoints(), Origin());
}

void generate(Code& code, CCallHelpers& jit)
{
    if (code.optLevel())
        generateWithAlreadyAllocatedRegisters(code, jit);
    else
        code.m_generateAndAllocateRegisters->generate(jit);
}

} } } // namespace JSC::B3::Air

#endif // ENABLE(B3_JIT)
