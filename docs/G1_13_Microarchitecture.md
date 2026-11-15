# 1-TOPS VEDA — Micro-architecture Document

**G1 item 1.13 — Micro-architecture document complete**
**Team:** VEDA · PSG College of Technology
**Project:** 1-TOPS Secure IoT RISC-V SoC (RV32IM + ASCON-128)
**Covers:** per-stage datapath, control signals, hazard / forwarding logic, memory interface protocol
**Revision:** 1.0 · 2026-11-15
**Based on:** `TOPS_FINAL/docs/architecture.md` (repo), `RV32IM_Core_architecture_v3.png`, `ARCHITECTURE_RV32I_3_STAGE_PIPELINE.png`, synthesis area reports (ASAP7)

---

## Figures

| Fig | File | What it shows |
|---|---|---|
| Fig 1 | `figures/RV32IM_Core_architecture_v3.png` | Full RV32IM core block diagram (datapath + control) |
| Fig 2 | `figures/ARCHITECTURE_RV32I_3_STAGE_PIPELINE.png` | 3-stage pipeline detail with hazards and forwarding paths |

---

## 1. Architectural overview

The core implements **RV32IM** with M-mode CSR support and two independent AXI4 master ports.

- **ISA:** RV32IM (base 32-bit integer + multiply/divide)
- **Privilege:** Machine mode only (see Spec §1.3)
- **Pipeline:** 3-stage in-order (`IF → DE → MW`)
- **Bus:** Dual independent AXI4 32-bit masters (IMEM read-only; DMEM R/W)
- **ALU:** Full 32-bit, single-cycle
- **MDU:** Booth Radix-4 multiplier (3-cycle), restoring divider (33-cycle)
- **Hazard handling:** Dynamic forwarding, load-use stall, control-hazard flush, memory stall freeze
- **CSRs:** 13 M-mode CSRs (see Spec §1.4)

Synthesis footprint (ASAP7 7 nm TT 0.7 V 25 °C, from `syn_soc/reports/area.rpt`):

| Block | Area (µm²) | % of core |
|---|---|---|
| Register file (32×32 b + bypass + clock-gates) | 612.04 | 43.9 % |
| MDU (multiplier + divider) | 282.79 | 20.3 % |
| ALU | 123.08 | 8.8 % |
| CSR regfile | 117.25 | 8.4 % |
| Pipeline reg DE→MW | 74.49 | 5.3 % |
| Pipeline reg IF→DE | 43.03 | 3.1 % |
| Branch comparator | 22.57 | 1.6 % |
| Decoder | 10.72 | 0.8 % |
| Immediate generator | 5.06 | 0.4 % |
| Hazard unit | 2.51 | 0.2 % |
| Controller | 4.30 | 0.3 % |
| Core top glue | ~95 | 6.9 % |
| **Core total (rv32_core_top)** | **1,392.68** | **100 %** |

---

## 2. Pipeline stage breakdown

```
        ┌─────────────┐       ┌──────────────┐       ┌──────────────┐
        │  IF Stage   │ ────► │   DE Stage   │ ────► │   MW Stage   │
        │ Fetch & PC  │       │ Decode & Exe │       │ Mem & Reg WB │
        └─────────────┘       └──────────────┘       └──────────────┘
               │                      │                      │
               ▼                      ▼                      ▼
         AXI4 IMEM Bus         MDU / ALU / CSR         AXI4 DMEM Bus
```

### 2.1 Stage 1 — Instruction Fetch (IF)

**Program Counter Unit** (integrated inside `rv32_core_top.sv`, IF logic):

- Tracks current PC. Parameter `RESET_PC` (default `32'h0000_0000`) — can be set to `0x8000_0000` for Spike ISS co-simulation (test only, not for silicon).
- Register `pc_out_IF` is reset to `RESET_PC` on `rst_n` assertion.

**Next-PC multiplexer** (priority high → low):

1. Trap/interrupt redirect — PC ← `mtvec` when trap taken.
2. Exception return — PC ← `mepc` on `mret`.
3. Branch/Jump taken — PC ← `opr_res_DE` (ALU-computed target).
4. Sequential — PC ← `pc_out_IF + 4`.

