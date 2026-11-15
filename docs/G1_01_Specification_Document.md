# 1-TOPS VEDA — SoC Specification Document

**Team:** VEDA · PSG College of Technology
**Project:** 1-TOPS Secure IoT RISC-V SoC (RV32IM + ASCON-128)
**Covers:** G1 items 1.1 – 1.11
**Target tape-out:** 1 December 2026
**Document status:** Frozen for G1 sign-off
**Revision:** 1.0 · 2026-11-15

---

## Figures referenced in this document

| Figure | File (commit alongside this document) | Source |
|---|---|---|
| Fig. 1 — RV32IM core block diagram | `figures/RV32IM_Core_architecture_v3.png` | local `PSG-1-TOPS\RV32IM_Core_architecture_v3.png` |
| Fig. 2 — RV32I 3-stage pipeline architecture | `figures/ARCHITECTURE_RV32I_3_STAGE_PIPELINE.png` | local `PSG-1-TOPS\RV32I_3_Stage_Pipeline_Architecture\ARCHITECTURE_RV32I_3_STAGE_PIPELINE.png` |

---

## 1.1 Core ISA Frozen

**Decision:** The core implements **RV32IM** (base 32-bit integer + integer multiply / divide extensions).

| Parameter | Value |
|---|---|
| ISA string | `rv32im_zicsr_zifencei` |
| Base integer set | RV32I |
| Multiply / divide | M extension |
| Compressed (C) | **NOT** implemented |
| Floating point (F/D) | **NOT** implemented |
| Atomic (A) | **NOT** implemented |
| Zicsr | Implemented (M-mode CSRs) |
| Zifencei | Implemented (FENCE.I) |

**Justification:** RV32IM delivers the integer throughput required for IoT firmware (ASCON crypto setup, peripheral drivers, sensor data processing) without the area overhead of C/F/D/A. Dhrystone 2.1 gives **1.281 DMIPS/MHz** on this core.

**Frozen in RTL:** `rtl/core/rv32_pkg.sv`, `rtl/core/decoder.sv`.

---

## 1.2 Pipeline Depth Frozen

**Decision:** **3-stage in-order pipeline — `IF → DE → MW`**, with **dynamic data forwarding** and **load-use stall insertion**.

| Stage | Name | Primary function |
|---|---|---|
| 1 | IF (Instruction Fetch) | PC generation, AXI4 IMEM read, pipe_if_de latch |
| 2 | DE (Decode & Execute) | Register file read, immediate gen, ALU, MDU, branch compare, CSR access |
| 3 | MW (Memory & Writeback) | AXI4 DMEM read/write, writeback mux, register file write |

**Hazard policy:**

| Hazard | Action |
|---|---|
| RAW (ALU → ALU) | Forward from MW stage back to DE operands |
| Load-use | Stall IF & DE for 1 cycle; insert bubble into MW |
| MDU busy (MUL/DIV) | Assert `mdu_stall`; freeze IF, DE and MW |
| Memory wait (AXI4) | Assert `dmem_stall`; freeze MW outputs |
| Branch / jump taken | Flush IF→DE register (1-cycle penalty) |
| Trap / MRET | Flush IF→DE, reload PC from mtvec / mepc |

**Justification:** A 3-stage pipeline is the best area / performance point for the target 100 MHz and the ASAP7 7 nm synthesis results (critical path ≈ 1.16 ns at 1 GHz target; closes 100 MHz trivially). 1 stage was too slow; 5 stages added forwarding area and branch latency with no throughput win for IoT firmware.

**Frozen in RTL:** `rtl/core/rv32_core_top.sv`, `rtl/core/pipe_if_de.sv`, `rtl/core/pipe_de_mw.sv`, `rtl/core/hazard_unit.sv`.

See Figure 2 (`figures/ARCHITECTURE_RV32I_3_STAGE_PIPELINE.png`) for the detailed pipeline diagram.

---

## 1.3 Privilege Modes Frozen

**Decision:** **Machine mode (M-mode) only.**

