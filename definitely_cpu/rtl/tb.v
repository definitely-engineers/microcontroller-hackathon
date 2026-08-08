`timescale 1ns/1ps
`include "config.vh"

module tb;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    wire [`ADDR_MSB:0] dbg_pc;
    wire dbg_halt;

    integer max_cycles;
    integer cycles;
    integer i;
    reg [1023:0] program_file;

    cpu dut (
        .clk(clk),
        .rst_n(rst_n),
        .dbg_pc(dbg_pc),
        .dbg_halt(dbg_halt)
    );

    always #5 clk = ~clk;

    task dump_registers;
        begin
            for (i = 0; i < `REG_COUNT; i = i + 1) begin
                if (i == 0)
                    $display("r%0d = 0x%08x", i, 32'h00000000);
                else
                    $display("r%0d = 0x%08x", i, dut.u_regfile.regs[i]);
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("PROGRAM=%s", program_file)) begin
            $display("ERROR: +PROGRAM=<hex file> is required");
            $finish;
        end
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles))
            max_cycles = 100;

        $readmemh(program_file, dut.u_imem.mem);
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        cycles = 0;
        while (!dbg_halt && cycles < max_cycles) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        #1;
        dump_registers();
        if (!dbg_halt)
            $display("ERROR: simulation timed out after %0d cycles", cycles);
        else
            $display("HALT at PC=0x%04x after %0d cycles", dbg_pc, cycles);
        $finish;
    end
endmodule
