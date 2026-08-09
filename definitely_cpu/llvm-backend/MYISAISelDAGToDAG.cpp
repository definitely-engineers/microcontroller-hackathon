// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 Analog Devices, Inc.
//===-- MYISAISelDAGToDAG.cpp - MYISA DAG->DAG Instruction Selection -----===//
//
// WHAT THIS FILE IS:
//   Implements the instruction selection pass — the transformation from a
//   legalized SelectionDAG (abstract operations on virtual registers) into
//   MachineInstrs (concrete MYISA instructions). This is where abstract DAG
//   nodes like "add" become concrete opcodes like MYISA::ADD_rrr.
//
// WHY IT MUST EXIST:
//   While TableGen patterns (in MYISAInstrInfo.td) handle most instruction
//   selection automatically via SelectCode(), some operations need custom C++
//   logic that cannot be expressed as a TableGen pattern:
//     - Constant materialization (choosing between ADD_rri, LI, or NEG+LI)
//     - CALLSEQ_START/END handling (result type mismatch with TableGen)
//     - Custom node selection (MYISAISD::CALL, CMP, BR_CC)
//     - Complex addressing mode decomposition (SelectAddr)
//     - Peephole optimizations (ADD with negative constant → SUB)
//
// WHAT EACH PART DOES:
//   MYISADAGToDAGISel class:
//     - Inherits from SelectionDAGISel (LLVM's ISel framework)
//     - Includes MYISAGenDAGISel.inc (TableGen-generated pattern matcher)
//     - Overrides Select() to handle custom cases before falling through
//       to SelectCode() for pattern-based matching
//
//   Select() method (the core of this file):
//     Handles these cases before falling through to SelectCode():
//       ISD::Constant — Multi-strategy constant materialization:
//         0–31:      ADD rd, r0, #imm (single instruction, 5-bit immediate)
//         32–65535:  LI rd, #imm (single instruction, 16-bit immediate)
//         -1..-31:   ADD rd, r0, #abs; NEG rd, rd (two instructions)
//         -32..-65535: LI rd, #abs; NEG rd, rd (two instructions)
//         Others:    fall through to ISelLowering (LUI+OR, multi-insn)
//       ISD::ADD — Peephole: add(x, -small_const) → SUB_rri(x, abs)
//       ISD::CALLSEQ_START/END — Manual selection to ADJCALLSTACKDOWN/UP
//       MYISAISD::CALL — Repacks operands for CALL machine instruction
//       MYISAISD::CMP — Selects between CMP_rr and CMP_ri
//       MYISAISD::BR_CC — Maps condition codes to branch opcodes
//
//   SelectAddr() method:
//     Implements the ComplexPattern "addr" from MYISAInstrInfo.td.
//     Decomposes an address expression into (Base, Offset) for memory
//     instructions. Handles three cases:
//       FrameIndex → (FI, 0)
//       reg + const → (reg, const) if const fits in signed 11 bits
//       bare reg → (reg, 0)
//
// WHAT COULD BE ADDED:
//   - Peephole optimizations: combine LOAD+SIGN_EXTEND, fuse CMP+Branch pairs
//   - More aggressive constant materialization for large values (LUI sequences)
//   - Post-ISel peephole pass integration (addPreEmitPass)
//   - Custom lowering for multiply-accumulate if hardware adds MAC instruction
//   - Address mode folding for scaled-offset memory accesses
//   - Predicated instruction selection if hardware adds conditional execution
//   - VLIW scheduling considerations if hardware adds instruction bundles
//
//===----------------------------------------------------------------------===//

#include "MYISA.h"
#include "MYISAISelLowering.h"
#include "MYISASubtarget.h"
#include "MYISATargetMachine.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/SelectionDAGISel.h"
#include "llvm/CodeGen/SelectionDAGNodes.h"
#include "llvm/Support/ErrorHandling.h"

#include <utility>

using namespace llvm;

#define DEBUG_TYPE "myisa-isel"

namespace {

// MYISADAGToDAGISel — The instruction selection pass for MYISA.
// This is a FunctionPass that runs on each function in the module.
// It transforms the SelectionDAG (after legalization) into MachineInstrs
// by calling Select() on each DAG node in bottom-up order.
class MYISADAGToDAGISel : public SelectionDAGISel {
  const MYISASubtarget *Subtarget;

public:
  static char ID;

