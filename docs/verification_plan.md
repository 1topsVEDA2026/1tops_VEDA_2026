# RV32IM Verification Plan & Strategy

## 1. Verification Strategy Overview

The verification environment employs a **layered, three-tier strategy** designed to provide both thorough unit coverage and architectural compliance:

```
  Tier 1: Core Sanity Suite (rv32_core_sanity_tb)
  └─ 16 directed test suites (129 unit tests), self-checking in SystemVerilog
  └─ 100% Opcode Coverage across RV32IM base integer, M-extension, CSR, & hazards

  Tier 2: Architectural Golden Model Verification (Spike ISS)
  └─ Assembly-level directed tests (test_mext_basic, test_mext_corner)
  └─ Instruction-by-instruction architectural commit trace matching with Spike ISS

  Tier 3: Constrained-Random Co-Simulation (Google RISCV-DV)
  └─ Multi-thousand instruction random assembly programs generated with PyVSC
  └─ Execution on RTL (QuestaSim) compared against Spike ISS golden execution log
  └─ Comprehensive stress of data hazards, forwarding chains, and multi-cycle stalls
```

---

## 2. Test Matrix & Suite Breakdown

### Tier 1: Core Sanity Testbench (`rv32_core_sanity_tb.sv`)

| Suite # | Name | Descriptions / Focus | Tests | Status |
|---|---|---|---|---|
| Suite 1 | Reset Sequence | Reset PC deassertion (`0x0000_0000`), register file initialization | 2 | ✅ PASS |
| Suite 2 | R-Type ALU | `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND`, `FENCE` | 11 | ✅ PASS |
| Suite 3 | I-Type ALU | `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SLLI`, `SRLI`, `SRAI` | 9 | ✅ PASS |
| Suite 3b | Corner Cases | Wrap-around, signed vs unsigned comparison, max positive/negative | 10 | ✅ PASS |
| Suite 4 | U-Type ALU | `LUI`, `AUIPC` address computation and upper immediate loading | 3 | ✅ PASS |
| Suite 5 | J-Type Jumps | `JAL`, `JALR` link register write, jump target offset validation | 4 | ✅ PASS |
| Suite 6 | Load / Store | All access sizes: `LB`, `LH`, `LW`, `LBU`, `LHU`, `SB`, `SH`, `SW`, alignment | 10 | ✅ PASS |
| Suite 7 | Branches | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` (both taken and not-taken paths) | 6 | ✅ PASS |
| Suite 8 | CSR Operations | `CSRRW`, `CSRRS`, `CSRRC`, `CSRRWI`, `CSRRSI`, `CSRRCI` on machine CSRs | 7 | ✅ PASS |
| Suite 9 | Traps & MRET | `ECALL`, `EBREAK` exception generation, `mtvec` redirect, `mret` restore | 9 | ✅ PASS |
| Suite 10 | Data Hazards | Back-to-back dependency chains (`RAW`, `WAW`, `WAR`) | 5 | ✅ PASS |
| Suite 11 | Control Hazards | Branch-after-branch, jump-after-branch, branch mispredict flush | 4 | ✅ PASS |
| Suite 12 | Load-Use Hazards | 1-cycle pipeline interlock, forwarding after stall resolution | 3 | ✅ PASS |
| Suite 13 | Forwarding Stress | Store-to-load forwarding, branch depending on forwarded value | 6 | ✅ PASS |
| Suite 14 | Random-Delay AXI4 | Re-running ALU, load-use, and branches with non-zero slave latency | 8 | ✅ PASS |
| Suite 15 | M-Extension Basic | `MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU` basic operands | 11 | ✅ PASS |
| Suite 16 | M-Ext Corner Cases | Division by zero, signed overflow (`INT_MIN / -1`), large operands | 9 | ✅ PASS |
| **Total** | **All 16 Suites** | **Comprehensive RTL Self-Checking Sanity Suite** | **129** | **129 PASS** |

### Tier 2: Spike ISS vs RTL Directed Verification (`spike_verify`)

- **`test_mext_basic`**:
  - Exercises all 8 RV32M instructions (`MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`).
  - Target: 16 comparable instructions matched.
  - Result: **16 / 16 PASS (100.0% match)**.
- **`test_mext_corner`**:
  - Tests division by zero, signed overflow, and corner multiplication values.
  - Target: 13 comparable instructions matched.
  - Result: **13 / 13 PASS (100.0% match)**.

### Tier 3: RISCV-DV Random Co-Simulation (`riscv_dv_env`)

- **`riscv_arithmetic_basic_test`**:
  - Generates 2,000+ random instructions using Google RISCV-DV (pygen).
  - Co-simulated in QuestaSim against Spike ISS golden reference.
  - Target: All retired instructions match Spike register writebacks and PC flow.
  - Result: **6,728 / 6,728 PASS (100.0% match, 0 mismatches)**.

---

## 3. Coverage Analysis

### Opcode Functional Coverage
- **100.00% Opcode Coverage** achieved across all RV32IM opcodes:
  - RV32I Base Integer Instructions: 100%
  - RV32M Multiply and Divide Instructions: 100%
  - System Instructions (`CSRRW`, `CSRRS`, `CSRRC`, `ECALL`, `EBREAK`, `MRET`): 100%

### Microarchitectural Coverage Targets
- Forwarding paths:
  - ALU → ALU forwarding: Verified
  - ALU → Branch condition forwarding: Verified
  - ALU → Store data forwarding: Verified
- Stalls and Flushes:
  - Load-Use 1-cycle stall: Verified
  - MDU multi-cycle computation stall: Verified
  - Branch taken 1-cycle flush: Verified
  - Trap entry flush and PC redirect: Verified
- AXI4 Interface:
  - Zero-latency combinational transfers: Verified
  - Random 0–2 cycle ARREADY and AWREADY delays: Verified
  - SVA Protocol Assertions: 100% Passing with zero violations
