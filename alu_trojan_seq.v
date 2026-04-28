// ============================================================================
// File       : alu_trojan_seq.v
// Description: 4-bit ALU with Sequential Hardware Trojan
//              Trojan Trigger : Specific 8-cycle input sequence detected
//                               Sequence: A cycles through 4'h1,2,3,4,5,6,7,8
//                               while op == 2'b00 (ADD) on each cycle
//              Trojan Payload : Corrupts output (inverts result) for 4 cycles
//                               after trigger sequence completes
// ============================================================================

module alu_trojan_seq (
    input  wire [3:0] A,
    input  wire [3:0] B,
    input  wire [1:0] op,
    output reg  [3:0] result,
    input  wire       clk,
    input  wire       rst
);

    // ----- Trojan State Machine -----
    reg [2:0] seq_state;       // Tracks position in the 8-step trigger sequence
    reg       trojan_active;   // High when Trojan payload is active
    reg [1:0] payload_count;   // Counts down the 4 corruption cycles

    // Expected A values for the trigger sequence
    wire seq_match;
    assign seq_match = (op == 2'b00) && (
        (seq_state == 3'd0 && A == 4'h1) ||
        (seq_state == 3'd1 && A == 4'h2) ||
        (seq_state == 3'd2 && A == 4'h3) ||
        (seq_state == 3'd3 && A == 4'h4) ||
        (seq_state == 3'd4 && A == 4'h5) ||
        (seq_state == 3'd5 && A == 4'h6) ||
        (seq_state == 3'd6 && A == 4'h7) ||
        (seq_state == 3'd7 && A == 4'h8)
    );

    // ----- Sequence Detection FSM -----
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            seq_state    <= 3'd0;
            trojan_active <= 1'b0;
            payload_count <= 2'd0;
        end else begin
            // Payload countdown
            if (trojan_active) begin
                if (payload_count == 2'd0) begin
                    trojan_active <= 1'b0;
                end else begin
                    payload_count <= payload_count - 1'b1;
                end
            end

            // Sequence tracking
            if (seq_match) begin
                if (seq_state == 3'd7) begin
                    // Full sequence detected — activate Trojan
                    trojan_active <= 1'b1;
                    payload_count <= 2'd3;
                    seq_state     <= 3'd0;
                end else begin
                    seq_state <= seq_state + 1'b1;
                end
            end else begin
                seq_state <= 3'd0; // Reset on mismatch
            end
        end
    end

    // ----- ALU with Trojan Payload -----
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result <= 4'b0000;
        end else begin
            case (op)
                2'b00: result <= trojan_active ? ~(A + B) : (A + B);
                2'b01: result <= trojan_active ? ~(A - B) : (A - B);
                2'b10: result <= trojan_active ? ~(A & B) : (A & B);
                2'b11: result <= trojan_active ? ~(A | B) : (A | B);
                default: result <= 4'b0000;
            endcase
        end
    end

endmodule