**AXI4 IMEM master** — read-only (AR + R channels only).

- `imem_arvalid` driven continuously when `!stall_IF`.
- `imem_rready = 1'b1` always (core accepts data without back-pressure).
- `imem_arsize = 3'b010` (4-byte), `imem_arburst = 2'b01` (INCR), `imem_arlen = 8'd0` (single beat).
- `imem_arcache = 4'b0010` (normal non-cacheable bufferable), `imem_arprot = 3'b100` (instruction, non-secure).

**Pipeline register `pipe_if_de`** — latches `pc_out_IF` and the fetched instruction into DE stage when `ready_DE` and no flush. On `flush_DE` (branch taken, trap, mret), the register is cleared (valid = 0, instruction = NOP).

### 2.2 Stage 2 — Decode & Execute (DE)

**Decoder (`decoder.sv`):** Decodes RV32IM opcodes, funct3, funct7, source/dest register addresses, immediate type, execution class (ALU / MDU / BR / LOAD / STORE / CSR / SYS), memory access width (byte/half/word), load sign-extension flag.

**Controller (`controller.sv`):** From decoder outputs, generates:
- ALU operand selects (`alu_src_a`, `alu_src_b`: rs1 / rs2 / imm / PC).
- ALU operation code.
- Writeback source (`wb_src`: ALU / MDU / MEM / CSR / PC+4).
- Register-file write enable.
- MDU start pulse.
- CSR read / write enables.
- Branch comparator opcode.

**Register File (`register_file.sv`):**
- 32 × 32 b, x0 hardwired to 0.
- **Synchronous write** on falling clk edge (or rising edge of `clk_gated` per clock-gating output of DC — both read/write actually on same clock domain in post-synth).
- **Asynchronous read** with internal bypass — if an instruction writes rd and a later instruction reads the same register in the same cycle, the newer write value is returned.
- Area: 612 µm² (dominates core area — 44 %).

**Immediate Generator (`imm_gen.sv`):** Extracts and sign-extends I / S / B / U / J immediates per RISC-V spec.

**ALU (`alu.sv`):** Single-cycle execution of:
- Arithmetic: `ADD`, `SUB`, `SLT`, `SLTU`, `LUI`, `AUIPC`.
- Logical: `AND`, `OR`, `XOR`.
- Shifts: `SLL`, `SRL`, `SRA`.
- Shift-amount is masked to 5 bits (`shamt[4:0]`).
- Sign-aware comparisons for `SLT` / `SLTU` and the branch comparator.

**MDU (`mdu.sv`) — Booth Radix-4 multiplier + Restoring divider:**

| Attribute | Multiplier | Divider |
|---|---|---|
| Algorithm | Booth Radix-4 (2-bit grouping) | Restoring |
| Partial products | 16 (halved from 32) | — |
| Latency (fixed) | **3 cycles** | **33 cycles** |
| Signed/unsigned | Both (MUL / MULH / MULHSU / MULHU) | Both (DIV / DIVU / REM / REMU) |
| Div-by-zero | Returns per RV32M: quotient = all-1s, remainder = dividend | — |
| INT_MIN / -1 overflow | Quotient = INT_MIN, remainder = 0 | — |
| Stall signal | `mdu_stall` — freezes IF, DE, MW while busy | |

**Branch Comparator (`branch_cmp.sv`):** Evaluates `BEQ / BNE / BLT / BGE / BLTU / BGEU` in DE for early branch resolution (1-cycle branch penalty — the IF→DE register is flushed, not the DE stage itself).

**CSR Unit (`csr_regfile.sv`):**
- Handles `CSRRW / CSRRS / CSRRC / CSRRWI / CSRRSI / CSRRCI` to M-mode CSRs.
- See Spec §1.4 for the full CSR table and §1.5 for trap entry / mret logic.

### 2.3 Stage 3 — Memory & Writeback (MW)

**AXI4 DMEM master** — full R/W (AW + W + B + AR + R).

