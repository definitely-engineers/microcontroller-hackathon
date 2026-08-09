# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Analog Devices, Inc.
"""
isa_config.py — ISA configuration for the assembler (edit this file).

This is the single source of truth for your instruction encoding. The generic
assembler engine (`asm.py`) imports the tables and encode_*() functions defined
here and needs no changes as your ISA grows — you only edit this file.

>>> The values below are a complete, working EXAMPLE encoding (a 32-bit, two-
>>> format design) so the toolchain runs out of the box. Replace the opcode
>>> tables, register map, and bit-field layouts with YOUR OWN ISA's design. <<<

Steps to adapt it:
  1. Set INSTR_WIDTH / REG_COUNT / REG_ALIASES to your architecture.
  2. Replace T1_OPS / T2_OPS with your mnemonics and opcode numbers.
  3. Update T1_UNARY / BRANCH_OPS / MEM_OPS to match your instruction groups.
  4. Rewrite TYPE1_LAYOUT / TYPE2_LAYOUT with your exact bit-field positions.
  5. Adjust encode_type1() / encode_type2() (or add more encoders) if your
     instruction formats differ from the two shown here.
"""

# ---------------------------------------------------------------------------
# Global ISA shape  — TODO: set for your architecture
# ---------------------------------------------------------------------------
INSTR_WIDTH = 32
REG_COUNT = 32
REG_ALIASES = {
    "sp": 2,
    "lr": 3,
}

# ---------------------------------------------------------------------------
# Opcode tables  — TODO: replace with your mnemonics + opcode values
# ---------------------------------------------------------------------------

# Type 1 opcodes (example: 14-bit opcode, MSB of the word is always 1)
T1_OPS = {
    "ADD": 0x0000,
    "SUB": 0x0001,
    "OR": 0x0002,
    "LOR": 0x0003,
    "AND": 0x0004,
    "LAND": 0x0005,
    "XOR": 0x0006,
    "NOT": 0x0007,
    "NEG": 0x0008,
    "ABS": 0x0009,
    "SHL": 0x000A,
    "SHR": 0x000B,
    "SAR": 0x000C,
    "CMP": 0x000D,
    "MUL": 0x000E,
    "MOV": 0x000F,
    "LUI": 0x0010,
}

# Type 1 ops that only use arg1 (no arg2)
T1_UNARY = {"NOT", "NEG", "ABS", "MOV", "LUI"}

# Type 2 opcodes (example: 9-bit opcode, MSB of the word is always 0)
T2_OPS = {
    "LOAD": 0x000,
    "STORE": 0x001,
    "LOADB": 0x002,
    "STOREB": 0x003,
    "JMP": 0x004,
    "JZ": 0x005,
    "JNZ": 0x006,
    "JLT": 0x007,
    "JGT": 0x008,
    "CALL": 0x009,
    "RET": 0x00A,
    "PUSH": 0x00B,
    "POP": 0x00C,
    "LI": 0x00D,
}

# Control-flow instructions that use branch/call target handling
BRANCH_OPS = {"JMP", "JZ", "JNZ", "JLT", "JGT", "CALL"}

# Memory instructions that use [addr] / [rN + off] operand handling
MEM_OPS = {"LOAD", "STORE", "LOADB", "STOREB"}


# ---------------------------------------------------------------------------
# Encoding layout  — TODO: all bit positions and widths live here
# ---------------------------------------------------------------------------

TYPE1_LAYOUT = {
    "msb": {"bit": 31, "value": 1},
    "opcode": {"lsb": 17, "width": 14},
    "arg1_imm": {"lsb": 16, "width": 1},
    "arg1_val": {"lsb": 11, "width": 5},
    "arg2_imm": {"lsb": 10, "width": 1},
    "arg2_val": {"lsb": 5, "width": 5},
    "result_reg": {"lsb": 0, "width": 5},
}

TYPE2_LAYOUT = {
    "msb": {"bit": 31, "value": 0},
    "opcode": {"lsb": 22, "width": 9},
    "ri": {"lsb": 21, "width": 1},
    "reg": {"lsb": 16, "width": 5},
    "addr": {"lsb": 0, "width": 16},
}

