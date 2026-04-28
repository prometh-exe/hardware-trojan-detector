#!/bin/bash
# ============================================================================
# run_all.sh — Master Automation Script
# Runs the complete Hardware Security Analysis pipeline:
#   1. Synthesis   (Yosys)
#   2. Simulation  (Icarus Verilog)
#   3. Analysis    (MATLAB / Octave)
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Hardware Security Analysis Framework — Master Pipeline    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "Started at: ${TIMESTAMP}"
echo ""

# ---- Step 1: Synthesis ----
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW} STEP 1/3: Yosys Synthesis${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if command -v yosys &> /dev/null; then
    bash "${SCRIPT_DIR}/synthesize.sh"
    echo -e "${GREEN}✓ Synthesis completed${NC}"
else
    echo -e "${RED}⚠ Yosys not found — skipping synthesis step${NC}"
    echo "  Install Yosys: sudo apt install yosys (Linux) or brew install yosys (macOS)"
fi
echo ""

# ---- Step 2: Simulation ----
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW} STEP 2/3: Icarus Verilog Simulation${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if command -v iverilog &> /dev/null; then
    bash "${SCRIPT_DIR}/simulate.sh"
    echo -e "${GREEN}✓ Simulation completed${NC}"
else
    echo -e "${RED}⚠ Icarus Verilog not found — skipping simulation step${NC}"
    echo "  Install: sudo apt install iverilog (Linux) or brew install icarus-verilog (macOS)"
fi
echo ""

# ---- Step 3: MATLAB/Octave Analysis ----
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW} STEP 3/3: MATLAB / Octave Analysis${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if command -v matlab &> /dev/null; then
    echo "  Running MATLAB analysis..."
    matlab -batch "run('${SCRIPT_DIR}/analyze_security.m')" 2>&1
    echo -e "${GREEN}✓ MATLAB analysis completed${NC}"
elif command -v octave &> /dev/null; then
    echo "  Running Octave analysis..."
    octave --no-gui "${SCRIPT_DIR}/analyze_security.m" 2>&1
    echo -e "${GREEN}✓ Octave analysis completed${NC}"
else
    echo -e "${RED}⚠ Neither MATLAB nor Octave found — skipping analysis step${NC}"
    echo "  Install: sudo apt install octave (Linux) or brew install octave (macOS)"
fi
echo ""

# ---- Final Summary ----
TIMESTAMP_END=$(date '+%Y-%m-%d %H:%M:%S')
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Pipeline Complete                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "Finished at: ${TIMESTAMP_END}"
echo ""
echo "Generated outputs:"
echo "  netlists/  — Gate-level netlists (Yosys)"
echo "  vcd/       — VCD waveform files (Icarus)"
echo "  sim/       — Simulation logs"
echo "  results/   — Analysis figures and reports (MATLAB)"
echo ""
echo "Next steps:"
echo "  1. Open VCD files in GTKWave for waveform inspection"
echo "  2. Review analysis plots in results/ directory"
echo "  3. Compare gate counts between clean and Trojan netlists"
echo ""
