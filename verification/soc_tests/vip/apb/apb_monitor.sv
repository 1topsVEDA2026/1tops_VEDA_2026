// =============================================================================
// APB Monitor
// =============================================================================
// Passive monitor that observes APB transactions on the bus and broadcasts
// them via analysis port to scoreboard/coverage collectors.

class apb_monitor extends uvm_monitor;

    `uvm_component_utils(apb_monitor)

    virtual apb_if vif;

    uvm_analysis_port #(apb_transaction) ap;

    function new(string name = "apb_monitor", uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "APB virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            apb_transaction txn;
            collect_transfer(txn);
            ap.write(txn);
        end
    endtask

    task collect_transfer(output apb_transaction txn);
        txn = apb_transaction::type_id::create("mon_txn");

        // Wait for SETUP phase (PSEL=1, PENABLE=0)
        @(posedge vif.clk);
        wait(vif.monitor_cb.psel && !vif.monitor_cb.penable);

        txn.addr  = vif.monitor_cb.paddr;
        txn.write = vif.monitor_cb.pwrite;
        txn.data  = vif.monitor_cb.pwdata;
        txn.strb  = vif.monitor_cb.pstrb;

        // Wait for ACCESS phase completion (PENABLE=1 && PREADY=1)
        @(posedge vif.clk);
        while (!(vif.monitor_cb.penable && vif.monitor_cb.pready)) begin
            @(posedge vif.clk);
        end

        txn.rdata  = vif.monitor_cb.prdata;
        txn.slverr = vif.monitor_cb.pslverr;

        `uvm_info("APB_MON", $sformatf("%s addr=0x%08h data=0x%08h rdata=0x%08h",
            txn.write ? "WRITE" : "READ", txn.addr, txn.data, txn.rdata), UVM_HIGH)
    endtask

endclass : apb_monitor
