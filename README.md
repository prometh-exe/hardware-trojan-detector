# Hardware Security Analysis Framework

A complete mini EDA security tool for detecting Hardware Trojans in RTL designs through side-channel analysis. Includes clean and Trojan-infected Verilog modules, testbenches, synthesis/simulation automation, a full MATLAB analysis engine with ML detection and DPA, and an interactive dashboard.

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
│   ├── alu_tb.v                 # ALU testbench (all 4 variants parallel)
│   └── aes_tb.v                 # AES testbench (clean vs Trojan)
│
├── Automation Scripts (Part 3)
│   ├── synthesize.sh            # Yosys synthesis → gate-level netlists
│   ├── simulate.sh              # Icarus Verilog → 6 individual VCDs
│   └── run_all.sh               # Master pipeline (zero manual steps)
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
│   └── trojan_dashboard.m       # MATLAB GUI — full interactive app
│
└── README.md
```

---

## Setup Instructions

### Prerequisites

| Tool | Version | Purpose | Install Command |
|------|---------|---------|----------------|
| **Icarus Verilog** | ≥ 10.0 | RTL simulation (iverilog + vvp) | `sudo apt install iverilog` |
| **Yosys** | ≥ 0.9 | Logic synthesis | `sudo apt install yosys` |
| **MATLAB** | R2020a+ | Analysis engine | [mathworks.com](https://mathworks.com) |
| *or* **GNU Octave** | ≥ 6.0 | Free MATLAB alternative | `sudo apt install octave` |
| **GTKWave** *(optional)* | ≥ 3.3 | VCD waveform viewer | `sudo apt install gtkwave` |

**MATLAB Toolboxes Required:**
- Core MATLAB (or GNU Octave)
- Statistics and Machine Learning Toolbox

### Installation

```bash
# Clone the repository
git clone https://github.com/prometh-exe/hardware-trojan-detector.git
cd hardware-trojan-detector

# Install dependencies (Ubuntu/Debian)
sudo apt update
sudo apt install iverilog yosys octave

# macOS (Homebrew)
brew install icarus-verilog yosys octave

# Make scripts executable
chmod +x run_all.sh synthesize.sh simulate.sh
```

---

## How to Run

### One-Command Full Pipeline (Zero Manual Steps)

```bash
./run_all.sh
```

This automatically executes:
1. **Yosys synthesis** → gate-level netlists in `netlists/`
2. **Icarus Verilog simulation** → 6 individual VCDs in `vcd/`
3. **MATLAB/Octave analysis** → plots + PDF report in `results/`

### Run Individual Steps

```bash
# Step 1: Synthesis only
./synthesize.sh

# Step 2: Simulation only (generates 6 VCDs)
./simulate.sh

# Step 3: Analysis only (requires VCDs from Step 2)
matlab -batch "report_gen"         # MATLAB
octave --no-gui --eval "report_gen"  # Octave

# Launch interactive dashboard
matlab -r "trojan_dashboard"
```

---

## Part 4 — MATLAB Analysis Engine

Connected pipeline of analysis scripts:

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

```matlab
trojan_dashboard
```

- **VCD Upload** — File picker for Clean and Trojan VCD files
- **Analysis Dropdown** — Toggle Comparison, Power Deviation, PCA Clusters, Anomaly Scores, Suspicious Signals
- **Generate PDF Report** — One-click button triggers `report_gen.m`
- Dark-themed UI with interactive plots

---

## Trojan Descriptions

### ALU Trojans (4-bit, identical ports)

| Variant | Trigger | Payload |
|---------|---------|---------|
| **Combinational** | `A == 4'b1111 && B == 4'b1111` | Flips LSB of result |
| **Sequential** | 8-cycle sequence: A=1,2,...,8 with op=ADD | Inverts result for 4 cycles |
| **Counter** | Every 10,000th clock cycle | Forces result to 0000 |

### AES Trojan

Maintains **functionally correct encryption** but adds a hidden `trojan_leak` register that XORs key bits when `plaintext[7:0] == 8'hFF`, creating detectable extra switching activity.

## Port Specifications

**ALU** (all variants identical):
```verilog
input  [3:0] A, B;
input  [1:0] op;
output [3:0] result;
input        clk, rst;
```

**AES** (both variants identical):
```verilog
input         clk, rst;
input  [127:0] key, plaintext;
output [127:0] ciphertext;
```

---

## Expected Outputs

| Output | Description |
|--------|-------------|
| **6 VCD Files** | One per design variant (4 ALU + 2 AES) |
| **Power Deviation Table** | Per signal, in milliwatts |
| **Z-Score Anomaly List** | Ranked suspicious signals |
| **PCA Scatter Plot** | Clean vs Trojan cluster separation |
| **ML Results** | Precision, Recall, F1, ROC per Trojan type |
| **DPA Traces** | Key byte correlation plots |
| **Dashboard** | Live interactive MATLAB App Designer app |

### Output Directory Structure

```
├── netlists/                          # Yosys synthesis output
│   ├── alu_clean_netlist.v
│   ├── alu_trojan_comb_netlist.v
│   ├── alu_trojan_seq_netlist.v
│   ├── alu_trojan_counter_netlist.v
│   ├── aes_clean_netlist.v
│   └── aes_trojan_netlist.v
│
├── vcd/                               # Simulation waveforms
│   ├── alu_clean.vcd
│   ├── alu_trojan_comb.vcd
│   ├── alu_trojan_seq.vcd
│   ├── alu_trojan_counter.vcd
│   ├── aes_clean.vcd
│   ├── aes_trojan.vcd
│   ├── alu_all.vcd                    # Combined ALU comparison
│   └── aes_all.vcd                    # Combined AES comparison
│
└── results/                           # Analysis output
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

### Sample Output: ML Detection Results

```
  ═══════════════════════════════════════════════════════
  ML Detection Results Summary
  ═══════════════════════════════════════════════════════
  Trojan Variant        Precision  Recall   F1       AUC
  ──────────────────────────────────────────────────────
  Combinational         0.9200     0.8800   0.8996   0.9450
  Sequential            0.9500     0.9100   0.9296   0.9680
  Counter               0.8800     0.8500   0.8647   0.9210
  ═══════════════════════════════════════════════════════
```

---

## Constraints

| Constraint | Specification |
|------------|--------------|
| Verilog Simulator | Icarus Verilog (free, open-source) |
| Synthesis Tool | Yosys (free, open-source) |
| MATLAB Toolboxes | Core MATLAB + Statistics and Machine Learning Toolbox only |
| Automation | `run_all.sh` executes entire pipeline with zero manual steps |
| Verilog Standard | Standard Verilog only — no SystemVerilog |
