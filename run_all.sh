#!/bin/bash
# ============================================================================
# run_all.sh — Master Automation Script (ZERO MANUAL STEPS)
# Executes the complete Hardware Security Analysis pipeline:
#   1. Synthesis   (Yosys)
#   2. Simulation  (Icarus Verilog) — generates 6 individual VCDs
#   3. Analysis    (MATLAB / Octave) — all engines + PDF report
#
# Requirements: Icarus Verilog, Yosys, MATLAB or GNU Octave
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Hardware Security Analysis Framework — Master Pipeline    ║"
echo "║          Fully Automated — Zero Manual Steps                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "Started at: ${TIMESTAMP}"
echo ""

ERRORS=0

# ---- Dependency Check ----
echo -e "${YELLOW}━━━ Checking Dependencies ━━━${NC}"
for tool in iverilog vvp yosys; do
    if command -v $tool &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $tool found: $(which $tool)"
    else
        echo -e "  ${RED}✗${NC} $tool NOT found"
        ERRORS=$((ERRORS + 1))
    fi
done

# Check for MATLAB or Octave
MATLAB_CMD=""
if command -v matlab &> /dev/null; then
    MATLAB_CMD="matlab -batch"
    echo -e "  ${GREEN}✓${NC} MATLAB found"
elif command -v octave &> /dev/null; then
    MATLAB_CMD="octave --no-gui --eval"
    echo -e "  ${GREEN}✓${NC} GNU Octave found"
else
    echo -e "  ${RED}✗${NC} Neither MATLAB nor Octave found"
    ERRORS=$((ERRORS + 1))
fi

if [ $ERRORS -gt 0 ]; then
    echo -e "\n${RED}Missing $ERRORS dependencies. Install them first:${NC}"
    echo "  sudo apt install iverilog yosys octave"
    echo "  (or: brew install icarus-verilog yosys octave)"
    exit 1
fi
echo ""

# ---- Step 1: Synthesis ----
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW} STEP 1/3: Yosys Synthesis${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
bash "${SCRIPT_DIR}/synthesize.sh"
echo -e "${GREEN}✓ Synthesis completed${NC}"
echo ""

# ---- Step 2: Simulation ----
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW} STEP 2/3: Icarus Verilog Simulation (6 VCDs)${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
bash "${SCRIPT_DIR}/simulate.sh"
echo -e "${GREEN}✓ Simulation completed — 6 individual VCDs generated${NC}"
echo ""

# ---- Step 3: MATLAB/Octave Analysis ----
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW} STEP 3/3: MATLAB / Octave Analysis + PDF Report${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  Running report_gen (calls all analysis engines automatically)..."
$MATLAB_CMD "cd('${SCRIPT_DIR}'); report_gen();" 2>&1
echo -e "${GREEN}✓ Analysis and PDF report completed${NC}"
echo ""

# ---- Verify Outputs ----
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW} Output Verification${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

check_output() {
    if [ -f "$1" ]; then
        echo -e "  ${GREEN}✓${NC} $1 ($(ls -lh "$1" | awk '{print $5}'))"
    else
        echo -e "  ${RED}✗${NC} $1 MISSING"
    fi
}

echo " VCD Files (6 individual):"
check_output "vcd/alu_clean.vcd"
check_output "vcd/alu_trojan_comb.vcd"
check_output "vcd/alu_trojan_seq.vcd"
check_output "vcd/alu_trojan_counter.vcd"
check_output "vcd/aes_clean.vcd"
check_output "vcd/aes_trojan.vcd"

echo ""
echo " Analysis Outputs:"
check_output "results/hardware_security_report.pdf"
check_output "results/analysis_report.txt"
check_output "results/power_deviation.png"
check_output "results/zscore_detection.png"
check_output "results/pca_clusters.png"
check_output "results/ml_detection.png"
check_output "results/dpa_correlation.png"

echo ""
echo " Synthesis Netlists:"
check_output "netlists/alu_clean_netlist.v"
check_output "netlists/aes_clean_netlist.v"

# ---- Final Summary ----
TIMESTAMP_END=$(date '+%Y-%m-%d %H:%M:%S')
echo ""
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║               Pipeline Complete — All Steps Done            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "Started:  ${TIMESTAMP}"
echo "Finished: ${TIMESTAMP_END}"
echo ""
echo "To inspect results:"
echo "  gtkwave vcd/alu_clean.vcd              # View waveforms"
echo "  open results/hardware_security_report.pdf  # View report"
echo "  matlab -r trojan_dashboard             # Launch interactive GUI"
echo ""
