`timescale 1ns / 1ps
//==============================================================================
// soc_no_core_scoreboard.sv
//
// UVM Scoreboard & Reference Model for SoC Verification Without Core
//==============================================================================

`ifndef SOC_NO_CORE_SCOREBOARD_SV
`define SOC_NO_CORE_SCOREBOARD_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_agent_pkg::*;

class soc_no_core_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(soc_no_core_scoreboard)

    // Analysis Implementation Port
    uvm_analysis_imp #(axi_transaction, soc_no_core_scoreboard) axi_analysis_export;

    // Reference Memory Model
    protected bit [31:0] ref_mem [bit [31:0]];

    // Statistics counters
    int unsigned match_count = 0;
    int unsigned mismatch_count = 0;
    int unsigned write_count = 0;
    int unsigned read_count = 0;

    function new(string name = "soc_no_core_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        axi_analysis_export = new("axi_analysis_export", this);
    endfunction

    virtual function void write(axi_transaction tr);
        bit [31:0] current_val;
        bit [31:0] new_val;
        bit [31:0] exp_data;

        if (tr.kind == axi_transaction::AXI_WRITE) begin
            write_count++;
            current_val = ref_mem.exists(tr.addr) ? ref_mem[tr.addr] : 32'h0;
            new_val     = current_val;

            if (tr.wstrb[0]) new_val[7:0]   = tr.wdata[7:0];
            if (tr.wstrb[1]) new_val[15:8]  = tr.wdata[15:8];
            if (tr.wstrb[2]) new_val[23:16] = tr.wdata[23:16];
            if (tr.wstrb[3]) new_val[31:24] = tr.wdata[31:24];

            ref_mem[tr.addr] = new_val;
            `uvm_info(get_type_name(), $sformatf("SCOREBOARD WRITE: Addr=0x%08h WData=0x%08h (Ref=0x%08h)",
                      tr.addr, tr.wdata, new_val), UVM_HIGH)

        end else if (tr.kind == axi_transaction::AXI_READ) begin
            read_count++;
            if (ref_mem.exists(tr.addr)) begin
                exp_data = ref_mem[tr.addr];
                if (tr.rdata === exp_data) begin
                    match_count++;
                    `uvm_info(get_type_name(), $sformatf("[SCOREBOARD PASS] Addr=0x%08h RData=0x%08h Matches Expected",
                              tr.addr, tr.rdata), UVM_LOW)
                end else begin
                    mismatch_count++;
                    `uvm_error(get_type_name(), $sformatf("[SCOREBOARD MISMATCH] Addr=0x%08h Act=0x%08h Exp=0x%08h",
                               tr.addr, tr.rdata, exp_data))
                end
            end else begin
                `uvm_info(get_type_name(), $sformatf("SCOREBOARD READ Uninitialised Addr=0x%08h RData=0x%08h",
                          tr.addr, tr.rdata), UVM_MEDIUM)
            end
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(), "==========================================================", UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("SCOREBOARD SUMMARY: Writes=%0d Reads=%0d Matches=%0d Mismatches=%0d",
                  write_count, read_count, match_count, mismatch_count), UVM_LOW)
        if (mismatch_count == 0) begin
            `uvm_info(get_type_name(), "STATUS: ALL CHECKED TRANSACTIONS MATCHED SUCCESSFULLY", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("STATUS: %0d MISMATCHES DETECTED", mismatch_count))
        end
        `uvm_info(get_type_name(), "==========================================================", UVM_LOW)
    endfunction

endclass : soc_no_core_scoreboard

`endif // SOC_NO_CORE_SCOREBOARD_SV
