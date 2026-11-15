`timescale 1ns/1ps
//==============================================================================
// tb_phase2_test.sv — Step 1 (SRAM Read/Write Sanity) harness + test
//
// Compile alongside axi4lite_slave_mem.sv (your existing DUT model).
// NOTE: this DUT has no address decode (awaddr>>2 direct into its array),
// so the sanity write/read below uses 0x0000_0100, not 0x8000_0000 - see
// the constraint comment in axi_agent_pkg.sv for why.
//==============================================================================

import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_agent_pkg::*;

//------------------------------------------------------------------------------
// soc_sram_sanity_seq — one write, one read-back, self-checked in the test
//------------------------------------------------------------------------------
class soc_sram_sanity_seq extends uvm_sequence #(axi_transaction);
    `uvm_object_utils(soc_sram_sanity_seq)

    localparam bit [31:0] TEST_ADDR  = 32'h0000_0100;
    localparam bit [31:0] TEST_WDATA = 32'hDEAD_BEEF;

    axi_transaction wr_tr, rd_tr;

    function new(string name = "soc_sram_sanity_seq");
        super.new(name);
    endfunction

    task body();
        wr_tr = axi_transaction::type_id::create("wr_tr");
        start_item(wr_tr);
        if (!wr_tr.randomize() with { kind == axi_transaction::AXI_WRITE;
                                      addr == TEST_ADDR;
                                      wdata == TEST_WDATA; })
            `uvm_fatal("SEQ", "write randomize failed")
        finish_item(wr_tr);

        if (wr_tr.bresp !== 2'b00)
            `uvm_error("SEQ", $sformatf("write BRESP was not OKAY: %0b", wr_tr.bresp))
        else
            `uvm_info("SEQ", $sformatf("write OK: %s", wr_tr.convert2string()), UVM_LOW)

        rd_tr = axi_transaction::type_id::create("rd_tr");
        start_item(rd_tr);
        if (!rd_tr.randomize() with { kind == axi_transaction::AXI_READ;
                                      addr == TEST_ADDR; })
            `uvm_fatal("SEQ", "read randomize failed")
        finish_item(rd_tr);

        if (rd_tr.rresp !== 2'b00)
            `uvm_error("SEQ", $sformatf("read RRESP was not OKAY: %0b", rd_tr.rresp))
        else if (rd_tr.rdata !== TEST_WDATA)
            `uvm_error("SEQ", $sformatf("READBACK MISMATCH: wrote 0x%08h, read 0x%08h",
                                        TEST_WDATA, rd_tr.rdata))
        else
            `uvm_info("SEQ", $sformatf("READBACK MATCH: %s", rd_tr.convert2string()), UVM_LOW)
    endtask
endclass : soc_sram_sanity_seq

//------------------------------------------------------------------------------
// soc_sram_test — builds one active axi_agent and runs the sanity sequence
//------------------------------------------------------------------------------
class soc_sram_test extends uvm_test;
    `uvm_component_utils(soc_sram_test)

    axi_agent agent;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = axi_agent::type_id::create("agent", this);
        agent.set_is_active(UVM_ACTIVE);
    endfunction

    task run_phase(uvm_phase phase);
        soc_sram_sanity_seq seq;
        phase.raise_objection(this);
        seq = soc_sram_sanity_seq::type_id::create("seq");
        seq.start(agent.sequencer);
        phase.drop_objection(this);
    endtask
endclass : soc_sram_test

//------------------------------------------------------------------------------
// tb_phase2_test — top-level harness: clock, reset, interface, DUT
//------------------------------------------------------------------------------
module tb_phase2_test;

    bit clk;
    bit rst_n;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
    end

    axi_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) intf (.clk(clk), .rst_n(rst_n));

    // DUT: your existing axi4lite_slave_mem.sv model
    axi4lite_slave_mem #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32),
        .MEM_DEPTH_WORDS(16384),
        .MEM_INIT_FILE("")
    ) u_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axi_awaddr  (intf.awaddr),
        .s_axi_awprot  (intf.awprot),
        .s_axi_awvalid (intf.awvalid),
        .s_axi_awready (intf.awready),
        .s_axi_wdata   (intf.wdata),
        .s_axi_wstrb   (intf.wstrb),
        .s_axi_wvalid  (intf.wvalid),
        .s_axi_wready  (intf.wready),
        .s_axi_bresp   (intf.bresp),
        .s_axi_bvalid  (intf.bvalid),
        .s_axi_bready  (intf.bready),
        .s_axi_araddr  (intf.araddr),
        .s_axi_arprot  (intf.arprot),
        .s_axi_arvalid (intf.arvalid),
        .s_axi_arready (intf.arready),
        .s_axi_rdata   (intf.rdata),
        .s_axi_rresp   (intf.rresp),
        .s_axi_rvalid  (intf.rvalid),
        .s_axi_rready  (intf.rready)
    );

    initial begin
        uvm_config_db#(virtual axi_if)::set(null, "*", "vif", intf);
        $dumpfile("tb_phase2_test.vcd");
        $dumpvars(0, tb_phase2_test);
        run_test();
    end

endmodule : tb_phase2_test
