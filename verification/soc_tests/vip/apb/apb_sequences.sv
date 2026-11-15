// =============================================================================
// APB Base Sequences
// =============================================================================
// Reusable base sequences for APB register read/write operations.

// ---- Single APB Write ----
class apb_write_seq extends uvm_sequence #(apb_transaction);

    `uvm_object_utils(apb_write_seq)

    bit [31:0] wr_addr;
    bit [31:0] wr_data;

    function new(string name = "apb_write_seq");
        super.new(name);
    endfunction

    task body();
        apb_transaction txn;
        txn = apb_transaction::type_id::create("wr_txn");
        start_item(txn);
        txn.addr  = wr_addr;
        txn.data  = wr_data;
        txn.write = 1'b1;
        txn.strb  = 4'hF;
        finish_item(txn);
    endtask

endclass : apb_write_seq

// ---- Single APB Read ----
class apb_read_seq extends uvm_sequence #(apb_transaction);

    `uvm_object_utils(apb_read_seq)

    bit [31:0] rd_addr;
    bit [31:0] rd_data;  // Output: captured read data

    function new(string name = "apb_read_seq");
        super.new(name);
    endfunction

    task body();
        apb_transaction txn;
        txn = apb_transaction::type_id::create("rd_txn");
        start_item(txn);
        txn.addr  = rd_addr;
        txn.write = 1'b0;
        finish_item(txn);
        rd_data = txn.rdata;
    endtask

endclass : apb_read_seq

// ---- Register Write-Read-Back Sequence ----
class apb_wr_rd_seq extends uvm_sequence #(apb_transaction);

    `uvm_object_utils(apb_wr_rd_seq)

    bit [31:0] addr;
    bit [31:0] data;
    bit [31:0] rdata;

    function new(string name = "apb_wr_rd_seq");
        super.new(name);
    endfunction

    task body();
        apb_write_seq wr;
        apb_read_seq  rd;

        // Write
        wr = apb_write_seq::type_id::create("wr");
        wr.wr_addr = addr;
        wr.wr_data = data;
        wr.start(m_sequencer);

        // Read back
        rd = apb_read_seq::type_id::create("rd");
        rd.rd_addr = addr;
        rd.start(m_sequencer);
        rdata = rd.rd_data;

        if (rdata !== data)
            `uvm_error("WR_RD_SEQ", $sformatf(
                "Mismatch at addr=0x%08h: wrote=0x%08h, read=0x%08h",
                addr, data, rdata))
        else
            `uvm_info("WR_RD_SEQ", $sformatf(
                "Match at addr=0x%08h: data=0x%08h", addr, data), UVM_MEDIUM)
    endtask

endclass : apb_wr_rd_seq
