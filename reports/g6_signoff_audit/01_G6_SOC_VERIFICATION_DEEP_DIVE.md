# G6 Verification Phase 4 & 5 — Line-by-Line Technical Deep Dive

**Reference**: Gate G6 (`1TOPS_Project_Signoff_Checkl (1).xlsx`)  
**Scope**: Verification Phase 4 (SoC without Core) & Phase 5 (Full SoC with Core)

---

## 1. Overview of Gate G6 Methodology

Gate G6 is divided into two major execution phases:
- **Phase 4: SoC Verification Without Core (Items 6.1 – 6.8)**
  - Replaces the CPU core with a UVM AXI Master Verification IP (VIP).
  - Isolates bus fabric and peripheral logic from CPU pipeline quirks.
  - Verifies register maps, byte enables, IP protocols, interrupt generation, and bus arbitration under high-speed stimulus.
- **Phase 5: Full SoC Verification With Core (Items 6.9 – 6.19)**
  - Reintegrates the synthesizable RV32IM CPU core (`rv32_core_top.sv`).
  - Verifies system boot sequences (Internal ROM vs External SPI Flash).
  - Executes bare-metal C applications to prove real firmware interaction with memory, peripherals, and interrupts.
  - Closes code and functional coverage, executes stress regressions, and freezes RTL for physical synthesis.

---

## 2. Item-by-Item Analysis of G6 Signoff Criteria

### 6.1: UVM SoC testbench built
* **Signoff Criteria**: AXI master agent emulating CPU accesses, IRQ VIP, peripheral VIPs and coverage model.
* **Tool**: VCS / QuestaSim.
* **Excel Status**: `Done` | **Coach Approved**: `No`.
* **What it means**: A complete UVM testbench environment containing an active AXI4/AXI4-Lite master VIP (to generate read/write transactions), an interrupt monitor VIP (to sample CLINT/PLIC outputs), peripheral VIPs (UART monitor, SPI flash model, GPIO agent, I2C agent), scoreboards, and functional coverage subscribers.
* **Current Evidence**: Available in `uvm_soc_nocore_verification/` and documented in `SoC_UVM_Verification_Final_Report.md`. Built with QuestaSim UVM 1.1d.
* **Corrections / Action to Close**: Present simulation transcripts and waveform logs to Coach for signoff approval.

---

### 6.2: Register tests pass
* **Signoff Criteria**: 100% of addressable registers read and written; RW/RO/W1C behaviour verified.
* **Tool**: VCS / QuestaSim.
* **Excel Status**: `Done` | **Coach Approved**: `No`.
* **What it means**: Automated register walk sequence (similar to UVM RAL built-in sequences) verifying that every writable bit accepts data, read-only bits do not mutate on write, and Write-1-to-Clear (W1C) interrupt status bits clear only when written with a `1`.
* **Current Evidence**: Exercised in `soc_tests.sv` via `soc_peripheral_reg_test` across CLINT, PLIC, GPIO, UART, Timer, SPI, and SysCtrl.
* **Corrections / Action to Close**: Include ASCON accelerator register address space (`0x4000_0000` to `0x4000_005F`, 24 registers) in the automated register walk to achieve 100% register space audit.

---

### 6.3: Register field coverage closed
* **Signoff Criteria**: Field-level functional coverage on enable and mode combinations met.
* **Tool**: VCS / Verdi / QuestaSim UCDB.
* **Excel Status**: `Not Started` | **Coach Approved**: `No`.
* **What it means**: Writing SystemVerilog `covergroup` definitions that track not just address hits, but the specific configuration modes: UART baud divisors and parity modes, Timer auto-reload enable, GPIO pin direction masks, SPI CPOL/CPHA modes, and ASCON encryption/decryption control bits.
* **Current Evidence**: Basic covergroups exist in `soc_no_core_coverage.sv` tracking address bins (`sram_bin`, `uart_bin`, etc.), but individual register bit-field combinations are not defined.
* **Corrections / Action to Close**: Expand `soc_no_core_coverage.sv` to add coverpoints on register control fields (e.g. `CTRL[0]` Start, `CTRL[1]` Mode, `STATUS[3:0]`). Run tests and generate a UCDB coverage report showing 100% field coverage.

---

### 6.4: Per-IP use cases pass
* **Signoff Criteria**: TX and RX path exercised for each integrated peripheral against its VIP.
* **Tool**: VCS / QuestaSim.
* **Excel Status**: `Done` | **Coach Approved**: `No`.
* **What it means**: Functional operational testing of each peripheral IP: UART transmitting and receiving bytes, SPI shifting out data and receiving MISO bytes, GPIO driving and sampling pins, Timer ticking down and triggering reload.
* **Current Evidence**: Implemented in `uvm_soc_nocore_verification/tests/soc_tests.sv` and `UVM_WITH_CORE/tests/subsystem_tests.sv`.
* **Corrections / Action to Close**: Add dedicated use cases for ASCON authenticated encryption and tag generation against a golden software C/Python model.

---

