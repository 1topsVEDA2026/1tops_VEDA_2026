# ==============================================================================
# wave.do - QuestaSim Waveform Formatting Script
# ==============================================================================

onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -noupdate -divider {Clock & Reset}
add wave -noupdate -format Logic /tb_soc_no_core_top/clk
add wave -noupdate -format Logic /tb_soc_no_core_top/rst_n

add wave -noupdate -divider {AXI VIP Bus}
add wave -noupdate -format Hexadecimal /tb_soc_no_core_top/axi_bus/awaddr
add wave -noupdate -format Logic /tb_soc_no_core_top/axi_bus/awvalid
add wave -noupdate -format Logic /tb_soc_no_core_top/axi_bus/awready
add wave -noupdate -format Hexadecimal /tb_soc_no_core_top/axi_bus/wdata
add wave -noupdate -format Hexadecimal /tb_soc_no_core_top/axi_bus/wstrb
add wave -noupdate -format Logic /tb_soc_no_core_top/axi_bus/wvalid
add wave -noupdate -format Logic /tb_soc_no_core_top/axi_bus/wready
add wave -noupdate -format Hexadecimal /tb_soc_no_core_top/axi_bus/bresp
add wave -noupdate -format Logic /tb_soc_no_core_top/axi_bus/bvalid
add wave -noupdate -format Logic /tb_soc_no_core_top/axi_bus/bready
add wave -noupdate -format Hexadecimal /tb_soc_no_core_top/axi_bus/araddr
add wave -noupdate -format Logic /tb_soc_no_core_top/axi_bus/arvalid
add wave -noupdate -format Logic /tb_soc_no_core_top/axi_bus/arready
add wave -noupdate -format Hexadecimal /tb_soc_no_core_top/axi_bus/rdata
add wave -noupdate -format Hexadecimal /tb_soc_no_core_top/axi_bus/rresp
add wave -noupdate -format Logic /tb_soc_no_core_top/axi_bus/rvalid
add wave -noupdate -format Logic /tb_soc_no_core_top/axi_bus/rready

add wave -noupdate -divider {Interrupt VIP (CLINT/PLIC)}
add wave -noupdate -format Logic /tb_soc_no_core_top/irq_bus/irq_clint
add wave -noupdate -format Logic /tb_soc_no_core_top/irq_bus/irq_plic

add wave -noupdate -divider {GPIO VIP}
add wave -noupdate -format Hexadecimal /tb_soc_no_core_top/gpio_bus/gpio_in
add wave -noupdate -format Hexadecimal /tb_soc_no_core_top/gpio_bus/gpio_out

add wave -noupdate -divider {DUT Internal Signals}
add wave -noupdate -format Hexadecimal /tb_soc_no_core_top/u_soc_dut/reg_clint
add wave -noupdate -format Hexadecimal /tb_soc_no_core_top/u_soc_dut/reg_plic
add wave -noupdate -format Hexadecimal /tb_soc_no_core_top/u_soc_dut/reg_gpio_out

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 250
configure wave -valuecolwidth 150
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1ns
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ps} {1000 ns}
