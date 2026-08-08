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
    output wire                    is_li,
    output wire                    is_halt,
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
    assign is_mov  = is_type1 && (t1_opcode == `OP_MOV);
    assign is_li   = !is_type1 && (t2_opcode == `OP_LI) && t2_ri;
    assign is_halt = !is_type1 && (t2_opcode == `OP_JMP) &&
                     !t2_ri && (immediate16 == 16'h0000);
    assign dest = is_li ? t2_reg : instr[4:0];
    assign reg_write_en = is_add || is_sub || is_mov || is_li;
endmodule
