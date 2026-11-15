`timescale 1ns / 1ps
//==============================================================================
// irq_agent_pkg.sv - IRQ UVM VIP Package for Monitoring Interrupt Signals
//==============================================================================
package irq_agent_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Transaction
    class irq_transaction extends uvm_sequence_item;
        `uvm_object_utils(irq_transaction)
        logic irq_clint;
        logic irq_plic;

        function new(string name = "irq_transaction");
            super.new(name);
        endfunction

        function string convert2string();
            return $sformatf("IRQ Tx: CLINT=%0b PLIC=%0b", irq_clint, irq_plic);
        endfunction
    endclass

    // Monitor
    class irq_monitor extends uvm_monitor;
        `uvm_component_utils(irq_monitor)

        virtual irq_if vif;
        uvm_analysis_port #(irq_transaction) item_collected_port;

        function new(string name = "irq_monitor", uvm_component parent = null);
            super.new(name, parent);
            item_collected_port = new("item_collected_port", this);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual irq_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("IRQ_MON", "Could not get virtual interface handles for irq_if")
            end
        endfunction

        virtual task run_phase(uvm_phase phase);
            irq_transaction tr;
            logic prev_clint = 0, prev_plic = 0;

            forever begin
                @(posedge vif.clk);
                if (vif.irq_clint !== prev_clint || vif.irq_plic !== prev_plic) begin
                    tr = irq_transaction::type_id::create("tr");
                    tr.irq_clint = vif.irq_clint;
                    tr.irq_plic  = vif.irq_plic;
                    prev_clint   = vif.irq_clint;
                    prev_plic    = vif.irq_plic;
                    item_collected_port.write(tr);
                    `uvm_info("IRQ_MON", $sformatf("[INTERRUPT DETECTED] CLINT=%0b, PLIC=%0b", tr.irq_clint, tr.irq_plic), UVM_MEDIUM)
                end
            end
        endtask
    endclass

    // Agent
    class irq_agent extends uvm_agent;
        `uvm_component_utils(irq_agent)
        irq_monitor monitor;

        function new(string name = "irq_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            monitor = irq_monitor::type_id::create("monitor", this);
        endfunction
    endclass

endpackage
