// ============================================================================
// File       : alu_trojan_comb.v
// Description: 4-bit ALU with Combinational Hardware Trojan
//              Trojan Trigger : A == 4'b1111 AND B == 4'b1111
//              Trojan Payload : Flips the LSB of the result
// ============================================================================

module alu_trojan_comb (
    input  wire [3:0] A,
    input  wire [3:0] B,
    input  wire [1:0] op,
    output reg  [3:0] result,
    input  wire       clk,
    input  wire       rst
);

    // Internal signals
    wire        trojan_trigger;
    wire [3:0]  clean_result;
    reg  [3:0]  alu_out;

    // ----- Clean ALU Logic -----
    always @(*) begin
        case (op)
            2'b00: alu_out = A + B;   // ADD
            2'b01: alu_out = A - B;   // SUB
            2'b10: alu_out = A & B;   // AND
            2'b11: alu_out = A | B;   // OR
            default: alu_out = 4'b0000;
        endcase
    end

    // ----- Trojan Trigger: purely combinational -----
    assign trojan_trigger = (A == 4'b1111) && (B == 4'b1111);

    // ----- Trojan Payload: flip LSB when triggered -----
    assign clean_result = trojan_trigger ? {alu_out[3:1], ~alu_out[0]} : alu_out;

    // ----- Registered Output -----
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result <= 4'b0000;
        end else begin
            result <= clean_result;
        end
    end

endmodule
