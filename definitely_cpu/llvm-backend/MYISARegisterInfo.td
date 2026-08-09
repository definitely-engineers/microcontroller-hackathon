// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 Analog Devices, Inc.
//===-- MYISARegisterInfo.td - MYISA Register defs -------*- tablegen -*-===//
//
// WHAT THIS FILE IS:
//   Declarative description of the MYISA register file. Defines every
//   physical register in the architecture and groups them into register
//   classes that the register allocator uses.
//
// WHY IT MUST EXIST:
//   LLVM's register allocator, instruction selector, and calling convention
//   all need to know what registers exist, how wide they are, and which ones
//   are available for allocation. Without this file, TableGen cannot generate
//   MYISAGenRegisterInfo.inc (register enum, class membership, encoding).
//
// WHAT TABLEGEN GENERATES FROM THIS:
//   MYISAGenRegisterInfo.inc contains:
//     - enum MYISA::R0, MYISA::R1, ..., MYISA::R31
//     - Register class membership arrays (which regs are in GPR, CREG, SP)
//     - HW encoding tables (5-bit register numbers for instruction encoding)
//     - Sub-register relationships (none here — flat register file)
//     - Callee-saved register lists (referenced from MYISACallingConv.td)
//
// WHAT EACH SECTION DOES:
//   1. MYISAReg class: base class defining the register encoding width (5 bits)
//      and namespace. Every physical register is an instance of this.
//   2. Physical register defs (R0–R31): one per architectural register.
//      The HWEncoding field maps to the 5-bit field in Type 1/Type 2 encodings.
//   3. Register classes (GPR, CREG, SP): logical groupings that tell the
//      register allocator which registers it may assign to virtual registers.
//      The allocation order within GPR puts caller-saved regs first (better
//      for reducing callee-save overhead in small functions).
//
// WHAT COULD BE ADDED:
//   - Sub-register definitions if the architecture gains 16-bit or 8-bit
//     sub-registers (e.g., R8_lo, R8_hi for byte access).
//   - Additional register classes for future extensions (e.g., a vector
//     register file, floating-point registers, or an accumulator class).
//   - Register tuples for multi-register operands (e.g., 64-bit pairs).
//   - CostPerUse settings if some registers are more expensive to use
//     (e.g., require extra save/restore in certain calling conventions).
//   - DwarfNumbers if DWARF debug info support is added (maps regs to
//     DWARF register numbers for stack unwinding).
//
//===----------------------------------------------------------------------===//

// Base class for all MYISA registers.
// Parameters:
//   Enc: 5-bit hardware encoding (appears in instruction bit fields)
//   n:   assembly-language name (e.g., "r0", "r8")
// The HWEncoding field is used by TableGen to generate register number
// tables for the MCCodeEmitter (binary encoding) and disassembler.
class MYISAReg<bits<5> Enc, string n> : Register<n> {
  let HWEncoding{4-0} = Enc;
  let Namespace = "MYISA";
}

//===----------------------------------------------------------------------===//
// Physical registers
//
// The MYISA architecture has 32 registers, r0–r31. The first 8 (r0–r7)
// are reserved for special purposes and are NOT available to the register
// allocator. The remaining 24 (r8–r31) are general-purpose.
//
// *** ADAPT FOR YOUR ISA: define one entry per architectural register.     ***
// *** Change the encoding (first arg) to match your register address bits. ***
//===----------------------------------------------------------------------===//

// --- Special-purpose registers (not allocatable) ---
// These registers have fixed hardware roles. The register allocator will
// never assign a virtual register to any of these (they are marked reserved
// in MYISARegisterInfo.cpp::getReservedRegs).

def R0  : MYISAReg< 0, "r0">;   // Hard-wired zero: reads always return 0, writes are discarded
def R1  : MYISAReg< 1, "r1">;   // Reserved: no architecturally defined read value
def R2  : MYISAReg< 2, "r2">;   // Stack pointer: points to top of stack, grows downward
def R3  : MYISAReg< 3, "r3">;   // Link register: CALL saves return address here
def R4  : MYISAReg< 4, "r4">;   // Thread pointer (reserved for OS/runtime use)
def R5  : MYISAReg< 5, "r5">;   // Conditional result: CMP writes comparison result here
def R6  : MYISAReg< 6, "r6">;   // ISR status (reserved for interrupt handling)
def R7  : MYISAReg< 7, "r7">;   // Reserved for future use

