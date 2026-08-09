# Definitely Engineers — Baseline ISA Specification

**Project:** 2026 Microcontroller Hackathon  
**ISA name:** MYISA / Definitely CPU Baseline  
**Version:** v0.3
**Status:** Baseline architecture and memory addressing encoding locked for implementation

> This baseline intentionally adopts the supplied MYISA worked-example ISA wherever possible to reduce LLVM/toolchain integration risk. Team-specific choices are limited mainly to memory organization and memory sizes. Any later ISA change must update this document first, then the RTL, assembler, LLVM backend, tests, and configuration together.

---

## 1. Core Architecture Parameters

| Parameter | Value | Status |
|---|---:|---|
| `DATA_WIDTH` | 32 bits | Team decision |
| `INSTR_WIDTH` | 32 bits, fixed width | Team decision / matches template |
| `REG_COUNT` | 32 | Team decision / matches template |
| `REG_ADDR_W` | 5 bits | Derived from 32 registers |
| `ADDR_WIDTH` | 16 bits | Team decision / matches template assumptions |
| `IMEM_DEPTH` | 8192 words | Team decision |
| `DMEM_DEPTH` | 32768 bytes | Team decision |
| Memory architecture | Harvard | Team decision |
| IMEM addressing | Word-addressed | Baseline decision |
| DMEM addressing | Byte-addressed | Baseline decision |
| `PC_INIT` | `0x0000` | Baseline decision |
| `SP_INIT` | `0x00007C00` | Adopt provided startup convention |
| Endianness | Little-endian | Adopt provided LLVM example |
| Pointer width | 32 bits | Adopt provided LLVM example |
| Stack alignment | 4 bytes | Adopt provided template |
| Stack direction | Grows downward | Adopt provided template |

### Implementation constants

```verilog
`define DATA_WIDTH   32
`define ADDR_WIDTH   16
`define INSTR_WIDTH  32
`define REG_COUNT    32
`define REG_ADDR_W   5
`define IMEM_DEPTH   8192
`define DMEM_DEPTH   32768
`define PC_INIT      16'h0000
```

Recommended project-level stack constant:

```verilog
`define SP_INIT      32'h00007C00
```

`0x7C00` is kept to match the provided `compile.py` startup stub, which initializes `r2` to decimal `31744`.

---

## 2. Memory Model

### 2.1 Harvard architecture

Instruction memory and data memory are physically/logically separate.

```text
                 CPU
              /       \
           IMEM       DMEM
       instructions    data
```

The baseline CPU may fetch an instruction and access data memory independently.

### 2.2 Instruction Memory — IMEM

- Addressing: **word-addressed**
- One IMEM address selects one complete 32-bit instruction.
- `PC` therefore advances by **1** for normal sequential execution.
- Valid implemented IMEM indices: `0` through `8191`.
- Capacity: `8192 × 32 bits = 32768 bytes` of instruction storage.
- Reset fetch address: `PC = 0x0000`.

Normal flow:

```text
PC = 0
PC = 1
PC = 2
...
```

### 2.3 Data Memory — DMEM

- Addressing: **byte-addressed**
- Size: **32768 bytes**
- Implemented byte address range: `0x0000` through `0x7FFF`.
- 32-bit word operations use 4 bytes.
- Baseline 32-bit data and stack accesses are 4-byte aligned.
- `LOADB` / `STOREB` support individual byte access.
- 32-bit data is little-endian.

### 2.4 Stack

- Stack pointer: `r2`
- Initial stack pointer: `0x00007C00`
- Stack grows toward lower addresses.
- Stack alignment: 4 bytes.
- `PUSH` decreases SP before storing.
- `POP` loads from the current stack location and then increases SP.
- 32-bit push/pop changes SP by 4 bytes.
- `r30` is used as a frame pointer when a frame pointer is required.

---

## 3. Register Map

The baseline adopts the provided MYISA worked-example register map.

| Register | Role | Allocation status |
|---|---|---|
| `r0` | Hard-wired zero | Reserved |
| `r1` | Reserved for future architectural use | Reserved |
| `r2` | Stack Pointer (SP) | Reserved |
| `r3` | Link Register (LR) | Reserved |
| `r4` | Thread pointer / reserved runtime register | Reserved |
| `r5` | Condition result register | Reserved |
| `r6` | ISR status / reserved | Reserved |
| `r7` | Reserved for future use | Reserved |
| `r8–r15` | Caller-saved GPRs; argument passing | Allocatable |
| `r16–r31` | Callee-saved GPRs | Allocatable |
| `r30` | Frame pointer when required | Callee-saved / special use |

### Required hardware behaviour

- `r0` always reads as `0`.
- Writes to `r0` are discarded.
- `r1` has no architecturally defined read value in the baseline implementation.
  Software must not use it as a general-purpose register or rely on it containing
  the current PC. The processor maintains the instruction PC as separate internal
  state.
- `r2` tracks the active stack pointer.
- `r3` stores the return address written by `CALL`.
- `r5` stores the result used by conditional branches.

---

## 4. Calling Convention / ABI

The baseline adopts the provided MYISA calling-convention design.

### Arguments

```text
arg1 -> r8
arg2 -> r9
arg3 -> r10
arg4 -> r11
arg5 -> r12
arg6 -> r13
arg7 -> r14
arg8 -> r15
additional arguments -> stack
```

Stack arguments are 4-byte sized/aligned for `i32`.

### Return value

```text
32-bit integer return value -> r8
```

### Register preservation

```text
Caller-saved: r8-r15
Callee-saved: r16-r31
```

If a callee uses a callee-saved register, it must preserve and restore it.

### Function calls

Baseline behaviour:

```text
CALL target:
    r3 (LR) <- address of instruction after CALL
    PC      <- target

