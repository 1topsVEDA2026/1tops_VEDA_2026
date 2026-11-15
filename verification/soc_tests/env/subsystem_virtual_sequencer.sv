// =============================================================================
// Subsystem Virtual Sequencer
// =============================================================================
// Holds a handle to the APB sequencer so test sequences can target
// any peripheral by using the appropriate base address.

class subsystem_virtual_sequencer extends uvm_sequencer;

    `uvm_component_utils(subsystem_virtual_sequencer)

    uvm_sequencer #(apb_transaction) apb_sqr;

    function new(string name = "subsystem_virtual_sequencer", uvm_component parent);
        super.new(name, parent);
    endfunction

endclass : subsystem_virtual_sequencer
