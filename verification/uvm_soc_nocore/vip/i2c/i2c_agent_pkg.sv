`timescale 1ns / 1ps
//==============================================================================
// i2c_agent_pkg.sv - I2C UVM VIP Package
//==============================================================================
package i2c_agent_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    class i2c_monitor extends uvm_monitor;
        `uvm_component_utils(i2c_monitor)
        virtual i2c_if vif;

        function new(string name = "i2c_monitor", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual i2c_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("I2C_MON", "Could not get i2c_if virtual interface")
            end
        endfunction
    endclass

    class i2c_agent extends uvm_agent;
        `uvm_component_utils(i2c_agent)
        i2c_monitor monitor;

        function new(string name = "i2c_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            monitor = i2c_monitor::type_id::create("monitor", this);
        endfunction
    endclass

endpackage
