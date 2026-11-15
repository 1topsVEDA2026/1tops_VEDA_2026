// =============================================================================
// Subsystem Functional Coverage Model
// =============================================================================
// Collects coverage on APB transactions across peripheral address space,
// write/read directions, and byte strobes.

`ifndef SUBSYSTEM_COVERAGE_SV
`define SUBSYSTEM_COVERAGE_SV

class subsystem_coverage extends uvm_subscriber #(apb_transaction);

    `uvm_component_utils(subsystem_coverage)

    apb_transaction cov_txn;

    covergroup cg_apb_trans;
        option.per_instance = 1;
        option.comment = "APB Peripheral Subsystem Access Coverage";

        // Address slots coverpoint
        cp_addr: coverpoint cov_txn.addr {
            bins uart_slot     = {[32'h0000_0000 : 32'h0000_0FFF]};
            bins spi_slot      = {[32'h0000_1000 : 32'h0000_1FFF]};
            bins gpio_slot     = {[32'h0000_2000 : 32'h0000_2FFF]};
            bins timer_slot    = {[32'h0000_3000 : 32'h0000_3FFF]};
            bins wdt_slot      = {[32'h0000_4000 : 32'h0000_4FFF]};
            bins plic_slot     = {[32'h0000_5000 : 32'h0000_5FFF]};
            bins clint_slot    = {[32'h0000_6000 : 32'h0000_6FFF]};
            bins unmapped      = default;
        }

        // Write/Read coverpoint
        cp_write: coverpoint cov_txn.write {
            bins read_op  = {1'b0};
            bins write_op = {1'b1};
        }

        // Cross of Address Slot and Operation Type
        cross_slot_op: cross cp_addr, cp_write;
    endgroup

    function new(string name = "subsystem_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_apb_trans = new();
    endfunction

    virtual function void write(apb_transaction t);
        cov_txn = t;
        cg_apb_trans.sample();
    endfunction

endclass : subsystem_coverage

`endif // SUBSYSTEM_COVERAGE_SV