- Byte (`SB / LB / LBU`), half-word (`SH / LH / LHU`), word (`SW / LW`) sizes.
- `dmem_wstrb[3:0]` drives byte-enable per RISC-V spec (e.g. `SB` at byte offset 2 → `wstrb = 4'b0100`).
- Internal FSM: `DM_IDLE → DM_RD → DM_IDLE` (loads) or `DM_IDLE → DM_WR → DM_IDLE` (stores).
- Supports zero-latency slaves (`ARREADY` + `RVALID` in same cycle as `ARVALID`) **and** multi-cycle slaves (random 0–2 cycle delays verified in Suite 14).
- Properly latches AR / AW / W handshakes occurring in `DM_IDLE` (bug #3 from `debugging_guide.md` — fixed).

**Writeback mux** selects `wdata` from:

| Source | Used by |
|---|---|
| ALU result | All ALU ops |
| MDU result | MUL / DIV / REM |
| Memory load data (sign/zero-extended) | LB / LH / LW / LBU / LHU |
| CSR read data | CSRR* |
| PC + 4 | JAL / JALR (link) |

**Register File writeback** — drives `rf_en_MW`, `rd_addr_MW`, `wdata` back to the register file in the same cycle. Writes to x0 are suppressed by the register file.

---

## 3. Hazard handling and pipeline interlocks

Detected by `hazard_unit.sv`:

| Hazard condition | Action |
|---|---|
| **RAW (ALU → ALU)** | Forward MW-stage result back to DE operand mux (`forward_a`, `forward_b`) |
| **Load-use** (LOAD in MW feeds DE operand) | Stall IF & DE one cycle; insert bubble into MW |
| **MDU busy** (multi-cycle MUL/DIV) | Assert `mdu_stall` — freeze IF, DE and MW stages |
| **Memory wait** (AXI4 DMEM `rvalid=0` or `wready=0`) | Assert `dmem_stall` — freeze MW outputs |
| **Branch / jump taken** | Flush IF→DE register (1-cycle branch penalty) |
| **Trap / MRET redirect** | Flush IF→DE register and reload PC from `mtvec` / `mepc` |

**Forwarding paths implemented:**

- ALU → ALU (rs1, rs2)
- ALU → Branch condition
- ALU → Store data

**No forwarding is needed** from MW-stage LOAD data to DE because the load-use interlock stalls instead — avoids a full MW→DE path and keeps the critical path short.

---

## 4. AXI4 bus interface specification

The core provides two independent 32-bit AXI4 master ports.

### 4.1 Instruction Memory Interface (IMEM)

| Channel | Signal | Dir | Description |
|---|---|---|---|
| AR | `imem_araddr[31:0]` | O | Instruction fetch address |
| AR | `imem_arvalid` | O | Address valid |
| AR | `imem_arready` | I | Slave ready |
| AR | `imem_arlen[7:0]` | O | `8'd0` — single beat |
| AR | `imem_arsize[2:0]` | O | `3'b010` — 4-byte word |
| AR | `imem_arburst[1:0]` | O | `2'b01` — INCR |
| AR | `imem_arcache[3:0]` | O | `4'b0010` — normal non-cacheable bufferable |
| AR | `imem_arprot[2:0]` | O | `3'b100` — instruction, non-secure, unprivileged-OK |
| AR | `imem_arlock` | O | `1'b0` — unlocked |
| R | `imem_rdata[31:0]` | I | Instruction word |
| R | `imem_rvalid` | I | Read-data valid |
| R | `imem_rready` | O | `1'b1` — always ready |
| R | `imem_rresp[1:0]` | I | Slave response (ignored except for assertion) |
| R | `imem_rlast` | I | Last-beat flag (unused — single-beat only) |

### 4.2 Data Memory Interface (DMEM)

| Channel | Signal | Dir | Description |
|---|---|---|---|
| AW | `dmem_awaddr[31:0]` | O | Store address |
| AW | `dmem_awvalid` | O | Write-address valid |
| AW | `dmem_awready` | I | Slave accepts write address |
| AW | `dmem_awlen[7:0]` | O | `8'd0` |
| AW | `dmem_awsize[2:0]` | O | Byte-width of access (0=byte, 1=half, 2=word) |
| AW | `dmem_awburst[1:0]` | O | `2'b01` |
| AW | `dmem_awcache[3:0]` | O | `4'b0000` |
| AW | `dmem_awprot[2:0]` | O | `3'b000` — data, non-secure |
| AW | `dmem_awlock` | O | `1'b0` |
| W | `dmem_wdata[31:0]` | O | Store data |
| W | `dmem_wstrb[3:0]` | O | Byte enable strobes |
| W | `dmem_wvalid` | O | Write-data valid |
| W | `dmem_wlast` | O | `1'b1` — single-beat always last |
| W | `dmem_wready` | I | Slave accepts data |
| B | `dmem_bvalid` | I | Write-response valid |
| B | `dmem_bresp[1:0]` | I | Write-response code (OKAY / SLVERR / DECERR) |
| B | `dmem_bready` | O | `1'b1` — always ready |
| AR | `dmem_araddr[31:0]` | O | Load address |
| AR | `dmem_arvalid` | O | Read-address valid |
| AR | `dmem_arready` | I | Slave accepts |
| AR | `dmem_arlen[7:0]` | O | `8'd0` |
| AR | `dmem_arsize[2:0]` | O | Byte-width |
| AR | `dmem_arburst[1:0]` | O | `2'b01` |
| AR | `dmem_arcache[3:0]` | O | `4'b0000` |
| AR | `dmem_arprot[2:0]` | O | `3'b000` |
| AR | `dmem_arlock` | O | `1'b0` |
| R | `dmem_rdata[31:0]` | I | Read data |
| R | `dmem_rvalid` | I | Read-data valid |
| R | `dmem_rready` | O | `1'b1` |
| R | `dmem_rresp[1:0]` | I | Read-response code |
| R | `dmem_rlast` | I | Unused |

### 4.3 Interrupt inputs

| Signal | Dir | Source |
|---|---|---|
| `irq_external` | I | PLIC output → mip.MEIP |
| `irq_timer` | I | CLINT timer compare → mip.MTIP |
| `irq_software` | I | CLINT msip register → mip.MSIP |

All three are **active-high**, level-sensitive, and treated as asynchronous at the chip boundary (2-flop synchroniser to be inserted in physical design).

---

## 5. Opcode coverage summary

100 % opcode coverage achieved — see Verification Plan §3 for the coverage database.

| Group | Instructions | Covered? |
|---|---|---|
| RV32I arithmetic | ADD/SUB/SLT/SLTU/AND/OR/XOR/SLL/SRL/SRA/LUI/AUIPC + I-form | ✅ 100 % |
| RV32I control | JAL/JALR/BEQ/BNE/BLT/BGE/BLTU/BGEU | ✅ 100 % |
| RV32I memory | LB/LH/LW/LBU/LHU/SB/SH/SW | ✅ 100 % |
| RV32I fence | FENCE / FENCE.I | ✅ 100 % |
| RV32M | MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU | ✅ 100 % |
| M-mode system | ECALL/EBREAK/MRET | ✅ 100 % |
| Zicsr | CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI | ✅ 100 % |

---

## 6. Known RTL issues (for G2 lint waivers)

From `TOPS_FINAL/spyglass_reports/spyglass_lint_summary.rpt`:

| # | File:line | Issue | Action |
|---|---|---|---|
| A | `csr_regfile.sv:106` | Incomplete `mip` assignment creates implicit latch | **Fix** — explicitly tie unused mip bits to 0 before RTL freeze |
| B | `booth_multiplier_radix4.sv:107` | Wallace tree array indexing triggers UNOPTFLAT (Verilator) | **Waive** — intentional combinational tree; no functional hazard |
| C | `rv32_core_top.sv` lines 29/68/69/230/353 + `imm_gen.sv:5` | Unused signals (`imem_rlast`, `dmem_rresp`, `dmem_rlast`, `csr_rd_DE`, `pc_out_MW`, `imm_gen` opcode bits) | **Waive** — AXI4 handshake signals required by protocol but not driven internal to core; opcode bits used only by decoder |
| D | `rv32_core_top.sv:594` | Complex SVA reset expression | **Waive** — intentional for protocol assertion |

---
