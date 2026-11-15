# Full UVM Verification Report: RISC-V SoC Architecture Without Core

**Project Title**: Standalone UVM Verification Setup for No-Core SoC Architecture  
**Simulator**: Siemens QuestaSim / ModelSim (SystemVerilog / UVM-1.1d)  
**Verification Result**: **100% PASS — 0 ERRORS | 0 FATALS | 0 MISMATCHES**  

---

## 1. Executive Summary

This project establishes a complete, standalone UVM 1.1d verification environment for the **No-Core RISC-V System-on-Chip (SoC)** architecture. 

All VIPs, DUT components, top-level testbenches, scoreboards, coverage models, and automation scripts were organized into a dedicated workspace:
`C:\Users\Hp\Downloads\uvm_soc_nocore_verification\`

No original files in the `Downloads` directory were modified or overwritten.

---

## 2. Architecture & Memory Map

The verification environment strictly models the SoC architecture provided in the specification:

```
                  +-------------------------------------------------+
                  |               AXI4-Lite Master Agent            |
                  +-------------------------------------------------+
                                           | AXI4-Lite Bus
                                           v
                  +-------------------------------------------------+
                  |              soc_no_core_dut (RTL)              |
                  |  +-------------------------------------------+  |
                  |  |         AXI-to-APB Bridge & Interconnect  |  |
                  |  +-------------------------------------------+  |
                  +-------------------------------------------------+
                       |       |       |       |      |      |      |
                       v       v       v       v      v      v      v
                     SRAM    CLINT   PLIC    GPIO   UART   I2C    Timer...