// --- General-purpose registers (allocatable) ---
// These are available to the register allocator. By convention:
//   r8–r15:  caller-saved (scratch) — also used for argument passing
//   r16–r31: callee-saved — function must preserve these across calls
//   r30:     used as frame pointer when variable-size stack frames are needed

// caller-saved / argument registers (r8-r15)
def R8  : MYISAReg< 8, "r8">;   // arg 1 + return value
def R9  : MYISAReg< 9, "r9">;   // arg 2
def R10 : MYISAReg<10, "r10">;  // arg 3
def R11 : MYISAReg<11, "r11">;  // arg 4
def R12 : MYISAReg<12, "r12">;  // arg 5
def R13 : MYISAReg<13, "r13">;  // arg 6
def R14 : MYISAReg<14, "r14">;  // arg 7
def R15 : MYISAReg<15, "r15">;  // arg 8

// callee-saved registers (r16-r31)
def R16 : MYISAReg<16, "r16">;
def R17 : MYISAReg<17, "r17">;
def R18 : MYISAReg<18, "r18">;
def R19 : MYISAReg<19, "r19">;
def R20 : MYISAReg<20, "r20">;
def R21 : MYISAReg<21, "r21">;
def R22 : MYISAReg<22, "r22">;
def R23 : MYISAReg<23, "r23">;
def R24 : MYISAReg<24, "r24">;
def R25 : MYISAReg<25, "r25">;
def R26 : MYISAReg<26, "r26">;
def R27 : MYISAReg<27, "r27">;
def R28 : MYISAReg<28, "r28">;
def R29 : MYISAReg<29, "r29">;
def R30 : MYISAReg<30, "r30">;  // frame pointer when one is needed
def R31 : MYISAReg<31, "r31">;

//===----------------------------------------------------------------------===//
// Register classes
//
// A RegisterClass groups registers that can be used interchangeably by the
// register allocator. Each virtual register is assigned to a class, and the
// allocator picks a physical register from that class.
//
// Parameters:
//   1. Namespace ("MYISA")
//   2. Value types the class can hold ([i32] = 32-bit integer)
//   3. Alignment in bits (32)
//   4. Members in allocation-preference order
//
// *** ADAPT FOR YOUR ISA: adjust which registers are allocatable and in    ***
// *** what order (caller-saved first is conventional).                     ***
//===----------------------------------------------------------------------===//

// GPR: General-purpose registers available for allocation (r8-r31).
// Allocation order: caller-saved first (r8-r15), then callee-saved (r16-r31).
// Putting caller-saved first means the allocator prefers them for short-lived
// values, reducing the number of callee-saves in the prologue/epilogue.
def GPR : RegisterClass<"MYISA", [i32], 32,
  // caller-saved first — 分配器优先用前面的，小函数就不必存 callee-saved
  (add R8,  R9,  R10, R11, R12, R13, R14, R15,
       R16, R17, R18, R19, R20, R21, R22, R23,
       R24, R25, R26, R27, R28, R29, R30, R31)>;

// CREG: Condition register class (r5 only).
// Used exclusively by CMP/branch instructions. The CMP instruction always
// writes to r5, and conditional branches (JZ, JNZ, JLT, JGT) read r5.
// This is a single-register class — it exists so LLVM's type system can
// distinguish condition values from general-purpose values.
def CREG : RegisterClass<"MYISA", [i32], 32, (add R5)>;

// SP: Stack pointer class (r2 only).
// Marked non-allocatable — the register allocator must never assign a
// virtual register to the stack pointer. SP is managed exclusively by
// frame lowering (prologue/epilogue) and stack adjustment pseudos.
def SP : RegisterClass<"MYISA", [i32], 32, (add R2)> {
  let isAllocatable = 0;
}

// FP: physical frame-pointer operand class. R30 remains allocatable through
// GPR in functions that do not need a frame pointer; this class is used only
// by codegen-only instructions emitted by frame lowering.
def FP : RegisterClass<"MYISA", [i32], 32, (add R30)> {
  let isAllocatable = 0;
}

// STACKREG: registers that the architectural PUSH/POP instructions may save.
// It includes the link register r3 in addition to the ordinary GPRs. Keeping
// this class non-allocatable prevents it from changing register allocation.
def STACKREG : RegisterClass<"MYISA", [i32], 32,
  (add R3, R8, R9, R10, R11, R12, R13, R14, R15,
       R16, R17, R18, R19, R20, R21, R22, R23,
       R24, R25, R26, R27, R28, R29, R30, R31)> {
  let isAllocatable = 0;
}
