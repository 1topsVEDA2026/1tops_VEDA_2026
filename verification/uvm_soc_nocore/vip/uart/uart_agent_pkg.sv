`timescale 1ns / 1ps
//==============================================================================
// uart_agent_pkg.sv - UART UVM VIP Package
//==============================================================================
package uart_agent_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    class uart_transaction extends uvm_sequence_item;
        `uvm_object_utils(uart_transaction)
        logic [7:0] rx_data;
        logic [7:0] tx_data;

        function new(string name = "uart_transaction");
            super.new(name);
        endfunction
    endclass

    class uart_monitor extends uvm_monitor;
        `uvm_component_utils(uart_monitor)
        virtual uart_if vif;

        function new(string name = "uart_monitor", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("UART_MON", "Could not get uart_if virtual interface")
            end
        endfunction
    endclass

    class uart_agent extends uvm_agent;
        `uvm_component_utils(uart_agent)
        uart_monitor monitor;

        function new(string name = "uart_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            monitor = uart_monitor::type_id::create("monitor", this);
        endfunction
    endclass

endpackage
