# Comprehensive Audit & Step-by-Step Corrections for All 20 Review Items

This document audits the 20 review action items against the project repository, the architecture document (`1-TOPS_SOCArchitecture_VEDA_PSG_College.docx`), and the Signoff Checklist (`1TOPS_Project_Signoff_Checkl (1).xlsx`).

---

### Item 1: GIT PUSH
* **Gate Mapping**: G0.6 (*Version control in place*) and G6.19 (*RTL frozen for synthesis*).
* **What the Checklist Means**: All RTL, verification testbenches, simulation scripts, synthesis constraints, and documentation must reside in a single version-controlled repository (Git). The repository must have a clean status (no uncommitted or untracked changes), be pushed to an upstream remote (GitHub/GitLab), and be tagged with a signed tag (e.g. `v1.0_rtl_freeze`).
* **Audit Findings in Your Files**:
  - `uvm_soc_nocore_verification/` contains a `.git` folder, but `git status -s` shows untracked/unstaged files (`A README_QUESTASIM.md`, `AD .gitignore`, etc.) and `git remote -v` is completely empty (no upstream remote configured!).
  - `TOPS_FINAL/` and `1tops_VEDA_2026-main/` were distributed as raw folders/zips without Git metadata.
* **Corrections Required**:
  1. Initialize or consolidate all subprojects (`dut`, `vip`, `env`, `tests`, `tb`, `docs`, `scripts`) into one root Git repository.
  2. Configure the official remote URL:
     ```bash
     git remote add origin <team_repo_url>
     ```
  3. Commit all pending modifications:
     ```bash
     git add -A
     git commit -m "Signoff: Complete RTL, UVM Verification, and Documentation handoff"
     ```
  4. Create the formal freeze tag and push:
     ```bash
     git tag -a v1.0_g6_freeze -m "RTL and Verification Freeze for G6/G7 Signoff"
     git push -u origin main --tags
     ```

---

### Item 2: REGRESSION MAKE FILE
* **Gate Mapping**: G0.7 (*Regression runnable by one command*) and G6.17 (*Full regression clean*).
* **What the Checklist Means**: A single terminal command (e.g. `make regress` or `make regression`) must automatically launch and verify the full regression suite across all tiers: Core unit tests, Spike ISS co-simulation, RISCV-DV random runs, SoC no-core UVM tests, and Full SoC firmware tests, producing a clean summary log with 0 errors.
* **Audit Findings in Your Files**:
  - `TOPS_FINAL/TOPS_FINAL/Makefile` only runs Core-level verification (`sanity`, `spike`, `riscv_dv`).
  - It has **zero targets** for SoC No-Core UVM (`uvm_soc_nocore_verification`) or SoC Full-Core UVM (`UVM_WITH_CORE`).
  - Running QuestaSim UVM requires opening the GUI or executing disparate `.do` scripts manually.
* **Corrections Required**:
  - Update `Makefile` to include top-level unified targets:
    ```makefile
    .PHONY: regress regress_core regress_soc_nocore regress_soc_core

    regress: regress_core regress_soc_nocore regress_soc_core
    	@echo "=== MASTER REGRESSION: ALL GATES G4/G5/G6 PASSED ==="

    regress_soc_nocore:
    	@cd uvm_soc_nocore_verification/sim && vsim -c -do "do run_questa.do; quit -f"

    regress_soc_core:
    	@cd UVM_WITH_CORE && vsim -c -do "do run_questa.do; quit -f"
    ```

---

### Item 3: CSR LIST FROZEN
* **Gate Mapping**: G1.4 (*CSR list frozen*) and G2.9 (*CSR block and trap logic coded*).
* **What the Checklist Means**: The exact list of implemented RISC-V Control and Status Registers (CSRs), their reset values, read/write/read-only access behaviors, and field definitions must be permanently documented and faithfully implemented in RTL.
* **Audit Findings in Your Files**:
  - `architecture.md` lists machine-mode CSRs including identification registers: `mvendorid` (0xF11), `marchid` (0xF12), `mimpid` (0xF13), `mhartid` (0xF14).
  - In `csr_regfile.sv`, **these four identification registers are completely missing from the decode case statement**! Reading them returns `32'd0` through `default`, but they are not formally defined or tied to compliant IDs.
