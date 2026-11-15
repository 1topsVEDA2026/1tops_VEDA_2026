# 1TOPS Secure IoT SoC

**RV32IM RISC-V Processor with ASCON-128 Cryptographic Accelerator**

| Parameter | Value |
|-----------|-------|
| Core | RV32IM, 3-Stage Pipelined (IF-DE-MW) |
| Multiplier | Radix-4 Booth (3-cycle), Restoring Divider (33-cycle) |
| Bus | Dual AXI4 Master (IMEM + DMEM) |
| Accelerator | ASCON-128 AEAD Encryption (AXI4-Lite, 0x9000) |
| Peripherals | GPIO, UART, SPI, Timer, Watchdog, PLIC, CLINT (APB) |
| Process | 28nm MPW (Tape-out: December 2026) |
| Training | VSI (VLSI System Integration) |
| Institute | PSG College of Technology |

---

## Signoff Status

**G0-G6: 94/94 Items Closed (84 Done + 10 N/A)**

| Gate | Description | Done | N/A | Total | Status |
|------|-------------|------|-----|-------|--------|
| G0 | Tools and Environment | 7 | 0 | 7/7 | Closed |
| G1 | Specification and Architecture | 15 | 0 | 15/15 | Closed |
| G2 | RTL Design - Core | 11 | 2 | 13/13 | Closed |
| G3 | SoC Integration | 12 | 4 | 16/16 | Closed |
| G4 | Unit and Core Sanity | 14 | 0 | 14/14 | Closed |
| G5 | SW and Random Streams | 10 | 0 | 10/10 | Closed |
| G6 | SoC Verification | 15 | 4 | 19/19 | Closed |

---

## Verification Results

| Tier | Test Suite | Tests | Result |
|------|-----------|-------|--------|
| Core Sanity (QuestaSim) | 16 suites, 129 directed tests | 129 | 129/129 PASS |
| Spike ISS Co-Simulation | Instruction-level trace compare | 129 | 100% match |
| RISCV-DV Random Regression | Arithmetic, M-ext, Random | 3 | 3/3 PASS (7,200 instr) |
| AXI4 Latency Stress | Random slave delay | 8 | 8/8 PASS |
| Peripheral UVM (No-Core) | 7 APB peripherals | 7 | 7/7 PASS, 0 UVM errors |
| Full SoC Integration | 8 firmware-driven tests | 8 | 8/8 PASS |
| ASCON-128 Security | Attack scenarios | 10 | 10/10 blocked |
| Dhrystone 2.1 Benchmark | 500 runs on Spike | - | 1.281 DMIPS/MHz |
| SpyGlass Core Lint | VC Static | - | 0 errors |
| SpyGlass SoC Lint + CDC | 39 modules | - | 0 errors |

---

## Quick Start

Run the complete regression suite:

```bash
make regression
```

Individual verification tiers:

```bash
make sanity       # Core Sanity Testbench (129 tests)
make spike        # Spike ISS directed verification
make riscv_dv     # RISCV-DV random co-simulation
make clean        # Clean build artifacts
```

---

## Architecture

```
                     +------------------------------------------+
                     |         RV32_CORE_TOP (RV32IM)           |
                     +------------------------------------------+
                                        |
       +--------------------------------+--------------------------------+
       |                                |                                |
  STAGE 1: IF                     STAGE 2: DE                     STAGE 3: MW
  - PC Generation                - 32x32 Register File           - AXI4 DMEM Master
  - Next-PC Mux                  - Immediate Generator            - Byte Enables (wstrb)
  - AXI4 IMEM Master (AR/R)     - RV32I ALU                      - Writeback Mux
  - pipe_if_de Register         - Booth Radix-4 MDU              - Load Sign/Zero Extend
                                 - Branch Comparator
                                 - CSR Unit (13 M-mode CSRs)
                                 - Hazard and Forwarding Unit
```

---

## Repository Structure