RET:
    PC      <- r3
```

Non-leaf functions must preserve LR when necessary.

---

## 5. LLVM Data Model

Use the provided LLVM example layout:

```text
e-p:32:32-i32:32-n32-S32
```

Meaning:

- `e` — little-endian
- `p:32:32` — 32-bit pointers, 32-bit aligned
- `i32:32` — 32-bit integers, 32-bit aligned
- `n32` — native integer width is 32 bits
- `S32` — stack alignment is 32 bits / 4 bytes

The physical memory address bus remains 16 bits even though LLVM pointers are 32 bits.

---

## 6. Instruction Encoding

All instructions are fixed-width **32-bit** words.

The baseline directly adopts the supplied two-format MYISA example encoding.

### 6.1 Type 1 — ALU / Calculation / Data Manipulation

```text
31 30                     17 16 15          11 10 9            5 4          0
+--+------------------------+--+--------------+--+---------------+------------+
|1 |      opcode [14]       |I1| arg1 [5]     |I2| arg2 [5]      | dest [5]   |
+--+------------------------+--+--------------+--+---------------+------------+
```

| Bits | Width | Field |
|---|---:|---|
| `[31]` | 1 | Type discriminator = `1` |
| `[30:17]` | 14 | Opcode |
| `[16]` | 1 | `arg1_is_imm` |
| `[15:11]` | 5 | `arg1` register ID or literal |
| `[10]` | 1 | `arg2_is_imm` |
| `[9:5]` | 5 | `arg2` register ID or literal |
| `[4:0]` | 5 | Destination register |

Immediate flag:

```text
0 -> corresponding 5-bit field is a register number
1 -> corresponding 5-bit field is an unsigned literal 0..31
```

### 6.2 Type 2 — Memory / Control / Large Immediate

```text
31 30                22 21 20           16 15                         0
+--+-------------------+--+---------------+-----------------------------+
|0 |    opcode [9]     |RI| register [5]  | address / immediate [16]    |
+--+-------------------+--+---------------+-----------------------------+
```

| Bits | Width | Field |
|---|---:|---|
| `[31]` | 1 | Type discriminator = `0` |
| `[30:22]` | 9 | Opcode |
| `[21]` | 1 | `ri` mode flag |
| `[20:16]` | 5 | Register |
| `[15:0]` | 16 | Mode-dependent address / immediate payload |

`ri` interpretation:

- `LI`: `ri = 1`; lower 16 bits are the immediate.
- Branch/call: `ri = 0` for PC-relative target; `ri = 1` for absolute target.
- Memory access: `ri = 0` for register-indirect/base+offset form; `ri = 1` for absolute address form.

For memory instructions, `[20:16]` is the data register: the destination for
`LOAD`/`LOADB`, or the source for `STORE`/`STOREB`.

Memory instructions reinterpret the low 16-bit payload as follows.

`ri = 1` — unsigned absolute byte address:

```text
31 30                22 21 20           16 15                         0
+--+-------------------+--+---------------+-----------------------------+
|0 |    opcode [9]     |1 | data reg [5]  | absolute address [16]       |
+--+-------------------+--+---------------+-----------------------------+
```

`ri = 0` — base register plus signed byte offset:

```text
31 30                22 21 20           16 15       11 10              0
+--+-------------------+--+---------------+-----------+------------------+
|0 |    opcode [9]     |0 | data reg [5]  | base [5]  | signed off [11]  |
+--+-------------------+--+---------------+-----------+------------------+
```

The signed 11-bit offset uses two's-complement representation and has the
inclusive range `-1024..+1023`. It is a byte offset and is not implicitly
scaled by the access size.

---

## 7. Immediate Strategy

Baseline strategy: **both inline immediates and dedicated load-immediate instructions**.

### Type 1 small immediate

- Width: 5 bits
- Range: `0..31`

Example:

```asm
ADD r10, r8, #5
```

### Type 2 large immediate

`LI` provides a 16-bit unsigned immediate.

- Width: 16 bits
- Range: `0..65535`
- Zero-extended into the 32-bit destination register.

Example:

```asm
LI r8, #1000
```

`LUI` is retained from the provided Type 1 opcode set for constructing larger 32-bit constants.

---

## 8. Opcode Assignments

The baseline directly adopts the opcode assignments in the provided `isa_config.py`.

### Type 1 opcodes

| Instruction | Opcode |
|---|---:|
| `ADD` | `0x0000` |
| `SUB` | `0x0001` |
| `OR` | `0x0002` |
| `LOR` | `0x0003` |
| `AND` | `0x0004` |
| `LAND` | `0x0005` |
| `XOR` | `0x0006` |
| `NOT` | `0x0007` |
| `NEG` | `0x0008` |
| `ABS` | `0x0009` |
| `SHL` | `0x000A` |
| `SHR` | `0x000B` |
| `SAR` | `0x000C` |
| `CMP` | `0x000D` |
| `MUL` | `0x000E` |
| `MOV` | `0x000F` |
| `LUI` | `0x0010` |

Unary group:

```text
NOT, NEG, ABS, MOV, LUI
```

### Type 2 opcodes

| Instruction | Opcode |
|---|---:|
| `LOAD` | `0x000` |
| `STORE` | `0x001` |
| `LOADB` | `0x002` |
| `STOREB` | `0x003` |
| `JMP` | `0x004` |
| `JZ` | `0x005` |
| `JNZ` | `0x006` |
| `JLT` | `0x007` |
| `JGT` | `0x008` |
| `CALL` | `0x009` |
| `RET` | `0x00A` |
| `PUSH` | `0x00B` |
| `POP` | `0x00C` |
| `LI` | `0x00D` |

---

## 9. Pseudo-Instructions

### `NOP`

```asm
NOP
```

Assembler encoding:

```asm
ADD r0, r0, r0
```

### `HALT`

```asm
HALT
```

Assembler encoding:

```asm
JMP 0
```

This is a PC-relative self-jump. The provided startup stub emits `HALT` after the entry function returns.

---

## 10. Control Flow Semantics

### Normal sequential execution

Because IMEM is word-addressed:

```text
next_pc = pc + 1
```

### PC-relative branch

The supplied assembler computes:

```text
offset = target_instruction_index - current_pc
```

Hardware convention:

```text
branch_target = current_pc + sign_extend(offset16)
```

An offset of `0` therefore targets the current instruction.

### Absolute branch

For branch/call with `ri = 1`:

```text
target = unsigned 16-bit absolute instruction address
```

### Conditional branches

`CMP` writes its comparison result to `r5`.

Conditional branch family:

```text
JZ
JNZ
JLT
JGT
```

Baseline comparison syntax and result encoding:

```asm
CMP r5, left, right
```

- `r5` is mandatory as the first operand; the assembler rejects any other
  destination register.
- Signed `left < right` writes `0xFFFFFFFF` (`-1`) to `r5`.
- `left == right` writes `0` to `r5`.
- Signed `left > right` writes `1` to `r5`.
- `JZ`, `JNZ`, `JLT`, and `JGT` always read `r5`.

The exact internal comparison-result encoding in `r5` must remain consistent between the RTL and compiler/backend implementation.

---

## 11. Memory Instruction Addressing

### Register-indirect / base + offset

`ri = 0`

Examples:

```asm
LOAD  r8, [r16]
LOAD  r8, [r30 + 4]
STORE r9, [sp + 8]
```

Effective address:

```text
DMEM byte address = base register + sign_extend(signed offset11)
```

Register-indirect encoding:

```text
[31]      type = 0
[30:22]   opcode9
[21]      ri = 0
[20:16]   load destination or store source register
[15:11]   base register
[10:0]    signed byte offset11, two's complement
```

The offset range is `-1024..+1023`. Values outside this range must be rejected
by the assembler or materialized as a separate address calculation by the
compiler; they must not be silently truncated.

### Absolute address

`ri = 1`

Examples:

```asm
LOAD  r8, [0x0100]
STORE r9, [0x0200]
```

Absolute encoding:

```text
[31]      type = 0
[30:22]   opcode9
[21]      ri = 1
[20:16]   load destination or store source register
[15:0]    unsigned absolute byte address16
```

The encoding permits `0x0000..0xFFFF`; the implemented DMEM currently occupies
`0x0000..0x7FFF`, so software must still use an implemented physical address.

Reference machine-code examples:

```text
LOAD  r8, [r30 + 4] -> 0x0008F004
LOAD  r8, [0x1234]  -> 0x00281234
STORE r9, [sp - 4]  -> 0x004917FC
```

### Access sizes

```text
LOAD / STORE   -> 32-bit word
LOADB / STOREB -> 8-bit byte
```

`LOADB` zero-extends the selected byte to 32 bits. `STOREB` writes the low
8 bits of the source register and leaves the other bytes unchanged.

---

## 12. Implementation Stages

### Stage 1 — Data Operations

First implementation target:

```text
ADD
SUB
MOV
LI
```

Primary end-to-end test:

```c
int add(int a, int b) {
    return a + b;
}
```

With startup arguments `[21, 21]`:

```text
r8 = 42
```

### Stage 2 — Control Flow

```text
CMP
JMP
JZ
JNZ
JLT
JGT
```

### Stage 3 — Functions / Memory / Stack

```text
LOAD
STORE
LOADB
STOREB
CALL
RET
PUSH
POP
```

Plus calling convention, callee-save handling, stack frames, and recursion.

---

## 13. Source-of-Truth Rule

All of the following must agree with this file:

```text
isa-spec.md
        |
        +--> definitely_cpu/rtl/include/config.vh
        +--> definitely_cpu/rtl/include/opcodes.vh
        +--> definitely_cpu/rtl/decoder.v
        +--> definitely_cpu/rtl/regfile.v
        +--> definitely_cpu/rtl/alu.v
        +--> definitely_cpu/rtl/imem.v
        +--> definitely_cpu/rtl/dmem.v
        |
        +--> definitely_cpu/tools/isa_config.py
        +--> definitely_cpu/tools/asm.py
        |
        +--> definitely_cpu/llvm-backend/MYISARegisterInfo.td
        +--> definitely_cpu/llvm-backend/MYISAInstrFormats.td
        +--> definitely_cpu/llvm-backend/MYISAInstrInfo.td
        +--> definitely_cpu/llvm-backend/MYISACallingConv.td
        +--> definitely_cpu/llvm-backend/MYISAFrameLowering.*
        +--> definitely_cpu/llvm-backend/MYISATargetMachine.cpp
        |
        +--> definitely_cpu/tests/
        
