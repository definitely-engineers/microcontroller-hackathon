`ifndef OPCODES_VH
`define OPCODES_VH

`define OP_ADD 14'h0000
`define OP_SUB 14'h0001
`define OP_CMP 14'h000D
`define OP_MOV 14'h000F
`define OP_LOAD   9'h000
`define OP_STORE  9'h001
`define OP_LOADB  9'h002
`define OP_STOREB 9'h003
`define OP_JMP 9'h004
`define OP_JZ  9'h005
`define OP_JNZ 9'h006
`define OP_JLT 9'h007
`define OP_JGT 9'h008
`define OP_CALL 9'h009
`define OP_RET  9'h00A
`define OP_LI  9'h00D

`endif
