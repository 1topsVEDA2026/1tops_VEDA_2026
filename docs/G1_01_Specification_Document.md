# 1-TOPS VEDA — SoC Specification Document

**Team:** VEDA · PSG College of Technology
**Project:** 1-TOPS Secure IoT RISC-V SoC (RV32IM + ASCON-128)
**Covers:** G1 items 1.1 – 1.11
**Target tape-out:** 1 December 2026
**Document status:** Frozen for G1 sign-off
**Revision:** 1.1 · 2026-11-17 (§1.7, §1.8, §1.10 and §1.11 updated for analog-block clock/reset architecture)

---

## Figures referenced in this document

| Figure | File (commit alongside this document) | Source |
|---|---|---|
| Fig. 1 — RV32IM core block diagram | `figures/RV32IM_Core_architecture_v3.png` | local `PSG-1-TOPS\RV32IM_Core_architecture_v3.png` |
| Fig. 2 — RV32I 3-stage pipeline architecture | `figures/ARCHITECTURE_RV32I_3_STAGE_PIPELINE.png` | local `PSG-1-TOPS\RV32I_3_Stage_Pipeline_Architecture\ARCHITECTURE_RV32I_3_STAGE_PIPELINE.png` |
| Fig. 3 — Clock architecture (drawio) | `figures/clock_architecture.drawio` | this document §1.10 |
| Fig. 4 — Reset architecture (drawio) | `figures/reset_architecture.drawio` | this document §1.10 |

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

**Frozen in RTL:** `rtl/core/csr_regfile.sv`.

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
| 0x0000_0005 | Load access fault | AXI4 DECERR on load (unmapped region) |
| 0x0000_0006 | Store address misaligned | Misaligned word/half store |
| 0x0000_0007 | Store access fault | AXI4 DECERR on store (unmapped region) |
| 0x0000_000B | Environment call from M-mode | `ECALL` |

**Trap boundary:** Traps are taken at the **DE stage** — the trapping instruction is the one whose PC is in DE when the trap is detected. Instructions ahead of it in IF are flushed; instructions behind it in MW complete writeback before the handler starts.

**Frozen in RTL:** `rtl/core/csr_regfile.sv`, `rtl/core/rv32_core_top.sv`.

---

## 1.6 Memory Organisation Frozen

**Decision:** 16 KB Instruction SRAM + 16 KB Data SRAM, no separate boot ROM (IMEM serves as boot source — see Boot Plan).

| Region | Base | Size (allocated) | SRAM macro size | Interface |
|---|---|---|---|---|
| Instruction SRAM | `0x0000_0000` | 16 KB | `I_SRAM_16Kb.sv` (16 KB) | AXI4 read-only (IMEM master) |
| Data SRAM | `0x0000_4000` | 16 KB | `D_SRAM_16Kb.sv` (16 KB) | AXI4 R/W (DMEM master) |
| Peripherals (APB) | `0x0000_8000` – `0x0000_EFFF` | 28 KB (7×4 KB slots) | — | AXI4 → APB bridge |
| ASCON-128 accelerator | `0x0000_F000` – `0x0000_F07F` | 128 B (32 regs) | — | AXI4-Lite slave (direct) |

**Prefetch buffer:** **Not** implemented (3-stage pipeline with zero-latency AXI4 slave makes prefetching unnecessary).

**I-cache:** **Not** implemented (IMEM is on-chip SRAM, zero-latency).

**Justification:** The 1-TOPS Guidelines recommend 32–64 KB per SRAM for RV32IM. VEDA's design uses 16 KB each, justified in `Architecture_Decision_references_VEDA_1-TOPS.docx` by IoT payload sizes (32–256 B) and the ASCON firmware footprint (~2–4× raw binary ≈ 8 KB). Coach waiver recorded.

**Frozen in RTL:** `Memory/I_SRAM_16Kb.sv`, `Memory/D_SRAM_16Kb.sv`.

---

## 1.7 SoC Block Diagram Approved

**See Figure 1 — `figures/RV32IM_Core_architecture_v3.png`** for the full SoC block diagram.