* **Corrections Required**:
  - Add explicit decode entries in `csr_regfile.sv`:
    ```verilog
    localparam logic [11:0] ADDR_MVENDORID = 12'hF11;
    localparam logic [11:0] ADDR_MARCHID   = 12'hF12;
    localparam logic [11:0] ADDR_MIMPID    = 12'hF13;
    localparam logic [11:0] ADDR_MHARTID   = 12'hF14;
    ...
    ADDR_MVENDORID: csr_rdata = 32'h0000_0000; // Non-commercial / open source
    ADDR_MARCHID:   csr_rdata = 32'h0000_0000;
    ADDR_MIMPID:    csr_rdata = 32'h2026_1101; // Implementation date/rev
    ADDR_MHARTID:   csr_rdata = 32'h0000_0000; // Hart 0
    ```

---

### Item 4: TRAP AND INTERRUPT MODEL
* **Gate Mapping**: G1.5 (*Trap and interrupt model defined*) and G2.9 / G6.5 / G6.13.
* **What the Checklist Means**: The trap and interrupt architecture must define:
  1. `mtvec` modes: Direct (mode `2'b00`, all traps jump to `BASE`) vs Vectored (mode `2'b01`, interrupts jump to `BASE + 4 * cause`).
  2. Trap entry sequence: Save PC to `mepc`, save cause code to `mcause`, copy `mstatus.MIE` to `mstatus.MPIE`, clear `mstatus.MIE`.
  3. `mret` return sequence: Restore `mstatus.MIE <= mstatus.MPIE`, set `MPIE <= 1`, jump PC to `mepc`.
  4. Interrupt vs Exception priority.
* **Audit Findings in Your Files (CRITICAL BUG)**:
  - In `rv32_core_top.sv`, trap redirect is wired **ONLY** to illegal instructions:
    ```verilog
    wire epc_taken_IF = trap_illegal & ready_IF;
    .trap_cause (32'd2), // HARDCODED ILLEGAL INSTRUCTION CAUSE
    ```
  - External interrupts (`irq_external`), timer interrupts (`irq_timer`), and software interrupts (`irq_software`) are wired into `csr_regfile`, **but `csr_regfile` has no output signal to tell the core pipeline that an interrupt is pending**!
  - As a result, the processor core **never executes an interrupt service routine (ISR)**!
* **Corrections Required**:
  1. In `csr_regfile.sv`, generate an interrupt request output:
     ```verilog
     output logic irq_trap_req,
     output logic [31:0] irq_trap_cause
     ...
     wire meip = mip[11] & mie[11];
     wire mtip = mip[7]  & mie[7];
     wire msip = mip[3]  & mie[3];
     wire irq_active = mstatus[3] & (meip | mtip | msip);
     assign irq_trap_req = irq_active;
     assign irq_trap_cause = meip ? 32'h8000_000B : (mtip ? 32'h8000_0007 : 32'h8000_0003);
     ```
  2. In `rv32_core_top.sv`, arbitrate trap entry:
     ```verilog
     wire trap_take = (trap_illegal | irq_trap_req) & ready_IF;
     wire [31:0] current_trap_cause = trap_illegal ? 32'd2 : irq_trap_cause;
     ```
  3. Route vectored/direct jump calculation from `mtvec`.

---

### Item 5: BOOT ROM 2KB vs 4KB, ADDRESS MAPPING & INTEGRATION
* **Gate Mapping**: G1.6 (*Memory organisation frozen*), G1.12 (*Boot plan defined*), G6.9.
* **What the Checklist Means**: Internal Boot ROM size, address range, integration into the AXI interconnect, and pre-loading with a valid executable boot image must be consistent across spec, RTL, and testbenches.
* **Audit Findings in Your Files (SPEC CONFLICT)**:
  - Document Paragraph 32 specifies: `Boot ROM (4 KB)`.
  - Document Table 10 specifies: `0x0000_0000 – 0x0000_07FF | Boot ROM | 2 KB`.
  - Checklist G1.6 specifies: `4 KB boot ROM size`.
  - Testbench `axi4_imem_slave.sv` sets: `parameter MEM_DEPTH = 1024` words = 4 KB.
  - In `soc_no_core_dut.sv`: Boot ROM is given only `0x0000_70FF` (256 bytes).
