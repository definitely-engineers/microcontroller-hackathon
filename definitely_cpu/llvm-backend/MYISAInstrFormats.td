// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 Analog Devices, Inc.
//===-- MYISAInstrFormats.td - MYISA Instruction Formats --*- tablegen -*-===//
//
// WHAT THIS FILE IS:
//   Defines the binary encoding formats for all MYISA instructions. Every
//   instruction in the ISA is either Type 1 (ALU/computation) or Type 2
//   (memory/control flow), each with a fixed 32-bit width but different
//   field layouts. This file provides base classes that concrete instruction
//   definitions in MYISAInstrInfo.td inherit from.
//
// WHY IT MUST EXIST:
//   LLVM's instruction definitions must include bit-field layouts so that:
//   1. TableGen can generate binary encoding tables for MCCodeEmitter
//      (assembly → object file).
//   2. TableGen can generate decoding tables for the disassembler
//      (object file → assembly).
//   3. The instruction operands are properly bound to bit fields, allowing
//      the register allocator's output to be encoded into machine words.
//   Even if you only emit assembly text (not binary), LLVM requires the
//   Inst field to be defined — it validates encoding consistency.
//
// WHAT EACH SECTION DOES:
//   - Type1Inst: base class for ALU instructions (bit 31 = 1)
//     Encodes: opcode (14 bits), arg1 (6 bits), arg2 (6 bits), result (5 bits)
//   - Type1RRR: subclass for three-operand ALU (reg, reg/imm → reg)
//     Used by: ADD, SUB, OR, AND, XOR, SHL, SHR, SAR, MUL, CMP
//   - Type1RR: subclass for two-operand ALU (reg → reg)
//     Used by: NOT, NEG, ABS, MOV, LUI
//   - Type2Inst: base class for memory/control instructions (bit 31 = 0)
//     Encodes: opcode (9 bits), reg/imm flag (1 bit), reg (5 bits), addr (16 bits)
//   - Type2Mem: subclass for load/store instructions
//   - Type2Branch: subclass for branch/jump instructions
//   - Type2Call: subclass for call instructions
//   - Type2Stack: subclass for push/pop stack operations
//   - Pseudo: instructions that exist only during codegen (never encoded)
//
// WHAT COULD BE ADDED:
//   - Type 3 format for future extensions (e.g., SIMD, long immediates)
//   - Compressed instruction format (16-bit) for code density
//   - Variable-length encoding support (would need changes to Size field)
//   - Multi-word instruction format for very wide immediates (48-bit or 64-bit)
//   - Predicated instruction format (condition field in every instruction)
//   - DecoderMethod fields for non-trivial encoding (e.g., scaled offsets)
//   - TSFlags field for passing encoding metadata to the code emitter
//
// All instructions are 32 bits wide.
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// Type 1 — ALU / Calculation / Data Manipulation
//
// This format is used for all arithmetic, logic, and data movement
// instructions that operate on registers and/or small immediates.
//
// *** ADAPT FOR YOUR ISA: rewrite this section to match your instruction   ***
// *** bit layout.  Change the field widths, positions, and type-detect bit ***
// *** to match your encoding.  The class hierarchy below can be simplified ***
// *** to a single base class if your ISA has a uniform format.             ***
//
// Bit layout (32 bits total):
//   [31]    = 1 (type discriminator — always 1 for Type 1 instructions)
//   [30:17] = opcode (14 bits — identifies the specific ALU operation)
//   [16:11] = arg1 (6 bits: bit[16]=register/immediate flag, bits[15:11]=value)
//   [10:5]  = arg2 (6 bits: bit[10]=register/immediate flag, bits[9:5]=value)
//   [4:0]   = result register (5 bits — destination register number)
//
// The arg flag bits determine interpretation:
//   flag=0: the 5-bit value is a register number (r0–r31)
//   flag=1: the 5-bit value is a literal constant (0–31)
//
// This gives Type 1 instructions three addressing modes:
//   reg, reg → reg   (both args are registers)
//   reg, imm → reg   (arg2 is a 5-bit immediate)
//   imm, reg → reg   (arg1 is a 5-bit immediate — rarely used)
//===----------------------------------------------------------------------===//

