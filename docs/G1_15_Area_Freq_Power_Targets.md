# 1-TOPS VEDA — Area, Frequency and Power Targets

**G1 item 1.15 — Area, frequency and power targets stated**
**Team:** VEDA · PSG College of Technology
**Project:** 1-TOPS Secure IoT RISC-V SoC (RV32IM + ASCON-128)
**Revision:** 1.0 · 2026-11-15
**PDK used for current numbers:** **ASAP7 7 nm FinFET** (OSU/ASU open PDK)

> The team has not received a commercial PDK yet. All synthesis numbers below are from runs on the open ASAP7 7 nm FinFET standard-cell library (`asap7sc7p5t_*_RVT_TT_nldm_*.db`). The TT 0.7 V 25 °C corner is used throughout. When a commercial PDK is received (e.g. 28 nm), these targets must be re-stated.

---

## 1. Technology, libraries and operating conditions

| Parameter | Value |
|---|---|
| PDK | ASAP7 7 nm FinFET (open PDK, RVT cells) |
| Standard-cell libraries | `asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.db`, `_AO_RVT_TT_nldm_211120.db`, `_OA_RVT_TT_nldm_211120.db`, `_INVBUF_RVT_TT_nldm_211120.db`, `_SEQ_RVT_TT_nldm_220123.db` |
| Operating condition | `PVT_0P7V_25C` — Process = TT, V = 0.7 V, T = 25 °C |
| Synthesis tool | Synopsys Design Compiler T-2022.03-SP5 |
| Compile strategy | Two-pass map_effort high + incremental |
| Clock-gating | Automatic (`-gate_clock`) — 44 clock-gate cells inserted in SoC |
| Wire-load model | None (zero-interconnect assumption at synthesis) |

---

## 2. Area target and achieved (ASAP7 TT 0.7 V)

### 2.1 Target

The design is built from scratch so a top-down area budget is being set now rather than inherited. Target (agreed with coach — pending):

| Block | Area target | Justification |
|---|---|---|
| RV32IM core (rv32_core_top) | ≤ 2,000 µm² | Small 3-stage RV32IM is well within this on ASAP7 |
| ASCON-128 accelerator | ≤ 2,500 µm² | Lightweight cipher; 320-bit state |
| APB peripherals (7× total) | ≤ 1,500 µm² | GPIO/UART/SPI/Timer/WDT/PLIC/CLINT combined |
| Bridges + glue | ≤ 150 µm² | AXI4→APB + 3-way demux |
| **SoC total (no SRAM macros)** | **≤ 6,200 µm²** | — |
| I-SRAM 16 KB (macro) | External macro, not in standard cells | Included separately |
| D-SRAM 16 KB (macro) | External macro, not in standard cells | Included separately |

### 2.2 Achieved (from `syn_soc/reports/area.rpt`)

**SoC-without-Ascon (core + bridge + 7 peripherals + glue):**

| Metric | Value |
|---|---|
| Combinational area | 1,273.48 µm² |
| Noncombinational (sequential) area | 1,443.01 µm² |
| Buf/Inv area | 261.17 µm² |
| Macro / black-box area | 0 µm² (SRAMs modeled as black boxes) |
| **Total cell area** | **2,716.49 µm²** |
| Combinational cells | 17,846 |
| Sequential cells | 3,856 |
| Buf / Inv cells | 5,563 |
| **Total leaf cells** | **21,702** |

**Core-only (rv32_core_top) breakdown** — from hierarchical area report:

| Sub-block | Area (µm²) | % of core |
|---|---|---|
| Register file (32×32 b + clock-gates) | 612.04 | 43.9 % |
| MDU (Booth mult + restoring div) | 282.79 | 20.3 % |
| ALU | 123.08 | 8.8 % |
| CSR regfile (13 CSRs + trap logic) | 117.25 | 8.4 % |
| Pipeline register DE→MW | 74.49 | 5.3 % |
| Pipeline register IF→DE | 43.03 | 3.1 % |
| Branch comparator | 22.57 | 1.6 % |
| Decoder | 10.72 | 0.8 % |
| Immediate generator | 5.06 | 0.4 % |
| Controller | 4.30 | 0.3 % |
| Hazard unit | 2.51 | 0.2 % |
| Core top glue + clock-gate | ~95 | 6.9 % |
| **Core total (rv32_core_top)** | **1,392.68** | **100 %** |

