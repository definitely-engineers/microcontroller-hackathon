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
    wire is_cmp;
    wire is_li;
    wire is_jmp;
    wire jump_is_absolute;
    wire is_jz;
    wire is_jnz;
    wire is_jlt;
    wire is_jgt;
    wire is_cond_branch;
    wire branch_is_absolute;
    wire branch_taken;
    wire is_call;
    wire call_is_absolute;
    wire is_ret;
    wire is_halt;
    wire [15:0] immediate16;
    wire reg_write_en;
    wire rf_write_en;
    wire [`REG_ADDR_W-1:0] rf_write_addr;
    wire [`REG_ADDR_W-1:0] rf_read_addr_a;
    wire [`DATA_MSB:0] rf_write_data;

    wire [`DATA_MSB:0] rf_a;
    wire [`DATA_MSB:0] rf_b;
    wire [`DATA_MSB:0] alu_a;
    wire [`DATA_MSB:0] alu_b;
    wire [`DATA_MSB:0] alu_result;
    wire [`DATA_MSB:0] wb_data;
    wire [`ADDR_MSB:0] relative_jump_target;
    wire [`ADDR_MSB:0] jump_target;
    wire [`ADDR_MSB:0] conditional_branch_target;
    wire [`ADDR_MSB:0] call_target;
    wire [`ADDR_MSB:0] return_address;

    assign dbg_pc = pc;
    assign dbg_halt = is_halt;
    assign rf_write_en = (reg_write_en || is_call) && rst_n;
    assign rf_write_addr = is_call ? `REG_ADDR_W'd3 : dest;
    assign is_cond_branch = is_jz || is_jnz || is_jlt || is_jgt;
    assign rf_read_addr_a = is_ret ? `REG_ADDR_W'd3
                                   : (is_cond_branch ? `REG_ADDR_W'd5 : arg1);
    assign return_address = pc + 1'b1;
    assign rf_write_data = is_call
                         ? {{(`DATA_WIDTH-`ADDR_WIDTH){1'b0}}, return_address}
                         : wb_data;
    // PC and the branch offset are both 16 bits. Two's-complement addition
    // therefore implements the ISA's signed PC-relative offset modulo 2^16.
    assign relative_jump_target = pc + immediate16;
    assign jump_target = jump_is_absolute ? immediate16 : relative_jump_target;
    assign conditional_branch_target = branch_is_absolute
                                     ? immediate16 : relative_jump_target;
    assign call_target = call_is_absolute ? immediate16 : relative_jump_target;
    assign branch_taken = (is_jz  && (rf_a == {`DATA_WIDTH{1'b0}}))
                       || (is_jnz && (rf_a != {`DATA_WIDTH{1'b0}}))
                       || (is_jlt && rf_a[`DATA_MSB])
                       || (is_jgt && !rf_a[`DATA_MSB]
                                  && (rf_a != {`DATA_WIDTH{1'b0}}));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc <= `PC_INIT;
        else if (is_halt)
            pc <= pc;
        else if (is_ret)
            pc <= rf_a[`ADDR_MSB:0];
        else if (is_call)
            pc <= call_target;
        else if (is_jmp)
            pc <= jump_target;
        else if (is_cond_branch && branch_taken)
            pc <= conditional_branch_target;
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
        .is_cmp(is_cmp),
        .is_li(is_li),
        .is_jmp(is_jmp),
        .jump_is_absolute(jump_is_absolute),
        .is_jz(is_jz),
        .is_jnz(is_jnz),
        .is_jlt(is_jlt),
        .is_jgt(is_jgt),
        .branch_is_absolute(branch_is_absolute),
        .is_call(is_call),
        .call_is_absolute(call_is_absolute),
        .is_ret(is_ret),
        .is_halt(is_halt),
        .immediate16(immediate16),
        .reg_write_en(reg_write_en)
    );

    regfile u_regfile (
        .clk(clk),
        .wr_en(rf_write_en),
        .wr_addr(rf_write_addr),
        .wr_data(rf_write_data),
        .rd_addr_a(rf_read_addr_a),
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