**Block inventory:**

```
   ┌──────────────────────────┐            ┌──────────────────────────┐
   │  ANALOG BLOCK (1-TOPS IP)│            │   RV32_CORE_TOP (RV32IM) │
   │    LDO · POR · PLL · LF  │            │    IF → DE → MW + MDU    │
   └────────────┬─────────────┘            └──────┬──────────────┬────┘
                │ CLK_PLL / PLL_LOCK / POR_N      │ AXI4 IMEM    │ AXI4 DMEM
                ▼                                 │              │
   ┌──────────────────────────┐                   │              │
   │  CCRC (rtl/soc/ccrc.sv)  │──► CLK_SYS ──────►│              │
   │  div, mux, PLL_LOCK sync │──► CLK_WDT ──────►│              │
   │  reset combine + sync    │──► sys_rst_n ────►│              │
   │                          │──► wdt_rst_n ────►│              │
   └──────────────────────────┘                   │              │
                                                  ▼              ▼
                                         ┌──────────────┐  ┌───────────────────┐
                                         │ IMEM 16 KB   │  │ 3-way address     │
                                         │ @ 0x0000     │  │ demux             │
                                         └──────────────┘  └──┬──────┬──────┬──┘
                                                              │      │      │
                                                     ┌────────┘      │      └────────┐
                                                     ▼               ▼               ▼
                                              ┌──────────┐   ┌───────────────┐  ┌─────────────┐
                                              │ DMEM 16KB│   │ AXI4→APB      │  │ ASCON-128   │
                                              │ @ 0x4000 │   │ bridge        │  │ AXI4-Lite   │
                                              └──────────┘   └──────┬────────┘  │ @ 0xF000    │
                                                                    │ APB       └─────────────┘
                              ┌───────┬───────┬───────┬──────┬──────┼──────┬──────┐
                              ▼       ▼       ▼       ▼      ▼      ▼      ▼      ▼
                           sys_ctrl GPIO    UART    SPI    TIMER   WDT   PLIC   CLINT
                           (APB)   @0x8000 @0x9000 @0xA000 @0xB000 @0xC000 @0xD000 @0xE000
                                                                    │
                                                                 CLK_WDT (independent counter)
```

**Clock source:** Analog PLL output, divided to CLK_SYS (100 MHz) and CLK_WDT (32.768 kHz) in the CCRC block. See §1.10 for the complete clock and reset architecture.

**Reset source:** Three cold sources (analog POR, external pad `PAD_RSTN`, PLL_LOCK gating) combined in CCRC. See §1.10.

---

## 1.8 Address Map Frozen

| Address range | Size | Slave | Interface | Access |
|---|---|---|---|---|
| `0x0000_0000` – `0x0000_3FFF` | 16 KB | Instruction SRAM | AXI4 | Read-only (from core IMEM master) |
| `0x0000_4000` – `0x0000_7FFF` | 16 KB | Data SRAM | AXI4 | Read / Write |
| `0x0000_8000` – `0x0000_8FFF` | 4 KB | sys_ctrl (CHIP_ID, RST_CAUSE, SCRATCH) | AXI4→APB | Read / Write |
| `0x0000_9000` – `0x0000_9FFF` | 4 KB | GPIO | AXI4→APB | Read / Write |
| `0x0000_A000` – `0x0000_AFFF` | 4 KB | UART | AXI4→APB | Read / Write |
| `0x0000_B000` – `0x0000_BFFF` | 4 KB | SPI | AXI4→APB | Read / Write |
| `0x0000_C000` – `0x0000_CFFF` | 4 KB | Timer | AXI4→APB | Read / Write |
| `0x0000_D000` – `0x0000_DFFF` | 4 KB | Watchdog | AXI4→APB | Read / Write (counter in CLK_WDT) |
| `0x0000_E000` – `0x0000_E7FF` | 2 KB | PLIC | AXI4→APB | Read / Write |
| `0x0000_E800` – `0x0000_EFFF` | 2 KB | CLINT | AXI4→APB | Read / Write |
| `0x0000_F000` – `0x0000_F07F` | 128 B | ASCON-128 AEAD | AXI4-Lite | Read / Write |
| `0x0000_F080` – `0xFFFF_FFFF` | — | **Unmapped** | — | AXI4 DECERR → core trap |

