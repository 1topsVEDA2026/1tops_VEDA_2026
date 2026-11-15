# 1-TOPS SoC Project Signoff Checklist — G6 Deep Dive & Review Audit

**Team**: VEDA — PSG College of Technology  
**Project**: Secure IoT Crypto SoC Based on ASCON-128 (RV32IM Core + ASCON-128 + AXI4/APB Peripherals)  
**Document Context**: Signoff Checklist Analysis & Review Action Items  
**Reference Workbook**: `1TOPS_Project_Signoff_Checkl (1).xlsx`  
**Reference Architecture**: `1-TOPS_SOCArchitecture_VEDA_PSG_College.pdf` / `.docx`

---

## 1. Executive Summary: What is G6 in the Excel Sheet?

In the 1-TOPS tape-out signoff methodology (from Architecture to Tape-Out), the project progress is tracked through 10 progressive gating milestones:

* **G0**: Tools, Environment & Approved Flow
* **G1**: Specification & Architecture Freeze
* **G2**: RTL Design — Core
* **G3**: SoC Integration
* **G4**: Verification Phase 1 & 2 — Unit and Core Sanity
* **G5**: Verification Phase 3 — Core with SW and Random Streams
* **G6**: **Verification Phase 4 & 5 — SoC without Core, then Full SoC** 👈 *(Your Assigned Task)*
* **G7**: Synthesis & DFT
* **G8**: Physical Design, STA & Physical Verification
* **G9**: Tape-Out Handoff

### The Purpose of Gate G6

Gate **G6** represents the **critical milestone before Synthesis (G7)**. Its primary mandate is to guarantee that:
1. **Phase 4 (SoC Without Core)**: The complete SoC bus interconnect (AXI4, AXI4-Lite, APB bridges) and peripheral subsystems (GPIO, UART, SPI, Timer, WDT, PLIC, CLINT, ASCON accelerator, SRAM, Boot ROM) are fully verified using a UVM testbench driven by an active AXI master verification IP (VIP).
2. **Phase 5 (Full SoC With Core)**: The RV32IM processor core is integrated into the SoC and successfully boots firmware, runs bare-metal C test programs, handles interrupts and exceptions from peripherals, and executes under concurrent bus traffic stress without hanging or deadlocking.
3. **Synthesis Freeze (6.19)**: The RTL is officially frozen, tagged in Git, and proven bug-free before logic synthesis and backend physical design begin.

---

## 2. Structure of the G6 Checklist in the Excel Sheet

The G6 sheet contains 19 specific signoff criteria (Rows 6.1 through 6.19). Each row tracks:
- **#**: Identification code (6.1 to 6.19).
- **Checklist Item**: The engineering milestone or requirement.
- **Signoff Criteria**: Objective, verifiable definition of "Done" expected by the coach and tape-out committee.
- **Tool**: Approved EDA tool required for signoff (VCS / Verdi / QuestaSim / Git).
- **Status**: Current milestone status (`Done`, `In Progress`, `Not Started`, `N/A`).
- **Owner**: Assigned engineer responsible for delivery.
- **Evidence**: Artifact link (simulation log, waveform VCD/FSDB, coverage database, testbench file).
- **Date Closed**: Completion timestamp.
- **Coach Approved**: Official formal signoff by the technical coach (`Yes` / `No`).
- **Comments / Waiver Reason**: Justification for waivers or notes.

---

## 3. High-Level Summary of G6 Items Status

