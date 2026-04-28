// ============================================================================
// File       : aes_tb.v
// Description: Testbench for AES-128 Clean and Trojan variants
//              - Drives both with identical plaintext/key pairs
//              - Dumps VCD for both modules
//              - Runs 10,000+ clock cycles
//              - Uses exhaustive-like patterns + random patterns
//              - Compatible with Icarus Verilog (iverilog + vvp)
// ============================================================================

`timescale 1ns / 1ps

module aes_tb;

    // ---- Clock & Reset ----
    reg          clk;
    reg          rst;
    reg  [127:0] key;
    reg  [127:0] plaintext;

    // ---- Outputs ----
    wire [127:0] ciphertext_clean;
    wire [127:0] ciphertext_trojan;

    // ---- Instantiate both AES modules ----
    aes_clean u_aes_clean (
        .clk(clk),
        .rst(rst),
        .key(key),
        .plaintext(plaintext),
        .ciphertext(ciphertext_clean)
    );

    aes_trojan u_aes_trojan (
        .clk(clk),
        .rst(rst),
        .key(key),
        .plaintext(plaintext),
        .ciphertext(ciphertext_trojan)
    );

    // ---- Clock: 10ns period ----
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- VCD Dump ----
    initial begin
        $dumpfile("aes_all.vcd");
        $dumpvars(0, aes_tb);
    end

    // ---- LFSR for pseudo-random generation ----
    reg [31:0] lfsr;
    wire lfsr_fb;
    assign lfsr_fb = lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0];

    task lfsr_next;
        begin
            lfsr <= {lfsr[30:0], lfsr_fb};
        end
    endtask

    // Build 128-bit value from LFSR (call 4 times to fill)
    function [127:0] gen_random_128;
        input [31:0] seed;
        reg [31:0] s;
        reg [127:0] val;
        integer j;
        begin
            s = seed;
            for (j = 0; j < 128; j = j + 1) begin
                val[j] = s[0];
                s = {s[30:0], s[31] ^ s[21] ^ s[1] ^ s[0]};
            end
            gen_random_128 = val;
        end
    endfunction

    // ---- Test Variables ----
    integer cycle_count;
    integer encrypt_count;
    integer mismatch_count;
    integer i;
    reg [127:0] saved_ct_clean;
    reg [127:0] saved_ct_trojan;

    // ---- Wait for encryption (11 clock cycles per encryption) ----
    task wait_encrypt;
        begin
            // AES takes 11 cycles: 1 load + 9 rounds + 1 final
            for (i = 0; i < 12; i = i + 1) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end
            #1; // settle
        end
    endtask

    // ---- Main Test ----
    initial begin
        // Init
        rst       = 1;
        key       = 128'd0;
        plaintext = 128'd0;
        lfsr      = 32'hDEAD_BEEF;
        cycle_count    = 0;
        encrypt_count  = 0;
        mismatch_count = 0;

        // Release reset
        #30;
        rst = 0;
        @(posedge clk);
        cycle_count = cycle_count + 1;

        $display("============================================================");
        $display(" AES-128 Testbench — Clean vs Trojan Comparison");
        $display("============================================================");

        // ---- Test 1: NIST known-answer test vector ----
        $display("\n[Test 1] NIST AES-128 test vector");
        key       = 128'h2b7e151628aed2a6abf7158809cf4f3c;
        plaintext = 128'h3243f6a8885a308d313198a2e0370734;
        wait_encrypt;
        encrypt_count = encrypt_count + 1;
        $display("  Key       = %h", key);
        $display("  Plaintext = %h", plaintext);
        $display("  CT Clean  = %h", ciphertext_clean);
        $display("  CT Trojan = %h", ciphertext_trojan);
        if (ciphertext_clean !== ciphertext_trojan) begin
            mismatch_count = mismatch_count + 1;
            $display("  *** CIPHERTEXT MISMATCH DETECTED ***");
        end

        // ---- Test 2: All-zero key and plaintext ----
        $display("\n[Test 2] All-zero key/plaintext");
        key       = 128'h0;
        plaintext = 128'h0;
        wait_encrypt;
        encrypt_count = encrypt_count + 1;
        $display("  CT Clean  = %h", ciphertext_clean);
        $display("  CT Trojan = %h", ciphertext_trojan);

        // ---- Test 3: Trojan trigger pattern (plaintext[7:0] = 0xFF) ----
        $display("\n[Test 3] Trojan trigger patterns (plaintext[7:0]=FF)");
        key = 128'hDEADBEEFCAFEBABE0123456789ABCDEF;
        for (i = 0; i < 20; i = i + 1) begin
            plaintext = {gen_random_128(lfsr + i)[127:8], 8'hFF}; // Force trigger
            lfsr_next;
            wait_encrypt;
            encrypt_count = encrypt_count + 1;
            if (ciphertext_clean !== ciphertext_trojan) begin
                mismatch_count = mismatch_count + 1;
                $display("  Trigger test %0d: CT MISMATCH", i);
            end
        end

        // ---- Test 4: Systematic key patterns ----
        $display("\n[Test 4] Systematic key/plaintext sweeps");
        for (i = 0; i < 50; i = i + 1) begin
            key       = {4{32'h01010101}} << i;
            plaintext = {4{32'hFEDCBA98}} ^ (128'd1 << i);
            wait_encrypt;
            encrypt_count = encrypt_count + 1;
            if (ciphertext_clean !== ciphertext_trojan)
                mismatch_count = mismatch_count + 1;
        end

        // ---- Test 5: Random test until 10,000+ cycles ----
        $display("\n[Test 5] Random encryptions until 10,000+ cycles");
        while (cycle_count < 10200) begin
            key       = gen_random_128(lfsr);
            lfsr_next;
            plaintext = gen_random_128(lfsr);
            lfsr_next;
            wait_encrypt;
            encrypt_count = encrypt_count + 1;

            if (ciphertext_clean !== ciphertext_trojan)
                mismatch_count = mismatch_count + 1;

            if (encrypt_count % 100 == 0)
                $display("  ... %0d encryptions, %0d cycles", encrypt_count, cycle_count);
        end

        // ---- Summary ----
        $display("\n============================================================");
        $display(" AES TEST SUMMARY");
        $display("============================================================");
        $display("  Total encryptions:    %0d", encrypt_count);
        $display("  Total clock cycles:   %0d", cycle_count);
        $display("  Ciphertext mismatches: %0d", mismatch_count);
        $display("  (Note: Trojan leaks via switching, not ciphertext)");
        $display("============================================================");

        #100;
        $finish;
    end

    // ---- Timeout ----
    initial begin
        #5000000;
        $display("TIMEOUT: AES simulation exceeded maximum time");
        $finish;
    end

endmodule
