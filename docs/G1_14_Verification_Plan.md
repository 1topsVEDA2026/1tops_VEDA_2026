# 1-TOPS VEDA — Verification Plan

**G1 item 1.14 — Verification plan (testplan) written**
**Team:** VEDA · PSG College of Technology
**Project:** 1-TOPS Secure IoT RISC-V SoC (RV32IM + ASCON-128)
**Revision:** 1.0 · 2026-11-15
**Based on:** `TOPS_FINAL/docs/verification_plan.md`, `1TOPS RISCV SoC Verification Strategy_v1.pdf`, actual results from TOPS_FINAL runs

This document consolidates the verification strategy and ties it to actual results already captured in the TOPS_FINAL regression. It closes G1 item 1.14 — feature-to-test-to-coverage-item mapping across all five verification phases.

---

## 1. Verification strategy overview

VEDA uses a **5-phase, layered verification approach** mapped onto the 1-TOPS Verification Strategy:

| Phase | Scope | Methodology | Tools | Status |
|---|---|---|---|---|
| 1 | Unit-level block verification | Directed SV testbenches per IP block | QuestaSim, waveform review | ✅ Done — 12 unit reports |
| 2 | Core sanity (RTL integration) | 16-suite self-checking testbench | QuestaSim | ✅ 129/129 PASS |
| 3 | Core with SW + random | Spike ISS co-simulation + RISCV-DV random | Spike, RISCV-DV, QuestaSim/VCS | ✅ 29/29 directed + 3/3 random (7,200 instr) |
| 4 | SoC without core (peripheral UVM AVIP) | UVM 1.1d APB AVIP against each peripheral | QuestaSim + UVM | ✅ 7/7 peripherals PASS |
| 5 | Full SoC (core + bridge + peripherals + ASCON) | Firmware-driven UVM tests | QuestaSim + UVM | ✅ 8/8 firmware tests PASS |

---

## 2. Feature → Test → Coverage mapping

### 2.1 Phase 1 — Unit-level verification

| Unit | Features verified | Testbench | Report |
|---|---|---|---|
| ALU | ADD/SUB/SLT/SLTU/AND/OR/XOR/SLL/SRL/SRA/LUI/AUIPC + corners | `tb_alu.sv` | `Unit_Level_Verification_v2/01_ALU_Verification.docx` |
| Branch comparator | BEQ/BNE/BLT/BGE/BLTU/BGEU signed+unsigned | `tb_branch_cmp.sv` | `02_BranchComparator_Verification.docx` |
| Register file | x0 hardwire, 32 regs R/W, bypass on same-cycle R/W | `tb_register_file.sv` | `03_RegisterFile_Verification.docx` |
| Data memory model | Byte/half/word access, sign-extend | — | `04_DataMemory_Verification.docx` |
| Instruction decoder | All RV32IM opcodes + funct3/funct7 | `tb_decoder.sv` | `05_InstructionDecoder_Verification.docx` |
| Immediate generator | I/S/B/U/J immediates | `tb_imm_gen.sv` | `06_ImmediateGenerator_Verification.docx` |
| Controller | Control signal correctness per opcode | — | `07_Controller_Verification.docx` |
| MUX2x1 | Basic selection | — | `08_MUX2x1_Verification.docx` |
| MUX3x1 writeback | ALU / MEM / MDU / CSR / PC+4 select | — | `09_MUX3x1_Writeback_Verification.docx` |
| Pipeline register IF→DE | Latch, flush, stall | — | `10_PipelineReg1_FirstReg_Verification.docx` |
| Pipeline register DE→MW | Latch, flush, stall | — | `11_PipelineReg2_SecondReg_Verification.docx` |
| Hazard unit | Forwarding, load-use, flush control | `tb_hazard_unit.sv` | `12_HazardUnit_Controller_Verification.docx` |

### 2.2 Phase 2 — Core sanity suite (`rv32_core_sanity_tb.sv`)

Self-checking 16-suite testbench; all 129 tests PASS on TOPS_FINAL.

