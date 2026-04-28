# Hardware Security Analysis Framework

A complete mini EDA security tool for detecting Hardware Trojans in RTL designs through side-channel analysis. This framework includes clean and Trojan-infected Verilog modules, testbenches, synthesis/simulation automation, and MATLAB-based statistical detection.

---

## Project Structure

```
├── RTL Design Files (Part 1)
│   ├── alu_clean.v              # Golden reference 4-bit ALU
│   ├── alu_trojan_comb.v        # Combinational Trojan (flips LSB)
│   ├── alu_trojan_seq.v         # Sequential Trojan (8-cycle trigger)
│   ├── alu_trojan_counter.v     # Counter Trojan (every 10,000th op)
│   ├── aes_sbox.v               # Shared AES S-Box module
│   ├── aes_clean.v              # Clean AES-128 encryption
│   └── aes_trojan.v             # AES-128 with key-leaking Trojan
│
├── Testbenches (Part 2)
│   ├── alu_tb.v                 # ALU testbench (all 4 variants)
│   └── aes_tb.v                 # AES testbench (clean vs Trojan)
│
├── Automation Scripts (Part 3)
│   ├── synthesize.sh            # Yosys synthesis → gate-level netlists
│   ├── simulate.sh              # Icarus Verilog simulation → VCD files
│   └── run_all.sh               # Master pipeline script
│
├── analyze_security.m           # MATLAB/Octave side-channel analysis
└── README.md                    # This file
```

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| **Icarus Verilog** | RTL simulation | `sudo apt install iverilog` |
| **Yosys** | Logic synthesis | `sudo apt install yosys` |
| **MATLAB/Octave** | Statistical analysis | `sudo apt install octave` |
| **GTKWave** (optional) | VCD waveform viewer | `sudo apt install gtkwave` |

## Quick Start

```bash
# Run the complete pipeline
chmod +x run_all.sh synthesize.sh simulate.sh
./run_all.sh

# Or run individual steps:
./synthesize.sh    # Step 1: Yosys synthesis
./simulate.sh      # Step 2: Icarus simulation
octave analyze_security.m  # Step 3: Analysis
```

## Trojan Descriptions

### ALU Trojans

| Variant | Trigger | Payload |
|---------|---------|---------|
| **Combinational** | `A == 4'b1111 && B == 4'b1111` | Flips LSB of result |
| **Sequential** | 8-cycle sequence: A=1,2,...,8 with op=ADD | Inverts result for 4 cycles |
| **Counter** | Every 10,000th clock cycle | Forces result to 0000 |

### AES Trojan

The AES Trojan maintains **functionally correct encryption** but adds a hidden `trojan_leak` register that XORs key bits when `plaintext[7:0] == 8'hFF`. This creates detectable extra switching activity in power/VCD analysis without corrupting the ciphertext.

## Port Specifications

**ALU** (all variants identical):
```
A[3:0], B[3:0], op[1:0], result[3:0], clk, rst
```

**AES** (both variants identical):
```
clk, rst, key[127:0], plaintext[127:0], ciphertext[127:0]
```

## Output Files

After running the pipeline:

- `netlists/` — Gate-level Verilog netlists + JSON + synthesis logs
- `vcd/` — VCD waveform files for GTKWave inspection
- `sim/` — Compilation and simulation logs
- `results/` — Analysis plots and detection report
