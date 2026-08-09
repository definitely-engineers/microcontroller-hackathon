// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 Analog Devices, Inc.
//===-- MYISAFrameLowering.cpp - MYISA Frame Lowering --------------------===//
//
// WHAT THIS FILE IS:
//   Implements function prologue and epilogue generation for MYISA. This is
//   the code that runs at the very beginning and end of every compiled function
//   to set up and tear down the stack frame.
//
// WHY IT MUST EXIST:
//   C functions need a stack frame for:
//     - Saving the link register (return address) for non-leaf functions
//     - Saving callee-saved registers that the function uses
//     - Allocating space for local variables (arrays, structs, spill slots)
//   Without proper prologue/epilogue, function calls would corrupt registers
//   and return addresses, causing immediate crashes.
//
// WHAT EACH FUNCTION DOES:
//   hasFP():
//     Decides whether a dedicated frame pointer (r30) is needed. Most
//     functions can use SP-relative addressing, but variable-sized alloca()
//     calls require a fixed reference point (FP).
//
//   emitPrologue():
//     Generates the function entry sequence:
//       1. PUSH r3 (save return address — only for non-leaf functions)
//       2. PUSH r16, PUSH r17, ... (save any callee-saved regs used)
//       3. MOV r30, r2 (set up frame pointer — only if hasFP())
//       4. SUB r2, r2, #framesize (allocate local variable space)
//     The SUB must loop in chunks of 31 because the 5-bit immediate can
//     only encode 0–31 per instruction.
//
//   emitEpilogue():
//     Generates the function exit sequence (mirrors prologue in reverse):
//       1. MOV r2, r30 (restore SP from FP) — OR —
//          ADD r2, r2, #framesize (deallocate locals)
//       2. POP r17, POP r16, ... (restore callee-saved regs, reverse order)
//       3. POP r3 (restore return address)
//     After this, the RET instruction transfers control back to the caller.
//
//   eliminateCallFramePseudoInstr():
//     Removes ADJCALLSTACKDOWN/ADJCALLSTACKUP pseudos. These exist to
//     inform the frame lowering about outgoing call argument space, but
//     since we pre-allocate all needed stack space in the prologue, the
//     pseudos are simply erased (no run-time SP adjustment needed around calls).
//
// WHAT COULD BE ADDED:
//   - Dynamic frame size support for alloca() (adjust SP at runtime)
//   - Stack probes / guard pages for stack overflow detection
//   - CFI (Call Frame Information) directives for DWARF debug info
//   - Shrink-wrapping optimization (defer prologue past early-exit branches)
//   - Tail call support (skip epilogue when tail-calling)
//   - Store-multiple / load-multiple instructions for faster save/restore
//   - Red zone optimization (small leaf functions skip SP adjustment)
//   - Split-stack support for goroutine-style lightweight threads
//
//===----------------------------------------------------------------------===//

#include "MYISAFrameLowering.h"
#include "MYISA.h"
#include "MYISAInstrInfo.h"
#include "MYISASubtarget.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"

#include <algorithm>
#include <cstdint>
#include <iterator>

using namespace llvm;

namespace {

constexpr uint64_t StackSlotSize = 4;
constexpr uint64_t MaxStackAdjustImm = 31;

static uint64_t getCalleeSavedFrameSize(const MachineFrameInfo &MFI) {
  return MFI.getCalleeSavedInfo().size() * StackSlotSize;
}

static void emitSPAdjustment(MachineBasicBlock &MBB,
                             MachineBasicBlock::iterator InsertPt,
                             const DebugLoc &DL, const MYISAInstrInfo &TII,
                             uint64_t Amount, bool Allocate,
                             MachineInstr::MIFlag Flag) {
  const unsigned Opcode = Allocate ? MYISA::SUB_sp_ri : MYISA::ADD_sp_ri;
  while (Amount != 0) {
    const uint64_t Chunk = std::min(Amount, MaxStackAdjustImm);
    BuildMI(MBB, InsertPt, DL, TII.get(Opcode), MYISA::R2)
        .addReg(MYISA::R2)
        .addImm(Chunk)
        .setMIFlag(Flag);
    Amount -= Chunk;
  }
}

} // end anonymous namespace

//===----------------------------------------------------------------------===//
// hasFP — Determine if a frame pointer is needed
//
// A frame pointer provides a fixed reference point in the stack frame that
// doesn't change as the SP is adjusted. It's needed when:
//   - The function uses variable-sized objects (alloca / VLAs)
//   - The frame address is taken (__builtin_frame_address)
// For all other functions, SP-relative addressing is sufficient and avoids
// dedicating r30 as the frame pointer (leaving it free for the allocator).
//===----------------------------------------------------------------------===//

bool MYISAFrameLowering::hasFP(const MachineFunction &MF) const {
  const MachineFrameInfo &MFI = MF.getFrameInfo();
  return MFI.hasVarSizedObjects() || MFI.isFrameAddressTaken();
}

bool MYISAFrameLowering::hasReservedCallFrame(const MachineFunction &MF) const {
  return !MF.getFrameInfo().hasVarSizedObjects();
}

//===----------------------------------------------------------------------===//
// emitPrologue — Generate function entry code
//===----------------------------------------------------------------------===//