| Suite # | Name | Features | Tests | Status |
|---|---|---|---|---|
| 1 | Reset Sequence | Reset PC = 0x0000_0000, regfile init | 2 | ✅ PASS |
| 2 | R-Type ALU | ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND/FENCE | 11 | ✅ PASS |
| 3 | I-Type ALU | ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI | 9 | ✅ PASS |
| 3b | Corner Cases | Wrap-around, signed vs unsigned, max positive/negative | 10 | ✅ PASS |
| 4 | U-Type ALU | LUI, AUIPC | 3 | ✅ PASS |
| 5 | J-Type Jumps | JAL, JALR + link register | 4 | ✅ PASS |
| 6 | Load / Store | LB/LH/LW/LBU/LHU/SB/SH/SW + alignment | 10 | ✅ PASS |
| 7 | Branches | BEQ/BNE/BLT/BGE/BLTU/BGEU taken + not-taken | 6 | ✅ PASS |
| 8 | CSR | CSRRW/CSRRS/CSRRC + I variants on M-mode CSRs | 7 | ✅ PASS |
| 9 | Traps & MRET | ECALL/EBREAK, mtvec redirect, mret restore | 9 | ✅ PASS |
| 10 | Data Hazards | RAW/WAW/WAR chains | 5 | ✅ PASS |
| 11 | Control Hazards | Branch-after-branch, jump-after-branch, flush | 4 | ✅ PASS |
| 12 | Load-Use | 1-cycle interlock + forwarding after stall | 3 | ✅ PASS |
| 13 | Forwarding Stress | Store-to-load fwd, branch on forwarded value | 6 | ✅ PASS |
| 14 | Random-Delay AXI4 | Non-zero slave latency (0–2 cycles) | 8 | ✅ PASS |
| 15 | M-Ext Basic | MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU | 11 | ✅ PASS |
| 16 | M-Ext Corner | DIV-by-zero, INT_MIN/-1, large operands | 9 | ✅ PASS |
| **Total** | | | **129** | **✅ 129 / 129 PASS** |

### 2.3 Phase 3 — Core with SW and Random streams

**3a. Spike ISS vs RTL directed verification:**

| Test | Instructions | Result (from `spike_verify/build/*/compare_result.txt`) |
|---|---|---|
| `test_mext_basic` | 16 (all 8 RV32M ops) | **16 / 16 PASS — 100 % match** |
| `test_mext_corner` | 13 (div-by-0, INT_MIN/-1, overflow) | **13 / 13 PASS — 100 % match** |

**3b. RISCV-DV random co-simulation** (TOPS_FINAL — latest run `riscv_dv_env/out_regression/riscv_dv_summary.log`, 11 Nov 2026):

| Test | Instructions matched | Result |
|---|---|---|
| `riscv_arithmetic_basic_test` | 973 | ✅ PASS |
| `riscv_mext_basic_test` | 2,323 | ✅ PASS |
| `riscv_rand_instr_test` | 3,904 | ✅ PASS |
| **Total** | **7,200** | **✅ 3 / 3 PASS** |

**3c. Benchmark:** Dhrystone 2.1 — `TOPS_FINAL/benchmark/dhrystone_spike.log`:
- 500 runs, 222,004 total cycles
- **1.281 DMIPS / MHz**

### 2.4 Phase 4 — SoC without core (peripheral UVM AVIP)

UVM 1.1d testbenches under `TOPS_Verification/UVM_TB/` — one per peripheral. Each uses the APB AVIP master agent driving the peripheral's slave port while the core is replaced by the AVIP.

| Peripheral | TB | Features verified | Result |
|---|---|---|---|
| GPIO | `UVM_TB/gpio` | 32-bit R/W, OE, input sync, IRQ | ✅ PASS (0 UVM_ERROR) |
| UART (16550) | `UVM_TB/uart` | TX, baud, FIFO, status regs | ✅ PASS |
| SPI master | `UVM_TB/spi` | Clock gen, 10-deep TX/RX FIFO, CS | ✅ PASS |
| Timer | `UVM_TB/timer` | Dual 32-bit counters, compare, prescaler, IRQ | ✅ PASS |
| Watchdog | `UVM_TB/watchdog` | Load/compare, timeout reset, IRQ | ✅ PASS |
| PLIC | `UVM_TB/plic` | 30 sources / 2 targets, priority, claim/complete | ✅ PASS |
| CLINT | `UVM_TB/clint` | Core-local timer + SW IRQs | ✅ PASS |
| **Total** | | | **✅ 7 / 7 PASS** |

### 2.5 Phase 5 — Full SoC (core + bridge + 7 peripherals + ASCON)

Firmware-driven UVM tests in `FUL_SOC_WITH_CORE/tests/`. Pre-compiled RISC-V firmware is loaded into IMEM at time 0; APB AVIP monitors (passive) observe all peripheral transactions for scoreboard checks.

| # | Test | What it verifies | Log | Result |
|---|---|---|---|---|
| 1 | `soc_boot_sanity_test` | Core boots; MUL 10×20 = 200 → GPIO | `logs/soc_boot_sanity_test.log` | ✅ PASS |
| 2 | `soc_gpio_write_test` | ALU pattern 0x55AA → GPIO write | `logs/soc_gpio_write_test.log` | ✅ PASS |
| 3 | `soc_uart_tx_test` | UART baud config + transmit 'A' | `logs/soc_uart_tx_test.log` | ✅ PASS |
| 4 | `soc_memory_test` | DMEM write / read-back → GPIO verify (0x5A) | `logs/soc_memory_test.log` | ✅ PASS |
| 5 | `soc_mext_test` | MUL + DIV + REM = 24 → GPIO verify | `logs/soc_mext_test.log` | ✅ PASS |
| 6 | `soc_reset_test` | Reset recovery, registers back to defaults | `logs/soc_reset_test.log` | ✅ PASS |
| 7 | `soc_stability_test` | 50 µs long-run, no deadlocks / hangs | `logs/soc_stability_test.log` | ✅ PASS |
| 8 | `subsystem_base_test` | Default firmware execution correct | `logs/subsystem_base_test.log` | ✅ PASS |
| **Total** | | | | **✅ 8 / 8 PASS** |

