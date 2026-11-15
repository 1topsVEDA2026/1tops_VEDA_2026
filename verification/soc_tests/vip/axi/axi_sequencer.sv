`timescale 1ns / 1ps
//==============================================================================
// axi_sequencer.sv
//
// UVM Sequencer for AXI4-Lite Master Agent
// Manages and controls transaction sequence item flow to the driver.
//==============================================================================

`ifndef AXI_SEQUENCER_SV
`define AXI_SEQUENCER_SV

class axi_sequencer extends uvm_sequencer #(axi_transaction);

    `uvm_component_utils(axi_sequencer)

    function new(string name = "axi_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass : axi_sequencer

`endif // AXI_SEQUENCER_SV