### 6.5: Interrupt path verified end to end
* **Signoff Criteria**: Every source verified from peripheral event to controller input; masking and priority checked.
* **Tool**: VCS / QuestaSim.
* **Excel Status**: `Not Started` | **Coach Approved**: `No`.
* **What it means**: Verifying the entire chain: Peripheral Event (e.g. UART RX full or Timer reload) $\rightarrow$ Peripheral IRQ output $\rightarrow$ PLIC / CLINT input line $\rightarrow$ Priority / Mask arbitration $\rightarrow$ Core `irq_external` / `irq_timer` input $\rightarrow$ Core pipeline trap taking (`mstatus.MIE`, `mie`, `mcause`, `mepc`) $\rightarrow$ Handler execution $\rightarrow$ Interrupt claim and completion handshake (`0x0C20_0004`).
* **Current Status / Critical Blocker**:
  - In `soc_no_core_dut.sv`, peripheral interrupts toggle the IRQ lines, but there is no core to take the trap.
  - In `rv32_core_top.sv`, **the core never redirects PC on `irq_external` or `irq_timer`**! Trap logic only monitors `trap_illegal`.
* **Corrections Needed**:
  1. Update `csr_regfile.sv` to compute `trap_irq_pending = mstatus[3] & ((mip[11] & mie[11]) | (mip[7] & mie[7]) | (mip[3] & mie[3]))`.
  2. In `rv32_core_top.sv`, arbiter between illegal instruction trap and interrupt trap; redirect `nxt_pc` to `mtvec` (vectored or direct), set `mcause` to `0x8000000B` (External) or `0x80000007` (Timer), save return PC in `mepc`, and clear `mstatus.MIE`.
  3. Verify the end-to-end flow with a testbench.

---

### 6.6: Bus bridge protocol verified
* **Signoff Criteria**: AXI to AXI-Lite to APB: ordering, responses, alignment and byte enables correct.
* **Tool**: VCS / QuestaSim.
* **Excel Status**: `Done` | **Coach Approved**: `No`.
* **What it means**: Verifying that 32-bit AXI bursts or single-beat transfers correctly convert into 2-cycle APB transfers (`SETUP` $\rightarrow$ `ACCESS` phase), byte enables (`wstrb` to `pstrb`) are preserved, and slave errors propagate to `bresp` / `rresp`.
* **Current Evidence**: Implemented in `axi4_to_apb_bridge.sv` and verified in `uvm_soc_nocore_verification`.

---

### 6.7: Memory map decode verified
* **Signoff Criteria**: Every address range hit; unmapped access returns the defined error.
* **Tool**: VCS / QuestaSim.
* **Excel Status**: `Not Started` | **Coach Approved**: `No`.
* **What it means**:
  1. Accesses to all designated regions (Boot ROM, IMEM, DMEM, CLINT, PLIC, ASCON, UART, SPI, GPIO, Timer) must hit their intended target with no address aliasing.
  2. Accesses to **unmapped holes** (e.g. `0x0000_0800 – 0x0000_FFFF`, `0x0001_8000 – 0x0001_FFFF`, or `0x4002_0000+`) must return `DECERR` on AXI (`2'b11`) or assert `PSLVERR` on APB rather than hanging the bus!
* **Current Status / Gap**:
  - In `soc_no_core_dut.sv` and `soc_top.sv`, unmapped address decode default branches are missing or return zero with `OKAY` (`2'b00`), violating AXI/APB bus standards.
* **Corrections Needed**: Add default error generation in address decoders to return `DECERR` (`2'b11`) and assert `pslverr` when unmapped regions are accessed.

---

### 6.8: Traffic stress run
* **Signoff Criteria**: Long random peripheral traffic plus interrupts; no hangs, no protocol violations.
* **Tool**: VCS / QuestaSim.
* **Excel Status**: `Not Started` | **Coach Approved**: `No`.
* **What it means**: Running simultaneous, concurrent transactions from the AXI master agent to SRAM, UART, SPI, and ASCON while random external interrupts trigger. No transaction may stall indefinitely.
* **Corrections Needed**: Create a dedicated stress sequence `soc_traffic_stress_seq` in UVM that forks parallel threads with random delays and backpressure.

---

### 6.9: Boot from internal ROM passes
* **Signoff Criteria**: Core fetches from ROM and reaches `main()`.
* **Tool**: VCS / QuestaSim.
* **Excel Status**: `Not Started` | **Coach Approved**: `No`.
* **What it means**: On system reset release (`rst_n` deasserted), the core program counter starts at `0x0000_0000` (Boot ROM base), fetches boot instructions (PLL lock wait, stack pointer setup `sp = 0x0002_7FF0`), copies firmware from ROM/Flash to SRAM, and jumps to `main()` in SRAM.
* **Corrections Needed**:
  - Ensure Boot ROM contains synthesizable instructions or is loaded with a boot image (`boot_rom.hex`).
  - Verify that the core executes the instructions and transitions PC to SRAM.

---

