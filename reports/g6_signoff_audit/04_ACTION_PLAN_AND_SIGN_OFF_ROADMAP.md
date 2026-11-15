# Action Plan & Step-by-Step Signoff Roadmap

This roadmap provides a structured sequence of actions for Team VEDA to complete Gate G6 and achieve 100% signoff approval from the technical coach.

---

## Phase 1: Architectural Alignment & Specification Clean-Up (Immediate)

1. **Clarify SRAM and Boot ROM Sizes in Documentation**:
   - Update `1-TOPS_SOCArchitecture_VEDA_PSG_College_of_Technology.docx` Table 10 to reflect:
     - Boot ROM: **4 KB** (`0x0000_0000` – `0x0000_0FFF`)
     - Instruction SRAM (IMEM): **16 KB** (`0x0001_0000` – `0x0001_3FFF`)
     - Data SRAM (DMEM): **16 KB** (`0x0002_0000` – `0x0002_3FFF`)
2. **Clarify Pin List & Pad Types (Review Item 10)**:
   - Add pad types (`PIDC`, `PODC`, `PIODC`), drive strengths (8 mA), and pull states to the Pin Table.
3. **Align Area & Frequency with Coach (Review Item 13)**:
   - Formally confirm the technology node (65 nm vs 28 nm), target clock (100 MHz), and die area target with the coach.

---

## Phase 2: RTL Fixes & Static Audits (1–2 Days)

1. **Apply Trap & Interrupt Patch to Core RTL (Review Item 4 / G6.5)**:
   - Apply the code patch to `csr_regfile.sv` and `rv32_core_top.sv` to enable real hardware interrupt trap handling.
2. **Apply SpyGlass / Lint Latch Patch (Review Item 18)**:
   - Update `csr_regfile.sv` to explicitly assign all 32 bits of `mip` to eliminate the latch warning.
   - Clean up null statements in `decoder.sv` and unused signal warnings.
3. **Add Reset Synchronizer (Review Item 9)**:
   - Integrate `rst_sync.sv` at `soc_top.sv` to safely synchronize `ext_rst_n`.
4. **Implement Bus Error Responses (Review Item 7 / G6.7)**:
   - Update `apb_interconnect.sv` to return `pslverr = 1'b1` on unmapped access.
5. **Add System Control Block `sys_ctrl.sv` (Review Item 17)**:
   - Instantiate synthesizable registers for Chip ID, reset status, and software reset.

---

## Phase 3: Verification Execution & Coverage Closure (2–3 Days)

1. **Unify the Master Regression Makefile (Review Item 2 / G6.17)**:
   - Add `regress_soc_nocore` and `regress_soc_core` targets to the root Makefile so that running `make regress` executes all testbenches.
2. **Run RISCV-DV with Fixed Seed Count $N=50$ (Review Item 20 / G5.5)**:
   - Execute the 50-seed regression script, collect logs, and generate `riscv_dv_summary.log`.
3. **Execute G6 Phase 4 (No-Core SoC) Verification (Items 6.1 – 6.8)**:
   - Run `soc_tests.sv` in `uvm_soc_nocore_verification`.
   - Close register field functional coverage (`soc_no_core_coverage.sv`) and generate HTML/UCDB report (Items 6.2, 6.3).
   - Run unmapped memory access tests to verify `DECERR` / `PSLVERR` (Item 6.7).
   - Run traffic stress test (Item 6.8).
4. **Execute G6 Phase 5 (Full SoC With Core) Verification (Items 6.9 – 6.18)**:
   - Compile a minimal bare-metal C boot program (`boot.c` and `crt0.s`) and load into Boot ROM / IMEM.
   - Verify core boots, fetches from ROM, and executes application in SRAM (Item 6.9).
   - Verify interrupt servicing end-to-end with UART and Timer (Item 6.5, 6.13).
   - Measure SoC code coverage with QuestaSim (`-cover bcesft`) to demonstrate $\ge 95\%$ (Item 6.16).

---

## Phase 4: Git Handoff & Formal Signoff (Final Step)

1. **Git Commit & Tagging (Review Item 1 / G6.19)**:
   - Initialize/clean Git repository, commit all final RTL, testbenches, and reports.
   - Create annotated tag:
     ```bash
     git tag -a v1.0_rtl_freeze -m "Official RTL and Verification Freeze for G6 Signoff"
     git push origin main --tags
     ```
2. **Update Signoff Checklist Spreadsheet (`1TOPS_Project_Signoff_Checkl (1).xlsx`)**:
   - Update statuses for G4.9, G4.13, G5.5, G6.1 to G6.19 from `Not Started` to `Done`.
   - Populate column G (*Evidence*) with relative paths to logs, reports, and coverage files.
3. **Present Gate G6 to Coach**:
   - Submit the documentation package in `mytaskinchecksignoff/` alongside simulation logs for coach signature.