| Mode | Implemented | Reason |
|---|---|---|
| Machine (M) | ✅ Yes | Required by spec; runs all firmware |
| Supervisor (S) | ❌ No | Not needed — no OS, no MMU, no virtual memory |
| User (U) | ❌ No | Not needed — single-privilege firmware model |

**No MMU.** All memory accesses are physical. No page tables.

**Justification:** The target application is bare-metal IoT firmware with ASCON crypto. There is no Linux or RTOS requirement that needs S-mode or an MMU. Dropping S/U modes removes ≈ 25 % of CSR area and all MMU logic.

**Frozen in RTL:** `rtl/core/csr_regfile.sv` (M-mode CSRs only), `rtl/core/decoder.sv` (MRET implemented, no SRET/URET).

---

## 1.4 CSR List Frozen

**Decision:** 13 Machine-mode CSRs implemented. All read/write on standard RISC-V CSR address space.

| # | Name | Address | Reset value | Access | Width | Purpose |
|---|---|---|---|---|---|---|
| 1 | `mstatus` | `0x300` | `0x0000_0000` | RW | 32 b | Machine status (MIE, MPIE, MPP) |
| 2 | `misa` | `0x301` | `0x4000_1100` | RO | 32 b | ISA ID: MXL=1 (RV32), I+M extensions |
| 3 | `mie` | `0x304` | `0x0000_0000` | RW | 32 b | Interrupt enable (MEIE, MTIE, MSIE) |
| 4 | `mtvec` | `0x305` | `0x0000_0000` | RW | 32 b | Trap vector base address (direct mode) |
| 5 | `mscratch` | `0x340` | `0x0000_0000` | RW | 32 b | Scratch register for trap handler |
| 6 | `mepc` | `0x341` | `0x0000_0000` | RW | 32 b | Exception program counter |
| 7 | `mcause` | `0x342` | `0x0000_0000` | RW | 32 b | Trap cause (interrupt bit + code) |
| 8 | `mtval` | `0x343` | `0x0000_0000` | RW | 32 b | Trap value (bad address / instruction) |
| 9 | `mip` | `0x344` | `0x0000_0000` | RO* | 32 b | Interrupt pending (MEIP/MTIP/MSIP driven from external IRQ pins) |
| 10 | `mhartid` | `0xF14` | `0x0000_0000` | RO | 32 b | Hart ID (single hart = 0) |
| 11 | `mvendorid` | `0xF11` | `0x0000_0000` | RO | 32 b | Vendor ID (0 = non-commercial) |
| 12 | `marchid` | `0xF12` | `0x0000_0000` | RO | 32 b | Architecture ID |
| 13 | `mimpid` | `0xF13` | `0x0000_0001` | RO | 32 b | Implementation ID (team version) |

> **Note on `mip`:** bits 11 (MEIP), 7 (MTIP), 3 (MSIP) are driven by the external `irq_external`, `irq_timer`, `irq_software` inputs and are read-only from software. Other bits are hardwired to 0.

**CSR instruction support:** `CSRRW`, `CSRRS`, `CSRRC`, `CSRRWI`, `CSRRSI`, `CSRRCI`.

**Frozen in RTL:** `rtl/core/csr_regfile.sv` (rv32_core_top.sv lines 51-71 show address map and register declarations).

**Open action:** SpyGlass flagged partial `mip` assignment in `csr_regfile.sv:106` (bits [31:12], [10:8], [6:4], [2:0] not explicitly driven → inferred latch). Fix before RTL freeze by explicitly tying unused bits to 0.

---

## 1.5 Trap and Interrupt Model Defined

**Trap vector:** Single entry at `mtvec`, **direct mode** (`mtvec[1:0] = 00`). Vectored mode not supported.

**Trap entry sequence:**

1. Hardware captures trapping PC into `mepc`.
2. Trap cause (interrupt bit [31] + cause code [30:0]) written to `mcause`.
3. For memory/instruction faults, offending address written to `mtval`; `mtval = 0` for ECALL/EBREAK.
4. `mstatus.MPIE <= mstatus.MIE` (save previous interrupt enable).
5. `mstatus.MIE <= 0` (disable interrupts in handler).
6. `mstatus.MPP <= 2'b11` (previous privilege = M).
7. PC redirected to `mtvec`.
8. IF→DE pipeline register flushed.

