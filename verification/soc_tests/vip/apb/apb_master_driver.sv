// =============================================================================
// APB Master Driver
// =============================================================================
// Drives APB protocol (IDLE → SETUP → ACCESS) on the virtual interface.
// Implements full APB3 protocol with PREADY handshake.

class apb_master_driver extends uvm_driver #(apb_transaction);

    `uvm_component_utils(apb_master_driver)

    virtual apb_if vif;

    function new(string name = "apb_master_driver", uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "APB virtual interface not set for driver")
    endfunction

    task run_phase(uvm_phase phase);
        // Initialize bus to idle
        vif.master_cb.psel    <= 1'b0;
        vif.master_cb.penable <= 1'b0;
        vif.master_cb.pwrite  <= 1'b0;
        vif.master_cb.paddr   <= '0;
        vif.master_cb.pwdata  <= '0;
        vif.master_cb.pstrb   <= '0;

        forever begin
            apb_transaction txn;
            seq_item_port.get_next_item(txn);
            drive_transfer(txn);
            seq_item_port.item_done();
        end
    endtask

    task drive_transfer(apb_transaction txn);
        // SETUP phase
        @(posedge vif.clk);
        vif.master_cb.psel    <= 1'b1;
        vif.master_cb.penable <= 1'b0;
        vif.master_cb.pwrite  <= txn.write;
        vif.master_cb.paddr   <= txn.addr;
        vif.master_cb.pwdata  <= txn.data;
        vif.master_cb.pstrb   <= txn.strb;

        // ACCESS phase
        @(posedge vif.clk);
        vif.master_cb.penable <= 1'b1;

        // Wait for PREADY
        do begin
            @(posedge vif.clk);
        end while (!vif.master_cb.pready);

        // Capture response
        txn.rdata  = vif.master_cb.prdata;
        txn.slverr = vif.master_cb.pslverr;

        // Return to IDLE
        vif.master_cb.psel    <= 1'b0;
        vif.master_cb.penable <= 1'b0;

        `uvm_info("APB_DRV", $sformatf("%s addr=0x%08h data=0x%08h rdata=0x%08h",
            txn.write ? "WRITE" : "READ", txn.addr, txn.data, txn.rdata), UVM_HIGH)
    endtask

endclass : apb_master_driver