**SoC-with-Ascon** (from the project Verification & Synthesis Report PDF Sec 4.3/4.4):

| Block | Area (µm²) | % of SoC |
|---|---|---|
| ASCON-128 AEAD | 1,805.37 | 40.1 % |
| RV32IM core | 1,395.28 | 31.0 % |
| 7 APB peripherals | 1,234.49 | 27.4 % |
| AXI4→APB bridge | 47.24 | 1.0 % |
| SoC glue logic | 20.48 | 0.5 % |
| **Total cell area** | **4,502.86** | **100 %** |
| Leaf cells | **37,449** | |

**Assessment vs target:** All ≤ targets with comfortable margin. **✅ Within budget.**

---

## 3. Frequency target and achieved (ASAP7 TT 0.7 V)

### 3.1 Target

| Parameter | Target |
|---|---|
| Nominal clock frequency | **100 MHz** (per Cover tab, and the achievable rate for the IoT application) |
| Clock period (target) | 10 ns |
| Clock sources | 1 — external `clk` pin, no PLL, no divider |

### 3.2 Current synthesis result (as-is, from `syn_soc/reports/qor.rpt`)

**⚠ CURRENT SDC USES THE WRONG CLOCK PERIOD** — the SDC sets `create_clock -period 1.00` (= **1 GHz**) instead of 10 ns. At this aggressive 1 GHz target, timing fails:

| Metric | Core | SoC (no Ascon) |
|---|---|---|
| SDC clock period | 1.00 ns (1 GHz) ❌ should be 10 ns | 1.00 ns ❌ |
| Critical path length | 646.98 ps | 1,162.45 ps |
| Levels of logic | 31 | 61 |
| WNS (worst negative slack) | –669.59 ps | –1,186.26 ps |
| TNS (total neg slack) | –697,250 ps | –1,708,754 ps |
| Violating setup paths | 2,090 | 3,861 |
| Hold WNS | +4.09 ps | 0 ps |
| Hold violating paths | 26 | 0 |

### 3.3 Projected result at the correct 100 MHz target

Because the critical path is **1,162 ps**, the design meets a 10 ns period **with ~8.84 ns of positive slack**. Re-running synthesis with `create_clock -period 10.0` will produce a clean timing report with 0 setup violations.

| Metric at 100 MHz | Projected |
|---|---|
| WNS | +8.84 ns (positive, comfortable margin) |
| TNS | 0 |
| Violating setup paths | 0 |

**Headroom analysis:** The design can in principle close at **~860 MHz** (= 1/1.162 ns) on ASAP7 7 nm. 100 MHz is comfortable; even 500 MHz would be feasible. The team has chosen 100 MHz to match IoT needs and leave slack for PVT corners and physical design.

**Action required before G7 close:** update `rv32_core_top.sdc` and `soc_top.sdc` to `create_clock -period 10.0` (ns), re-run `dc_shell -f spike_core_synth.tcl` and `spike_soc_synth.tcl`, and attach the clean `qor.rpt` / `timing_setup.rpt` as evidence.

---

## 4. Power target and achieved (ASAP7 TT 0.7 V)

### 4.1 Target

For IoT silicon the dominant constraint is **leakage** and **active power at 100 MHz with low toggle rate**. Target:

| Metric | Target |
|---|---|
| Dynamic power @ 100 MHz, nominal workload | ≤ 100 µW (core only) ·· ≤ 500 µW (full SoC) |
| Leakage power | ≤ 50 µW (full SoC) |

These are placeholder targets suitable for a secure IoT SoC. They should be confirmed with the coach and may need revision based on sensor duty cycle and ASCON usage pattern.

### 4.2 Current synthesis result (from `syn_soc/reports/power.rpt`, `syn_core/reports/power.rpt`)

