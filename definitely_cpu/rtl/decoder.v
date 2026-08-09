`include "config.vh"
`include "opcodes.vh"

module decoder (
    input  wire [`INSTR_WIDTH-1:0] instr,
    output wire                    is_type1,
    output wire [`T1_OPCODE_W-1:0] t1_opcode,
    output wire                    arg1_is_imm,
    output wire [`REG_ADDR_W-1:0] arg1,
    output wire                    arg2_is_imm,
    output wire [`REG_ADDR_W-1:0] arg2,
    output wire [`REG_ADDR_W-1:0] dest,
    output wire                    is_add,
    output wire                    is_cmp,
    output wire                    is_li,
    output wire                    is_jmp,
    output wire                    jump_is_absolute,
    output wire                    is_jz,
    output wire                    is_jnz,
    output wire                    is_jlt,
    output wire                    is_jgt,
    output wire                    branch_is_absolute,
    output wire                    is_call,
    output wire                    call_is_absolute,
    output wire                    is_ret,
    output wire                    is_halt,
    output wire                    is_load,
    output wire                    is_store,
    output wire                    is_loadb,
    output wire                    is_storeb,
    output wire                    memory_is_absolute,
    output wire [`REG_ADDR_W-1:0] memory_reg,
    output wire [`REG_ADDR_W-1:0] memory_base,
    output wire [10:0]             memory_offset11,
    output wire [15:0]             immediate16,
    output wire                    reg_write_en
);
    wire [`T2_OPCODE_W-1:0] t2_opcode = instr[30:22];
    wire                     t2_ri     = instr[21];
    wire [`REG_ADDR_W-1:0]   t2_reg    = instr[20:16];
    wire                     is_sub;
    wire                     is_mov;

    assign is_type1   = instr[31];
    assign t1_opcode  = instr[30:17];
    assign arg1_is_imm = instr[16];
    assign arg1       = instr[15:11];
    assign arg2_is_imm = instr[10];
    assign arg2       = instr[9:5];
    assign immediate16 = instr[15:0];

    assign is_add  = is_type1 && (t1_opcode == `OP_ADD);
    assign is_sub  = is_type1 && (t1_opcode == `OP_SUB);
    assign is_cmp  = is_type1 && (t1_opcode == `OP_CMP);
    assign is_mov  = is_type1 && (t1_opcode == `OP_MOV);
    assign is_li   = !is_type1 && (t2_opcode == `OP_LI) && t2_ri;
    assign is_jmp  = !is_type1 && (t2_opcode == `OP_JMP);
    assign jump_is_absolute = is_jmp && t2_ri;
    assign is_jz   = !is_type1 && (t2_opcode == `OP_JZ);
    assign is_jnz  = !is_type1 && (t2_opcode == `OP_JNZ);
    assign is_jlt  = !is_type1 && (t2_opcode == `OP_JLT);
    assign is_jgt  = !is_type1 && (t2_opcode == `OP_JGT);
    assign branch_is_absolute = t2_ri && (is_jz || is_jnz || is_jlt || is_jgt);
    assign is_call = !is_type1 && (t2_opcode == `OP_CALL);
    assign call_is_absolute = is_call && t2_ri;
    assign is_ret  = !is_type1 && (t2_opcode == `OP_RET);
    assign is_halt = is_jmp && !t2_ri && (immediate16 == 16'h0000);
    assign is_load   = !is_type1 && (t2_opcode == `OP_LOAD);
    assign is_store  = !is_type1 && (t2_opcode == `OP_STORE);
    assign is_loadb  = !is_type1 && (t2_opcode == `OP_LOADB);
    assign is_storeb = !is_type1 && (t2_opcode == `OP_STOREB);
    assign memory_is_absolute = t2_ri;
    assign memory_reg = t2_reg;
    assign memory_base = instr[15:11];
    assign memory_offset11 = instr[10:0];
    assign dest = (is_li || is_load || is_loadb)
                ? t2_reg
                : (is_cmp ? `REG_ADDR_W'd5 : instr[4:0]);
    assign reg_write_en = is_add || is_sub || is_cmp || is_mov || is_li ||
                          is_load || is_loadb;
endmodule