```

For any later ISA change:

1. Update this spec.
2. Update RTL.
3. Update assembler.
4. Update LLVM backend.
5. Update tests.
6. Re-run end-to-end simulation before merge.

---

## 14. Baseline Design Rationale

- 32-bit datapath and 32-bit fixed instructions match the supplied template and reduce integration risk.
- 32 registers preserve the supplied 5-bit register encoding and register/backend structure.
- 16-bit absolute physical addresses fit directly in the Type 2 format; the
  base-relative memory form reuses those bits as base5 + signed offset11.
- Harvard memory simplifies the intended single-cycle baseline CPU.
- Word-addressed IMEM gives simple `PC + 1` sequential execution.
- Byte-addressed DMEM is compatible with normal C byte access.
- The supplied register map, calling convention, instruction formats, opcodes, stack model, assembler conventions, and LLVM data layout are adopted instead of redesigned.
- The baseline goal is end-to-end correctness first; optimisation/novelty can be introduced later as measured variants.

---

## 15. Provided Files Adopted by This Baseline

```text
resources/software/template/tools/isa_config.py
resources/software/template/tools/asm.py
resources/software/template/llvm-backend/MYISARegisterInfo.td
resources/software/template/llvm-backend/MYISAInstrFormats.td
resources/software/template/llvm-backend/MYISAInstrInfo.td
resources/software/template/llvm-backend/MYISACallingConv.td
resources/software/template/llvm-backend/MYISAFrameLowering.h
resources/software/template/llvm-backend/MYISATargetMachine.cpp
resources/software/scripts/compile.py
docs/tutorial-workbook.pdf
```

The supplied files contain worked examples and TODOs. This specification records the team's decision to adopt those example conventions as the baseline unless explicitly overridden above.

---

## 16. Revision History

| Version | Date | Change |
|---|---|---|
| `v0.1` | 2026-08-08 | Initial team baseline. |
| `v0.2` | 2026-08-09 | Locked memory `ri=0` as base5 + signed offset11 while retaining `ri=1` absolute address16 and the existing Type 2 header. |
| `v0.3` | 2026-08-09 | Defined `LOADB` zero-extension and `STOREB` low-byte semantics for the data-memory implementation. |
