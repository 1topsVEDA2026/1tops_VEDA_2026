# ============================================================================
# run_questa.do — Master QuestaSim Macro Script for Full SoC with RISC-V Core
#
# Automates:
#   1. Library setup & Modelsim mappings
#   2. SystemVerilog Compilation of all RTL + UVM
#   3. Simulation launch with waveform groups
#
# Available Tests:
#   soc_boot_sanity_test    — Boot and basic MUL→GPIO write verification
#   soc_gpio_write_test     — GPIO write pattern test
#   soc_uart_tx_test        — UART transmit test
#   soc_memory_test         — DMEM read/write + GPIO verify
#   soc_mext_test           — M-extension (MUL/DIV/REM) verification
#   soc_reset_test          — Reset recovery test
#   soc_stability_test      — Long-run stability (no deadlocks)
#   subsystem_base_test     — Default firmware execution
# ============================================================================

transcript on

# Allow test name override: vsim ... -G test_name=soc_mext_test
if {![info exists ::test_name]} {
    set ::test_name "soc_boot_sanity_test"
}

# Clean and create work library
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# Global Include Directories
set INC_FLAGS "+incdir+./dut/peripherals/includes \
               +incdir+./dut/peripherals/includes/apb \
               +incdir+./dut/peripherals/includes/common_cells \
               +incdir+./dut/peripherals/includes/register_interface \
               +incdir+./dut/peripherals/includes/obi \
               +incdir+./dut/core \
               +incdir+./vip/apb \
               +incdir+./vip/axi \
               +incdir+./env \
               +incdir+./tests \
               +incdir+./tb \
               +incdir+./dut/peripherals/Peripherals/GPIO \
               +incdir+./dut/peripherals/Peripherals/PLIC \
               +incdir+./dut/peripherals/Peripherals/CLINT \
               +incdir+./dut/peripherals/Peripherals/UART \
               +incdir+./dut/peripherals/Peripherals/SPI \
               +incdir+./dut/peripherals/Peripherals/TIMER \
               +incdir+./dut/peripherals/Peripherals/WDT \
               -suppress 7027,2583,2388,7061"

# Compile APB VIP interfaces and packages first so peripherals can use apb_pkg
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./vip/apb/apb_if.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./vip/apb/apb_pkg.sv

echo "=========================================================="
echo " Step 1: Compiling RISC-V Core RTL..."
echo "=========================================================="

vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/rv32_pkg.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/alu.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/mdu.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/branch_cmp.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/controller.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/decoder.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/hazard_unit.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/imm_gen.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/register_file.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/csr_regfile.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/pipe_if_de.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/pipe_de_mw.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/instr_mem.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/data_mem.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/axi4_imem_slave.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/axi4_dmem_slave.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/core/rv32_core_top.sv

echo "=========================================================="
echo " Step 2: Compiling AXI4-to-APB Bridge..."
echo "=========================================================="

vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/bridge/axi4_to_apb_bridge.sv

echo "=========================================================="
echo " Step 3: Compiling Peripheral Infrastructure..."
echo "=========================================================="

# Packages & Common Infrastructure
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/includes/cf_math_pkg.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/includes/APB.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/includes/REG_BUS.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/includes/apb_to_reg.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/includes/apb_to_reg_v2.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/includes/sync.sv

echo "=========================================================="
echo " Step 4: Compiling Peripheral RTL..."
echo "=========================================================="

# GPIO
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/GPIO/gpio_reg_pkg.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/GPIO/gpio_reg_top.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/GPIO/gpio_input_stage.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/GPIO/gpio_input_stage_no_clk_gates.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/GPIO/gpio.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/GPIO/gpio_apb_wrap.sv

# PLIC
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/PLIC/top_pkg.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/PLIC/tlul_pkg.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/PLIC/prim_subreg.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/PLIC/prim_subreg_ext.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/PLIC/rv_plic_reg_pkg.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/PLIC/rv_plic_reg_top.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/PLIC/rv_plic_gateway.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/PLIC/rv_plic_target.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/PLIC/rv_plic.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/PLIC/plic_top.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/PLIC/plic_regmap.sv

# CLINT
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/CLINT/clic_pkg.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/CLINT/clicint_reg_pkg.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/CLINT/clicint_reg_top.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/CLINT/clicintv_reg_pkg.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/CLINT/clicintv_reg_top.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/CLINT/clicvs_reg_pkg.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/CLINT/clicvs_reg_top.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/CLINT/mclic_reg_pkg.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/CLINT/mclic_reg_top.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/CLINT/clic_gateway.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/CLINT/clic_target.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/CLINT/clic.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/CLINT/clic_apb.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/CLINT/clic_reg_adapter.sv

