# 1-TOPS VEDA — Area, Frequency and Power Targets

**G1 item 1.15 — Area, frequency and power targets stated**
**Team:** VEDA · PSG College of Technology
**Project:** 1-TOPS Secure IoT RISC-V SoC (RV32IM + ASCON-128)
**Target process:** TSMC 28 nm (LP / HPC variant TBD on PDK delivery)
**Target tape-out:** 1 December 2026
**Revision:** 2.0 · 2026-11-17

---

## 1. Scope

The targets stated below apply at tape-out sign-off on the TSMC 28 nm standard-cell library at the typical corner (TT, 0.9 V, 25 °C), **post-route**. Numerical estimates are based on scaling our pre-silicon synthesis results and standard 28 nm IoT SoC reference data.

---

## 2. Area targets

| Block | Target area (post-route) | Notes |
|---|---|---|
| RV32IM core (`rv32_core_top`) | ≤ 20,000 µm² | 3-stage pipeline, Booth MDU, CSRs |
| ASCON-128 accelerator | ≤ 20,000 µm² | AEAD engine + AXI4-Lite wrapper |
| 7 APB peripherals (GPIO/UART/SPI/Timer/WDT/PLIC/CLINT) | ≤ 15,000 µm² | Combined |
| AXI4 ↔ APB bridge + APB interconnect | ≤ 1,500 µm² | |
| CCRC + sys_ctrl | ≤ 2,500 µm² | Clock/reset + chip-info regs |
| **Digital total (standard cells)** | **≤ 60,000 µm² (~0.06 mm²)** | Excludes SRAM macros |
| I-SRAM 16 KB (macro) | ~0.12 mm² | TSMC SRAM compiler, TBD on delivery |
| D-SRAM 16 KB (macro) | ~0.12 mm² | TSMC SRAM compiler, TBD on delivery |
| Analog block (PLL + LDO + POR, 1-TOPS IP) | ~0.15 mm² | Fixed footprint from analog IP |
| Pad ring + seal ring + decaps | — | Dominated by minimum pad count; ~1 mm² die likely |
| **Target die area** | **≤ 1.5 mm²** | Pad-limited for this signal count |

---

## 3. Frequency target

| Parameter | Target |
|---|---|
| CLK_SYS target frequency | **100 MHz** |
| CLK_SYS period | 10.0 ns |
| CLK_WDT frequency | 32.768 kHz |
| WNS (worst negative slack) at sign-off | ≥ 0 ns, all corners |
| Hold violations at sign-off | 0, all corners |
| Clock sources | 1 — PLL output (from analog block, divided by 8 in CCRC) |
| Clock domains | 2 — CLK_SYS, CLK_WDT (asynchronous to each other) |

---

## 4. Power targets

Measured at TT 0.9 V 25 °C, 100 MHz operation, realistic firmware toggle profile.

| Mode | Metric | Target |
|---|---|---|
| **Active (100 MHz, typical IoT workload)** | Total dynamic power | ≤ 50 mW |
| | Of which core | ≤ 20 mW |
| | Of which ASCON during encryption | ≤ 15 mW (peaks only) |
| | Of which peripherals + buses | ≤ 15 mW |
| **Standby (clocks on, no activity)** | Dynamic power | ≤ 5 mW |
| | Leakage power (digital + SRAM) | ≤ 100 µW |
| **Deep sleep (CLK_SYS gated, CLK_WDT alive)** | Total chip power | ≤ 50 µW |
| **Energy per crypto block (ASCON-128, 128-bit block)** | — | ≤ 1 nJ / block |

---