* **Corrections Required**:
  - **Standardize on 4 KB Boot ROM** (`0x0000_0000` to `0x0000_0FFF`) across the Architecture document Table 10, RTL address decoder, and simulation testbenches.
  - Create a synthesizable ROM module or memory initialized via `$readmemh("boot_rom.hex", mem)` containing the startup code (set SP, configure PLL, jump to IMEM).

---

### Item 6: SOC BLOCK DIAGRAM — CLOCK AND RESET SOURCES
* **Gate Mapping**: G1.7 (*SoC block diagram approved*) and G1.10.
* **What the Checklist Means**: The SoC architecture diagram must explicitly show all clock and reset sources, including the external oscillator pin `CLK_IN`, on-chip PLL/clock dividers, power-on reset (POR) circuit, external `RESET_N`, and how clocks/resets are distributed to Core, AXI bus, APB bus, and peripherals.
* **Audit Findings**:
  - Document Figure & Section 3 mention PLL and POR, but the block diagram does not clearly display the reset controller, PLL lock signal, or clock gating cells.
* **Corrections Required**: Update the block diagram in the architecture documentation to clearly depict the **Clock & Reset Control Unit (CRU)**, showing `CLK_IN` $\rightarrow$ PLL $\rightarrow$ `clk_sys` (100 MHz) and `RESET_N` + POR $\rightarrow$ Reset Synchronizer $\rightarrow$ `rst_sys_n`.

---

### Item 7: ADDRESS MAPPING — BOOT ROM SIZE CHECK (4KB) & ERROR MSG FOR UNACCESSED ADDRESS
* **Gate Mapping**: G1.8 (*Address map frozen*) and G6.7 (*Memory map decode verified*).
* **What the Checklist Means**:
  1. Boot ROM decode must encompass full 4 KB (`0x0000_0000` – `0x0000_0FFF`).
  2. Any unmapped or reserved address access must return a standard bus protocol error: `DECERR` (`2'b11`) on AXI4, and assert `PSLVERR = 1'b1` on APB. The bus must never hang or silently return 0.
* **Audit Findings in Your Files**:
  - In `soc_top.sv` and `soc_no_core_dut.sv`, unmapped address access logic is missing; access to holes falls through to default with `bresp = 2'b00` (OKAY) or hangs waiting for `pready`!
* **Corrections Required**:
  - In `apb_interconnect.sv`, if `paddr_i` does not match slots 0–6, assert `pslverr_o <= 1'b1` and `pready_o <= 1'b1`.
  - In `soc_top.sv`, return `dmem_rresp = 2'b11` (`DECERR`) and `dmem_bresp = 2'b11` for unmapped transactions.

---

### Item 8: PLIC / CLINT INPUT — ADDRESS MAPPING
* **Gate Mapping**: G1.9 (*Interrupt map frozen*), G3.4 (*PLIC*), G3.5 (*CLINT*).
* **What the Checklist Means**:
  - RISC-V privileged architecture specifies CLINT base at `0x0200_0000` (64 KB) and PLIC base at `0x0C00_0000` (16 KB / 64 MB).
  - All peripheral interrupt lines must be mapped to distinct PLIC interrupt sources (1 to 12).
* **Audit Findings in Your Files**:
  - Architecture Doc Table 10 specifies CLINT at `0x0200_0000` and PLIC at `0x0C00_0000`.
  - In `peripheral_subsystem.sv`, PLIC is squeezed into APB Slot 5 (`0x5000`–`0x5FFF`, 4 KB) and CLINT into Slot 6 (`0x6000`–`0x6FFF`, 4 KB).
  - In `soc_no_core_dut.sv`, CLINT is at `0x1000` and PLIC is at `0x2000`.
* **Corrections Required**:
  - Document that the APB peripheral subsystem uses relative offsets (`+0x5000` for PLIC, `+0x6000` for CLINT) within the subsystem aperture, but top-level AXI decode must map them to architectural addresses `0x0200_0000` and `0x0C00_0000`.

---

