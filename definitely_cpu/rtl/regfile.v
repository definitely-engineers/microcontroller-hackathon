`include "config.vh"

module regfile (
    input  wire                    clk,
    input  wire                    wr_en,
    input  wire [`REG_ADDR_W-1:0] wr_addr,
    input  wire [`DATA_MSB:0]      wr_data,
    input  wire                    sp_wr_en,
    input  wire [`DATA_MSB:0]      sp_wr_data,
    input  wire [`REG_ADDR_W-1:0] rd_addr_a,
    input  wire [`REG_ADDR_W-1:0] rd_addr_b,
    output wire [`DATA_MSB:0]      rd_data_a,
    output wire [`DATA_MSB:0]      rd_data_b
);
    reg [`DATA_MSB:0] regs [0:`REG_COUNT-1];

    always @(posedge clk) begin
        // PUSH/POP update r2 (SP) while POP may also restore another
        // register through the normal write port on the same clock edge.
        if (sp_wr_en)
            regs[2] <= sp_wr_data;

        if (wr_en && wr_addr != {`REG_ADDR_W{1'b0}} &&
            !(sp_wr_en && wr_addr == `REG_ADDR_W'd2))
            regs[wr_addr] <= wr_data;
    end

    assign rd_data_a = (rd_addr_a == 0) ? {`DATA_WIDTH{1'b0}} : regs[rd_addr_a];
    assign rd_data_b = (rd_addr_b == 0) ? {`DATA_WIDTH{1'b0}} : regs[rd_addr_b];
endmodule
