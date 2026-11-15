`timescale 1ns / 1ps
//==============================================================================
// axi_sequences.sv
//
// Base and Utility Sequences for AXI4-Lite Master Agent
//==============================================================================

`ifndef AXI_SEQUENCES_SV
`define AXI_SEQUENCES_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_agent_pkg::*;

// -----------------------------------------------------------------------------
// Base Sequence
// -----------------------------------------------------------------------------
class axi_base_sequence extends uvm_sequence #(axi_transaction);

    `uvm_object_utils(axi_base_sequence)

    function new(string name = "axi_base_sequence");
        super.new(name);
    endfunction

    virtual task pre_body();
        if (starting_phase != null) begin
            starting_phase.raise_objection(this, get_type_name());
        end
    endtask

    virtual task post_body();
        if (starting_phase != null) begin
            starting_phase.drop_objection(this, get_type_name());
        end
    endtask

endclass : axi_base_sequence

// -----------------------------------------------------------------------------
// Single Write Sequence
// -----------------------------------------------------------------------------
class axi_write_seq extends axi_base_sequence;

    `uvm_object_utils(axi_write_seq)

    rand bit [31:0] waddr;
    rand bit [31:0] wdata;
    rand bit [3:0]  wstrb;

    constraint c_strb { wstrb == 4'b1111; }

    function new(string name = "axi_write_seq");
        super.new(name);
    endfunction

    virtual task body();
        axi_transaction tr;
        `uvm_do_with(tr, {
            kind  == axi_transaction::AXI_WRITE;
            addr  == local::waddr;
            wdata == local::wdata;
            wstrb == local::wstrb;
        })
    endtask

endclass : axi_write_seq

// -----------------------------------------------------------------------------
// Single Read Sequence
// -----------------------------------------------------------------------------
class axi_read_seq extends axi_base_sequence;

    `uvm_object_utils(axi_read_seq)

    rand bit [31:0] raddr;
    bit [31:0]      read_data;

    function new(string name = "axi_read_seq");
        super.new(name);
    endfunction

    virtual task body();
        axi_transaction tr;
        `uvm_do_with(tr, {
            kind == axi_transaction::AXI_READ;
            addr == local::raddr;
        })
        read_data = tr.rdata;
    endtask

endclass : axi_read_seq

// -----------------------------------------------------------------------------
// Write then Read Back Verification Sequence
// -----------------------------------------------------------------------------
class axi_wr_rd_seq extends axi_base_sequence;

    `uvm_object_utils(axi_wr_rd_seq)

    rand bit [31:0] addr;
    rand bit [31:0] data;
    bit [31:0]      rdata;

    function new(string name = "axi_wr_rd_seq");
        super.new(name);
    endfunction

    virtual task body();
        axi_transaction wr_tr, rd_tr;

        // Perform Write
        `uvm_do_with(wr_tr, {
            kind  == axi_transaction::AXI_WRITE;
            addr  == local::addr;
            wdata == local::data;
            wstrb == 4'b1111;
        })

        // Perform Read
        `uvm_do_with(rd_tr, {
            kind == axi_transaction::AXI_READ;
            addr == local::addr;
        })

        rdata = rd_tr.rdata;

        // Basic self-check
        if (rdata === data) begin
            `uvm_info(get_type_name(), $sformatf("MATCH: Addr=0x%08h Data=0x%08h", addr, rdata), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("MISMATCH: Addr=0x%08h Exp=0x%08h Act=0x%08h", addr, data, rdata))
        end
    endtask

endclass : axi_wr_rd_seq

`endif // AXI_SEQUENCES_SV