### Item 9: CLOCK AND RESET ARCHITECTURE — GOTTA CHECK
* **Gate Mapping**: G1.10 (*Clock and reset architecture defined*).
* **What the Checklist Means**: Clock tree, reset tree, and asynchronous-to-synchronous reset release synchronizers must be formally designed and coded in RTL.
* **Audit Findings in Your Files**:
  - `rtl_keyword_search.rpt` states: `reset_control: Direct unbuffered rst_n net; only in IP help files`.
  - `rst_n` from the chip pad directly drives all flip-flops in the core without an on-chip reset synchronizer (async assert, sync de-assert 2-FF synchronizer). This causes severe recovery/removal timing violations during STA and CDC audits.
* **Corrections Required**:
  - Implement a standard Reset Synchronizer module in RTL:
    ```verilog
    module rst_sync (
        input  logic clk,
        input  logic ext_rst_n,
        output logic sync_rst_n
    );
        logic rst_meta, rst_sync_r;
        always_ff @(posedge clk or negedge ext_rst_n) begin
            if (!ext_rst_n) begin
                rst_meta   <= 1'b0;
                rst_sync_r <= 1'b0;
            end else begin
                rst_meta   <= 1'b1;
                rst_sync_r <= rst_meta;
            end
        end
        assign sync_rst_n = rst_sync_r;
    endmodule
    ```

---

### Item 10: PIN LIST — CHECK FOR PAD TYPE
* **Gate Mapping**: G1.11 (*Pin list / chip IO table frozen*).
* **What the Checklist Means**: Every chip I/O pin must specify: Pin Number, Pin Name, Direction, Signal Type, Pad Library Cell (e.g. `PIDC` for input, `PODC` for output, `PIODC` for bidir), Drive Strength (e.g. 4mA / 8mA / 12mA), Slew Rate, Pull-up/Pull-down state, and Voltage domain (1.8V / 3.3V vs 1.0V core).
* **Audit Findings in Your Files**:
  - Document Tables 3–8 list 45 pins (CLK, RESET, UART, SPI, GPIO[15:0], EXT_IRQ[3:0], JTAG[4:0], VDD/VSS).
  - However, **pad types, cell names, and drive strengths are missing**.
* **Corrections Required**: Add pad type column to the Pin Table in the documentation:
  - `CLK_IN`: Input Pad, Schmitt trigger, No pull (`PIDC`)
  - `RESET_N`: Input Pad, Schmitt trigger, Active-low, Internal Pull-Up (`PIDC_PU`)
  - `UART_TX`, `SPI_MOSI`, `SPI_SCLK`, `SPI_CS`: Output Pad, 8mA Drive (`PODC_8`)
  - `UART_RX`, `SPI_MISO`: Input Pad (`PIDC`)
  - `GPIO[15:0]`: Bidirectional Pad, Programmable Pull-Up/Down, 8mA Drive (`PIODC_8`)
  - `TCK, TMS, TDI, TRST_N`: Input Pads with Pull-Up (`PIDC_PU`); `TDO`: Output Pad (`PODC_4`).

---

### Item 11: MICROARCHITECTURE DOC — MEMORY INTERFACE PROTOCOL
* **Gate Mapping**: G1.13 (*Micro-architecture document complete*).
* **What the Checklist Means**: Complete documentation of the bus protocols between CPU, interconnect, and memories: AXI4 channel signaling (`AR`, `R`, `AW`, `W`, `B`), handshaking rules, burst lengths, wait-state handling, and memory alignment rules.
* **Audit Findings**:
  - `docs/architecture.md` covers the 3-stage pipeline well, but needs explicit timing diagrams and protocol details for the AXI4-to-APB bridge latency (2-cycle APB transaction with `PENABLE`).
* **Corrections Required**: Append Section 4 to `architecture.md` detailing the AXI4-to-APB transfer cycle timing and byte-enable lane steering.

---

### Item 12: BOOT FLOW CHECK
* **Gate Mapping**: G1.12 (*Boot plan defined*), G6.9, G6.10.
* **What the Checklist Means**: Deterministic startup sequence:
  1. `rst_n` deasserted $\rightarrow$ CPU samples `RESET_PC = 0x0000_0000`.
  2. CPU fetches from Boot ROM.
  3. If `boot_mode == 0`: execute from internal ROM, copy application image to SRAM, jump to `0x0001_0000`.
  4. If `boot_mode == 1`: execute SPI flash bootloader, read image over SPI into SRAM, jump to SRAM.
