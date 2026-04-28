// ============================================================================
// File       : alu_clean.v
// Description: Clean 4-bit ALU — ADD, SUB, AND, OR via op[1:0]
//              No hardware Trojan. This serves as the golden reference.
// ============================================================================

module alu_clean (
    input  wire [3:0] A,
    input  wire [3:0] B,
    input  wire [1:0] op,
    output reg  [3:0] result,
    input  wire       clk,
    input  wire       rst
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result <= 4'b0000;
        end else begin
            case (op)
                2'b00: result <= A + B;   // ADD
                2'b01: result <= A - B;   // SUB
                2'b10: result <= A & B;   // AND
                2'b11: result <= A | B;   // OR
                default: result <= 4'b0000;
            endcase
        end
    end

endmodule
