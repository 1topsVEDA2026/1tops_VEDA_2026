// =============================================================================
// APB VIP Package
// =============================================================================
// Packages all common APB VIP components for easy import.

package apb_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "apb_transaction.sv"
    `include "apb_master_driver.sv"
    `include "apb_monitor.sv"
    `include "apb_master_agent.sv"
    `include "apb_sequences.sv"
endpackage : apb_pkg