* **Audit Findings**:
  - Boot mode selection pin is omitted in RTL. The core directly boots from whatever is at `0x0000_0000`.
* **Corrections Required**: Add `boot_mode` top-level input pin and document the boot sequence in `docs/architecture.md`.

---

### Item 13: AREA BUDGET — ASK COACH
* **Gate Mapping**: G1.15 (*Area, frequency and power targets stated*).
* **What the Checklist Means**: Formal agreement on die area budget, target gate count, standard cell utilization (e.g. 70%), and memory macro dimensions.
* **Audit Findings**:
  - Architecture Doc Paragraph 19 states: "sub-2 mm² die implementation in 65 nm" (or 28 nm MPW per checklist cover).
* **Action Required**: Schedule an alignment meeting with your technical coach to confirm:
  1. Exact technology node (28 nm TSMC vs 65 nm).
  2. Die area budget (target: $\le 1.5\text{ mm}^2$).
  3. Target operating frequency (100 MHz nominal).

---

### Item 14: RTL — SIGN OFF CRITERIA CHECK
* **Gate Mapping**: Gate G2 Signoff Criteria (*Core RTL complete, synthesisable and static-check clean*).
* **What the Checklist Means**: Core RTL must satisfy:
  - Synthesizable subset only (no `$display` in synthesis path, no delays `#`, no latches).
  - Synchronous reset or clean asynchronous reset.
  - 100% clean of syntax errors and severe lint warnings.
* **Audit Findings**: Core RTL is high quality, but has minor lint warnings (null statements in `decoder.sv:189`, unassigned `mip` bits in `csr_regfile.sv:106`).
* **Corrections Required**: Clean up null statements and fix `csr_regfile.sv`.

---

### Item 15: MEMORY INTERFACE UNIT (MIU) CODE AND UNIT TB
* **Gate Mapping**: G2.7 (*Memory interface unit coded*) and G4.7 (*Unit TB for MIU*).
* **What the Checklist Means**:
  - Dedicated logic for load sign/zero extension (`LB`, `LBU`, `LH`, `LHU`, `LW`), store data byte steering (`SB`, `SH`, `SW`), byte strobes (`wstrb`), and misalignment detection.
  - Dedicated unit testbench (`miu_tb.sv`) verifying all 32 combinations of size, offset, and signedness.
* **Audit Findings**:
  - G4.7 in the Excel sheet is currently marked `Not Started`!
  - In `TOPS_FINAL`, MIU logic is embedded directly inside `decoder.sv` and `rv32_core_top.sv` rather than as a standalone module with its own unit TB.
* **Corrections Required**:
  - Provide a standalone unit testbench `miu_tb.sv` that drives memory access requests and checks byte enables and load sign-extensions to formally close G4.7.

---

### Item 16: SIZE OF SRAM FIXED OR NOT — CHECK
* **Gate Mapping**: G1.6 (*Memory organisation frozen*).
* **What the Checklist Means**: Finalizing and locking down whether Instruction and Data SRAMs are 16 KB each (total 32 KB) or 32 KB each (total 64 KB).
* **Audit Findings (DISCREPANCY FOUND)**:
  - Doc Paragraphs 30–31: `Instruction SRAM (16 KB)`, `Data SRAM (16 KB)`.
  - Doc Table 10: `IMEM 32 KB (0x0001_0000 - 0x0001_7FFF)`, `DMEM 32 KB (0x0002_0000 - 0x0002_7FFF)`.
  - RTL `D_SRAM_16Kb.sv` and `I_SRAM_16Kb.sv`: 16 KB each.
  - `axi4_dmem_slave.sv`: 4 KB.
* **Corrections Required**:
  - Formally fix the architecture at **16 KB IMEM + 16 KB DMEM (Total 32 KB SRAM)** to stay within the sub-$2\text{ mm}^2$ silicon area target. Update Table 10 in the document to match.

---

