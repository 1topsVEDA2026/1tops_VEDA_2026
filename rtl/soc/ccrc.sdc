#=============================================================================
# ccrc.sdc  —  Clock & Reset Controller timing constraints
#
# Project : 1-TOPS VEDA Secure IoT RISC-V SoC
# Scope   : Defines both clock domains, declares them asynchronous to each
#           other, and tags the reset-synchroniser arcs as false paths.
#           Companion to rtl/soc/ccrc.sv and docs/G1_01_Specification_Document.md §1.10.
#
# Include this file from soc_top.sdc, or load directly in DC with:
#   read_sdc  scripts/ccrc.sdc
#=============================================================================

#-----------------------------------------------------------------------------
# 1. Clock definitions
#-----------------------------------------------------------------------------

# CLK_SYS  —  100 MHz digital system clock
# In exploration mode we used period 1.00 ns; production target is 10.00 ns.
# Pick the right line for the current run.
# create_clock -name CLK_SYS -period 1.00  [get_pins u_ccrc/clk_sys]  ;# exploration (1 GHz)
create_clock   -name CLK_SYS -period 10.00 [get_pins u_ccrc/clk_sys]  ;# production  (100 MHz)

# CLK_WDT  —  32.768 kHz watchdog clock (period ≈ 30 517.578 ns)
create_clock   -name CLK_WDT -period 30517.6 [get_pins u_ccrc/clk_wdt]

# CLK_XTAL  —  virtual root crystal clock, for PLL_LOCK sync chain
# (25 MHz = 40 ns)
create_clock   -name CLK_XTAL -period 40.00 [get_ports clk_xtal]

# CLK_PLL  —  virtual PLL output clock, 800 MHz = 1.25 ns
create_clock   -name CLK_PLL  -period 1.25  [get_ports clk_pll]

#-----------------------------------------------------------------------------
# 2. Clock groups  —  declare asynchronous relationships
#-----------------------------------------------------------------------------

# CLK_SYS and CLK_WDT are asynchronous to each other. CDC paths between
# them are handled by Gray-coded + 2-FF sync for counter readback and
# toggle+ack handshake for config writes.
set_clock_groups -asynchronous \
    -group {CLK_SYS CLK_PLL}   \
    -group {CLK_WDT}           \
    -group {CLK_XTAL}

#-----------------------------------------------------------------------------
# 3. False paths on reset synchronisers
#-----------------------------------------------------------------------------

# sys_rst_n chain (cold_rst_n → sys_rst_meta → sys_rst_sync_n on CLK_SYS)
set_false_path -to   [get_pins u_ccrc/sys_rst_meta_reg/D]
set_false_path -from [get_pins u_ccrc/sys_rst_meta_reg/CLR] \
               -to   [get_pins u_ccrc/sys_rst_sync_n_reg/CLR]

# wdt_rst_n chain (cold_rst_n → wdt_rst_meta → wdt_rst_sync_n on CLK_WDT)
set_false_path -to   [get_pins u_ccrc/wdt_rst_meta_reg/D]
set_false_path -from [get_pins u_ccrc/wdt_rst_meta_reg/CLR] \
               -to   [get_pins u_ccrc/wdt_rst_sync_n_reg/CLR]

# PLL_LOCK 2-FF chain on CLK_XTAL
set_false_path -to [get_pins u_ccrc/pll_lock_meta_reg/D]

#-----------------------------------------------------------------------------
# 4. Input delays — chip pad side
#-----------------------------------------------------------------------------

# PAD_RSTN is async; set_false_path is applied instead of input_delay.
set_false_path -from [get_ports pad_rstn]

# POR_N comes from the analog block through a chip-internal net; also async.
set_false_path -from [get_pins u_analog/por_n]

# PLL_LOCK is async; false path to the first FF of the sync chain only.
set_false_path -from [get_pins u_analog/pll_lock] \
               -to   [get_pins u_ccrc/pll_lock_meta_reg/D]

#-----------------------------------------------------------------------------
# 5. Reset uncertainty  —  allow a sensible margin on async signals
#-----------------------------------------------------------------------------

set_clock_uncertainty -setup 0.100 [get_clocks CLK_SYS]
set_clock_uncertainty -hold  0.050 [get_clocks CLK_SYS]

set_clock_uncertainty -setup 50.0  [get_clocks CLK_WDT]
set_clock_uncertainty -hold  10.0  [get_clocks CLK_WDT]

#-----------------------------------------------------------------------------
# 6. Case analysis  —  constrain the clock mux select
#-----------------------------------------------------------------------------

# In normal operation sync_pll_lock = 1 → clk_sys follows CLK_PLL/8.
# Constrain timing for the PLL-selected case; the XTAL fallback is validated
# separately in a second DC run with the opposite case analysis.
set_case_analysis 1 [get_pins u_ccrc/sync_pll_lock]
