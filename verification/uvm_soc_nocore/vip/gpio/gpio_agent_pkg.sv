`timescale 1ns / 1ps
//==============================================================================
// gpio_agent_pkg.sv - GPIO UVM VIP Package
//==============================================================================
package gpio_agent_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    class gpio_transaction extends uvm_sequence_item;
        `uvm_object_utils(gpio_transaction)
        rand logic [31:0] gpio_in;
        logic [31:0]      gpio_out;

        function new(string name = "gpio_transaction");
            super.new(name);
        endfunction
    endclass

    class gpio_monitor extends uvm_monitor;
        `uvm_component_utils(gpio_monitor)
        virtual gpio_if vif;
        uvm_analysis_port #(gpio_transaction) item_collected_port;

        function new(string name = "gpio_monitor", uvm_component parent = null);
            super.new(name, parent);
            item_collected_port = new("item_collected_port", this);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual gpio_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("GPIO_MON", "Could not get gpio_if virtual interface")
            end
        endfunction

        virtual task run_phase(uvm_phase phase);
            gpio_transaction tr;
            logic [31:0] prev_gpio_out = 0;

            forever begin
                @(posedge vif.clk);
                if (vif.gpio_out !== prev_gpio_out) begin
                    tr = gpio_transaction::type_id::create("tr");
                    tr.gpio_in  = vif.gpio_in;
                    tr.gpio_out = vif.gpio_out;
                    prev_gpio_out = vif.gpio_out;
                    item_collected_port.write(tr);
                    `uvm_info("GPIO_MON", $sformatf("[GPIO OUT CHANGED] GPIO_OUT=0x%08h", tr.gpio_out), UVM_HIGH)
                end
            end
        endtask
    endclass

    class gpio_agent extends uvm_agent;
        `uvm_component_utils(gpio_agent)
        gpio_monitor monitor;

        function new(string name = "gpio_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            monitor = gpio_monitor::type_id::create("monitor", this);
        endfunction
    endclass

endpackage
