// =============================================================================
// Subsystem UVM Package
// =============================================================================
// Packages all subsystem UVM verification components.

package subsystem_pkg;
    import uvm_pkg::*;
    import apb_pkg::*;
    `include "uvm_macros.svh"

    `include "subsystem_scoreboard.sv"
    `include "subsystem_virtual_sequencer.sv"
    `include "subsystem_coverage.sv"
    `include "subsystem_env.sv"
    `include "subsystem_sequences.sv"
    `include "subsystem_tests.sv"
endpackage : subsystem_pkg
