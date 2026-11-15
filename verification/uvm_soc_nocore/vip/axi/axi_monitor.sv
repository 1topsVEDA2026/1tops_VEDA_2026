`timescale 1ns / 1ps
//==============================================================================
// axi_monitor.sv
//
// UVM Passive Monitor for AXI4-Lite Interface
// Observes AW, W, B, AR, and R channel handshakes and broadcasts sampled
// axi_transaction sequence items via an analysis port.
//==============================================================================

`ifndef AXI_MONITOR_SV
`define AXI_MONITOR_SV

class axi_monitor extends uvm_monitor;

    `uvm_component_utils(axi_monitor)

    // Virtual Interface Handle
    virtual axi_if vif;

    // UVM Analysis Port
    uvm_analysis_port #(axi_transaction) item_collected_port;

    // Constructor
    function new(string name = "axi_monitor", uvm_component parent = null);
        super.new(name, parent);
        item_collected_port = new("item_collected_port", this);
    endfunction

    // -------------------------------------------------------------------------
    // Build Phase: Retrieve Virtual Interface
    // -------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"})
        end
    endfunction

    // -------------------------------------------------------------------------
    // Run Phase: Concurrent Write and Read Monitoring Loops
    // -------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);

        wait (vif.rst_n === 1'b1);

        fork
            monitor_writes();
            monitor_reads();
        join
    endtask

    // -------------------------------------------------------------------------
    // Monitor Write Transactions
    // -------------------------------------------------------------------------
    protected task monitor_writes();
        axi_transaction tr;
        bit [31:0] captured_addr;
        bit [31:0] captured_data;
        bit [3:0]  captured_strb;

        forever begin
            tr = axi_transaction::type_id::create("tr");
            tr.op = AXI_WRITE;

            // Wait for AWVALID & AWREADY
            do begin
                @(vif.monitor_cb);
            end while (!(vif.monitor_cb.awvalid && vif.monitor_cb.awready));
            captured_addr = vif.monitor_cb.awaddr;
            tr.prot       = vif.monitor_cb.awprot;

            // Wait for WVALID & WREADY (may occur same or different cycle)
            do begin
                @(vif.monitor_cb);
            end while (!(vif.monitor_cb.wvalid && vif.monitor_cb.wready));
            captured_data = vif.monitor_cb.wdata;
            captured_strb = vif.monitor_cb.wstrb;

            // Wait for BVALID & BREADY
            do begin
                @(vif.monitor_cb);
            end while (!(vif.monitor_cb.bvalid && vif.monitor_cb.bready));

            tr.addr  = captured_addr;
            tr.data  = captured_data;
            tr.strb  = captured_strb;
            $cast(tr.resp, vif.monitor_cb.bresp);

            `uvm_info(get_type_name(), $sformatf("Monitored WRITE: %s", tr.convert2string()), UVM_MEDIUM)
            item_collected_port.write(tr);
        end
    endtask

    // -------------------------------------------------------------------------
    // Monitor Read Transactions
    // -------------------------------------------------------------------------
    protected task monitor_reads();
        axi_transaction tr;

        forever begin
            tr = axi_transaction::type_id::create("tr");
            tr.op = AXI_READ;

            // Wait for ARVALID & ARREADY
            do begin
                @(vif.monitor_cb);
            end while (!(vif.monitor_cb.arvalid && vif.monitor_cb.arready));
            tr.addr = vif.monitor_cb.araddr;
            tr.prot = vif.monitor_cb.arprot;

            // Wait for RVALID & RREADY
            do begin
                @(vif.monitor_cb);
            end while (!(vif.monitor_cb.rvalid && vif.monitor_cb.rready));

            tr.rdata = vif.monitor_cb.rdata;
            $cast(tr.resp, vif.monitor_cb.rresp);

            `uvm_info(get_type_name(), $sformatf("Monitored READ: %s", tr.convert2string()), UVM_MEDIUM)
            item_collected_port.write(tr);
        end
    endtask

endclass : axi_monitor

`endif // AXI_MONITOR_SV
