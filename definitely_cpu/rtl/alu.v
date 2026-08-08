`include "config.vh"
`include "opcodes.vh"
//Arithmetic Logic Unit，算术逻辑单元

module alu (
    input  wire [`T1_OPCODE_W-1:0] op,
    input  wire [`DATA_MSB:0]      a,
    input  wire [`DATA_MSB:0]      b,
    output reg  [`DATA_MSB:0]      result
);
    always @(*) begin
        case (op)
            `OP_ADD: result = a + b;
            `OP_SUB: result = a - b;
            default: result = {`DATA_WIDTH{1'b0}};
        endcase
    end
endmodule