**MRET sequence:**

1. `mstatus.MIE <= mstatus.MPIE` (restore interrupt enable).
2. `mstatus.MPIE <= 1`.
3. `mstatus.MPP <= 2'b00` (lowest privilege).
4. PC redirected to `mepc`.

**Interrupt sources (all async, level-sensitive on `irq_*` inputs):**

| IRQ | mip bit | mcause code | Source |
|---|---|---|---|
| Machine external | MEIP [11] | 0x8000_000B | PLIC output |
| Machine timer | MTIP [7] | 0x8000_0007 | CLINT timer compare |
| Machine software | MSIP [3] | 0x8000_0003 | CLINT software IRQ register |

**Nested interrupts:** **NOT supported.** Once the handler runs, `MIE=0` keeps further interrupts masked until software re-enables or `MRET` restores. A handler must save/restore `mepc`, `mcause`, `mstatus`, and clobbered GPRs if it re-enables interrupts.

**Exception codes implemented:**

| mcause | Name | Trigger |
|---|---|---|
| 0x0000_0000 | Instruction address misaligned | PC[1:0] != 00 on branch/jump |
| 0x0000_0002 | Illegal instruction | Unknown opcode / illegal CSR |
| 0x0000_0003 | Breakpoint | `EBREAK` |
| 0x0000_0004 | Load address misaligned | Misaligned word/half load |
| 0x0000_0006 | Store address misaligned | Misaligned word/half store |
| 0x0000_000B | Environment call from M-mode | `ECALL` |

**Trap boundary:** Traps are taken at the **DE stage** — the trapping instruction is the one whose PC is in DE when the trap is detected. Instructions ahead of it in IF are flushed; instructions behind it in MW complete writeback before the handler starts.

**Frozen in RTL:** `rtl/core/csr_regfile.sv` (trap logic, lines 125-144), `rtl/core/rv32_core_top.sv` (trap routing).

---

## 1.6 Memory Organisation Frozen

**Decision:** 16 KB Instruction SRAM + 16 KB Data SRAM, no separate boot ROM (IMEM serves as boot source — see Boot Plan).

| Region | Base | Size (allocated) | SRAM macro size | Interface |
|---|---|---|---|---|
| Instruction SRAM | `0x0000_0000` | 16 KB | `I_SRAM_16Kb.sv` (16 KB) | AXI4 read-only (IMEM master) |
| Data SRAM | `0x0000_1000` | 16 KB | `D_SRAM_16Kb.sv` (16 KB) | AXI4 R/W (DMEM master) |
| Peripherals (APB) | `0x0000_2000` – `0x0000_8FFF` | 28 KB (7×4 KB slots) | — | AXI4 → APB bridge |
| ASCON-128 accelerator | `0x0000_9000` – `0x0000_907F` | 128 B (32 regs) | — | AXI4-Lite slave (direct) |

**Prefetch buffer:** **Not** implemented (3-stage pipeline with zero-latency AXI4 slave makes prefetching unnecessary).

**I-cache:** **Not** implemented (IMEM is on-chip SRAM, zero-latency).

> **Address-map vs. SRAM-size reconciliation** — the SoC address map previously allocated **4 KB** regions for IMEM / DMEM but the actual SRAM macros are **16 KB each** per the Architecture Decision reference. This spec freezes the regions at **16 KB each** (0x0000–0x3FFF for IMEM, 0x4000–0x7FFF for DMEM) with the peripheral base moved to 0x8000 if the team wishes to align regions to macro boundaries. If the 4 KB regions are kept, the top 12 KB of each SRAM is unmapped and should be commented as such. **Pending team decision.**

**Justification:** The 1-TOPS Guidelines recommend 32–64 KB per SRAM for RV32IM. VEDA's design uses 16 KB each, justified in `Architecture_Decision_references_VEDA_1-TOPS.docx` by IoT payload sizes (32–256 B) and the ASCON firmware footprint (~2–4× raw binary = ~8 KB). Coach waiver recorded.

