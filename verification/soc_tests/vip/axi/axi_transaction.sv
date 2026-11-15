`timescale 1ns / 1ps
//==============================================================================
// axi_transaction.sv
//
// UVM Sequence Item for AXI4-Lite Master Agent
// Defines transaction fields, constraints, factory registration, and
// utility methods (do_copy, do_compare, convert2string).
//==============================================================================

`ifndef AXI_TRANSACTION_SV
`define AXI_TRANSACTION_SV

typedef enum bit {
    AXI_READ  = 1'b0,
    AXI_WRITE = 1'b1
} axi_op_e;

typedef enum bit [1:0] {
    AXI_RESP_OKAY   = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11
} axi_resp_e;

class axi_transaction extends uvm_sequence_item;

    // -------------------------------------------------------------------------
    // Randomized Request Fields
    // -------------------------------------------------------------------------
    rand bit [31:0]   addr;
    rand bit [31:0]   data;
    rand bit [3:0]    strb;
    rand axi_op_e     op;
    rand bit [2:0]    prot;
    rand int unsigned delay; // Inter-transaction delay in clock cycles

    // -------------------------------------------------------------------------
    // Response Fields (populated by driver / monitor)
    // -------------------------------------------------------------------------
    bit [31:0]        rdata;
    axi_resp_e        resp;

    // -------------------------------------------------------------------------
    // UVM Factory Registration
    // -------------------------------------------------------------------------
    `uvm_object_utils_begin(axi_transaction)
        `uvm_field_enum(axi_op_e, op, UVM_ALL_ON)
        `uvm_field_int(addr, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(data, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(strb, UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(prot, UVM_ALL_ON)
        `uvm_field_int(delay, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(rdata, UVM_ALL_ON | UVM_HEX)
        `uvm_field_enum(axi_resp_e, resp, UVM_ALL_ON)
    `uvm_object_utils_end

    // -------------------------------------------------------------------------
    // Constraints
    // -------------------------------------------------------------------------
    // 32-bit word alignment constraint
    constraint c_addr_align {
        addr[1:0] == 2'b00;
    }

    // Write strobe constraint (at least 1 byte enabled for writes)
    constraint c_strb {
        if (op == AXI_WRITE) {
            strb != 4'b0000;
        } else {
            strb == 4'b1111;
        }
    }

    // Default protection (normal, non-secure, data access)
    constraint c_prot {
        prot == 3'b000;
    }

    // Bounded inter-transaction delay constraint
    constraint c_delay {
        delay inside {[0:10]};
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------
    function new(string name = "axi_transaction");
        super.new(name);
    endfunction

    // -------------------------------------------------------------------------
    // Virtual Methods
    // -------------------------------------------------------------------------
    virtual function string convert2string();
        if (op == AXI_WRITE) begin
            return $sformatf("AXI_WRITE  Addr=0x%08h Data=0x%08h Strb=%04b Resp=%s Delay=%0d",
                             addr, data, strb, resp.name(), delay);
        end else begin
            return $sformatf("AXI_READ   Addr=0x%08h RData=0x%08h Resp=%s Delay=%0d",
                             addr, rdata, resp.name(), delay);
        end
    endfunction

    virtual function void do_copy(uvm_object rhs);
        axi_transaction rhs_tx;
        if (!$cast(rhs_tx, rhs)) begin
            `uvm_fatal("AXI_TX_COPY", "Cast failed in do_copy()")
            return;
        end
        super.do_copy(rhs);
        this.addr  = rhs_tx.addr;
        this.data  = rhs_tx.data;
        this.strb  = rhs_tx.strb;
        this.op    = rhs_tx.op;
        this.prot  = rhs_tx.prot;
        this.delay = rhs_tx.delay;
        this.rdata = rhs_tx.rdata;
        this.resp  = rhs_tx.resp;
    endfunction

    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        axi_transaction rhs_tx;
        if (!$cast(rhs_tx, rhs)) return 0;
        return (super.do_compare(rhs, comparer) &&
                (this.op == rhs_tx.op) &&
                (this.addr == rhs_tx.addr) &&
                (this.op == AXI_WRITE ? (this.data == rhs_tx.data) : (this.rdata == rhs_tx.rdata)) &&
                (this.resp == rhs_tx.resp));
    endfunction

endclass : axi_transaction

`endif // AXI_TRANSACTION_SV