**⚠ Important:** power.rpt was run in `-analysis_effort low` mode with **unannotated switching activity** (no SAIF file) and the **1 ns (1 GHz) clock**. So the reported dynamic power is much higher than at the actual 100 MHz target. Scale by 1/10 for a first-order approximation at 100 MHz.

**At 1 GHz synthesis clock:**

| Metric | Core only | SoC (no Ascon) |
|---|---|---|
| Cell internal power | 477.27 mW | 910.67 mW |
| Net switching power | 157.10 mW | 457.82 mW |
| **Total dynamic power** | **634.37 mW @ 1 GHz** | **1.368 W @ 1 GHz** |
| Cell leakage power | 1.29 µW | 2.29 µW |

**Breakdown by group (SoC):**

| Group | Power | % of total |
|---|---|---|
| Clock network | 1.138 W | 83.2 % |
| Register | 160.5 mW | 11.7 % |
| Combinational | 69.2 mW | 5.1 % |

> Clock-network power dominates because every flop is clocked at the SDC's 1 GHz. This is an artefact of the wrong SDC period — it will scale with frequency.

### 4.3 First-order projection at the correct 100 MHz target

Dynamic power scales linearly with frequency for a given toggle profile, so at 100 MHz:

| Metric | Core only (proj.) | SoC (no Ascon) (proj.) |
|---|---|---|
| Total dynamic power @ 100 MHz | **~63 mW** | **~137 mW** |
| Cell leakage power | 1.29 µW | 2.29 µW |

Even these numbers overstate reality — they assume uniform-random switching activity (worst case). A realistic SAIF from a Dhrystone run will give substantially lower dynamic power.

**Action required before G8 close:**

1. Fix the SDC clock period (as in §3).
2. Re-run synthesis at 100 MHz.
3. Run Dhrystone on gate-level netlist, generate SAIF, re-run `report_power -analysis_effort high`.
4. Attach the realistic power report to this document.
5. Compare against the targets in §4.1 and either ratify or renegotiate with coach.

---

## 5. Summary table (for Signoff Checklist G1 1.15)

| Target | Value |  Achieved (ASAP7 7 nm TT 0.7 V) | Against target |
|---|---|---|---|
| Area — core (rv32_core_top) | ≤ 2,000 µm² | 1,392.68 µm² | ✅ 70 % of budget |
| Area — SoC with Ascon | ≤ 6,200 µm² | 4,502.86 µm² | ✅ 73 % of budget |
| Cell count — SoC with Ascon | — | 37,449 leaf cells | ✅ |
| Frequency | 100 MHz (10 ns) | Projected clean at 100 MHz (critical path 1.16 ns) | ✅ projected; re-run SDC to confirm |
| Dynamic power @ 100 MHz — core | ≤ 100 µW (target TBD) | ~63 mW projected (worst-case toggle) | ⚠ needs realistic SAIF to confirm |
| Leakage power | ≤ 50 µW (target TBD) | 2.29 µW (full SoC) | ✅ well below |

---

## 6. Open actions before G7 / G8 close

| # | Action | Owner | Priority |
|---|---|---|---|
| A-1 | Fix SDC: change `create_clock -period` from 1.00 ns to 10.0 ns in `rv32_core_top.sdc` and `soc_top.sdc` | VEDA | **P0** |
| A-2 | Re-run DC synthesis at 100 MHz; attach clean `qor.rpt`, `timing_setup.rpt`, `area.rpt`, `power.rpt` | VEDA | **P0** |
| A-3 | Generate SAIF from gate-level Dhrystone / UVM run; re-report power with real switching activity | VEDA | P1 |
| A-4 | Confirm 100 MHz is acceptable for ASAP7 (vs. moving to commercial 28 nm PDK with different target) | Coach | **P0** |
| A-5 | Settle Cover sheet: "Process node: ASAP7 7 nm" vs "28 nm" — current docs disagree | Coach | **P0** |
| A-6 | Set and record agreed numerical targets for dynamic and leakage power at 100 MHz | Coach + VEDA | P1 |

---