**Frozen in RTL:** `Memory/I_SRAM_16Kb.sv`, `Memory/D_SRAM_16Kb.sv`.

---

## 1.7 SoC Block Diagram Approved

**See Figure 1 — `figures/RV32IM_Core_architecture_v3.png`** for the full SoC block diagram.

**Block inventory (clockwise from core):**

```
                    ┌─────────────────────────────────────────┐
                    │          RV32_CORE_TOP (RV32IM)         │
                    └──────────┬──────────────────┬───────────┘
                               │ AXI4 IMEM        │ AXI4 DMEM
                               │                  │
                 ┌─────────────┴────────┐    ┌────┴──────────────────────────┐
                 │  I-SRAM 16 KB        │    │ 3-way address demux           │
                 │  @ 0x0000_0000       │    └─┬──────────┬──────────┬───────┘
                 └──────────────────────┘      │          │          │
                                      ┌────────┘          │          └──────────┐
                                      │                   │                     │
                                 ┌────┴──────┐    ┌───────┴────────┐     ┌──────┴─────────┐
                                 │ D-SRAM    │    │ AXI4-to-APB    │     │ ASCON-128      │
                                 │ 16 KB     │    │ Bridge         │     │ AEAD (AXI4-Lite)│
                                 │ @ 0x1000  │    └────┬───────────┘     │ @ 0x9000       │
                                 └───────────┘         │                 └────────────────┘
                                                       │ APB
                        ┌──────────┬──────────┬────────┼────────┬──────────┬──────────┐
                        │          │          │        │        │          │          │
                     ┌──┴──┐    ┌──┴──┐    ┌──┴──┐  ┌──┴──┐  ┌──┴──┐    ┌──┴──┐    ┌──┴──┐
                     │UART │    │ SPI │    │GPIO │  │TIMER│  │ WDT │    │PLIC │    │CLINT│
                     │0x2k │    │0x3k │    │0x4k │  │0x5k │  │0x6k │    │0x7k │    │0x8k │
                     └─────┘    └─────┘    └─────┘  └─────┘  └─────┘    └──┬──┘    └──┬──┘
                                                                           │          │
                                                                           └────┬─────┘
                                                                                │ IRQs
                                                                     ┌──────────┴──────────┐
                                                                     │ irq_external (PLIC) │
                                                                     │ irq_timer    (CLINT)│
                                                                     │ irq_software (CLINT)│
                                                                     └─────────────────────┘
```

**Clock source:** Single external `clk` input. No internal PLL. No clock domain crossings in the current design (async inputs `uart_rx`, `gpio_in`, external interrupt pins to be synchronised in physical design).

**Reset source:** Single external active-low `rst_n` input. Global synchronous-release / async-assert reset distributed to all blocks.

---

## 1.8 Address Map Frozen

| Address range | Size | Slave | Interface | Access |
|---|---|---|---|---|
| `0x0000_0000` – `0x0000_3FFF` | 16 KB | Instruction SRAM | AXI4 | Read-only (from core IMEM master) |
| `0x0000_4000` – `0x0000_7FFF` | 16 KB | Data SRAM | AXI4 | Read / Write |
| `0x0000_8000` – `0x0000_8FFF` | 4 KB | UART | AXI4→APB | Read / Write |
| `0x0000_9000` – `0x0000_9FFF` | 4 KB | SPI | AXI4→APB | Read / Write |
| `0x0000_A000` – `0x0000_AFFF` | 4 KB | GPIO | AXI4→APB | Read / Write |
| `0x0000_B000` – `0x0000_BFFF` | 4 KB | Timer | AXI4→APB | Read / Write |
| `0x0000_C000` – `0x0000_CFFF` | 4 KB | Watchdog | AXI4→APB | Read / Write |
| `0x0000_D000` – `0x0000_DFFF` | 4 KB | PLIC | AXI4→APB | Read / Write |
| `0x0000_E000` – `0x0000_EFFF` | 4 KB | CLINT | AXI4→APB | Read / Write |
| `0x0000_F000` – `0x0000_F07F` | 128 B | ASCON-128 AEAD | AXI4-Lite | Read / Write |
| `0x0000_F080` – `0xFFFF_FFFF` | — | **Unmapped** | — | Error response (DECERR) |

