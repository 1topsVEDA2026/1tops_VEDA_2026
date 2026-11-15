`timescale 1ns / 1ps
//==============================================================================
// soc_no_core_env.sv
//
// UVM Environment for SoC Verification Without Core
//==============================================================================

`ifndef SOC_NO_CORE_ENV_SV
`define SOC_NO_CORE_ENV_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

import axi_agent_pkg::*;
import irq_agent_pkg::*;
import gpio_agent_pkg::*;
import uart_agent_pkg::*;
import i2c_agent_pkg::*;
import spi_agent_pkg::*;

`include "soc_no_core_scoreboard.sv"
`include "soc_no_core_coverage.sv"

class soc_no_core_env extends uvm_env;

    `uvm_component_utils(soc_no_core_env)

    // Components
    axi_agent               axi_agent_inst;
    irq_agent               irq_vif_agent;
    gpio_agent              gpio_vif_agent;
    uart_agent              uart_vif_agent;
    i2c_agent               i2c_vif_agent;
    spi_agent               spi_vif_agent;

    soc_no_core_scoreboard  scoreboard;
    soc_no_core_coverage    coverage;

    function new(string name = "soc_no_core_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        axi_agent_inst = axi_agent::type_id::create("axi_agent_inst", this);
        irq_vif_agent  = irq_agent::type_id::create("irq_vif_agent", this);
        gpio_vif_agent = gpio_agent::type_id::create("gpio_vif_agent", this);
        uart_vif_agent = uart_agent::type_id::create("uart_vif_agent", this);
        i2c_vif_agent  = i2c_agent::type_id::create("i2c_vif_agent", this);
        spi_vif_agent  = spi_agent::type_id::create("spi_vif_agent", this);

        scoreboard     = soc_no_core_scoreboard::type_id::create("scoreboard", this);
        coverage       = soc_no_core_coverage::type_id::create("coverage", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        axi_agent_inst.monitor.ap.connect(scoreboard.axi_analysis_export);
        axi_agent_inst.monitor.ap.connect(coverage.analysis_export);
    endfunction

endclass : soc_no_core_env

`endif // SOC_NO_CORE_ENV_SV