// Type1Inst: base class for all Type 1 instructions.
// Parameters:
//   op:      14-bit opcode value (identifies ADD vs SUB vs AND etc.)
//   outs:    output operand list (usually one GPR destination)
//   ins:     input operand list (source registers and/or immediates)
//   asmstr:  assembly string template (e.g., "ADD\t$rd, $rs1, $rs2")
//   pattern: SelectionDAG pattern for automatic instruction selection
class Type1Inst<bits<14> op, dag outs, dag ins, string asmstr,
                list<dag> pattern>
    : Instruction {
  let Namespace = "MYISA";
  let Size = 4;                    // All instructions are 4 bytes (32 bits)

  field bits<32> Inst;             // The full 32-bit encoded instruction word
  field bits<32> SoftFail = 0;     // Bits that may differ in the disassembler (none)

  // Type bit: always 1 for Type 1 (distinguishes from Type 2 at decode time)
  let Inst{31} = 1;

  // Opcode: 14 bits identifying the specific operation
  bits<14> Opcode = op;
  let Inst{30-17} = Opcode;

  // Operand fields — subclasses bind these to DAG operands ($rd, $rs1, etc.)
  bits<6> arg1;                    // Source operand 1 (flag + 5-bit value)
  bits<6> arg2;                    // Source operand 2 (flag + 5-bit value)
  bits<5> result;                  // Destination register number

  let Inst{16-11} = arg1;
  let Inst{10-5}  = arg2;
  let Inst{4-0}   = result;

  // Standard Instruction fields required by LLVM infrastructure
  dag OutOperandList = outs;
  dag InOperandList = ins;
  let AsmString = asmstr;
  let Pattern = pattern;
}

// Type1RRR: Three-operand Type 1 instruction (two sources + one destination).
// Used for binary ALU operations: ADD, SUB, AND, OR, XOR, SHL, SHR, SAR, MUL, CMP.
//
// Operand binding:
//   $rd  → result field (5 bits: destination register)
//   $rs1 → arg1 field (flag=0 for register, value=register number)
//   arg2 must be bound by the concrete instruction (either to $rs2 or $imm)
//
// The flag bit in arg1 is hardcoded to 0 (register source). For instructions
// where arg2 is an immediate, the concrete def sets arg2 = {1, imm}.
class Type1RRR<bits<14> op, string mnemonic, dag outs, dag ins,
               string asmstr, list<dag> pattern>
    : Type1Inst<op, outs, ins, asmstr, pattern> {
  bits<5> rd;                      // Destination register operand
  bits<5> rs1;                     // First source register operand
  let result   = rd;               // Wire $rd to the result bit field
  let arg1{5}  = 0;               // Flag = 0 means "this is a register"
  let arg1{4-0}= rs1;             // Wire $rs1 to the arg1 value bits
}

// Type1RRR above is a complete WORKED EXAMPLE of an instruction format class:
// it inherits the base encoding and binds the DAG operands ($rd, $rs1, ...)
// to specific bit fields. Use it as a model for every other format your ISA
// needs.
//
//===----------------------------------------------------------------------===//
// Type1RR — 两操作数（一元运算）：只用 arg1，arg2 填 0
// 用于：MOV, NOT, NEG, ABS, LUI
//===----------------------------------------------------------------------===//
class Type1RR<bits<14> op, string mnemonic, dag outs, dag ins,
              string asmstr, list<dag> pattern>
    : Type1Inst<op, outs, ins, asmstr, pattern> {
  bits<5> rd;
  bits<5> rs1;
  let result    = rd;
  let arg1{5}   = 0;        // flag = 0：源是寄存器
  let arg1{4-0} = rs1;
  let arg2      = 0;        // 一元运算不用 arg2
}

//===----------------------------------------------------------------------===//
// Type2Inst — 内存 / 控制流指令的基类（bit 31 = 0）
//
//   [31]    = 0            类型位
//   [30:22] = opcode (9)
//   [21]    = ri           reg/imm 标志
//   [20:16] = reg (5)
//   [15:0]  = addr (16)    地址 / 16 位立即数
//===----------------------------------------------------------------------===//
class Type2Inst<bits<9> op, dag outs, dag ins, string asmstr,
                list<dag> pattern> : Instruction {
  let Namespace = "MYISA";
  let Size = 4;
  field bits<32> Inst;
  field bits<32> SoftFail = 0;

  let Inst{31} = 0;                  // 类型位：Type 2
  bits<9> Opcode = op;
  let Inst{30-22} = Opcode;

  bits<1>  ri;
  bits<5>  reg;
  bits<16> addr;
  let Inst{21}    = ri;
  let Inst{20-16} = reg;
  let Inst{15-0}  = addr;

  dag OutOperandList = outs;
  dag InOperandList  = ins;
  let AsmString = asmstr;
  let Pattern   = pattern;
}