  MYISADAGToDAGISel(MYISATargetMachine &TM, CodeGenOpt::Level OL)
      : SelectionDAGISel(ID, TM, OL) {}

  // runOnMachineFunction — Called once per function. Caches the subtarget
  // reference, then delegates to the base class which drives Select().
  bool runOnMachineFunction(MachineFunction &MF) override {
    Subtarget = &MF.getSubtarget<MYISASubtarget>();
    return SelectionDAGISel::runOnMachineFunction(MF);
  }

  // Select — Called for each DAG node. Our override handles custom cases;
  // unhandled nodes fall through to SelectCode() (TableGen patterns).
  void Select(SDNode *N) override;

  // SelectAddr — ComplexPattern implementation for memory address decomposition.
  // Called by the TableGen-generated code when matching the "addr" pattern.
  bool SelectAddr(SDValue Addr, SDValue &Base, SDValue &Offset);

  StringRef getPassName() const override {
    return "MYISA DAG->DAG Pattern Instruction Selection";
  }

// Include the TableGen-generated pattern matching code.
// SelectCode() is defined here — it's a giant switch/case that matches
// DAG patterns to MYISA instructions based on MYISAInstrInfo.td patterns.
#include "MYISAGenDAGISel.inc"
};

char MYISADAGToDAGISel::ID = 0;

} // end anonymous namespace

//===----------------------------------------------------------------------===//
// Select — The main instruction selection dispatch
//
// This is called bottom-up for every node in the SelectionDAG. Nodes that
// have already been selected (isMachineOpcode()) are skipped. Custom cases
// are handled by the switch statement; everything else falls through to
// SelectCode() which applies TableGen patterns.
//===----------------------------------------------------------------------===//