### 6.10: Boot from external SPI flash passes
* **Signoff Criteria**: Boot mode pin = 1: code fetched from the SPI flash model and executed.
* **Tool**: VCS / QuestaSim.
* **Excel Status**: `Not Started` | **Coach Approved**: `No`.
* **What it means**: When the top-level `boot_mode` pin is sampled high at reset, the system boots from external SPI flash (or internal ROM executes a SPI bootloader routine that reads image headers and binary from SPI flash).
* **Current Status / Gap**: `boot_mode` pin is completely missing in `soc_top.sv` RTL!
* **Corrections Needed**: Add `boot_mode` pin to `soc_top.sv`, define boot mode selection logic in ROM or hardware multiplexer.

---

### 6.11: SRAM load / ROM remap boot passes
* **Signoff Criteria**: If supported: SRAM loaded from flash, remap occurs and execution continues.
* **Tool**: VCS / QuestaSim.
* **Excel Status**: `Not Started` | **Coach Approved**: `No`.
* **What it means**: After initial boot, address `0x0000_0000` is dynamically remapped from Boot ROM to Instruction SRAM so that interrupt vectors and subsequent jumps execute from fast SRAM.
* **Current Status**: Not implemented in RTL (`rtl_keyword_search.rpt` confirmed 0 matches for `rom_remap`). If the architecture uses fixed memory addresses (Boot ROM at `0x0000_0000`, IMEM at `0x0001_0000`), request a formal waiver from the coach marking this item **N/A**!

---

### 6.12: Bare-metal C test suite passes
* **Signoff Criteria**: Memory march and walking-ones, timer/SW/external interrupts, UART/SPI/GPIO loopbacks.
* **Tool**: VCS / QuestaSim + RISC-V GCC.
* **Excel Status**: `Not Started` | **Coach Approved**: `No`.
* **What it means**: Compiling actual C code (`march_test.c`, `interrupt_test.c`, `uart_loopback.c`) using `riscv32-unknown-elf-gcc`, loading the generated `.hex` into memory, and executing in `soc_top.sv`.
* **Corrections Needed**: Create a bare-metal firmware directory with linker script (`link.ld`), startup assembly (`crt0.s`), and standard C tests.

---

### 6.13: Trap robustness under load passes
* **Signoff Criteria**: Interrupts during load/store/branch-dense code; nested interrupt policy exercised if supported.
* **Tool**: VCS / QuestaSim.
* **Excel Status**: `Not Started` | **Coach Approved**: `No`.
* **What it means**: Firing asynchronous interrupts specifically while the CPU pipeline is executing back-to-back load-use stalls, multi-cycle MDU operations (`DIV`), and taken branches. Confirms that no instruction is executed twice, skipped, or corrupted.
* **Corrections Needed**: Requires the interrupt trap logic in `rv32_core_top.sv` to be completed first (see item 6.5).

---

### 6.14: SoC random and stress tests pass
* **Signoff Criteria**: Random arbitration, power-on reset sequences, interconnect backpressure and wait states.
* **Tool**: VCS / QuestaSim.
* **Excel Status**: `Not Started` | **Coach Approved**: `No`.
* **What it means**: Injecting random ready delays on AXI slave channels (`arready`, `awready`, `wready`) and APB `pready` wait states to stress pipeline stall logic.

---

### 6.15: SoC functional coverage closed
* **Signoff Criteria**: Address map, interrupt sources and boot modes all covered.
* **Tool**: VCS / Verdi / QuestaSim.
* **Excel Status**: `Not Started` | **Coach Approved**: `No`.
* **What it means**: Generating unified coverage metrics showing 100% hits across all address spaces, interrupt lines, and operating modes.

---

### 6.16: SoC code coverage >= 95%
* **Signoff Criteria**: Statement, branch and toggle with written waivers.
* **Tool**: VCS / Verdi / QuestaSim (`-cover bcesft`).
* **Excel Status**: `Not Started` | **Coach Approved**: `No`.
* **What it means**: Structural RTL code coverage (Statement $\ge$ 95%, Branch $\ge$ 90%, Toggle $\ge$ 85%). Any unreached code (e.g. tie-offs, debug logic) must have written engineering waivers.

---

### 6.17: Full regression clean
* **Signoff Criteria**: Directed, random and software suites: zero failures on the RTL handed to synthesis.
* **Tool**: VCS / QuestaSim.
* **Excel Status**: `Not Started` | **Coach Approved**: `No`.
* **What it means**: Running the automated regression makefile (`make regress`) across all test suites with 100% pass rate.

---

### 6.18: No deadlocks in long runs
* **Signoff Criteria**: Long-run test completes; no unbounded stalls.
* **Tool**: VCS / QuestaSim.
* **Excel Status**: `Not Started` | **Coach Approved**: `No`.
* **What it means**: Running simulations of > 1,000,000 cycles without watchdog triggers or bus freeze.

---

### 6.19: RTL frozen for synthesis
* **Signoff Criteria**: Repo tagged; later changes need coach approval and a full regression re-run.
* **Tool**: Git.
* **Excel Status**: `Done` *(Needs Correction)* | **Coach Approved**: `No`.
* **What it means**: Git repository committed, clean status, tagged (`git tag -a v1.0_rtl_freeze`), and pushed to remote server.
* **Current Status / Gap**: Marked Done in Excel, but Git repository has uncommitted files and no remote configured. Must be properly executed and approved.