//===----------------------------------------------------------------------===//
// Type2LI — 装 16 位立即数进寄存器
// ri = 1 表示 addr 字段装的是字面量而不是地址（和 tools/asm.py 一致）
//===----------------------------------------------------------------------===//
class Type2LI<bits<9> op, dag outs, dag ins, string asmstr,
              list<dag> pattern>
    : Type2Inst<op, outs, ins, asmstr, pattern> {
  bits<5>  rd;
  bits<16> imm;
  let ri   = 1;
  let reg  = rd;
  let addr = imm;
}

//===----------------------------------------------------------------------===//
// Type2Mem — 内存访问：LOAD_reg / STORE_reg
//
// ⚠️ 已知的位预算问题（Stage 3 要正式解决）：
//   register-indirect 寻址需要 rd(5) + rbase(5) + offset(16) = 26 位，
//   加 opcode(9) + 类型位(1) = 36 位 > 32。装不下。
//
//   Stage 1 只需要这两条指令"存在"，让 boilerplate 的 MYISAInstrInfo.cpp
//   （spill/reload）能编译过。它们在 Stage 1 的测试程序里不会被用到。
//
//   因为后端没有 MCCodeEmitter（MCTargetDesc/ 里没有那个文件），LLVM 只产生
//   汇编文本，二进制编码由 tools/isa_config.py 负责。所以这里的位绑定留空
//   （TableGen 允许 Inst 位为未定义 '?'），不影响正确性。
//
//   Stage 3 要定的方案（保持 opcode 位置不变，只重新划分低 22 位）：
//     [31]=0  [30:22]=opcode(9)  [21:17]=rd(5)  [16:12]=rbase(5)  [11:0]=offset(12)
//===----------------------------------------------------------------------===//
class Type2Mem<bits<9> op, dag outs, dag ins, string asmstr,
               list<dag> pattern>
    : Type2Inst<op, outs, ins, asmstr, pattern> {
  let ri = 0;
  // reg / addr 位布局 Stage 3 再定
}

//===----------------------------------------------------------------------===//
// Type2NoArg — 不带操作数的控制流指令（RET）
//===----------------------------------------------------------------------===//
class Type2NoArg<bits<9> op, dag outs, dag ins, string asmstr,
                 list<dag> pattern>
    : Type2Inst<op, outs, ins, asmstr, pattern> {
  let ri   = 0;
  let reg  = 0;
  let addr = 0;
}

// TODO: define the remaining instruction formats for your ISA. Common
//       additional formats are:
//         - a two-operand ALU format (unary ops: NOT/NEG/MOV/...)
//         - a memory-access format (load/store) with an address field
//         - a branch/jump format (set isBranch = 1; isTerminator = 1;)
//         - a call format         (set isCall = 1;)
//         - a stack push/pop format
//       Each is just another `class ... : <base> { let <field> = ...; }`.
//       Add or remove formats to match your own encoding — a very regular ISA
//       might need only one or two.

// Pseudo-instruction — not encoded; exists only during code generation.
// Pseudos are used for operations that need to exist in the MachineInstr
// representation (for the register allocator, scheduler, etc.) but are
// either expanded into real instructions later or represent bookkeeping
// that doesn't appear in the final output (e.g., ADJCALLSTACKDOWN/UP).
//
// Key properties:
//   isPseudo=1: tells the AsmPrinter to skip emission
//   isCodeGenOnly=1: never appears in the assembler or disassembler
//   Inst=0: no binary encoding
class Pseudo<dag outs, dag ins, string asmstr, list<dag> pattern>
    : Instruction {
  let Namespace      = "MYISA";
  let OutOperandList = outs;
  let InOperandList  = ins;
  let AsmString      = asmstr;
  let Pattern        = pattern;
  let isPseudo       = 1;
  let isCodeGenOnly  = 1;
  field bits<32> Inst = 0;         // No encoding for pseudos
  field bits<32> SoftFail = 0;
}