void MYISADAGToDAGISel::Select(SDNode *N) {
  // Already selected by a previous pass or TableGen — skip.
  if (N->isMachineOpcode()) {
    N->setNodeId(-1);
    return;
  }

  switch (N->getOpcode()) {
  default:
    break;  // Fall through to SelectCode() for TableGen pattern matching

  case ISD::ADD: {
    // LLVM canonicalises subtraction by a constant into addition of a
    // negative constant in several common cases (including recursion's
    // `value - 1`).  MYISA immediates are unsigned, so select a small
    // negative RHS as the equivalent SUB-immediate instruction.
    SDValue LHS = N->getOperand(0);
    SDValue RHS = N->getOperand(1);
    if (!isa<ConstantSDNode>(RHS) && isa<ConstantSDNode>(LHS))
      std::swap(LHS, RHS);

    if (const auto *CN = dyn_cast<ConstantSDNode>(RHS)) {
      const int64_t Value = CN->getSExtValue();
      if (Value < 0 && Value >= -31) {
        SDLoc DL(N);
        SDValue Magnitude =
            CurDAG->getTargetConstant(-Value, DL, MVT::i32);
        SDValue Ops[] = {LHS, Magnitude};
        ReplaceNode(N, CurDAG->getMachineNode(MYISA::SUB_rri, DL,
                                               MVT::i32, Ops));
        return;
      }
    }
    break;
  }

  case ISD::Constant: {
    // Select constants explicitly.  Leaving non-negative values to the
    // generated matcher can turn a PHI's zero value into an invalid
    // `LI rd, #rd` after register allocation/rematerialisation.  A target
    // constant keeps LI's source operand an immediate all the way to MC.
    const int64_t Value = cast<ConstantSDNode>(N)->getSExtValue();
    SDLoc DL(N);

    if (Value >= 0 && Value <= 65535) {
      SDValue Imm = CurDAG->getTargetConstant(Value, DL, MVT::i32);
      ReplaceNode(N,
                  CurDAG->getMachineNode(MYISA::LI, DL, MVT::i32, Imm));
      return;
    }

    if (Value >= 0)
      report_fatal_error("MYISA cannot materialise this positive constant");

    const int64_t Magnitude = -Value;
    if (Magnitude > 65535)
      report_fatal_error("MYISA cannot materialise this negative constant");

    SDValue Imm = CurDAG->getTargetConstant(Magnitude, DL, MVT::i32);
    SDNode *Positive =
        CurDAG->getMachineNode(MYISA::LI, DL, MVT::i32, Imm);
    SDValue PosValue(Positive, 0);
    ReplaceNode(N, CurDAG->getMachineNode(MYISA::NEG_rr, DL, MVT::i32,
                                           PosValue));
    return;
  }

  case ISD::LOAD: {
    // Select memory operations explicitly instead of relying on the generated
    // ComplexPattern matcher.  A composite memsrc expands to two machine
    // operands (base, offset); keeping that expansion here prevents the load
    // result operand from being confused with either address component.
    auto *LD = cast<LoadSDNode>(N);
    SDLoc DL(N);
    SDValue Base;
    SDValue Offset;
    if (!SelectAddr(LD->getBasePtr(), Base, Offset))
      report_fatal_error("Unable to select MYISA load address");

    unsigned Opcode = MYISA::LOAD_reg;
    if (LD->getMemoryVT() == MVT::i8) {
      if (LD->getExtensionType() != ISD::ZEXTLOAD)
        report_fatal_error("MYISA only supports zero-extending byte loads");
      Opcode = MYISA::LOADB_reg;
    } else if (LD->getMemoryVT() != MVT::i32 ||
               LD->getExtensionType() != ISD::NON_EXTLOAD) {
      report_fatal_error("Unsupported MYISA load type");
    }

    SDValue Ops[] = {Base, Offset, LD->getChain()};
    SDVTList VTs = CurDAG->getVTList(LD->getValueType(0), MVT::Other);
    SDNode *Result = CurDAG->getMachineNode(Opcode, DL, VTs, Ops);
    CurDAG->setNodeMemRefs(cast<MachineSDNode>(Result),
                           {LD->getMemOperand()});
    ReplaceNode(N, Result);
    return;
  }

  case ISD::STORE: {
    // Mirror the explicit load selection above.  Operand order is deliberately
    // value, base, offset, chain, matching STORE_reg/STOREB_reg exactly.
    auto *ST = cast<StoreSDNode>(N);
    SDLoc DL(N);
    SDValue Base;
    SDValue Offset;
    if (!SelectAddr(ST->getBasePtr(), Base, Offset))
      report_fatal_error("Unable to select MYISA store address");

    unsigned Opcode;
    if (ST->getMemoryVT() == MVT::i8)
      Opcode = MYISA::STOREB_reg;
    else if (ST->getMemoryVT() == MVT::i32)
      Opcode = MYISA::STORE_reg;
    else
      report_fatal_error("Unsupported MYISA store type");

    SDValue Ops[] = {ST->getValue(), Base, Offset, ST->getChain()};
    SDNode *Result =
        CurDAG->getMachineNode(Opcode, DL, MVT::Other, Ops);
    CurDAG->setNodeMemRefs(cast<MachineSDNode>(Result),
                           {ST->getMemOperand()});
    ReplaceNode(N, Result);
    return;
  }

  case ISD::CALLSEQ_START:
  case ISD::CALLSEQ_END: {
    SDLoc DL(N);
    const bool IsStart = N->getOpcode() == ISD::CALLSEQ_START;
    const unsigned Opcode = IsStart ? MYISA::ADJCALLSTACKDOWN
                                    : MYISA::ADJCALLSTACKUP;

    // Generic call-sequence nodes place the chain first.  Machine pseudos
    // instead expect their two explicit size operands first, followed by the
    // chain and (for CALLSEQ_END) optional glue.
    SmallVector<SDValue, 5> Ops;
    for (unsigned I = 1; I < 3; ++I) {
      const auto *Amount = cast<ConstantSDNode>(N->getOperand(I));
      Ops.push_back(CurDAG->getTargetConstant(Amount->getZExtValue(), DL,
                                              MVT::i32));
    }
    Ops.push_back(N->getOperand(0));
    if (!IsStart && N->getNumOperands() > 3)
      Ops.push_back(N->getOperand(3));

    SDVTList VTs = CurDAG->getVTList(MVT::Other, MVT::Glue);
    ReplaceNode(N, CurDAG->getMachineNode(Opcode, DL, VTs, Ops));
    return;
  }

  case MYISAISD::CALL: {
    SDLoc DL(N);
    SDValue Chain = N->getOperand(0);
    SmallVector<SDValue, 12> Ops;
    SDValue Glue;

    // The fixed machine operand is the target.  Register arguments and the
    // register mask follow as variadic operands; chain and glue must be last.
    Ops.push_back(N->getOperand(1));
    for (unsigned I = 2; I < N->getNumOperands(); ++I) {
      SDValue Op = N->getOperand(I);
      if (Op.getValueType() == MVT::Glue)
        Glue = Op;
      else
        Ops.push_back(Op);
    }
    Ops.push_back(Chain);
    if (Glue)
      Ops.push_back(Glue);

    SDVTList VTs = CurDAG->getVTList(MVT::Other, MVT::Glue);
    ReplaceNode(N, CurDAG->getMachineNode(MYISA::CALL, DL, VTs, Ops));
    return;
  }

  case MYISAISD::CMP: {
    SDLoc DL(N);
    SDValue Chain = N->getOperand(0);
    SDValue LHS = N->getOperand(1);
    SDValue RHS = N->getOperand(2);
    unsigned Opcode = MYISA::CMP_rr;

    if (const auto *CN = dyn_cast<ConstantSDNode>(RHS)) {
      uint64_t Imm = CN->getZExtValue();
      if (Imm <= 31) {
        Opcode = MYISA::CMP_ri;
        RHS = CurDAG->getTargetConstant(Imm, DL, MVT::i32);
      }
    }

    SDVTList VTs = CurDAG->getVTList(MVT::Other, MVT::Glue);
    SDValue Ops[] = {LHS, RHS, Chain};
    ReplaceNode(N, CurDAG->getMachineNode(Opcode, DL, VTs, Ops));
    return;
  }

  case MYISAISD::BR_CC: {
    SDLoc DL(N);
    SDValue Chain = N->getOperand(0);
    ISD::CondCode CC = cast<CondCodeSDNode>(N->getOperand(1))->get();
    SDValue Target = N->getOperand(2);
    SDValue Glue = N->getOperand(3);

    auto EmitBranch = [&](unsigned Opcode, SDValue InputChain,
                          SDValue InputGlue) -> SDNode * {
      SmallVector<SDValue, 3> Ops{Target, InputChain};
      if (InputGlue)
        Ops.push_back(InputGlue);
      return CurDAG->getMachineNode(Opcode, DL, MVT::Other, Ops);
    };

    unsigned PrimaryOpcode;
    bool AlsoEqual = false;
    switch (CC) {
    case ISD::SETEQ: PrimaryOpcode = MYISA::JZ; break;
    case ISD::SETNE: PrimaryOpcode = MYISA::JNZ; break;
    case ISD::SETLT: PrimaryOpcode = MYISA::JLT; break;
    case ISD::SETGT: PrimaryOpcode = MYISA::JGT; break;
    case ISD::SETLE: PrimaryOpcode = MYISA::JLT; AlsoEqual = true; break;
    case ISD::SETGE: PrimaryOpcode = MYISA::JGT; AlsoEqual = true; break;
    default:
      report_fatal_error("Unexpected MYISA conditional branch code");
    }

    SDNode *Primary = EmitBranch(PrimaryOpcode, Chain, Glue);
    if (!AlsoEqual) {
      ReplaceNode(N, Primary);
      return;
    }

    // a <= b  => JLT target; JZ target
    // a >= b  => JGT target; JZ target
    SDNode *Equal = EmitBranch(MYISA::JZ, SDValue(Primary, 0), SDValue());
    ReplaceNode(N, Equal);
    return;
  }

  // TODO: handle the DAG nodes that need custom C++ selection (i.e. anything
  //       that cannot be expressed as a simple TableGen pattern in the .td).
  //       For each case, build the machine instruction(s) with
  //       CurDAG->getMachineNode(...) and finish with ReplaceNode(N, ...);
  //       then `return;`. Cases you typically need to implement:
  //
  //         case ISD::Constant:   materialise an integer constant using the
  //             cheapest sequence your ISA can encode (small immediate, load-
  //             immediate, load-upper + or, negate, ...).
  //         case ISD::CALLSEQ_START / ISD::CALLSEQ_END:  emit your
  //             ADJCALLSTACKDOWN / ADJCALLSTACKUP pseudos (these usually must
  //             be selected by hand because of their {chain, glue} result).
  //         case <YourISD>::CALL:  repack the call operands into machine form.
  //         case <YourISD>::CMP:   pick the register vs. immediate compare.
  //         case <YourISD>::BR_CC: map the LLVM condition code onto your
  //             conditional-branch opcodes (JZ/JNZ/JLT/JGT or equivalents).
  //
  //       You may also add peephole cases (e.g. rewrite ADD(x, -k) into a
  //       SUB) here. The Stage 2–3 tutorials walk through each case above.
  }

  // No custom match — try TableGen-generated patterns (SelectCode).
  // This handles all the simple cases: ADD_rrr, SUB_rrr, LOAD_reg, etc.
  SelectCode(N);
}

