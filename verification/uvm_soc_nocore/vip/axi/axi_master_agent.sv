`timescale 1ns / 1ps
//==============================================================================
// axi_master_agent.sv
//
// UVM Agent for AXI4-Lite Master Interface
// Encapsulates Driver, Sequencer, and Monitor components.
//==============================================================================

`ifndef AXI_MASTER_AGENT_SV
`define AXI_MASTER_AGENT_SV

class axi_master_agent extends uvm_agent;

    `uvm_component_utils(axi_master_agent)

    // Components
    axi_master_driver driver;
    axi_sequencer     sequencer;
    axi_monitor        monitor;

    // Constructor
    function new(string name = "axi_master_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // -------------------------------------------------------------------------
    // Build Phase
    // -------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Always create monitor
        monitor = axi_monitor::type_id::create("monitor", this);

        // Create driver and sequencer if active agent
        if (get_is_active() == UVM_ACTIVE) begin
            driver    = axi_master_driver::type_id::create("driver", this);
            sequencer = axi_sequencer::type_id::create("sequencer", this);
        end
    endfunction

    // -------------------------------------------------------------------------
    // Connect Phase
    // -------------------------------------------------------------------------
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        if (get_is_active() == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass : axi_master_agent

`endif // AXI_MASTER_AGENT_SV
