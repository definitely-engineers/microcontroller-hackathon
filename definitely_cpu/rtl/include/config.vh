`timescale 1ns/1ps

`ifndef CONFIG_VH
`define CONFIG_VH

`define DATA_WIDTH  32
`define DATA_MSB    31
`define ADDR_WIDTH  16
`define ADDR_MSB    15
`define INSTR_WIDTH 32
`define REG_COUNT   32
`define REG_ADDR_W  5
`define IMEM_DEPTH  8792
`define DMEM_DEPTH  32768
`define PC_INIT     16'h0000

`define T1_OPCODE_W 14
`define T2_OPCODE_W 9

`endif
