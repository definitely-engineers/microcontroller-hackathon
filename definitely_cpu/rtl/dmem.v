`include "config.vh"

// Byte-addressed, little-endian data memory.
// Reads are combinational so the baseline single-cycle CPU can write a loaded
// value back to the register file on the same clock edge. Stores commit on the
// rising edge. Out-of-range reads return zero and writes are ignored.
module dmem #(
    parameter DEPTH = `DMEM_DEPTH
) (
    input  wire                   clk,
    input  wire [`ADDR_MSB:0]     addr,
    input  wire                   write_word_en,
    input  wire                   write_byte_en,
    input  wire [`DATA_MSB:0]     write_data,
    output reg  [`DATA_MSB:0]     read_word,
    output reg  [7:0]             read_byte
);
    reg [7:0] mem [0:DEPTH-1];
    wire [`ADDR_WIDTH:0] last_word_addr = {1'b0, addr} + 3;

    always @(*) begin
        read_byte = 8'h00;
        read_word = {`DATA_WIDTH{1'b0}};

        if (addr < DEPTH)
            read_byte = mem[addr];

        if (last_word_addr < DEPTH) begin
            read_word = {
                mem[addr + 3],
                mem[addr + 2],
                mem[addr + 1],
                mem[addr]
            };
        end
    end

    always @(posedge clk) begin
        if (write_word_en && last_word_addr < DEPTH) begin
            mem[addr]     <= write_data[7:0];
            mem[addr + 1] <= write_data[15:8];
            mem[addr + 2] <= write_data[23:16];
            mem[addr + 3] <= write_data[31:24];
        end else if (write_byte_en && addr < DEPTH) begin
            mem[addr] <= write_data[7:0];
        end
    end
endmodule
