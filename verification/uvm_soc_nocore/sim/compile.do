# ==============================================================================
# compile.do - QuestaSim Compilation Script for SoC UVM Verification
# ==============================================================================

# Create work library if it does not exist
if [file exists work] {
    vdel -lib work -all
}
vlib work
vmap work work

# Define Include Paths using SV standard + format (plus individual args)
set INCDIRS "+incdir+../vip/axi+../vip/irq+../vip/gpio+../vip/uart+../vip/i2c+../vip/spi_flash+../env+../tests+../tb+../dut"

puts "===> Compiling VIP Packages and Interfaces..."
vlog -sv $INCDIRS ../vip/axi/axi_if.sv
vlog -sv $INCDIRS ../vip/axi/axi_agent_pkg.sv

vlog -sv $INCDIRS ../vip/irq/irq_if.sv
vlog -sv $INCDIRS ../vip/irq/irq_agent_pkg.sv

vlog -sv $INCDIRS ../vip/gpio/gpio_if.sv
vlog -sv $INCDIRS ../vip/gpio/gpio_agent_pkg.sv

vlog -sv $INCDIRS ../vip/uart/uart_if.sv
vlog -sv $INCDIRS ../vip/uart/uart_agent_pkg.sv

vlog -sv $INCDIRS ../vip/i2c/i2c_if.sv
vlog -sv $INCDIRS ../vip/i2c/i2c_agent_pkg.sv

vlog -sv $INCDIRS ../vip/spi_flash/spi_if.sv
vlog -sv $INCDIRS ../vip/spi_flash/spi_flash_model.sv

puts "===> Compiling DUT Modules..."
vlog -sv $INCDIRS ../dut/axi4lite_slave_mem.sv
vlog -sv $INCDIRS ../dut/soc_no_core_dut.sv

puts "===> Compiling Top Testbench & UVM Test Library..."
vlog -sv $INCDIRS ../tb/tb_soc_no_core_top.sv

puts "===> Compilation Completed Successfully!"
