`timescale 1ns / 1ps
//==============================================================================
// spi_flash_model.sv - SPI Flash Behavioral Model VIP & Package
//==============================================================================
package spi_agent_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    class spi_monitor extends uvm_monitor;
        `uvm_component_utils(spi_monitor)
        virtual spi_if vif;

        function new(string name = "spi_monitor", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual spi_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("SPI_MON", "Could not get spi_if virtual interface")
            end
        endfunction
    endclass

    class spi_agent extends uvm_agent;
        `uvm_component_utils(spi_agent)
        spi_monitor monitor;

        function new(string name = "spi_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            monitor = spi_monitor::type_id::create("monitor", this);
        endfunction
    endclass

endpackage
