# SoC Verification Without Core - UVM Testbench Environment

This folder `uvm_soc_nocore_verification` contains the complete UVM Verification setup matching the architecture diagram in **Screenshot 2026-09-12 214029.png**.

---

## Directory & File Structure

```
c:\Users\Hp\Downloads\uvm_soc_nocore_verification\
├── dut/
│   ├── soc_no_core_dut.sv         (Complete SoC No-Core DUT module matching diagram)
│   └── axi4lite_slave_mem.sv      (SRAM Memory model for memory testing)
├── vip/
│   ├── axi/                       (AXI Master Agent VIP package & interfaces)
│   │   ├── axi_if.sv
│   │   ├── axi_transaction.sv
│   │   ├── axi_sequences.sv
│   │   ├── axi_sequencer.sv
│   │   ├── axi_master_driver.sv
│   │   ├── axi_monitor.sv
│   │   ├── axi_master_agent.sv
│   │   └── axi_agent_pkg.sv
│   ├── irq/                       (IRQ VIP - Monitors CLINT/PLIC interrupt lines)
│   │   ├── irq_if.sv
│   │   └── irq_agent_pkg.sv
│   ├── gpio/                      (GPIO VIP - Monitors & drives GPIO pins)
│   │   ├── gpio_if.sv
│   │   └── gpio_agent_pkg.sv
│   ├── uart/                      (UART VIP - Monitors serial TX/RX lines)
│   │   ├── uart_if.sv
│   │   └── uart_agent_pkg.sv
│   ├── i2c/                       (I2C VIP - Monitors I2C SDA/SCL lines)
│   │   ├── i2c_if.sv
│   │   └── i2c_agent_pkg.sv
│   └── spi_flash/                 (SPI Flash Model VIP - Responds to SPI Master)
│       ├── spi_if.sv
│       └── spi_flash_model.sv
├── env/
│   ├── soc_no_core_env.sv         (UVM Env instantiating all VIPs, Scoreboard & Coverage)
│   ├── soc_no_core_scoreboard.sv  (Scoreboard tracking memory & register transactions)
│   └── soc_no_core_coverage.sv    (Functional Coverage Subscriber measuring coverage)
├── tests/
│   └── soc_tests.sv               (UVM Test library: Sanity, Reg, Interrupt, System tests)
├── tb/
│   └── tb_soc_no_core_top.sv      (Top-level Testbench connecting all interfaces & DUT)
└── sim/
    ├── compile.do                 (QuestaSim script to compile all SV files & VIPs)
    ├── run_questa.do              (Master QuestaSim script to compile, run & view waves)
    ├── wave.do                    (Formated waveform configuration script)
    └── run.bat                    (Windows one-click batch launcher)
```

---

## Why Each File Was Created / Copied

1. **`dut/soc_no_core_dut.sv` (NEW)**:
   - **Why created**: Represents the `SoC - NoCore` block from your architecture diagram. Connects the AXI-to-AXI-Lite bridge, AXI-Lite-to-APB interconnect, and peripheral register blocks for CLINT, PLIC, GPIO, UART, I2C, Timer, SPI Master, Boot RoM, SysCtrl, and SRAM.

2. **`vip/irq/` (NEW)**:
   - **Why created**: Implements the `IRQ VIP` block from the diagram. Monitors `irq_clint` and `irq_plic` interrupt lines coming out of the DUT.

3. **`vip/gpio/`, `vip/uart/`, `vip/i2c/`, `vip/spi_flash/` (NEW)**:
   - **Why created**: Implements the `GPIO VIP`, `UART VIP`, `I2C VIP`, and `SPI Flash Model` blocks from the diagram.

4. **`env/soc_no_core_coverage.sv` (NEW)**:
   - **Why created**: Implements the `Coverage Model` block from the diagram. Tracks functional coverage across AXI operation types, memory spaces, and peripheral register access.

5. **`env/soc_no_core_env.sv` (UPDATED)**:
   - **Why updated**: Connects all VIP agents, Scoreboard, and Functional Coverage subscriber together as specified in the `env` green box of the block diagram.

6. **`tests/soc_tests.sv` (UPDATED)**:
   - **Why updated**: Provides tests for every aspect of the SoC architecture:
     - `soc_sanity_test`: Basic SRAM read/write check.
     - `soc_peripheral_reg_test`: Register access check across CLINT, PLIC, GPIO, UART, Boot RoM, SysCtrl.
     - `soc_interrupt_test`: Triggers and checks CLINT/PLIC interrupts.
     - `soc_full_system_test`: Comprehensive verification test.

7. **`tb/tb_soc_no_core_top.sv` (UPDATED)**:
   - **Why updated**: Top testbench instantiating `soc_no_core_dut`, creating clock/reset generators, linking virtual interfaces to `uvm_config_db`, and calling `run_test()`.

8. **`sim/*.do` and `sim/run.bat` (NEW)**:
   - **Why created**: Enables 1-click execution in QuestaSim without typing complex compile commands manually.

---

## What You Need to Do in QuestaSim

### Method 1: Using QuestaSim GUI (Recommended)
1. Open **QuestaSim / ModelSim**.
2. Go to **File -> Change Directory...** and select:
   `C:\Users\Hp\Downloads\uvm_soc_nocore_verification\sim`
3. In the QuestaSim Transcript window (bottom panel), type:
   ```tcl
   do run_questa.do
   ```
4. QuestaSim will automatically:
   - Compile all VIPs, DUT, Env, Tests, and Top testbench.
   - Load the `soc_sanity_test`.
   - Open the Waveform viewer with formatted signals.
   - Run the simulation to completion and print the UVM Scoreboard & Coverage Report!

---

### Method 2: Running Different UVM Tests
To run specific tests from the UVM test library, run these commands in the QuestaSim transcript:

- **Run Peripheral Register Test**:
  ```tcl
  vsim -voptargs="+acc" +UVM_TESTNAME=soc_peripheral_reg_test work.tb_soc_no_core_top
  run -all
  ```

- **Run Interrupt Test (CLINT & PLIC verification)**:
  ```tcl
  vsim -voptargs="+acc" +UVM_TESTNAME=soc_interrupt_test work.tb_soc_no_core_top
  run -all
  ```

- **Run Full System Test**:
  ```tcl
  vsim -voptargs="+acc" +UVM_TESTNAME=soc_full_system_test work.tb_soc_no_core_top
  run -all
  ```

---

### Method 3: One-Click Windows Batch Execution
Alternatively, double-click:
`C:\Users\Hp\Downloads\uvm_soc_nocore_verification\sim\run.bat`
This will launch QuestaSim directly from Windows and execute the full compilation and verification suite automatically.
