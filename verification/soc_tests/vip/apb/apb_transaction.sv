// =============================================================================
// APB Transaction (Sequence Item)
// =============================================================================
// UVM sequence item for APB read/write transactions.

class apb_transaction extends uvm_sequence_item;

    // Transaction fields
    rand bit [31:0] addr;
    rand bit [31:0] data;
    rand bit        write;   // 1=write, 0=read
    rand bit [3:0]  strb;    // Byte strobe

    // Response (filled by driver/monitor)
    bit [31:0] rdata;
    bit        slverr;

    `uvm_object_utils_begin(apb_transaction)
        `uvm_field_int(addr,   UVM_ALL_ON)
        `uvm_field_int(data,   UVM_ALL_ON)
        `uvm_field_int(write,  UVM_ALL_ON)
        `uvm_field_int(strb,   UVM_ALL_ON)
        `uvm_field_int(rdata,  UVM_ALL_ON)
        `uvm_field_int(slverr, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "apb_transaction");
        super.new(name);
        strb = 4'hF;  // Full word strobe by default
    endfunction

    // Constraint: address aligned to 4 bytes
    constraint addr_aligned_c {
        addr[1:0] == 2'b00;
    }

endclass : apb_transaction
