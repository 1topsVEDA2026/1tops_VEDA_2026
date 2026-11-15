# Rigorous Verification Audit Report: All "Not Done" Signoff Criteria

**Gate**: G6 (Verification Phase 4 & 5 — SoC without Core, then Full SoC)  
**Target Workbook**: `1TOPS_Project_Signoff_Checkl (1).xlsx`  
**Audit Scope**: Forensic inspection of all 14 "Not Started / Not Done" items in Gate G6, plus linked predecessor items (G3.9, G4.7, G4.9, G4.13, G5.5, G5.6, G5.10).

---

## 1. Executive Audit Summary

A forensic review of the source code, testbenches, simulation logs, and test scripts across `uvm_soc_nocore_verification`, `UVM_WITH_CORE`, `TOPS_FINAL`, and `1tops_VEDA_2026-main` reveals:

| Item # | Checklist Name | Signoff Criteria in Excel | Actually Verified in Files? | Current Audit Verdict | Critical Blocker / Evidence Gap |
| :---: | :--- | :--- | :---: | :---: | :--- |
| **6.3** | Register field coverage closed | Field-level functional coverage on enable and mode combinations met | ❌ **NO** | **UNVERIFIED (0%)** | `soc_no_core_coverage.sv` only has address bins (which don't match test addresses!); 0 field-level coverpoints exist. |
| **6.5** | Interrupt path verified end to end | Every source verified from peripheral event to controller input; masking/priority checked | ❌ **NO** | **BLOCKED BY RTL BUG** | `soc_interrupt_test` only writes to dummy regs. In `rv32_core_top.sv`, **CPU core never redirects PC on interrupts**! |
| **6.7** | Memory map decode verified | Every address range hit; unmapped access returns defined error | ❌ **NO** | **UNVERIFIED** | `soc_tests.sv` never accesses unmapped addresses. RTL does not generate `DECERR` on AXI or `PSLVERR` on APB. |
| **6.8** | Traffic stress run | Long random peripheral traffic plus interrupts; no hangs, no protocol violations | ❌ **NO** | **INSUFFICIENT (Toy Test)** | `soc_full_system_test` only runs 24 fixed transactions (~200 ns). Needs thousands of randomized transactions. |
| **6.9** | Boot from internal ROM passes | Core fetches from ROM and reaches `main()` | ❌ **NO** | **UNVERIFIED** | `tb_top_with_core.sv` preloads 7 raw instructions into IMEM. No Boot ROM module or boot firmware binary exists in TB. |
| **6.10** | Boot from external SPI flash passes | Boot mode pin = 1: code fetched from SPI flash model and executed | ❌ **NO** | **MISSING IN RTL** | `soc_top.sv` has **no `boot_mode` pin** and no SPI bootloader fetch routine. |
| **6.11** | SRAM load / ROM remap boot passes | If supported: SRAM loaded from flash, remap occurs and execution continues | ❌ **NO** | **NOT SUPPORTED / WAIVER** | `rtl_keyword_search.rpt` confirmed 0 matches for `rom_remap`. Must request formal **N/A Waiver** from Coach. |
| **6.12** | Bare-metal C test suite passes | Memory march, timer/SW/ext interrupts, UART/SPI/GPIO loopbacks | ❌ **NO** | **UNVERIFIED** | No compiled C test suite, no linker script (`link.ld`), and no CRT startup assembly exist in `UVM_WITH_CORE`. |
| **6.13** | Trap robustness under load passes | Interrupts during load/store/branch-dense code; nested interrupt policy exercised | ❌ **NO** | **BLOCKED BY RTL** | Blocked because the CPU core lacks interrupt trap hardware. |
| **6.14** | SoC random and stress tests pass | Random arbitration, POR sequences, interconnect backpressure and wait states | ❌ **NO** | **UNVERIFIED** | Testbenches run with zero-delay combinational handshakes; no random wait states are injected. |
| **6.15** | SoC functional coverage closed | Address map, interrupt sources and boot modes all covered | ❌ **NO** | **UNVERIFIED** | No unified functional coverage database exists for the SoC. |
| **6.16** | SoC code coverage >= 95% | Statement, branch and toggle with written waivers | ❌ **NO** | **UNVERIFIED** | No code coverage database (`.ucdb` or `simv.vdb`) has been generated for `soc_top.sv`. |
| **6.17** | Full regression clean | Directed, random and software suites: zero failures on RTL handed to synthesis | ❌ **NO** | **UNVERIFIED** | No master Makefile target runs the full regression across Core + No-Core + Full SoC. |
| **6.18** | No deadlocks in long runs | Long-run test completes; no unbounded stalls | ❌ **NO** | **UNVERIFIED** | Long soak test (> 1,000,000 cycles) has not been performed. |

---

## 2. Detailed Technical Breakdown for Each "Not Done" Item

### Item 6.3: Register Field Coverage Closed
* **Signoff Criteria**: *Field-level functional coverage on enable and mode combinations met.*
* **Forensic Finding**:
  In `uvm_soc_nocore_verification/env/soc_no_core_coverage.sv`:
  ```systemverilog
  cp_addr_space: coverpoint tr_item.addr {
      bins sram_mem   = {[32'h8000_0000 : 32'h8000_0FFF]};
      bins clint_reg  = {[32'h1000_0000 : 32'h1000_00FF]};
      ...
  }
  ```
  1. The covergroup `cg_soc_axi` only samples transaction addresses, NOT register data fields!
  2. The address bins in `soc_no_core_coverage.sv` are defined at `32'h1000_XXXX` and `32'h8000_XXXX`, whereas `soc_tests.sv` accesses `32'h0000_XXXX`. Because of this mismatch, all transactions fell into `bins unmapped = default`!
  3. There is **zero field-level coverage** on UART baud divisors, Timer auto-reload enable, GPIO direction masks, SPI CPOL/CPHA, or ASCON modes.
* **Verdict**: **NOT VERIFIED**.
* **What is required to mark DONE**:
  Fix the address bins in `soc_no_core_coverage.sv` to match `0x0000_XXXX`, and add explicit field coverpoints for peripheral control registers.

---

### Item 6.5: Interrupt Path Verified End to End
* **Signoff Criteria**: *Every source verified from peripheral event to controller input; masking and priority checked.*
* **Forensic Finding**:
  1. In `uvm_soc_nocore_verification/tests/soc_tests.sv`, `soc_interrupt_test` only writes `1` then `0` to raw register addresses `0x1000` (CLINT) and `0x2000` (PLIC). It does not test the 12 peripheral interrupt sources (ASCON Done, UART TX/RX, SPI, GPIO, Timer, WDT, EXT_IRQ).
  2. In `UVM_WITH_CORE/dut/soc_top.sv`, interrupts are OR'ed (`assign irq_external = wdt_irq | plic_irq;`) and routed to `rv32_core_top`.
  3. In `rv32_core_top.sv` lines 124–140:
     ```verilog
     wire epc_taken_IF = trap_illegal & ready_IF;
     .trap_cause (32'd2) // Hardcoded illegal instruction!
     ```
     **The core RTL completely lacks interrupt trap redirection!** When `irq_external` goes high, the CPU core continues executing linear code without taking an interrupt vector.
* **Verdict**: **NOT VERIFIED — BLOCKED BY CORE RTL HARDWARE LIMITATION**.
* **What is required to mark DONE**:
  Apply Code Patch 2 from `03_SPEC_VS_RTL_DISCREPANCIES_AND_FIXES.md` to `csr_regfile.sv` and `rv32_core_top.sv` so that interrupts trigger pipeline flush, redirect `nxt_pc` to `mtvec`, and update `mcause` to `0x8000000B`.

---

### Item 6.7: Memory Map Decode Verified
* **Signoff Criteria**: *Every address range hit; unmapped access returns the defined error.*
* **Forensic Finding**:
  1. `soc_tests.sv` accesses SRAM and peripheral base registers, but **never attempts an access to unmapped address holes** (e.g. `0x0000_0800`, `0x0001_8000`, `0x4002_0000`).
  2. In `soc_no_core_dut.sv` and `soc_top.sv`, unmapped address decode branches do not exist; accesses default to `bresp = 2'b00` (OKAY) or leave the bus hanging without asserting `pready`.
  3. No test asserts or verifies that AXI receives `DECERR` (`2'b11`) or that APB asserts `PSLVERR = 1'b1`.
* **Verdict**: **NOT VERIFIED**.
* **What is required to mark DONE**:
  Update `apb_interconnect.sv` and `axi4_to_apb_bridge.sv` to assert error responses, and add a test `soc_unmapped_access_test` that deliberately reads/writes unmapped addresses and checks for `DECERR` / `PSLVERR`.

---

### Item 6.8: Traffic Stress Run
* **Signoff Criteria**: *Long random peripheral traffic plus interrupts; no hangs, no protocol violations.*
* **Forensic Finding**:
  In `uvm_soc_nocore_verification/tests/soc_tests.sv`, `soc_full_system_test` contains:
  ```systemverilog
  for (int i = 0; i < 16; i++) ... // 16 SRAM writes/reads
  for (int p = 1; p <= 8; p++) ... // 8 peripheral writes
  #100ns;
  ```
  This is a total of **24 sequential transactions** running in approximately **200 nanoseconds**.
  A signoff-grade "Traffic Stress Run" requires tens of thousands of randomized, burst-mode transactions interleaved with concurrent asynchronous interrupts to expose race conditions and FIFO overflows.
* **Verdict**: **NOT VERIFIED (Current test is only a basic sanity test)**.
* **What is required to mark DONE**:
  Create `soc_stress_test` running $\ge 5,000$ randomized AXI read/write transactions with background interrupt pulses.

---

### Item 6.9: Boot from Internal ROM Passes
* **Signoff Criteria**: *Core fetches from ROM and reaches `main()`.*
* **Forensic Finding**:
  1. In `UVM_WITH_CORE/tb/tb_top_with_core.sv`, the testbench manually writes 7 assembly instructions into the RAM model (`u_imem.mem[0:6] = ...`).
  2. There is **no synthesizable Boot ROM module** instantiated in `soc_top.sv`.
  3. No bootloader binary (`boot_rom.hex`) exists that performs hardware initialization (stack setup, PLL wait) and jumps to `main()` in SRAM.
* **Verdict**: **NOT VERIFIED**.
* **What is required to mark DONE**:
  Instantiate a 4 KB Boot ROM at `0x0000_0000` in `soc_top.sv`, pre-load it with startup assembly (`crt0.s`), release reset, and observe the core jumping to SRAM.

---

### Item 6.10: Boot from External SPI Flash Passes
* **Signoff Criteria**: *Boot mode pin = 1: code fetched from the SPI flash model and executed.*
* **Forensic Finding**:
  1. `soc_top.sv` contains **no `boot_mode` pin** in its port declaration.
  2. `rtl_keyword_search.rpt` confirmed 0 matches for `boot_mode` in all RTL files.
  3. No SPI bootloader routine exists to copy external flash memory contents to SRAM via the SPI master controller.
* **Verdict**: **NOT VERIFIED — MISSING HARDWARE & FIRMWARE**.
* **What is required to mark DONE**:
  Add `input logic boot_mode` to `soc_top.sv` and implement the SPI boot sequence in testbench or Boot ROM.

---

### Item 6.11: SRAM Load / ROM Remap Boot Passes
* **Signoff Criteria**: *If supported: SRAM loaded from flash, remap occurs and execution continues.*
* **Forensic Finding**:
  `rtl_keyword_search.rpt` audited the entire codebase and returned **0 matches for `rom_remap`**.
  The SoC uses a static address map (Boot ROM permanently at `0x0000_0000`, IMEM at `0x0001_0000`).
* **Verdict**: **NOT APPLICABLE (Hardware does not implement dynamic remapping)**.
* **What is required to mark DONE**:
  Request a formal signoff waiver from your coach to mark item 6.11 as **N/A** (with justification: *"Static memory architecture; core executes directly from partitioned IMEM/DMEM addresses"*).

---

### Item 6.12: Bare-Metal C Test Suite Passes
* **Signoff Criteria**: *Memory march and walking-ones, timer/SW/external interrupts, UART/SPI/GPIO loopbacks.*
* **Forensic Finding**:
  1. In `UVM_WITH_CORE/tb/tb_top_with_core.sv`, the core only runs 7 hardcoded assembly instructions (ADDI, MUL, LUI, SW, NOP, JAL).
  2. There is no C compiler flow, no linker script (`link.ld`), and no C test suites (`march_test.c`, `uart_test.c`, etc.) in the workspace.
* **Verdict**: **NOT VERIFIED**.
* **What is required to mark DONE**:
  Compile bare-metal C test applications using `riscv32-unknown-elf-gcc`, generate `.hex` files, and run them on `UVM_WITH_CORE`.

---

### Item 6.13: Trap Robustness Under Load Passes
* **Signoff Criteria**: *Interrupts during load/store/branch-dense code; nested interrupt policy exercised if supported.*
* **Forensic Finding**:
  Since the core RTL currently cannot take interrupt traps (Item 6.5 blocker), testing interrupt robustness during dense load/store code has never been executed.
* **Verdict**: **NOT VERIFIED**.
* **What is required to mark DONE**:
  Once the interrupt trap logic is patched into `rv32_core_top.sv`, fire random interrupts while running high-load memory march code.

---

### Item 6.14: SoC Random and Stress Tests Pass
* **Signoff Criteria**: *Random arbitration, power-on reset sequences, interconnect backpressure and wait states.*
* **Forensic Finding**:
  All UVM simulations currently run with ideal zero-delay bus responses. Slave interfaces assert `ready = 1'b1` without injecting multi-cycle wait states or backpressure.
* **Verdict**: **NOT VERIFIED**.
* **What is required to mark DONE**:
  Configure `delay_en = 1'b1` in the AXI and APB slave models to inject 1 to 3 cycles of random backpressure during transactions.

---

### Item 6.15: SoC Functional Coverage Closed
* **Signoff Criteria**: *Address map, interrupt sources and boot modes all covered.*
* **Forensic Finding**:
  No functional coverage database exists that proves 100% coverage across address ranges, interrupt lines, and boot modes.
* **Verdict**: **NOT VERIFIED**.
* **What is required to mark DONE**:
  Merge coverage databases across test runs using QuestaSim `vcover merge` and produce a report showing $\ge 100\%$ on planned metrics.

---

### Item 6.16: SoC Code Coverage >= 95%
* **Signoff Criteria**: *Statement, branch and toggle with written waivers.*
* **Forensic Finding**:
  No code coverage data exists for `soc_top.sv` or `soc_no_core_dut.sv`.
* **Verdict**: **NOT VERIFIED**.
* **What is required to mark DONE**:
  Run full regression with coverage instrumentation enabled (`vlog -cover bcesft` and `vsim -coverage`) and generate the HTML coverage report.

---

### Item 6.17: Full Regression Clean
* **Signoff Criteria**: *Directed, random and software suites: zero failures on the RTL handed to synthesis.*
* **Forensic Finding**:
  No single regression script exists that compiles and runs both the Core tests and the SoC tests.
* **Verdict**: **NOT VERIFIED**.
* **What is required to mark DONE**:
  Create master `make regress` target and ensure it runs all suites with 0 errors.

---

### Item 6.18: No Deadlocks in Long Runs
* **Signoff Criteria**: *Long-run test completes; no unbounded stalls.*
* **Forensic Finding**:
  Long soak tests (> 1,000,000 cycles) have not been run.
* **Verdict**: **NOT VERIFIED**.
* **What is required to mark DONE**:
  Execute an extended simulation of at least 1,000,000 clock cycles without simulation hang or deadlock.

---

## 3. Predecessor Gate Items Flagged as "Not Started"

The following open items in preceding gates directly block or impact G6 signoff:

| Gate & Item # | Item Description | Actual Status in Files | Action Required to Close |
| :---: | :--- | :--- | :--- |
| **G3.9** | **Boot ROM integrated** | `Not Started` | Instantiate 4 KB ROM in `soc_top.sv`. |
| **G4.7** | **Unit TB for MIU** | `Not Started` | Write `miu_tb.sv` testing byte-enables and sign extensions. |
| **G4.9** | **Unit regression 100% pass** | `Not Started` in sheet, but **129/129 tests pass** in `core_sanity_exec.log` | **Ready for Done**: Update Excel status and link `core_sanity_exec.log`. |
| **G4.13** | **Hazard tests pass at core level** | `Not Started` in sheet, but **exercised in sanity suite** | **Ready for Done**: Update Excel status and link sanity log. |
| **G5.5** | **riscv-dv regression stable** | `Not Started` | Run 50 seeds ($N=50$) to close this item. |
| **G5.6** | **Memory latency randomisation run** | `Not Started` | Enable `delay_en=1` in `axi4_dmem_slave.sv`. |
| **G5.10**| **Core bug list closed** | `Not Started` | Fix SpyGlass latch in `csr_regfile.sv` and close bug tracker. |
