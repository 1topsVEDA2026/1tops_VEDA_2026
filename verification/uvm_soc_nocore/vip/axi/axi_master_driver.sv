`timescale 1ns / 1ps
//==============================================================================
// axi_master_driver.sv
//
// UVM Master Driver for AXI4-Lite Interface
// Drives AXI4-Lite Write (AW/W/B) and Read (AR/R) transactions onto the
// SystemVerilog virtual interface using clocking blocks.
//==============================================================================

`ifndef AXI_MASTER_DRIVER_SV
`define AXI_MASTER_DRIVER_SV

class axi_master_driver extends uvm_driver #(axi_transaction);

    `uvm_component_utils(axi_master_driver)

    // Virtual Interface Handle
    virtual axi_if vif;

    // Constructor
    function new(string name = "axi_master_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // -------------------------------------------------------------------------
    // Build Phase: Retrieve Virtual Interface from Config DB
    // -------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"})
        end
    endfunction

    // -------------------------------------------------------------------------
    // Run Phase: Main Driver Loop
    // -------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);

        // Wait for Reset Release
        wait (vif.rst_n === 1'b0);
        vif.reset_signals();
        wait (vif.rst_n === 1'b1);
        @(vif.master_cb);

        forever begin
            seq_item_port.get_next_item(req);
            drive_transfer(req);
            seq_item_port.item_done();
        end
    endtask

    // -------------------------------------------------------------------------
    // Transfer Dispatcher
    // -------------------------------------------------------------------------
    virtual task drive_transfer(axi_transaction tr);
        // Inter-transaction delay
        if (tr.delay > 0) begin
            repeat (tr.delay) @(vif.master_cb);
        end

        if (tr.op == AXI_WRITE) begin
            drive_write(tr);
        end else begin
            drive_read(tr);
        end
    endtask

    // -------------------------------------------------------------------------
    // AXI Write Transaction Handshake (AW + W -> B)
    // -------------------------------------------------------------------------
    virtual task drive_write(axi_transaction tr);
        bit aw_done = 0;
        bit w_done  = 0;

        `uvm_info(get_type_name(), $sformatf("Driving WRITE to Addr=0x%08h Data=0x%08h Strb=%04b",
                  tr.addr, tr.data, tr.strb), UVM_HIGH)

        // Drive Address and Data channels
        vif.master_cb.awaddr  <= tr.addr;
        vif.master_cb.awprot  <= tr.prot;
        vif.master_cb.awvalid <= 1'b1;

        vif.master_cb.wdata   <= tr.data;
        vif.master_cb.wstrb   <= tr.strb;
        vif.master_cb.wvalid  <= 1'b1;

        // Handshake wait loop for AWREADY and WREADY
        fork
            begin : wait_awready
                while (!aw_done) begin
                    @(vif.master_cb);
                    if (vif.master_cb.awready && vif.master_cb.awvalid) begin
                        vif.master_cb.awvalid <= 1'b0;
                        aw_done = 1'b1;
                    end
                end
            end

            begin : wait_wready
                while (!w_done) begin
                    @(vif.master_cb);
                    if (vif.master_cb.wready && vif.master_cb.wvalid) begin
                        vif.master_cb.wvalid <= 1'b0;
                        w_done = 1'b1;
                    end
                end
            end
        join

        // Drive BREADY and wait for BVALID response
        vif.master_cb.bready <= 1'b1;
        do begin
            @(vif.master_cb);
        end while (!vif.master_cb.bvalid);

        // Sample Write Response
        $cast(tr.resp, vif.master_cb.bresp);
        vif.master_cb.bready <= 1'b0;

        `uvm_info(get_type_name(), $sformatf("WRITE Complete: Addr=0x%08h Resp=%s",
                  tr.addr, tr.resp.name()), UVM_HIGH)
    endtask

    // -------------------------------------------------------------------------
    // AXI Read Transaction Handshake (AR -> R)
    // -------------------------------------------------------------------------
    virtual task drive_read(axi_transaction tr);
        `uvm_info(get_type_name(), $sformatf("Driving READ to Addr=0x%08h", tr.addr), UVM_HIGH)

        // Drive Read Address Channel
        vif.master_cb.araddr  <= tr.addr;
        vif.master_cb.arprot  <= tr.prot;
        vif.master_cb.arvalid <= 1'b1;

        do begin
            @(vif.master_cb);
        end while (!vif.master_cb.arready);

        vif.master_cb.arvalid <= 1'b0;

        // Drive RREADY and wait for RVALID
        vif.master_cb.rready <= 1'b1;
        do begin
            @(vif.master_cb);
        end while (!vif.master_cb.rvalid);

        // Sample Read Data and Response
        tr.rdata = vif.master_cb.rdata;
        $cast(tr.resp, vif.master_cb.rresp);
        vif.master_cb.rready <= 1'b0;

        `uvm_info(get_type_name(), $sformatf("READ Complete: Addr=0x%08h RData=0x%08h Resp=%s",
                  tr.addr, tr.rdata, tr.resp.name()), UVM_HIGH)
    endtask

endclass : axi_master_driver

`endif // AXI_MASTER_DRIVER_SV
