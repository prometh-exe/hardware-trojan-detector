#!/bin/bash
# ============================================================================
# simulate.sh — Icarus Verilog Simulation Script
# Compiles and runs all testbenches, generates 6 individual VCD files
# (one per design variant) plus 2 combined VCDs for comparison analysis.
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Output directories
VCD_DIR="vcd"
SIM_DIR="sim"
mkdir -p "$VCD_DIR" "$SIM_DIR"

echo "============================================================"
echo " Icarus Verilog Simulation — Hardware Security Framework"
echo "============================================================"
echo ""

# ============================================================
# Individual ALU variant simulations (4 separate VCDs)
# ============================================================
ALU_VARIANTS="alu_clean alu_trojan_comb alu_trojan_seq alu_trojan_counter"
ALU_INDEX=0

for VARIANT in $ALU_VARIANTS; do
    ALU_INDEX=$((ALU_INDEX + 1))
    echo "--------------------------------------------------------------"
    echo " [${ALU_INDEX}/6] ${VARIANT} — Individual VCD"
    echo "--------------------------------------------------------------"

    # Generate a per-variant testbench wrapper on the fly
    cat > "${SIM_DIR}/${VARIANT}_wrap_tb.v" << VEOF
\`timescale 1ns / 1ps
module ${VARIANT}_wrap_tb;
    reg         clk;
    reg         rst;
    reg  [3:0]  A;
    reg  [3:0]  B;
    reg  [1:0]  op;
    wire [3:0]  result;

    ${VARIANT} uut (
        .A(A), .B(B), .op(op), .result(result), .clk(clk), .rst(rst)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    reg [15:0] lfsr;
    wire lfsr_fb;
    assign lfsr_fb = lfsr[15] ^ lfsr[14] ^ lfsr[12] ^ lfsr[3];

    integer cycle_count;
    integer i;

    initial begin
        \$dumpfile("${VARIANT}.vcd");
        \$dumpvars(0, ${VARIANT}_wrap_tb);

        rst = 1; A = 0; B = 0; op = 0;
        lfsr = 16'hACE1;
        cycle_count = 0;
        #20; rst = 0; #10;

        // Exhaustive: 1024 combinations
        for (i = 0; i < 1024; i = i + 1) begin
            A = i[3:0]; B = i[7:4]; op = i[9:8];
            @(posedge clk); #1;
            cycle_count = cycle_count + 1;
        end

        // Sequential trigger sequence
        op = 2'b00;
        for (i = 1; i <= 8; i = i + 1) begin
            A = i[3:0]; B = 4'd0;
            @(posedge clk); #1;
            cycle_count = cycle_count + 1;
        end

        // Random to 12000 cycles
        while (cycle_count < 12000) begin
            A = lfsr[3:0]; B = lfsr[7:4]; op = lfsr[9:8];
            lfsr = {lfsr[14:0], lfsr_fb};
            @(posedge clk); #1;
            cycle_count = cycle_count + 1;
        end

        #100; \$finish;
    end

    initial begin #2000000; \$finish; end
endmodule
VEOF

    echo "  Compiling..."
    iverilog -o "${SIM_DIR}/${VARIANT}_wrap.vvp" \
        "${VARIANT}.v" \
        "${SIM_DIR}/${VARIANT}_wrap_tb.v" \
        2>&1 | tee "${SIM_DIR}/${VARIANT}_compile.log"

    echo "  Simulating..."
    cd "$VCD_DIR"
    vvp "../${SIM_DIR}/${VARIANT}_wrap.vvp" 2>&1 | tee "../${SIM_DIR}/${VARIANT}_sim.log"
    cd "$SCRIPT_DIR"

    if [ -f "${VCD_DIR}/${VARIANT}.vcd" ]; then
        echo "  ✓ ${VCD_DIR}/${VARIANT}.vcd"
    else
        echo "  ✗ VCD generation failed!"
    fi
    echo ""
done

# ============================================================
# Individual AES variant simulations (2 separate VCDs)
# ============================================================
AES_VARIANTS="aes_clean aes_trojan"

for VARIANT in $AES_VARIANTS; do
    ALU_INDEX=$((ALU_INDEX + 1))
    echo "--------------------------------------------------------------"
    echo " [${ALU_INDEX}/6] ${VARIANT} — Individual VCD"
    echo "--------------------------------------------------------------"

    cat > "${SIM_DIR}/${VARIANT}_wrap_tb.v" << VEOF
\`timescale 1ns / 1ps
module ${VARIANT}_wrap_tb;
    reg          clk;
    reg          rst;
    reg  [127:0] key;
    reg  [127:0] plaintext;
    wire [127:0] ciphertext;

    ${VARIANT} uut (
        .clk(clk), .rst(rst), .key(key),
        .plaintext(plaintext), .ciphertext(ciphertext)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    reg [31:0] lfsr;
    wire lfsr_fb;
    assign lfsr_fb = lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0];

    integer cycle_count, enc_count, i;

    initial begin
        \$dumpfile("${VARIANT}.vcd");
        \$dumpvars(0, ${VARIANT}_wrap_tb);

        rst = 1; key = 128'd0; plaintext = 128'd0;
        lfsr = 32'hDEADBEEF;
        cycle_count = 0; enc_count = 0;
        #30; rst = 0;
        @(posedge clk); cycle_count = cycle_count + 1;

        // NIST test vector
        key       = 128'h2b7e151628aed2a6abf7158809cf4f3c;
        plaintext = 128'h3243f6a8885a308d313198a2e0370734;
        for (i = 0; i < 12; i = i + 1) begin
            @(posedge clk); cycle_count = cycle_count + 1;
        end
        enc_count = enc_count + 1;

        // Trigger patterns (plaintext[7:0]=FF)
        key = 128'hDEADBEEFCAFEBABE0123456789ABCDEF;
        for (i = 0; i < 20; i = i + 1) begin
            plaintext = {lfsr, lfsr, lfsr, {lfsr[31:8], 8'hFF}};
            lfsr = {lfsr[30:0], lfsr_fb};
            repeat(12) begin @(posedge clk); cycle_count = cycle_count + 1; end
            enc_count = enc_count + 1;
        end

        // Random until 10000+ cycles
        while (cycle_count < 10200) begin
            key       = {lfsr, lfsr, lfsr, lfsr};
            lfsr = {lfsr[30:0], lfsr_fb};
            plaintext = {lfsr, lfsr, lfsr, lfsr};
            lfsr = {lfsr[30:0], lfsr_fb};
            repeat(12) begin @(posedge clk); cycle_count = cycle_count + 1; end
            enc_count = enc_count + 1;
        end

        #100; \$finish;
    end

    initial begin #5000000; \$finish; end
endmodule
VEOF

    echo "  Compiling..."
    iverilog -o "${SIM_DIR}/${VARIANT}_wrap.vvp" \
        aes_sbox.v \
        "${VARIANT}.v" \
        "${SIM_DIR}/${VARIANT}_wrap_tb.v" \
        2>&1 | tee "${SIM_DIR}/${VARIANT}_compile.log"

    echo "  Simulating..."
    cd "$VCD_DIR"
    vvp "../${SIM_DIR}/${VARIANT}_wrap.vvp" 2>&1 | tee "../${SIM_DIR}/${VARIANT}_sim.log"
    cd "$SCRIPT_DIR"

    if [ -f "${VCD_DIR}/${VARIANT}.vcd" ]; then
        echo "  ✓ ${VCD_DIR}/${VARIANT}.vcd"
    else
        echo "  ✗ VCD generation failed!"
    fi
    echo ""
done

# ============================================================
# Combined testbenches (for comparison analysis)
# ============================================================
echo "--------------------------------------------------------------"
echo " [BONUS] Combined ALU Testbench (all 4 in parallel)"
echo "--------------------------------------------------------------"
echo "  Compiling..."
iverilog -o "${SIM_DIR}/alu_tb.vvp" \
    alu_clean.v alu_trojan_comb.v alu_trojan_seq.v alu_trojan_counter.v \
    alu_tb.v 2>&1 | tee "${SIM_DIR}/alu_compile.log"
echo "  Simulating..."
cd "$VCD_DIR"
vvp "../${SIM_DIR}/alu_tb.vvp" 2>&1 | tee "../${SIM_DIR}/alu_sim.log"
cd "$SCRIPT_DIR"
echo ""

echo "--------------------------------------------------------------"
echo " [BONUS] Combined AES Testbench (clean vs trojan)"
echo "--------------------------------------------------------------"
echo "  Compiling..."
iverilog -o "${SIM_DIR}/aes_tb.vvp" \
    aes_sbox.v aes_clean.v aes_trojan.v \
    aes_tb.v 2>&1 | tee "${SIM_DIR}/aes_compile.log"
echo "  Simulating..."
cd "$VCD_DIR"
vvp "../${SIM_DIR}/aes_tb.vvp" 2>&1 | tee "../${SIM_DIR}/aes_sim.log"
cd "$SCRIPT_DIR"
echo ""

# ---- Summary ----
echo "============================================================"
echo " Simulation Complete — 6 Individual + 2 Combined VCDs"
echo "============================================================"
echo " VCD files:"
ls -lh "${VCD_DIR}"/*.vcd 2>/dev/null || echo "  (none found)"
echo ""
echo " Simulation logs:"
ls -lh "${SIM_DIR}"/*.log 2>/dev/null || echo "  (none found)"
echo "============================================================"
