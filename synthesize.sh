#!/bin/bash
# ============================================================================
# synthesize.sh — Yosys Synthesis Script
# Runs Yosys synthesis on all Verilog RTL files, outputs gate-level netlists
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Output directory for netlists
NETLIST_DIR="netlists"
mkdir -p "$NETLIST_DIR"

echo "============================================================"
echo " Yosys Synthesis — Hardware Security Analysis Framework"
echo "============================================================"
echo ""

# List of RTL design files to synthesize (excluding testbenches & shared modules)
ALU_DESIGNS="alu_clean alu_trojan_comb alu_trojan_seq alu_trojan_counter"
AES_DESIGNS="aes_clean aes_trojan"

# Function to synthesize a single module
synthesize_module() {
    local MODULE_NAME="$1"
    local VERILOG_FILE="$2"
    local EXTRA_FILES="$3"
    local OUTPUT_FILE="${NETLIST_DIR}/${MODULE_NAME}_netlist.v"
    local JSON_FILE="${NETLIST_DIR}/${MODULE_NAME}_netlist.json"

    echo "--------------------------------------------------------------"
    echo " Synthesizing: ${MODULE_NAME}"
    echo "  Input:  ${VERILOG_FILE}"
    echo "  Output: ${OUTPUT_FILE}"
    echo "--------------------------------------------------------------"

    # Create Yosys script
    cat > "${NETLIST_DIR}/${MODULE_NAME}_synth.ys" << EOF
# Yosys synthesis script for ${MODULE_NAME}
read_verilog ${EXTRA_FILES} ${VERILOG_FILE}
hierarchy -check -top ${MODULE_NAME}
proc
opt
fsm
opt
memory
opt
techmap
opt
clean
# Write gate-level netlist
write_verilog -noattr ${OUTPUT_FILE}
write_json ${JSON_FILE}
# Print statistics
stat
EOF

    yosys -s "${NETLIST_DIR}/${MODULE_NAME}_synth.ys" 2>&1 | tee "${NETLIST_DIR}/${MODULE_NAME}_synth.log"

    if [ $? -eq 0 ]; then
        echo "  ✓ ${MODULE_NAME} synthesized successfully"
    else
        echo "  ✗ ${MODULE_NAME} synthesis FAILED"
        return 1
    fi
    echo ""
}

# ---- Synthesize ALU variants ----
echo ""
echo "========== ALU Synthesis =========="
for design in $ALU_DESIGNS; do
    synthesize_module "$design" "${design}.v" ""
done

# ---- Synthesize AES variants (need aes_sbox.v) ----
echo ""
echo "========== AES Synthesis =========="
for design in $AES_DESIGNS; do
    synthesize_module "$design" "${design}.v" "aes_sbox.v"
done

echo ""
echo "============================================================"
echo " Synthesis Complete — Netlists saved to ${NETLIST_DIR}/"
echo "============================================================"
ls -la "${NETLIST_DIR}"/*.v 2>/dev/null || echo "  (no netlist files found)"
echo ""