# UART
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/UART/apb_uart.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/UART/reg_uart_wrap.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/includes/apb_uart_wrap.sv

# SPI
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/SPI/spi_master_fifo.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/SPI/spi_master_clkgen.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/SPI/spi_master_tx.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/SPI/spi_master_rx.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/SPI/spi_master_controller.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/SPI/spi_master_apb_if.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/SPI/apb_spi_master.sv

# Timer
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/TIMER/timer.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/TIMER/apb_timer.sv

# Watchdog
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/WDT/apb_watchdog.sv

# APB Interconnect & Peripheral Subsystem Top
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/apb_interconnect.sv
vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/peripherals/Peripherals/peripheral_subsystem.sv

echo "=========================================================="
echo " Step 5: Compiling SoC Top..."
echo "=========================================================="

vlog -reportprogress 300 -sv {*}$INC_FLAGS ./dut/soc_top.sv

echo "=========================================================="
echo " Step 6: Compiling UVM Environment..."
echo "=========================================================="

vlog -reportprogress 300 -sv {*}$INC_FLAGS ./env/subsystem_pkg.sv

echo "=========================================================="
echo " Step 7: Compiling Testbench..."
echo "=========================================================="

vlog -reportprogress 300 -sv {*}$INC_FLAGS ./tb/tb_top_with_core.sv

echo "=========================================================="
echo " Step 8: Launching Simulation..."
echo " Test: $::test_name"
echo "=========================================================="

vsim -coverage -voptargs="+acc -suppress 7061" -suppress 7061 +UVM_TESTNAME=$::test_name work.tb_top_with_core

# ============================================================================
# Waveform Configuration
# ============================================================================

if {![batch_mode]} {
    catch {
        add wave -group {Clocks & Reset} \
            /tb_top_with_core/HCLK \
            /tb_top_with_core/HRESETn

        add wave -group {Core IF Stage} \
            /tb_top_with_core/u_soc_top/u_core/pc_out_IF \
            /tb_top_with_core/u_soc_top/u_core/instr_IF

        add wave -group {DMEM AXI4 Master} \
            /tb_top_with_core/u_soc_top/dmem_awaddr \
            /tb_top_with_core/u_soc_top/dmem_awvalid \
            /tb_top_with_core/u_soc_top/dmem_awready \
            /tb_top_with_core/u_soc_top/dmem_wdata \
            /tb_top_with_core/u_soc_top/dmem_wvalid \
            /tb_top_with_core/u_soc_top/dmem_wready \
            /tb_top_with_core/u_soc_top/dmem_araddr \
            /tb_top_with_core/u_soc_top/dmem_arvalid \
            /tb_top_with_core/u_soc_top/dmem_arready \
            /tb_top_with_core/u_soc_top/dmem_rdata \
            /tb_top_with_core/u_soc_top/dmem_rvalid

        add wave -group {Address Demux} \
            /tb_top_with_core/u_soc_top/is_periph_req \
            /tb_top_with_core/u_soc_top/is_periph_wr \
            /tb_top_with_core/u_soc_top/is_periph_rd

        add wave -group {AXI-to-APB Bridge} \
            /tb_top_with_core/u_soc_top/u_bridge/*

        add wave -group {APB Bus} \
            /tb_top_with_core/u_soc_top/apb_paddr \
            /tb_top_with_core/u_soc_top/apb_pwdata \
            /tb_top_with_core/u_soc_top/apb_prdata \
            /tb_top_with_core/u_soc_top/apb_pwrite \
            /tb_top_with_core/u_soc_top/apb_psel \
            /tb_top_with_core/u_soc_top/apb_penable \
            /tb_top_with_core/u_soc_top/apb_pready

        add wave -group {GPIO} \
            /tb_top_with_core/gpio_out \
            /tb_top_with_core/gpio_oe \
            /tb_top_with_core/gpio_in

        add wave -group {UART} \
            /tb_top_with_core/uart_rx \
            /tb_top_with_core/uart_tx

        add wave -group {Interrupts} \
            /tb_top_with_core/u_soc_top/irq_external \
            /tb_top_with_core/u_soc_top/irq_timer \
            /tb_top_with_core/u_soc_top/wdt_irq \
            /tb_top_with_core/u_soc_top/gpio_irq \
            /tb_top_with_core/u_soc_top/uart_irq

        wave zoomfull
    }
}
run -all
coverage save -onexit soc_with_core.ucdb
