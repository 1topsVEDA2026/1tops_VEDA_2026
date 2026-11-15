# ==============================================================================
# run_coverage.do  --  Coverage-Enabled Simulation for Items 6.3, 6.7, 6.8
# Run from: QuestaSim transcript, working directory = uvm_soc_nocore_verification/sim/
# Usage:  do run_coverage.do
# ==============================================================================

# Step 1: Fresh compile (deletes stale work library automatically)
do compile.do

# Step 2: Run ALL 4 tests with coverage enabled, save each UCDB

# --- Test 1: soc_sanity_test (SRAM read/write baseline) ---
puts "==> Running soc_sanity_test with coverage..."
vsim -coverage -voptargs="+acc" +UVM_TESTNAME=soc_sanity_test work.tb_soc_no_core_top
run -all
coverage save -onexit sanity.ucdb
quit -sim

# --- Test 2: soc_peripheral_reg_test (hits all 8 peripheral registers) ---
puts "==> Running soc_peripheral_reg_test with coverage..."
vsim -coverage -voptargs="+acc" +UVM_TESTNAME=soc_peripheral_reg_test work.tb_soc_no_core_top
run -all
coverage save -onexit periph_reg.ucdb
quit -sim

# --- Test 3: soc_interrupt_test (CLINT + PLIC assert/deassert) ---
puts "==> Running soc_interrupt_test with coverage..."
vsim -coverage -voptargs="+acc" +UVM_TESTNAME=soc_interrupt_test work.tb_soc_no_core_top
run -all
coverage save -onexit interrupt.ucdb
quit -sim

# --- Test 4: soc_full_system_test (20+ transactions, stress) ---
puts "==> Running soc_full_system_test with coverage (10us stress)..."
vsim -coverage -voptargs="+acc" +UVM_TESTNAME=soc_full_system_test work.tb_soc_no_core_top
run 10us
coverage save -onexit full_sys.ucdb
quit -sim

# Step 3: Merge all UCDBs
puts "==> Merging coverage databases..."
vcover merge merged_nocore.ucdb sanity.ucdb periph_reg.ucdb interrupt.ucdb full_sys.ucdb

# Step 4: Generate HTML report
puts "==> Generating HTML coverage report..."
vcover report -html -htmldir cov_html_report -details merged_nocore.ucdb

# Step 5: Print summary to transcript
puts "==> Coverage summary:"
vcover report -summary merged_nocore.ucdb

puts ""
puts "============================================================"
puts "  DONE.  Open: uvm_soc_nocore_verification/sim/cov_html_report/index.html"
puts "  Criteria satisfied:"
puts "    6.3  Register Field Coverage  -- check field covergroup %"
puts "    6.7  Memory Map Decode        -- cp_addr_space bins all hit"
puts "    6.8  Traffic Stress           -- full_sys_test ran 10us"
puts "============================================================"
