# ==============================================================================
# SpyGlass Lint & CDC TCL Script — Full SoC Top (soc_top)
# Methodology Goals:
#   1. lint/lint_rtl
#   2. cdc/cdc_verify
# Usage: sg_shell -f spyglass_soc_lint_cdc.tcl
# ==============================================================================

set project_name "soc_top_lint_cdc"
new_project ${project_name}

# Target Top Module
set_option top soc_top

# Design and Language Settings
set_option enableSV09 yes
set_option language_mode mixed
set_option allow_module_override yes
set_option designread_enable_synthesis yes
set_option designread_disable_flatten no

# Include Directories
set SOC_DIR "/home/ti_ml/TOPS/FUL_SOC_WITH_CORE/dut"
set CORE_DIR "/home/ti_ml/TOPS_FINAL"

set_option incdir [list \
    ${SOC_DIR}/peripherals/includes \
    ${SOC_DIR}/peripherals/includes/apb \
    ${SOC_DIR}/peripherals/includes/common_cells \
    ${SOC_DIR}/peripherals/includes/register_interface \
    ${SOC_DIR}/peripherals/includes/obi \
    ${CORE_DIR} \
    ${SOC_DIR}/peripherals/Peripherals/GPIO \
    ${SOC_DIR}/peripherals/Peripherals/PLIC \
    ${SOC_DIR}/peripherals/Peripherals/CLINT \
    ${SOC_DIR}/peripherals/Peripherals/UART \
    ${SOC_DIR}/peripherals/Peripherals/SPI \
    ${SOC_DIR}/peripherals/Peripherals/TIMER \
    ${SOC_DIR}/peripherals/Peripherals/WDT \
]

# ------------------------------------------------------------------------------
# 1. Core Processor RTL Files
# ------------------------------------------------------------------------------
read_file -type verilog ${CORE_DIR}/rv32_pkg.sv
read_file -type verilog ${CORE_DIR}/alu.sv
read_file -type verilog ${CORE_DIR}/booth_multiplier_radix4.sv
read_file -type verilog ${CORE_DIR}/mdu.sv
read_file -type verilog ${CORE_DIR}/branch_cmp.sv
read_file -type verilog ${CORE_DIR}/controller.sv
read_file -type verilog ${CORE_DIR}/decoder.sv
read_file -type verilog ${CORE_DIR}/hazard_unit.sv
read_file -type verilog ${CORE_DIR}/imm_gen.sv
read_file -type verilog ${CORE_DIR}/register_file.sv
read_file -type verilog ${CORE_DIR}/csr_regfile.sv
read_file -type verilog ${CORE_DIR}/pipe_if_de.sv
read_file -type verilog ${CORE_DIR}/pipe_de_mw.sv
read_file -type verilog ${CORE_DIR}/instr_mem.sv
read_file -type verilog ${CORE_DIR}/data_mem.sv
read_file -type verilog ${CORE_DIR}/axi4_imem_slave.sv
read_file -type verilog ${CORE_DIR}/axi4_dmem_slave.sv
read_file -type verilog ${CORE_DIR}/rv32_core_top.sv

# ------------------------------------------------------------------------------
# 2. Interconnect & Protocol Bridges
# ------------------------------------------------------------------------------
read_file -type verilog ${SOC_DIR}/bridge/axi4_to_apb_bridge.sv
read_file -type verilog ${SOC_DIR}/peripherals/includes/cf_math_pkg.sv
read_file -type verilog ${SOC_DIR}/peripherals/includes/APB.sv
read_file -type verilog ${SOC_DIR}/peripherals/includes/REG_BUS.sv
read_file -type verilog ${SOC_DIR}/peripherals/includes/apb_to_reg.sv
read_file -type verilog ${SOC_DIR}/peripherals/includes/apb_to_reg_v2.sv
read_file -type verilog ${SOC_DIR}/peripherals/includes/sync.sv

# ------------------------------------------------------------------------------
# 3. Peripheral Subsystem (GPIO, PLIC, CLINT, UART, SPI, Timer, WDT)
# ------------------------------------------------------------------------------
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/GPIO/gpio_reg_pkg.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/GPIO/gpio_reg_top.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/GPIO/gpio_input_stage.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/GPIO/gpio_input_stage_no_clk_gates.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/GPIO/gpio.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/GPIO/gpio_apb_wrap.sv