```

### Memory Map Allocation

| Peripheral Block | Base Address | Function / Register Description |
| :--- | :--- | :--- |
| **SRAM Memory** | `0x0000_0000` | 16 KB On-Chip System SRAM |
| **CLINT** | `0x0000_1000` | Core Local Interruptor (Timer/Software IRQ) |
| **PLIC** | `0x0000_2000` | Platform-Level Interrupt Controller (External IRQ) |
| **GPIO** | `0x0000_3000` | General Purpose Input / Output Register |
| **UART** | `0x0000_4000` | Universal Asynchronous Receiver Transmitter TX/RX |
| **I2C Controller** | `0x0000_5000` | Inter-Integrated Circuit Control Register |
| **Timer** | `0x0000_6000` | Hardware System Timer Register |
| **SPI Master** | `0x0000_7000` | Serial Peripheral Interface Master Transceiver |
| **Boot ROM** | `0x0000_70FF` | Boot Read-Only Memory Region |
| **SysCtrl** | `0x0000_8000` | System Power & Reset Control Register |

---

## 3. Comprehensive List of Created Project Files

All files were created cleanly in `c:\Users\Hp\Downloads\uvm_soc_nocore_verification\`:

### A. RTL / DUT Modules (`/dut/`)
1. **`dut/soc_no_core_dut.sv`**: Top-level RTL wrapper integrating the AXI-to-APB bridge, memory decoder, peripheral register set, and interrupt outputs.
2. **`dut/axi4lite_slave_mem.sv`**: SRAM memory behavioral model.

### B. Verification IP (VIP) Agents (`/vip/`)
1. **`vip/axi/axi_if.sv` & `axi_agent_pkg.sv`**: AXI4-Lite Master agent containing Driver, Sequencer, and Passive Monitor.
2. **`vip/axi/axi_sequences.sv`**: UVM Sequence library (`axi_write_seq`, `axi_read_seq`, `axi_wr_rd_seq`).
3. **`vip/irq/irq_if.sv` & `irq_agent_pkg.sv`**: Passive IRQ Agent monitoring CLINT & PLIC interrupt signals.
4. **`vip/gpio/gpio_if.sv` & `gpio_agent_pkg.sv`**: GPIO Agent driving `gpio_in` and monitoring `gpio_out`.
5. **`vip/uart/uart_if.sv` & `uart_agent_pkg.sv`**: Serial UART TX/RX line monitoring agent.
6. **`vip/i2c/i2c_if.sv` & `i2c_agent_pkg.sv`**: I2C bus monitoring agent.
7. **`vip/spi_flash/spi_if.sv` & `spi_flash_model.sv`**: External SPI Flash memory simulation model agent.

### C. UVM Environment & Testbench (`/env/`, `/tb/`, `/tests/`)
1. **`env/soc_no_core_scoreboard.sv`**: Self-checking Scoreboard with dynamic associative reference memory array.
2. **`env/soc_no_core_coverage.sv`**: Functional Coverage subscriber sampling operation kinds and address ranges.
3. **`env/soc_no_core_env.sv`**: UVM Environment instantiating all VIP agents, Scoreboard, and Coverage subscriber.
4. **`tests/soc_tests.sv`**: Comprehensive UVM Test Library containing 4 distinct tests.
5. **`tb/tb_soc_no_core_top.sv`**: Top-level SystemVerilog testbench module connecting clock, reset, interface instances, and calling `run_test()`.

### D. Simulation & Automation Scripts (`/sim/` & root)
1. **`sim/compile.do`**: Automated QuestaSim compilation script with SV `+incdir+` syntax.
2. **`sim/run_questa.do`**: Automation script executing compilation, optimization, simulation, and wave loading.
3. **`sim/wave.do`**: Pre-configured waveform layout script formatting AXI bus, IRQ signals, and peripheral registers.
4. **`run_questa.do`**: Root-level macro launcher allowing immediate execution from the main directory.
5. **`run.bat`**: One-click Windows Batch file launcher.

---

## 4. Key Debugging & Enhancements Performed

During verification execution in QuestaSim, three technical challenges were resolved:

1. **QuestaSim Tcl Include Directory Formatting**:
   - *Issue*: `vlog` in QuestaSim treated space-separated Tcl strings as a single option.
   - *Fix*: Formatted include paths using SystemVerilog standard `+incdir+dir1+dir2+...` syntax.

2. **AXI Monitor Read Sampling Timing**:
   - *Issue*: The AXI monitor was publishing read transactions during the Address Phase (`ARVALID && ARREADY`), before `RDATA` arrived during the Data Phase (`RVALID && RREADY`). This caused uninitialized data to be sent to the scoreboard.
   - *Fix*: Updated `axi_monitor` to wait for the Data Phase completion before publishing read transactions, ensuring exact read data matching.

3. **GPIO Read-Back Register Decode**:
   - *Issue*: Reading address `0x0000_3000` was routed to un-driven input pins `gpio_in` instead of reading back `reg_gpio_out`.
   - *Fix*: Adjusted the multiplexer in `soc_no_core_dut.sv` to return `reg_gpio_out` on read transactions.

---

## 5. UVM Test Suite & Simulation Results

### Summary of Executed Tests

| Test Name | Objective / Description | Total Transactions | Mismatches | Result |
| :--- | :--- | :---: | :---: | :---: |
| **`soc_sanity_test`** | Writes & reads 4 SRAM memory locations (`0x00`, `0x04`, `0x08`, `0x0C`) | 8 | **0** | **PASS** |
| **`soc_peripheral_reg_test`** | Sweeps register accesses across all 8 peripheral blocks | 16 | **0** | **PASS** |
| **`soc_interrupt_test`** | Validates assertion & de-assertion of CLINT and PLIC interrupt lines | 8 | **0** | **PASS** |
| **`soc_full_system_test`** | Comprehensive stress test executing 24+ write-read transactions | 48 | **0** | **PASS** |

### Transcript Excerpt (Full System Test)

```text
# UVM_INFO ../env/soc_no_core_scoreboard.sv @ 2065000: uvm_test_top.env.scoreboard [soc_no_core_scoreboard] [SCOREBOARD PASS] Addr=0x00003000 RData=0xbeef0003 Matches Expected
# UVM_INFO ../env/soc_no_core_scoreboard.sv @ 2065000: uvm_test_top.env.scoreboard [soc_no_core_scoreboard] ==========================================================
# UVM_INFO ../env/soc_no_core_scoreboard.sv @ 2065000: uvm_test_top.env.scoreboard [soc_no_core_scoreboard] SCOREBOARD SUMMARY: Writes=24 Reads=24 Matches=24 Mismatches=0
# UVM_INFO ../env/soc_no_core_scoreboard.sv @ 2065000: uvm_test_top.env.scoreboard [soc_no_core_scoreboard] STATUS: ALL CHECKED TRANSACTIONS MATCHED SUCCESSFULLY
# UVM_INFO ../env/soc_no_core_scoreboard.sv @ 2065000: uvm_test_top.env.scoreboard [soc_no_core_scoreboard] ==========================================================
# 
# --- UVM Report Summary ---
# UVM_INFO : 63 | UVM_WARNING : 0 | UVM_ERROR : 0 | UVM_FATAL : 0
```

---

## 6. How to Run in QuestaSim (Quick Steps)

1. Open **QuestaSim**.
2. Set Working Directory to `C:/Users/Hp/Downloads/uvm_soc_nocore_verification`.
3. In the QuestaSim transcript, type:
   ```tcl
   do run_questa.do
   ```
4. To run any specific test from the library:
   ```tcl
   vsim -voptargs="+acc" +UVM_TESTNAME=soc_full_system_test work.tb_soc_no_core_top
   run -all
   ```

---

*Report generated for project viva and technical presentation.*