void MYISAFrameLowering::emitPrologue(MachineFunction &MF,
                                       MachineBasicBlock &MBB) const {
  MachineBasicBlock::iterator MBBI = MBB.begin();
  const MYISASubtarget &STI = MF.getSubtarget<MYISASubtarget>();
  const MYISAInstrInfo &TII = *STI.getInstrInfo();
  MachineFrameInfo &MFI = MF.getFrameInfo();
  DebugLoc DL;

  if (MBBI != MBB.end())
    DL = MBBI->getDebugLoc();

  // PEI inserts callee-saved PUSH instructions before calling this hook.
  // Allocate locals after those pushes so the final SP is the base used by
  // frame-index elimination.
  while (MBBI != MBB.end() && MBBI->getFlag(MachineInstr::FrameSetup) &&
         MBBI->getOpcode() == MYISA::PUSH)
    ++MBBI;

  if (MBBI != MBB.end())
    DL = MBBI->getDebugLoc();

  const uint64_t StackSize = MFI.getStackSize();
  const uint64_t CalleeSavedSize = getCalleeSavedFrameSize(MFI);
  assert(StackSize >= CalleeSavedSize && "invalid MYISA stack frame size");
  const uint64_t LocalSize = StackSize - CalleeSavedSize;

  if (hasFP(MF))
    BuildMI(MBB, MBBI, DL, TII.get(MYISA::MOV_fp_sp), MYISA::R30)
        .addReg(MYISA::R2)
        .setMIFlag(MachineInstr::FrameSetup);

  emitSPAdjustment(MBB, MBBI, DL, TII, LocalSize,
                   /*Allocate=*/true, MachineInstr::FrameSetup);
}

//===----------------------------------------------------------------------===//
// emitEpilogue — Generate function exit code (mirrors prologue in reverse)
//===----------------------------------------------------------------------===//

void MYISAFrameLowering::emitEpilogue(MachineFunction &MF,
                                       MachineBasicBlock &MBB) const {
  MachineBasicBlock::iterator MBBI = MBB.getLastNonDebugInstr();
  const MYISASubtarget &STI = MF.getSubtarget<MYISASubtarget>();
  const MYISAInstrInfo &TII = *STI.getInstrInfo();
  MachineFrameInfo &MFI = MF.getFrameInfo();
  DebugLoc DL;

  if (MBBI != MBB.end())
    DL = MBBI->getDebugLoc();

  // PEI has inserted callee-saved POPs immediately before RET. Release local
  // space before the first POP so each restore reads its matching PUSH slot.
  MachineBasicBlock::iterator RestorePt = MBBI;
  while (RestorePt != MBB.begin()) {
    MachineBasicBlock::iterator Prev = std::prev(RestorePt);
    if (!Prev->getFlag(MachineInstr::FrameDestroy) ||
        Prev->getOpcode() != MYISA::POP)
      break;
    RestorePt = Prev;
  }

  const uint64_t StackSize = MFI.getStackSize();
  const uint64_t CalleeSavedSize = getCalleeSavedFrameSize(MFI);
  assert(StackSize >= CalleeSavedSize && "invalid MYISA stack frame size");
  const uint64_t LocalSize = StackSize - CalleeSavedSize;

  if (hasFP(MF))
    BuildMI(MBB, RestorePt, DL, TII.get(MYISA::MOV_sp_fp), MYISA::R2)
        .addReg(MYISA::R30)
        .setMIFlag(MachineInstr::FrameDestroy);
  else
    emitSPAdjustment(MBB, RestorePt, DL, TII, LocalSize,
                     /*Allocate=*/false, MachineInstr::FrameDestroy);
}

bool MYISAFrameLowering::spillCalleeSavedRegisters(
    MachineBasicBlock &MBB, MachineBasicBlock::iterator MI,
    ArrayRef<CalleeSavedInfo> CSI, const TargetRegisterInfo *) const {
  if (CSI.empty())
    return false;

  DebugLoc DL;
  if (MI != MBB.end())
    DL = MI->getDebugLoc();
  const TargetInstrInfo &TII = *MBB.getParent()->getSubtarget().getInstrInfo();

  for (const CalleeSavedInfo &Info : CSI) {
    Register Reg = Info.getReg();
    MBB.addLiveIn(Reg);
    BuildMI(MBB, MI, DL, TII.get(MYISA::PUSH))
        .addReg(Reg, RegState::Kill)
        .setMIFlag(MachineInstr::FrameSetup);
  }
  return true;
}

bool MYISAFrameLowering::restoreCalleeSavedRegisters(
    MachineBasicBlock &MBB, MachineBasicBlock::iterator MI,
    MutableArrayRef<CalleeSavedInfo> CSI,
    const TargetRegisterInfo *) const {
  if (CSI.empty())
    return false;

  DebugLoc DL;
  if (MI != MBB.end())
    DL = MI->getDebugLoc();
  const TargetInstrInfo &TII = *MBB.getParent()->getSubtarget().getInstrInfo();

  for (const CalleeSavedInfo &Info : llvm::reverse(CSI))
    BuildMI(MBB, MI, DL, TII.get(MYISA::POP), Info.getReg())
        .setMIFlag(MachineInstr::FrameDestroy);
  return true;
}

//===----------------------------------------------------------------------===//
// eliminateCallFramePseudoInstr — Remove ADJCALLSTACKDOWN/UP pseudos
//
// These pseudo-instructions mark where outgoing call arguments are set up
// and torn down. Since MYISA allocates the maximum needed outgoing arg
// space in the prologue (included in FrameSize), no runtime SP adjustment
// is needed around individual calls — just erase the pseudos.
//===----------------------------------------------------------------------===//

MachineBasicBlock::iterator MYISAFrameLowering::eliminateCallFramePseudoInstr(
    MachineFunction &MF, MachineBasicBlock &MBB,
    MachineBasicBlock::iterator MI) const {
  return MBB.erase(MI);
}
