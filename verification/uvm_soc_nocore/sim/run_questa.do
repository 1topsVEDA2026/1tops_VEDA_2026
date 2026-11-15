# ==============================================================================
# run_questa.do - Master QuestaSim Simulation Launcher Script
# ==============================================================================

# 1. Execute compilation
do compile.do

# 2. Start simulation with UVM test (Default: soc_sanity_test)
# Options: +UVM_TESTNAME=soc_sanity_test, soc_peripheral_reg_test, soc_interrupt_test, soc_full_system_test
vsim -voptargs="+acc" +UVM_TESTNAME=soc_sanity_test work.tb_soc_no_core_top

# 3. Load Waveforms
do wave.do

# 4. Run Simulation
run -all