> **Note:** This map reflects the **16 KB SRAM freeze** (1.6). If the team keeps 4 KB SRAM allocation, substitute the earlier `0x0000_0000` / `0x0000_1000` / `0x0000_2000` / `0x0000_9000` scheme used in `full_soc_fixes_applied.md` and PDF Sec 4.1.2. **Pick one and update RTL + this doc together.**

**Decode:** 3-way address demux in `soc_top.sv` glue logic routes based on `addr[15:12]`.

**Unmapped-access policy:** Any read or write outside the mapped regions returns an AXI4 `DECERR` (`bresp = 2'b11` / `rresp = 2'b11`). The core treats this as a Load/Store access fault (`mcause = 0x5` for load, `0x7` for store — to be added if not already in `csr_regfile.sv`).

**No overlaps.** Verified by inspection and by the Milestone 4 firmware test `soc_memory_test`.

---

## 1.9 Interrupt Map Frozen

**Controller topology:**

- **PLIC** handles all peripheral interrupts and drives `irq_external` into the core (mip.MEIP).
- **CLINT** handles timer compare and software interrupts, driving `irq_timer` (mip.MTIP) and `irq_software` (mip.MSIP).

**PLIC interrupt source table (30 sources, 2 targets — M-mode hart 0 context + 1 reserved for future expansion):**

| IRQ # | Source | Priority (default) | Notes |
|---|---|---|---|
| 0 | Reserved (no-source) | — | Per PLIC spec |
| 1 | UART RX FIFO non-empty | 3 | Edge-rising |
| 2 | UART TX FIFO empty | 3 | Level |
| 3 | UART line-status error | 5 | Edge-rising |
| 4 | SPI TX done | 3 | Edge-rising |
| 5 | SPI RX FIFO non-empty | 3 | Edge-rising |
| 6 | SPI overrun / underrun | 5 | Edge-rising |
| 7 | GPIO pin 0 — edge | 2 | Configurable rise/fall |
| 8 – 14 | GPIO pins 1 – 7 edge | 2 | Configurable |
| 15 | Watchdog pre-timeout | 6 | Level |
| 16 | Watchdog timeout (reset coming) | 7 | Level (highest) |
| 17 | ASCON — operation complete | 4 | Edge-rising |
| 18 | ASCON — auth failure | 6 | Edge-rising |
| 19 – 30 | Reserved (expansion) | — | Hardwired 0 for now |

**Priority scheme:** 3-bit priority (0 = disabled, 7 = highest). Higher numeric = higher priority. Ties broken by lower IRQ number first.

**Claim/complete:** Standard RISC-V PLIC protocol — handler reads `claim` register to get active IRQ id, services, writes same id back to `complete` register.

**CLINT interrupt sources:**

| Signal | Source | mip bit |
|---|---|---|
| `irq_timer` | `mtimecmp` ≤ `mtime` | MTIP [7] |
| `irq_software` | CLINT `msip` register bit 0 | MSIP [3] |

**Frozen in RTL:** `Peripherals/PLIC/` directory, `Peripherals/CLINT.sv`, `Peripherals/TIMER.sv`.

---

## 1.10 Clock and Reset Architecture Defined

**Clock topology:**

```
   External clock pin (clk)
          │
          ▼
   ┌──────────────────┐
   │  No PLL / divider│  ← Single clock domain
   └──────┬───────────┘
          │
          └──> core, bridge, all peripherals, SRAM macros, ASCON
```

| Parameter | Value |
|---|---|
| Clock sources | 1 — external `clk` pin |
| On-chip PLL | None |
| Dividers | None |
| Clock gating | Automatic (DC `-gate_clock`) — 44 clock-gate cells inserted (per synthesis area report) |
| Target frequency | 100 MHz (per Cover tab) |
| Nominal critical path | ≈ 1.16 ns (closes 100 MHz ≈ 10 ns trivially) |

**Reset topology:**

