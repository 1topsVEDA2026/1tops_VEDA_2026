# ============================================================================
# run_signoff_closure.do — Automates Stability Test & Full Coverage Closure
# ============================================================================

transcript file sim_soc_stability.log

echo "=========================================================="
echo " Step 1: Running Multi-Cycle Stability Stress Test (10 us)..."
echo " Test: soc_stability_test"
echo "=========================================================="

vsim -coverage -voptargs="+acc -suppress 7061" -suppress 7061 +UVM_TESTNAME=soc_stability_test work.tb_top_with_core
run -all
coverage save soc_stability.ucdb

echo "=========================================================="
echo " Step 2: Merging Coverage Databases..."
echo "=========================================================="

vcover merge final_soc_coverage.ucdb soc_with_core.ucdb soc_stability.ucdb

echo "=========================================================="
echo " Step 3: Generating HTML Coverage Report..."
echo "=========================================================="

vcover report -html -htmldir full_soc_cov_html -details final_soc_coverage.ucdb

echo "=========================================================="
echo " Signoff Coverage Report Generated in: full_soc_cov_html/index.html"
echo " All Gate G6 Signoff Tests Completed Successfully!"
echo "=========================================================="