read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/PLIC/top_pkg.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/PLIC/tlul_pkg.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/PLIC/prim_subreg.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/PLIC/prim_subreg_ext.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/PLIC/rv_plic_reg_pkg.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/PLIC/rv_plic_reg_top.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/PLIC/rv_plic_gateway.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/PLIC/rv_plic_target.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/PLIC/rv_plic.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/PLIC/plic_top.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/PLIC/plic_regmap.sv

read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/CLINT/clic_pkg.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/CLINT/clicint_reg_pkg.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/CLINT/clicint_reg_top.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/CLINT/clicintv_reg_pkg.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/CLINT/clicintv_reg_top.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/CLINT/clicvs_reg_pkg.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/CLINT/clicvs_reg_top.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/CLINT/mclic_reg_pkg.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/CLINT/mclic_reg_top.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/CLINT/clic_gateway.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/CLINT/clic_target.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/CLINT/clic.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/CLINT/clic_apb.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/CLINT/clic_reg_adapter.sv

read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/UART/apb_uart.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/UART/reg_uart_wrap.sv
read_file -type verilog ${SOC_DIR}/peripherals/includes/apb_uart_wrap.sv

read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/SPI/spi_master_fifo.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/SPI/spi_master_clkgen.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/SPI/spi_master_tx.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/SPI/spi_master_rx.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/SPI/spi_master_controller.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/SPI/spi_master_apb_if.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/SPI/apb_spi_master.sv

read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/TIMER/timer.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/TIMER/apb_timer.sv

read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/WDT/apb_watchdog.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/apb_interconnect.sv
read_file -type verilog ${SOC_DIR}/peripherals/Peripherals/peripheral_subsystem.sv

# ------------------------------------------------------------------------------
# 4. Ascon Hardware Cryptographic Accelerator
# ------------------------------------------------------------------------------
read_file -type verilog ${SOC_DIR}/ascon/roundconstant.v
read_file -type verilog ${SOC_DIR}/ascon/roundcounter.v
read_file -type verilog ${SOC_DIR}/ascon/linear_layer.v
read_file -type verilog ${SOC_DIR}/ascon/sub_layer.v
read_file -type verilog ${SOC_DIR}/ascon/Permutation.v
read_file -type verilog ${SOC_DIR}/ascon/Encryption.v
read_file -type verilog ${SOC_DIR}/ascon/Decryption.v
read_file -type verilog ${SOC_DIR}/ascon/Ascon.v
read_file -type verilog ${SOC_DIR}/ascon/ascon_axi_slave_lite_v1_0_S00_AXI.v
read_file -type verilog ${SOC_DIR}/ascon/ascon_axi.v

# ------------------------------------------------------------------------------
# 5. SoC Top-Level
# ------------------------------------------------------------------------------
read_file -type verilog ${SOC_DIR}/soc_top.sv

# Compile / Link Design
compile_design

# ------------------------------------------------------------------------------
# GOAL 1: lint/lint_rtl
# ------------------------------------------------------------------------------
current_goal lint/lint_rtl
run_goal

set report_dir "/home/ti_ml/TOPS_FINAL/spyglass_reports/soc_top"
exec mkdir -p ${report_dir}/lint

write_report -reportdir ${report_dir}/lint project_summary
write_report -reportdir ${report_dir}/lint moresimple > ${report_dir}/lint/moresimple.rpt

# ------------------------------------------------------------------------------
# GOAL 2: cdc/cdc_verify (Clock Domain Crossing & Reset Integrity)
# ------------------------------------------------------------------------------
current_goal cdc/cdc_verify

# Clocks specification
# Primary system clock
define_clock -name clk -period 10.0 -edge {0 5.0}

# Derived clocks: SPI Master clock output
define_clock -name spi_sclk -domain SPI_CLK

# Asynchronous resets
define_reset -name rst_n -value 0

run_goal

exec mkdir -p ${report_dir}/cdc
write_report -reportdir ${report_dir}/cdc cdc_summary
write_report -reportdir ${report_dir}/cdc cdc_detailed > ${report_dir}/cdc/cdc_detailed.rpt

save_project
exit -force
