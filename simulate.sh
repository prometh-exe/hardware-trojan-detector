#!/bin/bash
# ============================================================================
# simulate.sh — Icarus Verilog Simulation Script
# Compiles and runs all testbenches, generates VCD waveform files
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

# ---- Compile & Run ALU Testbench ----
echo "--------------------------------------------------------------"
echo " [1/2] ALU Testbench"
echo "--------------------------------------------------------------"
echo "  Compiling..."
iverilog -o "${SIM_DIR}/alu_tb.vvp" \
    alu_clean.v \
    alu_trojan_comb.v \
    alu_trojan_seq.v \
    alu_trojan_counter.v \
    alu_tb.v \
    2>&1 | tee "${SIM_DIR}/alu_compile.log"

echo "  Running simulation..."
cd "$VCD_DIR"
vvp "../${SIM_DIR}/alu_tb.vvp" 2>&1 | tee "../${SIM_DIR}/alu_sim.log"
cd "$SCRIPT_DIR"

if [ -f "${VCD_DIR}/alu_all.vcd" ]; then
    echo "  ✓ ALU VCD generated: ${VCD_DIR}/alu_all.vcd"
    ls -lh "${VCD_DIR}/alu_all.vcd"
else
    echo "  ✗ ALU VCD generation failed!"
fi
echo ""

# ---- Compile & Run AES Testbench ----
echo "--------------------------------------------------------------"
echo " [2/2] AES Testbench"
echo "--------------------------------------------------------------"
echo "  Compiling..."
iverilog -o "${SIM_DIR}/aes_tb.vvp" \
    aes_sbox.v \
    aes_clean.v \
    aes_trojan.v \
    aes_tb.v \
    2>&1 | tee "${SIM_DIR}/aes_compile.log"

echo "  Running simulation..."
cd "$VCD_DIR"
vvp "../${SIM_DIR}/aes_tb.vvp" 2>&1 | tee "../${SIM_DIR}/aes_sim.log"
cd "$SCRIPT_DIR"

if [ -f "${VCD_DIR}/aes_all.vcd" ]; then
    echo "  ✓ AES VCD generated: ${VCD_DIR}/aes_all.vcd"
    ls -lh "${VCD_DIR}/aes_all.vcd"
else
    echo "  ✗ AES VCD generation failed!"
fi
echo ""

# ---- Summary ----
echo "============================================================"
echo " Simulation Complete"
echo "============================================================"
echo " VCD files:"
ls -lh "${VCD_DIR}"/*.vcd 2>/dev/null || echo "  (none found)"
echo ""
echo " Simulation logs:"
ls -lh "${SIM_DIR}"/*.log 2>/dev/null || echo "  (none found)"
echo "============================================================"