---

## 3. Coverage targets and closure

### 3.1 Opcode functional coverage (per TOPS_FINAL `verification_plan.md` §3)

| Group | Coverage | Status |
|---|---|---|
| RV32I base integer | 100 % | ✅ Closed |
| RV32M multiply / divide | 100 % | ✅ Closed |
| System instructions (CSRR*, ECALL, EBREAK, MRET) | 100 % | ✅ Closed |

### 3.2 Micro-architectural coverage

| Area | Item | Status |
|---|---|---|
| Forwarding | ALU → ALU | ✅ Verified |
| Forwarding | ALU → Branch condition | ✅ Verified |
| Forwarding | ALU → Store data | ✅ Verified |
| Stalls | Load-use 1-cycle stall | ✅ Verified |
| Stalls | MDU multi-cycle stall | ✅ Verified |
| Flushes | Branch-taken 1-cycle flush | ✅ Verified |
| Flushes | Trap entry flush + PC redirect | ✅ Verified |

### 3.3 AXI4 interface coverage

| Scenario | Status |
|---|---|
| Zero-latency combinational transfers | ✅ Verified |
| Random 0–2 cycle ARREADY / AWREADY delays | ✅ Verified (Suite 14) |
| SVA protocol assertions | ✅ 100 % passing, 0 violations |

### 3.4 Code coverage (open action)

| Metric | Target | Status |
|---|---|---|
| Statement | ≥ 95 % | ⚠ To be reported — run `urg` / Verdi on the QuestaSim coverage DB |
| Branch | ≥ 95 % | ⚠ To be reported |
| Toggle | ≥ 95 % | ⚠ To be reported |
| Expression | ≥ 95 % | ⚠ To be reported |

**Action:** Produce code-coverage merged report from TOPS_FINAL regression run; attach to this doc before G5 close.

---

## 4. Random-regression plan (G5 5.5)

**Current:** 3 directed random tests (7,200 instructions) in TOPS_FINAL.

**Target for G5 close:** N seeds — N to be agreed with coach from 1k – 10k seeds range. Proposed plan:

| Test | Seeds | Rationale |
|---|---|---|
| `riscv_arithmetic_basic_test` | 500 | Baseline coverage |
| `riscv_mext_basic_test` | 500 | M-ext specific stress |
| `riscv_rand_instr_test` | 1,000 | Mixed-opcode random |
| **Target total** | **2,000** | Within 1k – 10k guideline |

**Pass criterion:** 100 % Spike-RTL trace match, 0 mismatches across all seeds. Any mismatch is a P0 bug.

---

## 5. Bug tracking

All bugs discovered and resolved during verification are listed in `TOPS_FINAL/docs/debugging_guide.md` §4:

| # | Bug | Severity | Status |
|---|---|---|---|
| 1 | Base-address alignment (Spike 0x80000000 vs RTL 0x00000000) | P1 | ✅ Fixed — RESET_PC parameter added |
| 2 | Multi-cycle retirement duplicate logging | P2 | ✅ Fixed — `!stall_MW` gate added |
| 3 | AXI4 DMEM handshake latching in DM_IDLE | P1 | ✅ Fixed — latch AR/AW/W on handshake |
| 4 | Hex memory conversion byte-vs-word addressing | P2 | ✅ Fixed — convert_hex.py updated |
| 5 | PyVSC / PyBoolector API incompatibility | P3 | ✅ Fixed — monkey-patches applied |
| 6 | Pygen callstack generator missing attribute | P3 | ✅ Fixed — `num_of_sub_program=0` |

**Open bugs:** None P0/P1 open. One P3 to review:

| # | Issue | Severity | Action |
|---|---|---|---|
| S-1 | `csr_regfile.sv:106` — partial `mip` assignment inferring latch | P3 | Fix before RTL freeze |

---

## 6. Tools and infrastructure

| Tool | Version | License / source | Role |
|---|---|---|---|
| QuestaSim | 2022.4 | `1717@14.139.1.126` | Primary simulator |
| VCS | U-2023.03 | Synopsys | Alt. simulator, lint, RISCV-DV comp |
| SpyGlass (VC Static) | 2023.03 | Synopsys | Lint, CDC |
| Verdi | — | Synopsys | Waveform debug |
| RISC-V GCC | 16.1.0 | Open-source | Cross-compile |
| Spike ISS | v1.1.1+ | Open-source | Golden model |
| RISCV-DV | Latest | Google (Apache 2.0) | Random test gen |
| ASAP7 PDK | — | OSU / ASU open PDK | Synthesis |
| Design Compiler | T-2022.03-SP5 | Synopsys | Synthesis |

---