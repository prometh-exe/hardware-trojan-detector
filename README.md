# Hardware Security Analysis Framework

A complete mini EDA security tool for detecting Hardware Trojans in RTL designs through side-channel analysis. This framework includes clean and Trojan-infected Verilog modules, testbenches, synthesis/simulation automation, and a full MATLAB-based analysis engine with ML detection and DPA.

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
├── MATLAB Analysis Engine (Part 4)
│   ├── parse_vcd.m              # Universal VCD parser → toggle vectors
│   ├── power_model.m            # P = α×C×V²×f dynamic power estimation
│   ├── zscore_detect.m          # Z-score anomaly detection (±2.5σ)
│   ├── pca_engine.m             # PCA cluster separation analysis
│   ├── ml_detect.m              # Isolation Forest ML detection
│   ├── dpa_engine.m             # Differential Power Analysis (CPA)
│   ├── report_gen.m             # Auto-generate PDF report
│   └── analyze_security.m       # Standalone analysis script
│
├── Interactive Dashboard (Part 5)
│   └── trojan_dashboard.m       # MATLAB App — full interactive GUI
│
└── README.md
```

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| **Icarus Verilog** | RTL simulation | `sudo apt install iverilog` |
| **Yosys** | Logic synthesis | `sudo apt install yosys` |
| **MATLAB/Octave** | Analysis engine | `sudo apt install octave` |
| **GTKWave** (optional) | VCD viewer | `sudo apt install gtkwave` |

## Quick Start

```bash
# Run the complete pipeline
chmod +x run_all.sh synthesize.sh simulate.sh
./run_all.sh

# Or run individual steps:
./synthesize.sh                    # Step 1: Yosys synthesis
./simulate.sh                     # Step 2: Icarus simulation
matlab -batch "report_gen"         # Step 3: Full analysis + PDF report

# Or in Octave:
octave --no-gui -e "report_gen"
```

## Part 4 — MATLAB Analysis Engine

The analysis pipeline is a connected set of MATLAB/Octave scripts:

```
parse_vcd.m → power_model.m → zscore_detect.m
                             → pca_engine.m
                             → ml_detect.m
                             → dpa_engine.m
                                    ↓
                              report_gen.m → PDF Report
```

| Script | Method | Output |
|--------|--------|--------|
| `parse_vcd.m` | VCD parsing → toggle vectors | Structured signal data |
| `power_model.m` | P = α×C×V²×f estimation | Power deviation (mW) |
| `zscore_detect.m` | Z-score (±2.5σ threshold) | Ranked suspicious signals |
| `pca_engine.m` | PCA + Mahalanobis distance | Cluster plots, outliers |
| `ml_detect.m` | Isolation Forest | Precision, Recall, F1, ROC, AUC |
| `dpa_engine.m` | CPA correlation attack | Recovered key bytes |
| `report_gen.m` | Aggregate all results | PDF report |

## Part 5 — Interactive Dashboard

Launch the GUI with:
```matlab
trojan_dashboard
```

**Features:**
- **VCD Upload** — File picker for Clean and Trojan VCD files
- **Analysis Dropdown** — Select from 5 analysis views:
  - Toggle Comparison (Bar Chart)
  - Power Deviation (Heat Map)
  - PCA Clusters (Scatter Plot)
  - Anomaly Scores (Timeline)
  - Suspicious Signals (Red Flags)
- **Generate PDF Report** — One-click button triggers `report_gen.m`
- Dark-themed UI with interactive plots

## Trojan Descriptions

### ALU Trojans

| Variant | Trigger | Payload |
|---------|---------|---------|
| **Combinational** | `A == 4'b1111 && B == 4'b1111` | Flips LSB of result |
| **Sequential** | 8-cycle sequence: A=1,2,...,8 with op=ADD | Inverts result for 4 cycles |
| **Counter** | Every 10,000th clock cycle | Forces result to 0000 |

### AES Trojan

Maintains **functionally correct encryption** but adds a hidden `trojan_leak` register that XORs key bits when `plaintext[7:0] == 8'hFF`, creating detectable extra switching activity for side-channel analysis.

## Port Specifications

**ALU** (all variants identical):
```verilog
A[3:0], B[3:0], op[1:0], result[3:0], clk, rst
```

**AES** (both variants identical):
```verilog
clk, rst, key[127:0], plaintext[127:0], ciphertext[127:0]
```

## Output Files

After running the full pipeline:

```
├── netlists/          # Gate-level Verilog netlists + synthesis logs
├── vcd/               # VCD waveform files
├── sim/               # Compilation and simulation logs
└── results/
    ├── hardware_security_report.pdf
    ├── analysis_report.txt
    ├── power_deviation.png
    ├── power_traces.png
    ├── zscore_detection.png
    ├── pca_clusters.png
    ├── ml_detection.png
    ├── dpa_correlation.png
    └── analysis_workspace.mat
```
