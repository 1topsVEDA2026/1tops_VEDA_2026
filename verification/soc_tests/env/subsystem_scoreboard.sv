// =============================================================================
// Subsystem Scoreboard
// =============================================================================
// Receives APB transactions from the monitor and checks read-back values
// against expected data stored during write transactions for R/W registers.

class subsystem_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(subsystem_scoreboard)

    uvm_analysis_imp #(apb_transaction, subsystem_scoreboard) ap_imp;

    // Expected register values: addr → data
    bit [31:0] expected_regs [bit [31:0]];

    // Statistics
    int unsigned num_writes;
    int unsigned num_reads;
    int unsigned num_matches;
    int unsigned num_mismatches;

    function new(string name = "subsystem_scoreboard", uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap_imp = new("ap_imp", this);
    endfunction

    // Helper: returns 1 if address is a hardware Status / Read-Only / Shared / Action register
    function bit is_status_or_shared_reg(bit [31:0] addr);
        bit [31:0] periph_offset = addr & 32'h0000_0FFF;
        bit [31:0] periph_base   = addr & 32'hFFFF_F000;

        case (periph_base)
            32'h0000_0000: begin // UART
                if (periph_offset == 32'h00 || // RBR (Read) / THR (Write) shared buffer
                    periph_offset == 32'h08 || // IIR (Read) / FCR (Write) shared addr
                    periph_offset == 32'h14 || // LSR Read-Only status
                    periph_offset == 32'h18)   // MSR Read-Only status
                    return 1'b1;
            end
            32'h0000_1000: begin // SPI
                if (periph_offset == 32'h00 || // SPI_STATUS
                    periph_offset == 32'h18 || // SPI_TXFIFO
                    periph_offset == 32'h20)   // SPI_RXFIFO
                    return 1'b1;
            end
            32'h0000_2000: begin // GPIO
                if (periph_offset == 32'h00 ||  // GPIO_INFO
                    periph_offset == 32'h100 || // GPIO_IN0
                    periph_offset == 32'h140 || // GPIO_IN1
                    periph_offset == 32'h200 || // GPIO_SET0 (write-only pulse)
                    periph_offset == 32'h280 || // GPIO_CLR0 (write-only pulse)
                    periph_offset == 32'h300)   // GPIO_TOGL0 (write-only pulse)
                    return 1'b1;
            end
            32'h0000_3000: begin // TIMER
                if (periph_offset == 32'h08 || periph_offset == 32'h0C) // TMR_CNT_LO / HI live value
                    return 1'b1;
            end
            32'h0000_4000: begin // WATCHDOG
                if (periph_offset == 32'h04 || // WDT_SR / INTCLR
                    periph_offset == 32'h0C || // WDT_CNT / VALUE live counter
                    periph_offset == 32'h14)   // WDT_KEY write-only
                    return 1'b1;
            end
            32'h0000_5000: begin // PLIC
                if (periph_offset == 32'h80 || // PLIC pending status
                    periph_offset == 32'h204|| // PLIC claim/complete T0
                    periph_offset == 32'h304)  // PLIC claim/complete T1
                    return 1'b1;
            end
            32'h0000_6000: begin // CLINT
                return 1'b1; // CLINT timer and interrupt status registers
            end
            default: return 1'b0;
        endcase
        return 1'b0;
    endfunction

    // Called by analysis port when monitor captures a transaction
    function void write(apb_transaction txn);
        if (txn.write) begin
            expected_regs[txn.addr] = txn.data;
            num_writes++;
            `uvm_info("SCB", $sformatf("WRITE: addr=0x%08h data=0x%08h",
                txn.addr, txn.data), UVM_MEDIUM)
        end else begin
            num_reads++;
            if (expected_regs.exists(txn.addr)) begin
                if (is_status_or_shared_reg(txn.addr)) begin
                    // Hardware status / shared register read — log status readback
                    num_matches++;
                    `uvm_info("SCB", $sformatf("READ STATUS REG: addr=0x%08h RData=0x%08h",
                        txn.addr, txn.rdata), UVM_MEDIUM)
                end else if (txn.rdata === expected_regs[txn.addr]) begin
                    num_matches++;
                    `uvm_info("SCB", $sformatf("READ MATCH: addr=0x%08h data=0x%08h",
                        txn.addr, txn.rdata), UVM_MEDIUM)
                end else begin
                    num_mismatches++;
                    `uvm_error("SCB", $sformatf(
                        "READ MISMATCH: addr=0x%08h expected=0x%08h got=0x%08h",
                        txn.addr, expected_regs[txn.addr], txn.rdata))
                end
            end else begin
                num_matches++;
                `uvm_info("SCB", $sformatf("READ (initial reset read): addr=0x%08h data=0x%08h",
                    txn.addr, txn.rdata), UVM_MEDIUM)
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCB", "============================================", UVM_LOW)
        `uvm_info("SCB", "        SCOREBOARD SUMMARY", UVM_LOW)
        `uvm_info("SCB", "============================================", UVM_LOW)
        `uvm_info("SCB", $sformatf("  Writes:      %0d", num_writes), UVM_LOW)
        `uvm_info("SCB", $sformatf("  Reads:       %0d", num_reads), UVM_LOW)
        `uvm_info("SCB", $sformatf("  Matches:     %0d", num_matches), UVM_LOW)
        `uvm_info("SCB", $sformatf("  Mismatches:  %0d", num_mismatches), UVM_LOW)
        `uvm_info("SCB", "============================================", UVM_LOW)
        if (num_mismatches == 0)
            `uvm_info("SCB", "  RESULT: *** PASS ***", UVM_LOW)
        else
            `uvm_error("SCB", "  RESULT: *** FAIL ***")
    endfunction

endclass : subsystem_scoreboard