**Decode:** 3-way AXI4 address demux in `soc_top.sv` routes based on `addr[15:12]`:
- `addr[15:14] == 2'b00` → IMEM / DMEM
- `addr[15:12] == 4'hF` → ASCON (AXI4-Lite)
- all others in `0x8` – `0xE` range → AXI4→APB bridge → APB interconnect

**ASCON on AXI4-Lite:** ASCON is attached as a **direct AXI4-Lite slave**. The core's DMEM master is constrained to single-beat, 4-byte-aligned transactions (`arlen=awlen=8'd0`, `arsize=awsize=3'b010`, `arlock=awlock=1'b0`), which matches the AXI4-Lite subset exactly. No bridge is required — the demux routes `VALID`/`READY`/`addr`/`data`/`strobes`/`resp` straight into ASCON's AXI4-Lite port. The AXI4-specific signals (burst length, burst type, ID, lock, cache attributes, last-beat) are left unconnected on the ASCON side.

**Unmapped-access policy:** Any read or write outside the mapped regions returns an AXI4 `DECERR` (`bresp = 2'b11` / `rresp = 2'b11`). The core treats this as a Load/Store access fault (`mcause = 0x5` for load, `0x7` for store — see §1.5).

**No overlaps.** Verified by inspection and by the Milestone 4 firmware test `soc_memory_test`.

---

## 1.9 Interrupt Map Frozen

**Controller topology:**

- **PLIC** handles all peripheral interrupts and drives `irq_external` into the core (mip.MEIP).
- **CLINT** handles timer compare and software interrupts, driving `irq_timer` (mip.MTIP) and `irq_software` (mip.MSIP).

**PLIC interrupt source table (30 sources, 2 targets — M-mode hart 0 context + 1 reserved):**

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
| 15 | Watchdog pre-timeout | 6 | Level (from CLK_WDT via 2-FF sync) |
| 16 | Watchdog timeout (reset coming) | 7 | Level (highest) |
| 17 | ASCON — operation complete | 4 | Edge-rising |
| 18 | ASCON — auth failure | 6 | Edge-rising |
| 19 – 30 | Reserved (expansion) | — | Hardwired 0 for now |

**Priority scheme:** 3-bit priority (0 = disabled, 7 = highest). Higher numeric = higher priority. Ties broken by lower IRQ number first.

**Claim/complete:** Standard RISC-V PLIC protocol — handler reads `claim` register, services, writes same id back to `complete`.

**CLINT interrupt sources:**

| Signal | Source | mip bit |
|---|---|---|
| `irq_timer` | `mtimecmp` ≤ `mtime` | MTIP [7] |
| `irq_software` | CLINT `msip` register bit 0 | MSIP [3] |

**Frozen in RTL:** `Peripherals/PLIC/`, `Peripherals/CLINT.sv`, `Peripherals/TIMER.sv`.

---

## 1.10 Clock and Reset Architecture Defined

The SoC runs on a **two-clock, three-reset-source** architecture. The Analog Block (provided by 1-TOPS as IP) delivers the raw primitives (LDO, POR, PLL, LF reference); a dedicated **Clock + Reset Controller (CCRC)** turns them into the digital `CLK_SYS` / `CLK_WDT` clocks and the `sys_rst_n` / `wdt_rst_n` reset trees.

See `figures/clock_architecture.drawio` and `figures/reset_architecture.drawio` for the detailed diagrams. A compact summary is below.

### 1.10.1 Clock sources

| Source | Frequency | Path | Purpose |
|---|---|---|---|
| XTAL into analog PLL | 25 MHz → **800 MHz** | `CLK_PLL` from Analog Block | Divided to CLK_SYS (100 MHz) for all digital blocks |
| XTAL / N (in CCRC) or LF OSC (in analog) | **32.768 kHz** | `CLK_WDT` | Always-on watchdog counter |

### 1.10.2 Clock domains

| Domain | Frequency | Scope | Reset |
|---|---|---|---|
| `CLK_SYS` | 100 MHz | `rv32_core_top`, IMEM, DMEM, ASCON, AXI4→APB bridge, APB interconnect, `sys_ctrl`, `ccrc` APB side, all 7 APB peripherals | `sys_rst_n` |
| `CLK_WDT` | 32.768 kHz | Watchdog counter core (always-on, survives PLL glitches) | `wdt_rst_n` |

All blocks on `CLK_SYS` share the same clock edge → **no internal CDC** within the digital design. The Booth multiplier (3 cy) and restoring divider (33 cy) are multi-cycle *within* CLK_SYS, handled by the `mdu_stall` handshake — this is **not** a CDC. The AXI4 ↔ APB bridge is pure protocol conversion inside CLK_SYS — also not a CDC.

### 1.10.3 Clock tree diagram

```
   ┌─────────────────────────────────────────────────────────────┐
   │              ANALOG BLOCK  (1-TOPS provided IP)             │
   │                                                             │
   │   XTAL_IN ──┐                                               │
   │   XTAL_OUT ─┤                                               │
   │             │  ┌─────┐   ┌─────┐   ┌─────────────────────┐  │
   │             └──│ LDO │   │ POR │   │ PLL   25 → 800 MHz  │  │
   │                └──┬──┘   └──┬──┘   └─────────┬───────────┘  │
   │                   │         │                │              │
   │                VDD/VDDIO  POR_N        CLK_PLL, PLL_LOCK    │
   └───────────────────┼─────────┼────────────────┼──────────────┘
                       │         │                │
                       ▼         ▼                ▼
   ┌─────────────────────────────────────────────────────────────┐
   │              CCRC   (rtl/soc/ccrc.sv)                       │
   │                                                             │
   │   /8 divider  →  clk mux (PLL | XTAL fallback)  → CLK_SYS   │
   │   /763 LF divider on XTAL                       → CLK_WDT   │
   │   PLL_LOCK → 2-FF sync on XTAL                              │
   │   Reset combine (POR_N & PAD_RSTN & sync_pll_lock)          │
   │       → 2-FF async-assert / sync-release on CLK_SYS         │
   │       → sys_rst_n                                           │
   │   Independent 2-FF sync-release on CLK_WDT                  │
   │       → wdt_rst_n                                           │
   │   Reset-cause latch                            → rst_cause  │
   └─────┬──────────────┬───────────────┬──────────────┬─────────┘
         │              │               │              │
     CLK_SYS         CLK_WDT        sys_rst_n     wdt_rst_n
    (100 MHz)     (32.768 kHz)
         │              │               │              │
         ▼              ▼               ▼              ▼
   ┌─────────────────────────────┐   ┌───────────────────────────┐
   │ CLK_SYS DOMAIN              │   │ CLK_WDT DOMAIN            │
   │ core, IMEM, DMEM, ASCON,    │   │ Watchdog counter          │
   │ AXI4↔APB bridge,            │   │ (Gray-coded counter;      │
   │ APB interconnect,           │   │  readback → 2-FF sync     │
   │ sys_ctrl, ccrc APB side,    │   │  to CLK_SYS APB)          │
   │ GPIO, UART, SPI, Timer,     │   │                           │
   │ PLIC, CLINT                 │   │ 1 CDC crossing in / out   │
   └─────────────────────────────┘   └───────────────────────────┘
