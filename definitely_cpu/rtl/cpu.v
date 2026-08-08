`include "config.vh"

module cpu (
    input  wire                 clk,
    input  wire                 rst_n,
    output wire [`ADDR_MSB:0]  dbg_pc,
    output wire                 dbg_halt
);
    reg [`ADDR_MSB:0] pc;
    wire [`INSTR_WIDTH-1:0] instr;

    wire is_type1;
    wire [`T1_OPCODE_W-1:0] t1_opcode;
    wire arg1_is_imm;
    wire [`REG_ADDR_W-1:0] arg1;
    wire arg2_is_imm;
    wire [`REG_ADDR_W-1:0] arg2;
    wire [`REG_ADDR_W-1:0] dest;
    wire is_add;
    wire is_li;
    wire is_jmp;
    wire jump_is_absolute;
    wire is_halt;
    wire [15:0] immediate16;
    wire reg_write_en;
    wire rf_write_en;

    wire [`DATA_MSB:0] rf_a;
    wire [`DATA_MSB:0] rf_b;
    wire [`DATA_MSB:0] alu_a;
    wire [`DATA_MSB:0] alu_b;
    wire [`DATA_MSB:0] alu_result;
    wire [`DATA_MSB:0] wb_data;
    wire [`ADDR_MSB:0] relative_jump_target;
    wire [`ADDR_MSB:0] jump_target;

    assign dbg_pc = pc;
    assign dbg_halt = is_halt;
    assign rf_write_en = reg_write_en && rst_n;
    // PC and the branch offset are both 16 bits. Two's-complement addition
    // therefore implements the ISA's signed PC-relative offset modulo 2^16.
    assign relative_jump_target = pc + immediate16;
    assign jump_target = jump_is_absolute ? immediate16 : relative_jump_target;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc <= `PC_INIT;
        else if (is_halt)
            pc <= pc;
        else if (is_jmp)
            pc <= jump_target;
        else
            pc <= pc + 1'b1;
    end

    imem u_imem (
        .addr(pc),
        .data(instr)
    );

    decoder u_decoder (
        .instr(instr),
        .is_type1(is_type1),
        .t1_opcode(t1_opcode),
        .arg1_is_imm(arg1_is_imm),
        .arg1(arg1),
        .arg2_is_imm(arg2_is_imm),
        .arg2(arg2),
        .dest(dest),
        .is_add(is_add),
        .is_li(is_li),
        .is_jmp(is_jmp),
        .jump_is_absolute(jump_is_absolute),
        .is_halt(is_halt),
        .immediate16(immediate16),
        .reg_write_en(reg_write_en)
    );

    regfile u_regfile (
        .clk(clk),
        .wr_en(rf_write_en),
        .wr_addr(dest),
        .wr_data(wb_data),
        .rd_addr_a(arg1),
        .rd_addr_b(arg2),
        .rd_data_a(rf_a),
        .rd_data_b(rf_b)
    );

    assign alu_a = arg1_is_imm ? {{(`DATA_WIDTH-5){1'b0}}, arg1} : rf_a;
    assign alu_b = arg2_is_imm ? {{(`DATA_WIDTH-5){1'b0}}, arg2} : rf_b;

    alu u_alu (
        .op(t1_opcode),
        .a(alu_a),
        .b(alu_b),
        .result(alu_result)
    );

    assign wb_data = is_li ? {{(`DATA_WIDTH-16){1'b0}}, immediate16} : alu_result;
endmodule