# Memory instructions reuse the Type 2 low 16-bit payload according to ri:
#   ri = 1: unsigned absolute byte address [15:0]
#   ri = 0: base register [15:11] + signed two's-complement offset [10:0]
MEM_BASE_WIDTH = 5
MEM_OFFSET_WIDTH = 11


def _mask(width: int) -> int:
    return (1 << width) - 1


TYPE1_IMM_MAX = _mask(TYPE1_LAYOUT["arg1_val"]["width"])
TYPE2_ADDR_MASK = _mask(TYPE2_LAYOUT["addr"]["width"])
MEM_BASE_MASK = _mask(MEM_BASE_WIDTH)
MEM_OFFSET_MASK = _mask(MEM_OFFSET_WIDTH)
MEM_OFFSET_MIN = -(1 << (MEM_OFFSET_WIDTH - 1))
MEM_OFFSET_MAX = (1 << (MEM_OFFSET_WIDTH - 1)) - 1


def _encode_with_layout(layout: dict, fields: dict) -> int:
    """Generic encoder from a field layout + field values."""
    instr = 0
    if "msb" in layout:
        instr |= (layout["msb"]["value"] & 1) << layout["msb"]["bit"]

    for name, spec in layout.items():
        if name == "msb":
            continue
        value = fields[name]
        instr |= (value & _mask(spec["width"])) << spec["lsb"]

    # Keep instruction width bounded for safety.
    return instr & _mask(INSTR_WIDTH)


def encode_type1(opcode, arg1_imm, arg1_val, arg2_imm, arg2_val, result_reg):
    return _encode_with_layout(
        TYPE1_LAYOUT,
        {
            "opcode": opcode,
            "arg1_imm": arg1_imm,
            "arg1_val": arg1_val,
            "arg2_imm": arg2_imm,
            "arg2_val": arg2_val,
            "result_reg": result_reg,
        },
    )


def encode_type2(opcode, ri, reg, addr):
    return _encode_with_layout(
        TYPE2_LAYOUT,
        {
            "opcode": opcode,
            "ri": ri,
            "reg": reg,
            "addr": addr,
        },
    )


def encode_memory_type2(opcode, data_reg, *, absolute_addr=None,
                        base_reg=None, offset=0):
    """Encode a Type 2 memory instruction using the ISA's two address modes.

    Exactly one mode must be selected:
      * absolute_addr: ri=1 with an unsigned 16-bit byte address
      * base_reg: ri=0 with a signed 11-bit byte offset
    """
    if not (0 <= opcode <= _mask(TYPE2_LAYOUT["opcode"]["width"])):
        raise ValueError(f"Type 2 opcode out of range: {opcode}")
    if not (0 <= data_reg < REG_COUNT):
        raise ValueError(f"Data register out of range: r{data_reg}")

    if absolute_addr is not None:
        if base_reg is not None:
            raise ValueError(
                "Memory instruction cannot use absolute and base modes together")
        if not (0 <= absolute_addr <= TYPE2_ADDR_MASK):
            raise ValueError(
                f"Absolute memory address {absolute_addr} out of range "
                f"(must be 0-{TYPE2_ADDR_MASK})")
        return encode_type2(opcode, 1, data_reg, absolute_addr)

    if base_reg is None:
        raise ValueError(
            "Register-indirect memory instruction requires a base register")
    if not (0 <= base_reg < REG_COUNT):
        raise ValueError(f"Base register out of range: r{base_reg}")
    if not (MEM_OFFSET_MIN <= offset <= MEM_OFFSET_MAX):
        raise ValueError(
            f"Memory offset {offset} out of range "
            f"(must be {MEM_OFFSET_MIN}..{MEM_OFFSET_MAX})")

    payload = ((base_reg & MEM_BASE_MASK) << MEM_OFFSET_WIDTH)
    payload |= offset & MEM_OFFSET_MASK
    return encode_type2(opcode, 0, data_reg, payload)