```

### 1.10.4 Reset sources

| Source | Kind | Driven by | Scope | Cause code |
|---|---|---|---|---|
| Analog POR | Async, cold | POR cell in analog block | Whole SoC | `POR` (0001) |
| External pad `PAD_RSTN` | Async, cold | Off-chip reset pin (CMOS + Schmitt) | Whole SoC | `PAD` (0010) |
| `PLL_LOCK` | Gating signal | Analog PLL | Gates sync-release of `sys_rst_n` | — |
| Watchdog timeout | Warm | WDT counter (CLK_WDT) | CLK_SYS domain only | `WDT` (0100) |
| Software reset | Warm | `sys_ctrl` register write | CLK_SYS domain only | `SW`  (1000) |

### 1.10.5 Reset architecture diagram

```
   Analog POR_N  ───┐
   PAD_RSTN      ───┤──► AND ──► cold_rst_n (async)
   PLL_LOCK  → [2-FF sync on XTAL] ──┘

                                     ┌─────────────────────┐
                                     │ 2-FF sync-release   │
                     cold_rst_n ────►│ on CLK_SYS          │
                                     └─────────┬───────────┘
                                               │
   Warm sources ─────────┐                     │
       wdt_reset ──[2FF sync CLK_SYS]──┐       │
       sw_reset  ─────────────────────── OR ───┤
                                               │
                                               ▼
                                          sys_rst_n
                                               │
                                     ┌─────────┴────────┐
                                     │  reset tree      │
                                     │  (CTS-buffered)  │
                                     └──┬───┬───┬───┬───┘
                                        │   │   │   │
                                       core bridge IMEM APB periphs ...

   cold_rst_n ─► [2-FF sync on CLK_WDT] ─► wdt_rst_n ─► WDT counter