//===----------------------------------------------------------------------===//
// SelectAddr — Complex pattern implementation for memory addressing
//
// This function is called by the TableGen-generated ISel code whenever a
// memory instruction uses the "addr" ComplexPattern. It decomposes an address
// DAG node into a (Base, Offset) pair suitable for the LOAD_reg/STORE_reg
// instruction format: LOAD rd, [Base + Offset].
//
// Cases handled:
//   1. FrameIndex → (FI, 0) — stack-allocated variables
//   2. reg + const → (reg, const) — if constant fits in signed 11 bits
//   3. bare reg → (reg, 0) — pointer dereference with no offset
//===----------------------------------------------------------------------===//

bool MYISADAGToDAGISel::SelectAddr(SDValue Addr, SDValue &Base,
                                    SDValue &Offset) {
  // Case 1: Frame index (stack variable access)
  // Convert to TargetFrameIndex which will be replaced with SP+offset
  // during frame index elimination (MYISARegisterInfo::eliminateFrameIndex).
  if (FrameIndexSDNode *FIN = dyn_cast<FrameIndexSDNode>(Addr)) {
    Base = CurDAG->getTargetFrameIndex(FIN->getIndex(), MVT::i32);
    Offset = CurDAG->getTargetConstant(0, SDLoc(Addr), MVT::i32);
    return true;
  }

  // Case 2: fold base + constant when the byte offset fits the signed 11-bit
  // memory field. A constant may appear on either side of the commutative ADD.
  if (Addr.getOpcode() == ISD::ADD) {
    SDValue BaseOp = Addr.getOperand(0);
    SDValue OffsetOp = Addr.getOperand(1);

    if (isa<ConstantSDNode>(BaseOp) && !isa<ConstantSDNode>(OffsetOp))
      std::swap(BaseOp, OffsetOp);

    if (const ConstantSDNode *CN = dyn_cast<ConstantSDNode>(OffsetOp)) {
      int64_t OffsetValue = CN->getSExtValue();
      if (OffsetValue >= -1024 && OffsetValue <= 1023) {
        if (FrameIndexSDNode *FIN = dyn_cast<FrameIndexSDNode>(BaseOp))
          Base = CurDAG->getTargetFrameIndex(FIN->getIndex(), MVT::i32);
        else
          Base = BaseOp;
        Offset = CurDAG->getTargetConstant(OffsetValue, SDLoc(Addr), MVT::i32);
        return true;
      }
    }
  }

  // Fallback: materialise complex or out-of-range address arithmetic into a
  // register, then use that register with a zero memory offset.
  Base = Addr;
  Offset = CurDAG->getTargetConstant(0, SDLoc(Addr), MVT::i32);
  return true;
}

//===----------------------------------------------------------------------===//
// Factory function — Creates and returns the ISel pass instance.
// Called by MYISAPassConfig::addInstSelector() in MYISATargetMachine.cpp.
//===----------------------------------------------------------------------===//

FunctionPass *llvm::createMYISAISelDag(MYISATargetMachine &TM) {
  return new MYISADAGToDAGISel(TM, CodeGenOpt::Default);
}
