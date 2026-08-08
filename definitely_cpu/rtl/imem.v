`include "config.vh"

module imem #(
    parameter DEPTH = `IMEM_DEPTH
) (
    input  wire [`ADDR_MSB:0]       addr,
    output wire [`INSTR_WIDTH-1:0] data
);
    reg [`INSTR_WIDTH-1:0] mem [0:DEPTH-1];

    assign data = mem[addr];
endmodule
