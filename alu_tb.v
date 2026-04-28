// ============================================================================
// File       : alu_tb.v
// Description: Testbench for all 4 ALU variants (clean + 3 Trojans)
//              - Instantiates all variants in parallel
//              - Dumps individual VCD per variant
//              - Runs exhaustive + random inputs
//              - Runs at least 10,000 clock cycles
//              - Compatible with Icarus Verilog (iverilog + vvp)
// ============================================================================

`timescale 1ns / 1ps

module alu_tb;

    // ---- Clock & Reset ----
    reg         clk;
    reg         rst;
    reg  [3:0]  A;
    reg  [3:0]  B;
    reg  [1:0]  op;

    // ---- Outputs from each variant ----
    wire [3:0]  result_clean;
    wire [3:0]  result_comb;
    wire [3:0]  result_seq;
    wire [3:0]  result_counter;

    // ---- Instantiate all ALU variants ----
    alu_clean u_clean (
        .A(A), .B(B), .op(op), .result(result_clean), .clk(clk), .rst(rst)
    );

    alu_trojan_comb u_comb (
        .A(A), .B(B), .op(op), .result(result_comb), .clk(clk), .rst(rst)
    );

    alu_trojan_seq u_seq (
        .A(A), .B(B), .op(op), .result(result_seq), .clk(clk), .rst(rst)
    );

    alu_trojan_counter u_counter (
        .A(A), .B(B), .op(op), .result(result_counter), .clk(clk), .rst(rst)
    );

    // ---- Clock Generation: 10ns period ----
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- LFSR for pseudo-random inputs ----
    reg [15:0] lfsr;
    wire lfsr_feedback;
    assign lfsr_feedback = lfsr[15] ^ lfsr[14] ^ lfsr[12] ^ lfsr[3];

    task lfsr_step;
        begin
            lfsr <= {lfsr[14:0], lfsr_feedback};
        end
    endtask

    // ---- VCD Dump ----
    initial begin
        // Dump all signals into one VCD for comparison analysis
        $dumpfile("alu_all.vcd");
        $dumpvars(0, alu_tb);
    end

    // ---- Counters ----
    integer cycle_count;
    integer mismatch_comb;
    integer mismatch_seq;
    integer mismatch_counter;
    integer i;

    // ---- Main Test Sequence ----
    initial begin
        // Initialize
        rst = 1;
        A   = 0;
        B   = 0;
        op  = 0;
        lfsr = 16'hACE1; // seed
        cycle_count     = 0;
        mismatch_comb   = 0;
        mismatch_seq    = 0;
        mismatch_counter = 0;

        // Release reset
        #20;
        rst = 0;
        #10;

        $display("============================================================");
        $display(" ALU Testbench — Exhaustive + Random, 4 Variants");
        $display("============================================================");

        // ---- Phase 1: Exhaustive test (all A, B, op combinations) ----
        // 16 * 16 * 4 = 1024 combinations
        $display("\n[Phase 1] Exhaustive test: 1024 input combinations");
        for (i = 0; i < 1024; i = i + 1) begin
            A  = i[3:0];
            B  = i[7:4];
            op = i[9:8];
            @(posedge clk);
            #1; // allow outputs to settle
            cycle_count = cycle_count + 1;

            // Compare against clean reference
            if (result_comb !== result_clean) begin
                mismatch_comb = mismatch_comb + 1;
                $display("  [COMB TROJAN] Mismatch @ cycle %0d: A=%b B=%b op=%b | clean=%b comb=%b",
                         cycle_count, A, B, op, result_clean, result_comb);
            end
            if (result_seq !== result_clean) begin
                mismatch_seq = mismatch_seq + 1;
                $display("  [SEQ TROJAN]  Mismatch @ cycle %0d: A=%b B=%b op=%b | clean=%b seq=%b",
                         cycle_count, A, B, op, result_clean, result_seq);
            end
            if (result_counter !== result_clean) begin
                mismatch_counter = mismatch_counter + 1;
                $display("  [CTR TROJAN]  Mismatch @ cycle %0d: A=%b B=%b op=%b | clean=%b ctr=%b",
                         cycle_count, A, B, op, result_clean, result_counter);
            end
        end

        // ---- Phase 2: Trigger the sequential Trojan ----
        $display("\n[Phase 2] Sequential Trojan trigger sequence (A=1..8, op=ADD)");
        op = 2'b00;
        for (i = 1; i <= 8; i = i + 1) begin
            A = i[3:0];
            B = 4'd0;
            @(posedge clk);
            #1;
            cycle_count = cycle_count + 1;
        end
        // Check next few cycles for corruption
        for (i = 0; i < 10; i = i + 1) begin
            A = $random;
            B = $random;
            op = $random;
            @(posedge clk);
            #1;
            cycle_count = cycle_count + 1;
            if (result_seq !== result_clean) begin
                mismatch_seq = mismatch_seq + 1;
                $display("  [SEQ TROJAN]  Post-trigger mismatch @ cycle %0d: A=%b B=%b op=%b | clean=%b seq=%b",
                         cycle_count, A, B, op, result_clean, result_seq);
            end
        end

        // ---- Phase 3: Random test to reach 10,000+ cycles ----
        $display("\n[Phase 3] Random inputs until 12,000 cycles");
        while (cycle_count < 12000) begin
            A  = lfsr[3:0];
            B  = lfsr[7:4];
            op = lfsr[9:8];
            lfsr_step;
            @(posedge clk);
            #1;
            cycle_count = cycle_count + 1;

            if (result_comb !== result_clean)
                mismatch_comb = mismatch_comb + 1;
            if (result_seq !== result_clean)
                mismatch_seq = mismatch_seq + 1;
            if (result_counter !== result_clean)
                mismatch_counter = mismatch_counter + 1;

            // Periodic status
            if (cycle_count % 3000 == 0)
                $display("  ... cycle %0d", cycle_count);
        end

        // ---- Summary ----
        $display("\n============================================================");
        $display(" TEST SUMMARY (%0d total cycles)", cycle_count);
        $display("============================================================");
        $display("  Combinational Trojan mismatches: %0d", mismatch_comb);
        $display("  Sequential Trojan mismatches:    %0d", mismatch_seq);
        $display("  Counter Trojan mismatches:       %0d", mismatch_counter);
        $display("============================================================");

        #100;
        $finish;
    end

    // ---- Timeout safety ----
    initial begin
        #2000000; // 200,000 ns safety timeout
        $display("TIMEOUT: Simulation exceeded maximum time");
        $finish;
    end

endmodule