```

### 1.10.6 Reset release sequence

| Step | Event |
|---|---|
| 1 | Power rails rise → LDO stabilises → analog `POR_N` de-asserts |
| 2 | XTAL starts, PLL enters tracking, `PLL_LOCK` asserts |
| 3 | CCRC 2-FF-syncs `PLL_LOCK` onto the XTAL-driven clock |
| 4 | `cold_rst_n = POR_N & PAD_RSTN & sync_pll_lock` → 1 |
| 5 | 2-FF sync-release drives `sys_rst_n = 1` on CLK_SYS |
| 6 | Reset tree de-asserts across all CLK_SYS blocks |
| 7 | Core begins IF at `RESET_PC = 0x0000_0000` (IMEM boot) |

### 1.10.7 Clock domain crossing (CDC) table

Every genuine clock-domain crossing in the design. SpyGlass CDC must report **zero unwaived violations** for G3.15 sign-off.

| # | Source domain | Destination domain | Signal(s) | Sync policy |
|---|---|---|---|---|
| 1 | Analog (POR) | CLK_SYS reset tree | `POR_N` | Async-assert / sync-release (2-FF) |
| 2 | Pad | CLK_SYS reset tree | `PAD_RSTN` | Async-assert / sync-release (2-FF) |
| 3 | Analog (PLL) | CCRC (XTAL clk) | `PLL_LOCK` | 2-FF synchroniser |
| 4 | Pad | CLK_SYS (UART) | `uart_rx` | 2-FF inside UART input stage |
| 5 | Pad | CLK_SYS (GPIO) | `gpio_in[31:0]` | 2-FF inside GPIO input stage |
| 6 | Pad | CLK_SYS (SPI) | `spi_miso` | 2-FF inside SPI master |
| 7 | Pad | CLK_SYS (PLIC) | `ext_irq` (if added) | 2-FF inside PLIC gateway |
| 8 | CLK_WDT | CLK_SYS APB | WDT counter readback | Gray-coded + 2-FF sync |
| 9 | CLK_SYS APB | CLK_WDT | WDT config writes (enable, reload) | Toggle-sync + ack handshake |
| 10 | Pad (TCK) | CLK_SYS | JTAG `tck`/`tms`/`tdi` (future) | RISC-V Debug Module v0.13 |

**Explicitly NOT CDC** (recorded to pre-empt reviewer questions):
- Core pipeline ↔ MDU (Booth 3 cy, divider 33 cy) — same CLK_SYS, multi-cycle via `mdu_stall`.
- AXI4 ↔ APB bridge — both on CLK_SYS; protocol conversion only.
- Core ↔ IMEM / DMEM / ASCON — all on CLK_SYS.
- PLIC / CLINT ↔ core — all on CLK_SYS.

### 1.10.8 Async-to-sync strategy (SpyGlass-enforceable rules)

1. **Every external pad input** passes through a 2-FF synchroniser clocked by CLK_SYS before any combinational logic.
2. **Every reset signal** uses async-assert, sync-release on the destination clock. No logic between the two sync-release flops.
3. **Multi-bit values crossing domains** (current case: WDT counter → APB) use Gray coding + 2-FF sync. Single-bit control signals use toggle-sync with acknowledge.
4. **CDC waivers** listed with a one-line rationale each in `scripts/spyglass_cdc_waivers.tcl`.
5. **Reset synchroniser flops** must be back-to-back, same clock, same reset source, no clock-gating — tagged as `set_false_path` in SDC.

### 1.10.9 Frozen in RTL / scripts

- `rtl/soc/ccrc.sv` — clock and reset controller (divider, mux, PLL_LOCK sync, reset combining, reset-cause latch)
- `rtl/soc/sys_ctrl.sv` — APB-visible chip ID / reset-cause mirror / scratch / SW-reset trigger
- SDC: `scripts/ccrc.sdc` — defines `CLK_SYS` at 10 ns, `CLK_WDT` at 30.5 µs, `set_false_path` on the two reset-synchroniser arcs, `set_clock_groups -asynchronous` between CLK_SYS and CLK_WDT
- SpyGlass CDC project: `scripts/spyglass_soc_lint_cdc.tcl` — updated to declare both domains and the WDT crossing

---

## 1.11 Pin List / Chip IO Table Frozen

**Top-level module:** `soc_top`.

**Chip IO summary (digital + analog):**

| Signal | Dir | Width | Function | Pad type |
|---|---|---|---|---|
| **Clock + crystal** | | | | |
| `XTAL_IN` | AI | 1 | PLL reference crystal — pin 1 | Analog input pad |
| `XTAL_OUT` | AO | 1 | PLL reference crystal — pin 2 | Analog output pad |
| **Chip reset** | | | | |
| `PAD_RSTN` | I | 1 | Async active-low chip reset | CMOS input + Schmitt |
| **UART** | | | | |
| `uart_rx` | I | 1 | UART receive data | CMOS input |
| `uart_tx` | O | 1 | UART transmit data | CMOS tri-state output |
| **SPI master** | | | | |
| `spi_sclk` | O | 1 | SPI clock out | CMOS output |
| `spi_mosi` | O | 1 | SPI master-out slave-in | CMOS output |
| `spi_miso` | I | 1 | SPI master-in slave-out | CMOS input |
| `spi_cs_n[0]` | O | 1 | SPI chip select 0 (active-low) | CMOS output |
| **GPIO** | | | | |
| `gpio[31:0]` | IO | 32 | GPIO bidirectional | CMOS bi-directional pad with OE |
| **JTAG / Debug (TBD, planned)** | | | | |
| `tck` | I | 1 | JTAG test clock | CMOS input |
| `tms` | I | 1 | JTAG mode select | CMOS input + pull-up |
| `tdi` | I | 1 | JTAG data in | CMOS input + pull-up |
| `tdo` | O | 1 | JTAG data out | CMOS output |
| `trst_n` | I | 1 | JTAG async reset (optional) | CMOS input + pull-up |
| **Supplies** | | | | |
| `VDD` | P | — | 0.7 V core supply | Core supply pad |
| `VDDIO` | P | — | 1.8 V IO supply (TBD) | IO supply pad |
| `VDDA` | P | — | Analog supply (PLL/LDO/POR) | Analog supply pad |
| `VSS` | P | — | Core ground | Ground pad |
| `VSSA` | P | — | Analog ground | Analog ground pad |

**Pad-cell library:** TBD — tied to chosen production PDK (currently ASAP7 exploratory; 28 nm foundry pad library pending).

**Total chip signal pin count:** approx **41** signal pins (not counting supplies):
- 2 crystal (XTAL_IN/OUT)
- 1 PAD_RSTN
- 2 UART
- 4 SPI
- 32 GPIO (bi-dir)
- ~5 JTAG (final count pending G9.1)
