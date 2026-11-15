`ifndef AXI_AGENT_PKG_SV
`define AXI_AGENT_PKG_SV
//==============================================================================
// axi_agent_pkg — UVM VIP Package for AXI Master Interface
//==============================================================================
package axi_agent_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    //--------------------------------------------------------------------------
    // axi_transaction
    //--------------------------------------------------------------------------
    class axi_transaction extends uvm_sequence_item;

        typedef enum bit { AXI_READ = 1'b0, AXI_WRITE = 1'b1 } axi_kind_e;

        rand axi_kind_e     kind;
        rand bit [31:0]     addr;
        rand bit [31:0]     wdata;
        rand bit [3:0]      wstrb;
        rand bit [2:0]      prot;

        bit [31:0]          rdata;
        bit [1:0]           bresp;
        bit [1:0]           rresp;

        `uvm_object_utils_begin(axi_transaction)
            `uvm_field_enum(axi_kind_e, kind, UVM_ALL_ON)
            `uvm_field_int(addr,              UVM_ALL_ON)
            `uvm_field_int(wdata,             UVM_ALL_ON)
            `uvm_field_int(wstrb,             UVM_ALL_ON)
            `uvm_field_int(prot,              UVM_ALL_ON)
            `uvm_field_int(rdata,             UVM_ALL_ON)
            `uvm_field_int(bresp,             UVM_ALL_ON)
            `uvm_field_int(rresp,             UVM_ALL_ON)
        `uvm_object_utils_end

        constraint c_word_aligned { addr[1:0] == 2'b00; }
        constraint c_in_range     { addr < 32'h0001_0000; }
        constraint c_default_strb {
            kind == AXI_WRITE -> wstrb == 4'b1111;
            kind == AXI_READ  -> wstrb == 4'b0000;
        }

        function new(string name = "axi_transaction");
            super.new(name);
        endfunction

        function string convert2string();
            if (kind == AXI_WRITE)
                return $sformatf("AXI-WR addr=0x%08h wdata=0x%08h bresp=%0b", addr, wdata, bresp);
            else
                return $sformatf("AXI-RD addr=0x%08h -> rdata=0x%08h rresp=%0b", addr, rdata, rresp);
        endfunction

    endclass : axi_transaction

    //--------------------------------------------------------------------------
    // axi_sequencer
    //--------------------------------------------------------------------------
    class axi_sequencer extends uvm_sequencer #(axi_transaction);
        `uvm_component_utils(axi_sequencer)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass : axi_sequencer

    //--------------------------------------------------------------------------
    // axi_driver
    //--------------------------------------------------------------------------
    class axi_driver extends uvm_driver #(axi_transaction);
        `uvm_component_utils(axi_driver)

        virtual axi_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
                `uvm_fatal("AXI_DRV", "virtual axi_if not set in config_db")
        endfunction

        task run_phase(uvm_phase phase);
            vif.master_cb.awvalid <= 1'b0;
            vif.master_cb.wvalid  <= 1'b0;
            vif.master_cb.bready  <= 1'b0;
            vif.master_cb.arvalid <= 1'b0;
            vif.master_cb.rready  <= 1'b0;
            @(posedge vif.rst_n);

            forever begin
                axi_transaction tr;
                seq_item_port.get_next_item(tr);
                if (tr.kind == axi_transaction::AXI_WRITE)
                    drive_write(tr);
                else
                    drive_read(tr);
                seq_item_port.item_done();
            end
        endtask

        task automatic drive_write(axi_transaction tr);
            vif.master_cb.awaddr  <= tr.addr;
            vif.master_cb.awprot  <= tr.prot;
            vif.master_cb.awvalid <= 1'b1;
            vif.master_cb.wdata   <= tr.wdata;
            vif.master_cb.wstrb   <= tr.wstrb;
            vif.master_cb.wvalid  <= 1'b1;

            do @(vif.master_cb); while (!(vif.master_cb.awready && vif.master_cb.wready));
            @(vif.master_cb);
            vif.master_cb.awvalid <= 1'b0;
            vif.master_cb.wvalid  <= 1'b0;

            do @(vif.master_cb); while (!vif.master_cb.bvalid);
            tr.bresp = vif.master_cb.bresp;
            vif.master_cb.bready <= 1'b1;
            @(vif.master_cb);
            vif.master_cb.bready <= 1'b0;
        endtask

        task automatic drive_read(axi_transaction tr);
            vif.master_cb.araddr  <= tr.addr;
            vif.master_cb.arprot  <= tr.prot;
            vif.master_cb.arvalid <= 1'b1;

            do @(vif.master_cb); while (!vif.master_cb.arready);
            @(vif.master_cb);
            vif.master_cb.arvalid <= 1'b0;

            do @(vif.master_cb); while (!vif.master_cb.rvalid);
            tr.rdata = vif.master_cb.rdata;
            tr.rresp = vif.master_cb.rresp;
            vif.master_cb.rready <= 1'b1;
            @(vif.master_cb);
            vif.master_cb.rready <= 1'b0;
        endtask

    endclass : axi_driver

    //--------------------------------------------------------------------------
    // axi_monitor — passive, captures write and completed read transactions
    //--------------------------------------------------------------------------
    class axi_monitor extends uvm_monitor;
        `uvm_component_utils(axi_monitor)

        virtual axi_if vif;
        uvm_analysis_port #(axi_transaction) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
                `uvm_fatal("AXI_MON", "virtual axi_if not set in config_db")
        endfunction

        task run_phase(uvm_phase phase);
            axi_transaction wr_tr;
            axi_transaction rd_tr;

            fork
                // Write Monitor
                forever begin
                    @(vif.mon_cb);
                    if (vif.mon_cb.awvalid && vif.mon_cb.awready &&
                        vif.mon_cb.wvalid  && vif.mon_cb.wready) begin
                        wr_tr = axi_transaction::type_id::create("wr_tr");
                        wr_tr.kind  = axi_transaction::AXI_WRITE;
                        wr_tr.addr  = vif.mon_cb.awaddr;
                        wr_tr.wdata = vif.mon_cb.wdata;
                        wr_tr.wstrb = vif.mon_cb.wstrb;
                        ap.write(wr_tr);
                    end
                end

                // Read Monitor (Waits for RVALID & RREADY to capture rdata)
                forever begin
                    @(vif.mon_cb);
                    if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
                        rd_tr = axi_transaction::type_id::create("rd_tr");
                        rd_tr.kind  = axi_transaction::AXI_READ;
                        rd_tr.addr  = vif.mon_cb.araddr;
                        do @(vif.mon_cb); while (!(vif.mon_cb.rvalid && vif.mon_cb.rready));
                        rd_tr.rdata = vif.mon_cb.rdata;
                        rd_tr.rresp = vif.mon_cb.rresp;
                        ap.write(rd_tr);
                    end
                end
            join
        endtask
    endclass : axi_monitor

    //--------------------------------------------------------------------------
    // axi_agent
    //--------------------------------------------------------------------------
    class axi_agent extends uvm_agent;
        `uvm_component_utils(axi_agent)

        axi_driver    driver;
        axi_sequencer sequencer;
        axi_monitor   monitor;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            monitor = axi_monitor::type_id::create("monitor", this);
            if (get_is_active() == UVM_ACTIVE) begin
                driver    = axi_driver::type_id::create("driver", this);
                sequencer = axi_sequencer::type_id::create("sequencer", this);
            end
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (get_is_active() == UVM_ACTIVE)
                driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction

    endclass : axi_agent

endpackage : axi_agent_pkg

`endif