| Item # | Checklist Item Description | Signoff Criteria | Current Status | Coach Approved | Current Project Reality & Gap |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **6.1** | UVM SoC testbench built | AXI master agent emulating CPU accesses, IRQ VIP, peripheral VIPs and coverage model | **Done** | No | Completed in `uvm_soc_nocore_verification` with QuestaSim UVM 1.1d testbench. Needs coach signoff. |
| **6.2** | Register tests pass | 100% of addressable registers read and written; RW/RO/W1C behaviour verified | **Done** | No | Verified for CLINT, PLIC, GPIO, UART, Timer, SPI, SysCtrl registers in `soc_peripheral_reg_test`. |
| **6.3** | Register field coverage closed | Field-level functional coverage on enable and mode combinations met | **Not Started** | No | `soc_no_core_coverage.sv` tracks basic address hits; full field-level cross coverage needs closure. |
| **6.4** | Per-IP use cases pass | TX and RX path exercised for each integrated peripheral against its VIP | **Done** | No | UART, SPI, GPIO, Timer exercised in `soc_tests.sv`. ASCON crypto engine needs inclusion. |
| **6.5** | Interrupt path verified end to end | Every source verified from peripheral event to controller input; masking and priority checked | **Not Started** | No | Peripheral IRQs trigger PLIC/CLINT in no-core TB, but **Core does not dispatch interrupt traps** in RTL! |
| **6.6** | Bus bridge protocol verified | AXI to AXI-Lite to APB: ordering, responses, alignment and byte enables correct | **Done** | No | AXI-to-APB bridge transactions verified in simulation. |
| **6.7** | Memory map decode verified | Every address range hit; unmapped access returns the defined error | **Not Started** | No | Address decoding works for valid peripherals, but **unmapped addresses do not return DECERR/PSLVERR**. |
| **6.8** | Traffic stress run | Long random peripheral traffic plus interrupts; no hangs, no protocol violations | **Not Started** | No | Needs a long-running constrained random test with simultaneous DMA/ASCON/UART traffic. |
| **6.9** | Boot from internal ROM passes | Core fetches from ROM and reaches `main()` | **Not Started** | No | Core boot PC (`0x0000_0000`) must fetch reset sequence from Boot ROM and jump to SRAM. |
| **6.10** | Boot from external SPI flash passes | Boot mode pin = 1: code fetched from the SPI flash model and executed | **Not Started** | No | Missing external boot mode pin/strap logic in `soc_top.sv` and SPI bootloader routine. |
| **6.11** | SRAM load / ROM remap boot passes | If supported: SRAM loaded from flash, remap occurs and execution continues | **Not Started** | No | Address remap logic is currently omitted in RTL (`rtl_keyword_search.rpt`). |
| **6.12** | Bare-metal C test suite passes | Memory march and walking-ones, timer/SW/external interrupts, UART/SPI/GPIO loopbacks | **Not Started** | No | Needs RISC-V GCC compiled C test programs running on `soc_top.sv`. |
| **6.13** | Trap robustness under load passes | Interrupts during load/store/branch-dense code; nested interrupt policy exercised if supported | **Not Started** | No | Requires core interrupt trap dispatch logic in `rv32_core_top.sv` to be implemented first. |
| **6.14** | SoC random and stress tests pass | Random arbitration, power-on reset sequences, interconnect backpressure and wait states | **Not Started** | No | Needs random wait-state insertion on AXI/APB buses during execution. |
| **6.15** | SoC functional coverage closed | Address map, interrupt sources and boot modes all covered | **Not Started** | No | UVM coverage collector must merge no-core and full-core runs to reach >= 100%. |
| **6.16** | SoC code coverage >= 95% | Statement, branch and toggle with written waivers | **Not Started** | No | Code coverage run with VCS/Verdi or QuestaSim (`-cover bcesft`) required. |
| **6.17** | Full regression clean | Directed, random and software suites: zero failures on the RTL handed to synthesis | **Not Started** | No | Master regression Makefile must run all unit, core, no-core, and full-SoC suites clean. |
| **6.18** | No deadlocks in long runs | Long-run test completes; no unbounded stalls | **Not Started** | No | Soak test of > 1,000,000 cycles without bus hung or pipeline deadlock. |
| **6.19** | RTL frozen for synthesis | Repo tagged; later changes need coach approval and a full regression re-run | **Done** *(Audit Flag)* | No | Marked Done in sheet, but Git repository has no release tag and has uncommitted files! |

---

## 4. Relationship to the User's 20 Checklist Items

The 20 review items listed in your prompt represent the **punchlist of technical issues, architectural ambiguities, and verification blockers** that must be resolved to bring G6 (and preceding gates G1-G5) to 100% formal signoff.

Detailed analysis and exact file-by-file corrections for all 20 items are documented in:
- `01_G6_SOC_VERIFICATION_DEEP_DIVE.md`
- `02_ALL_20_REVIEW_ACTION_ITEMS_AUDIT_AND_CORRECTIONS.md`
- `03_SPEC_VS_RTL_DISCREPANCIES_AND_FIXES.md`
- `04_ACTION_PLAN_AND_SIGN_OFF_ROADMAP.md`