```
.
|-- Makefile                                    # Build and regression automation
|-- README.md
|
|-- rtl/
|   |-- core/
|   |   |-- rv32_pkg.sv                         # ISA constants, opcodes, types
|   |   |-- rv32_core_top.sv                    # Top-level core (AXI4 masters, pipeline)
|   |   |-- alu.sv                              # Arithmetic and Logic Unit
|   |   |-- decoder.sv                          # Instruction decoder
|   |   |-- controller.sv                       # Control signal generator
|   |   |-- register_file.sv                    # 32x32 register file
|   |   |-- branch_cmp.sv                       # Branch comparator
|   |   |-- mdu.sv                              # Multiply/Divide Unit
|   |   |-- booth_multiplier_radix4.sv          # Radix-4 Booth multiplier
|   |   |-- hazard_unit.sv                      # Forwarding, stall, flush logic
|   |   |-- csr_regfile.sv                      # CSR register file and trap logic
|   |   |-- imm_gen.sv                          # Immediate generator
|   |   |-- pipe_if_de.sv                       # IF-DE pipeline register
|   |   +-- pipe_de_mw.sv                       # DE-MW pipeline register
|   +-- memory/
|       |-- axi4_imem_slave.sv                  # AXI4 instruction memory slave
|       |-- axi4_dmem_slave.sv                  # AXI4 data memory slave
|       |-- instr_mem.sv                        # Instruction memory model
|       +-- data_mem.sv                         # Data memory model
|
|-- Ascon_Hardware_Accelerator/                 # ASCON-128 AEAD encryption engine
|   |-- Ascon.v                                 # Top-level ASCON module
|   |-- Encryption.v, Decryption.v              # Enc/Dec datapaths
|   |-- Permutation.v, sub_layer.v              # ASCON permutation rounds
|   |-- linear_layer.v, roundconstant.v         # Linear diffusion and constants
|   +-- tb_simple.v                             # ASCON standalone testbench
|
|-- Peripherals/                                # APB peripheral RTL
|   |-- GPIO.sv, UART.sv, SPI.sv                # I/O peripherals
|   |-- TIMER.sv, CLINT.sv, PLIC               # Timer, interrupt controller
|
|-- Memory/                                     # SoC memory modules
|   |-- I_SRAM_16Kb.sv                          # 16 KB instruction SRAM
|   +-- D_SRAM_16Kb.sv                          # 16 KB data SRAM
|
|-- docs/
|   |-- architecture.md                         # Microarchitecture specification
|   |-- verification_plan.md                    # 3-tier verification strategy
|   +-- debugging_guide.md                      # Setup and debug reference
|
|-- verification/
|   |-- core_sanity/
|   |   +-- rv32_core_sanity_tb.sv              # 129-test self-checking testbench (G4)
|   |-- spike_verify/
|   |   |-- compare_spike_rtl.py                # ISS trace comparison script
|   |   +-- rv32im_spike_compare_tb.sv          # Spike co-simulation testbench
|   |-- riscv_dv/
|   |   |-- run_riscv_dv.sh                     # RISCV-DV automation script
|   |   |-- run_3_tests.sh                      # 3-test regression runner
|   |   |-- rv32im_riscv_dv_tb.sv               # Random co-simulation testbench
|   |   +-- riscv_dv_summary.log                # Regression result: 3/3 PASS
|   +-- benchmark/
|       |-- dhrystone_spike.log                 # Benchmark result: 1.281 DMIPS/MHz
|       |-- dhrystone.hex, dhrystone.ihex       # Compiled benchmark binaries
|       +-- src/                                # Dhrystone 2.1 source code
|
|-- reports/
|   |-- 1TOPS_RISCV_SoC_Verification_Synthesis_Report.pdf
|   +-- spyglass/
|       |-- spyglass_lint_summary.rpt           # Core lint: 0 errors
|       |-- soc_top_vcs_lint.log                # SoC lint + CDC analysis
|       |-- rtl_keyword_search.rpt              # Boot mode / strap search
|       |-- vcs_lint.log                        # VCS compilation log
|       +-- verilator_lint.log                  # Verilator cross-check
|
|-- scripts/
|   |-- spyglass_soc_lint_cdc.tcl               # SpyGlass TCL run script
|   +-- spyglass_soc.prj                        # SpyGlass project file (39 modules)
```

---

## Tools and Environment (G0)

| Tool | Version | Vendor | Purpose |
|------|---------|--------|---------|
| VCS | U-2023.03 | Synopsys | RTL compilation and simulation |
| QuestaSim | 2022.4 | Siemens EDA | UVM testbench execution |
| SpyGlass (VC Static) | 2023.03 | Synopsys | Lint and CDC analysis |
| Design Compiler | T-2022.03-SP5 | Synopsys | RTL synthesis |
| RISC-V GNU Toolchain | GCC 16.1.0 | Open-source | Cross-compilation |
| Spike ISS | Latest | Open-source | Reference ISA simulator |
| Google RISCV-DV | Latest | Open-source | Random test generation |

---

## Memory Organisation

| Region | Base Address | Size | Bus |
|--------|-------------|------|-----|
| Boot ROM / ISRAM | 0x0000_0000 | 4 KB | AXI4 |
| Data SRAM | 0x0000_1000 | 4 KB | AXI4 |
| ASCON-128 | 0x0000_9000 | 256 B | AXI4-Lite |
| Peripherals | APB mapped | 256 B each | APB |

---

## Key Design Decisions

1. **Boot:** PC hardwired to 0x00000000. Single boot source (internal ROM). No boot mode strap.
2. **Privilege:** Machine mode only (M-mode). 13 CSRs with defined reset values.
3. **Hazards:** Dynamic data forwarding with load-use stall insertion. Flush on trap/branch redirect.
4. **MDU:** Start/done/stall handshake. Bounded latency (MUL: 3 cycles, DIV: 33 cycles).
5. **CDC:** Async inputs (uart_rx, gpio_in, ext_irq) documented for synchronizer insertion in physical design.

---

## Documentation

- [Microarchitecture Specification](docs/architecture.md)
- [Verification Plan and Coverage](docs/verification_plan.md)
- [Setup and Debugging Guide](docs/debugging_guide.md)
- [Full Verification and Synthesis Report (PDF)](reports/1TOPS_RISCV_SoC_Verification_Synthesis_Report.pdf)

---

*1TOPS Secure IoT SoC Project | PSG College of Technology | November 2026*