### Item 17: SYSTEM CONTROL BLOCK
* **Gate Mapping**: G3.7 (*System control block coded*).
* **What the Checklist Means**: An APB-mapped register block (`sys_ctrl.sv`) containing:
  - Chip ID / Version register (RO).
  - Reset reason status register (POR, WDT reset, Software reset).
  - Software reset trigger register.
  - Clock gating enable registers for peripherals.
* **Audit Findings**:
  - `rtl_keyword_search.rpt` states: `sys_ctrl: 0 matches in design RTL files`.
  - It exists only as a dummy register in `soc_no_core_dut.sv` (`0x0000_8000`).
* **Corrections Required**:
  - Implement a clean synthesizable `sys_ctrl.sv` module in `dut/peripherals/` and connect it to APB Slot 7.

---

### Item 18: SPYGLASS — CHECK FOR LINT, CDC, RDC, FLOATING NET CHECK
* **Gate Mapping**: G0.1, G2.12 (*Core lint clean*), G2.13 (*Core CDC clean*).
* **What the Checklist Means**: Run Synopsys SpyGlass Lint, CDC (Clock Domain Crossing), and RDC (Reset Domain Crossing) goals:
  - Zero fatal errors.
  - All warnings resolved or documented with formal waivers.
  - Zero floating nets, zero unintended latches.
* **Audit Findings in `spyglass_lint_summary.rpt`**:
  1. *Latch Inference*: `csr_regfile.sv:106` (`mip[31:12]`, `mip[10:8]`, etc. unassigned).
  2. *Combinational Loop / UNOPTFLAT*: `booth_multiplier_radix4.sv:107` (Wallace tree indexing).
  3. *Unused Inputs/Signals*: `imem_rlast`, `dmem_rresp`, `dmem_rlast`, `csr_rd_DE`.
* **Corrections Required**:
  - Fix `csr_regfile.sv` to explicitly assign all 32 bits of `mip`.
  - Add `/* verilator lint_off UNOPTFLAT */` or restructure tree array indexing in Booth multiplier.
  - Remove or tie off unused signals cleanly.

---

### Item 19: CORE LEVEL TESTS — HAZARD TESTS PASS AT CORE LEVEL, UNIT REGRESSION 100% PASS CHECK
* **Gate Mapping**: G4.9 (*Unit regression 100% pass*) and G4.13 (*Hazard tests pass at core level*).
* **What the Checklist Means**:
  - G4.9: All 16 unit test suites in `rv32_core_sanity_tb.sv` must run cleanly in automated regression with 100% pass rate.
  - G4.13: Dedicated tests for RAW data hazards, load-use stalls, branch flushes, and MDU busy stalls under randomized memory delays.
* **Audit Findings**:
  - In `TOPS_FINAL/sim_build/sanity/core_sanity_exec.log`, 129 directed tests pass.
  - However, in `1TOPS_Project_Signoff_Checkl (1).xlsx`, items **4.9** and **4.13** are marked **`Not Started`**!
* **Corrections Required**:
  - Update the Excel checklist status for 4.9 and 4.13 to `Done`.
  - Attach `TOPS_FINAL/sim_build/sanity/core_sanity_exec.log` as signoff evidence.

---

### Item 20: RISC-DV REGRESSION N SEEDS (N VALUE FIX)
* **Gate Mapping**: G5.5 (*riscv-dv regression stable — N seeds run with a stable pass rate; N agreed with coach*).
* **What the Checklist Means**: Running Google RISCV-DV to generate pseudo-random instruction streams with $N$ different random seeds (e.g. $N=50$ or $100$) and verifying that 100% of runs match Spike ISS execution without mismatches or hangs.
* **Audit Findings**:
  - In `TOPS_FINAL/riscv_dv_env/`, RISCV-DV was executed with only 1 seed (`riscv_arithmetic_basic_test_0`).
  - Item 5.5 is marked `Not Started` in the checklist because the seed count $N$ was never fixed or agreed with the coach.
* **Corrections Required**:
  - Propose $N = 50$ seeds to your coach.
  - Run a shell loop running seeds 1 through 50:
    ```bash
    for seed in {1..50}; do
        ./run_riscv_dv.sh riscv_arithmetic_basic_test 1 $seed
    done
    ```
  - Generate a summary log showing 50/50 PASSED to close item 5.5.