```
   External reset pin (rst_n, active-low)
          │
          ▼
   ┌──────────────────┐
   │ Async assert     │
   │ Sync release     │  ← to be inserted at top level in physical design
   └──────┬───────────┘
          │
          └──> global reset distributed to all registers
```

| Parameter | Value |
|---|---|
| Reset sources | 1 — external `rst_n` pin |
| Polarity | Active-low |
| Assertion | Asynchronous |
| De-assertion | Synchronous (to insert at PD / gate-level) |
| Scope | Global — all flops reset to defined state |
| Warm-reset path | Watchdog timeout drives chip-level reset (TBD — currently generates NMI only) |

**Clock domain crossings (CDC):** None internal to the design. The following **asynchronous external inputs** must receive 2-flop synchronisers at the chip boundary (to be inserted in physical design — flagged in SpyGlass as requiring synchroniser pragmas):

| Pin | Comment |
|---|---|
| `uart_rx` | Async serial input |
| `gpio_in[31:0]` | Async GPIO inputs |
| `ext_irq` (if any external IRQ pin added) | Async |

**RDC (reset domain crossing):** Single reset domain → no RDC.

**Frozen in:** SDC constraints `syn_core/outputs/rv32_core_top.sdc`, `syn_soc/outputs/soc_top.sdc` (clock period to be updated from 1 ns → 10 ns to match 100 MHz target).

---

## 1.11 Pin List / Chip IO Table Frozen

**Top-level module:** `soc_top`.

**Chip IO summary:**

| Signal | Dir | Width | Function | Pad type | Mux |
|---|---|---|---|---|---|
| **Clock & reset** | | | | | |
| `clk` | I | 1 | System clock (external oscillator) | CMOS input | — |
| `rst_n` | I | 1 | Async active-low chip reset | CMOS input + Schmitt | — |
| **UART** | | | | | |
| `uart_rx` | I | 1 | UART receive data | CMOS input | — |
| `uart_tx` | O | 1 | UART transmit data | CMOS tri-state output | — |
| **SPI master** | | | | | |
| `spi_sclk` | O | 1 | SPI clock out | CMOS output | — |
| `spi_mosi` | O | 1 | SPI master-out slave-in | CMOS output | — |
| `spi_miso` | I | 1 | SPI master-in slave-out | CMOS input | — |
| `spi_cs_n[0]` | O | 1 | SPI chip select 0 (active-low) | CMOS output | — |
| **GPIO** | | | | | |
| `gpio_in[31:0]` | I | 32 | GPIO input | CMOS input (per pin) | GPIO / alt-fn bits in GPIO cfg register |
| `gpio_out[31:0]` | O | 32 | GPIO output | CMOS tri-state output | GPIO / alt-fn bits |
| `gpio_oe[31:0]` | O | 32 | GPIO output enable (per pin) | — (internal) | — |
| **JTAG / Debug** | | | | | |
| *TBD* | | | — not yet added — recommend adding 4 JTAG pins before tape-out | | |
| **Supplies** | | | | | |
| `VDD` | P | — | 0.7 V core supply (ASAP7 TT) | Core supply pad | — |
| `VDDIO` | P | — | 1.8 V IO supply (TBD) | IO supply pad | — |
| `VSS` / `GND` | P | — | Ground | Ground pad | — |

**Pad-cell library:** TBD — tied to chosen PDK (currently ASAP7 7 nm; no pad library shipped with ASAP7 — needs team decision for a commercial tape-out PDK).

**Total pin count:** approx **71** signal pins + supplies.
- 2 (clk / rst_n)
- 2 (UART)
- 4 (SPI)
- 64 (GPIO in+out) — note that `gpio_oe` is internal, so chip-level pin count for GPIO is 32 bi-directional pads with built-in `oe`.
- Revised signal pin count with bi-dir GPIO pads: **40 signal pins** + ~4 JTAG + supplies.

**Open actions before G9:**
1. Decide and freeze JTAG pin count (4 or 5 pins).
2. Confirm GPIO bi-directional pad usage vs separate in/out pins.
3. Choose IO pad-cell library for chosen tape-out PDK.
4. Produce bonding diagram and package-pinout table (G9.5).

---

