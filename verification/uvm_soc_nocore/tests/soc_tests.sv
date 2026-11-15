`timescale 1ns / 1ps
//==============================================================================
// soc_tests.sv
//
// UVM Test Library for RISC-V SoC Verification Without Core
// Contains:
// - soc_base_test
// - soc_sanity_test          (Multi-location SRAM Write/Read test)
// - soc_peripheral_reg_test  (Peripherals CLINT, PLIC, GPIO, UART, I2C, Timer, SPI, SysCtrl)
// - soc_interrupt_test       (CLINT & PLIC Interrupt assertion and deassertion verification)
// - soc_full_system_test     (Comprehensive 20+ transaction stress test suite)
//==============================================================================

`ifndef SOC_TESTS_SV
`define SOC_TESTS_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

import axi_agent_pkg::*;
import irq_agent_pkg::*;
import gpio_agent_pkg::*;

`include "soc_no_core_env.sv"
`include "axi_sequences.sv"

// -----------------------------------------------------------------------------
// Base Test
// -----------------------------------------------------------------------------
class soc_base_test extends uvm_test;

    `uvm_component_utils(soc_base_test)

    soc_no_core_env env;

    function new(string name = "soc_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = soc_no_core_env::type_id::create("env", this);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

endclass : soc_base_test

// -----------------------------------------------------------------------------
// Sanity Test: Multi-Word Write/Read Check to SRAM Memory (0x0000_0000 - 0x0000_0030)
// -----------------------------------------------------------------------------
class soc_sanity_test extends soc_base_test;

    `uvm_component_utils(soc_sanity_test)

    function new(string name = "soc_sanity_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        axi_wr_rd_seq seq;
        bit [31:0] test_addrs[4] = '{32'h0000_0000, 32'h0000_0004, 32'h0000_0008, 32'h0000_000C};
        bit [31:0] test_datas[4] = '{32'h1234_5678, 32'hDEAD_BEEF, 32'hCAFE_BABE, 32'hA5A5_5A5A};

        phase.raise_objection(this, get_type_name());

        `uvm_info(get_type_name(), "==========================================", UVM_LOW)
        `uvm_info(get_type_name(), "=== Starting Extended soc_sanity_test ===", UVM_LOW)
        `uvm_info(get_type_name(), "==========================================", UVM_LOW)

        for (int i = 0; i < 4; i++) begin
            seq = axi_wr_rd_seq::type_id::create($sformatf("seq_sram_%0d", i));
            seq.addr = test_addrs[i];
            seq.data = test_datas[i];
            seq.start(env.axi_agent_inst.sequencer);
        end

        #100ns;
        `uvm_info(get_type_name(), "=== Ending Extended soc_sanity_test ===", UVM_LOW)
        phase.drop_objection(this, get_type_name());
    endtask

endclass : soc_sanity_test

// -----------------------------------------------------------------------------
// Peripheral Register Test: Access All Peripherals
// -----------------------------------------------------------------------------
class soc_peripheral_reg_test extends soc_base_test;

    `uvm_component_utils(soc_peripheral_reg_test)

    function new(string name = "soc_peripheral_reg_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        axi_wr_rd_seq seq;
        phase.raise_objection(this, get_type_name());

        `uvm_info(get_type_name(), "==================================================", UVM_LOW)
        `uvm_info(get_type_name(), "=== Starting Extended soc_peripheral_reg_test ===", UVM_LOW)
        `uvm_info(get_type_name(), "==================================================", UVM_LOW)

        // 1. CLINT Register
        seq = axi_wr_rd_seq::type_id::create("seq_clint");
        seq.addr = 32'h0000_1000; seq.data = 32'h0000_0001;
        seq.start(env.axi_agent_inst.sequencer);

        // 2. PLIC Register
        seq = axi_wr_rd_seq::type_id::create("seq_plic");
        seq.addr = 32'h0000_2000; seq.data = 32'h0000_0001;
        seq.start(env.axi_agent_inst.sequencer);

        // 3. GPIO Register
        seq = axi_wr_rd_seq::type_id::create("seq_gpio");
        seq.addr = 32'h0000_3000; seq.data = 32'h5A5A_A5A5;
        seq.start(env.axi_agent_inst.sequencer);

        // 4. UART Register
        seq = axi_wr_rd_seq::type_id::create("seq_uart");
        seq.addr = 32'h0000_4000; seq.data = 32'h0000_0041; // 'A'
        seq.start(env.axi_agent_inst.sequencer);

        // 5. I2C Register
        seq = axi_wr_rd_seq::type_id::create("seq_i2c");
        seq.addr = 32'h0000_5000; seq.data = 32'h0000_0080;
        seq.start(env.axi_agent_inst.sequencer);

        // 6. Timer Register
        seq = axi_wr_rd_seq::type_id::create("seq_timer");
        seq.addr = 32'h0000_6000; seq.data = 32'h0000_FFFF;
        seq.start(env.axi_agent_inst.sequencer);

        // 7. SPI Master Register
        seq = axi_wr_rd_seq::type_id::create("seq_spi");
        seq.addr = 32'h0000_7000; seq.data = 32'h1234_ABCD;
        seq.start(env.axi_agent_inst.sequencer);

        // 8. SysCtrl Register
        seq = axi_wr_rd_seq::type_id::create("seq_sysctrl");
        seq.addr = 32'h0000_8000; seq.data = 32'h0000_00FF;
        seq.start(env.axi_agent_inst.sequencer);

        #100ns;
        `uvm_info(get_type_name(), "=== Ending Extended soc_peripheral_reg_test ===", UVM_LOW)
        phase.drop_objection(this, get_type_name());
    endtask

endclass : soc_peripheral_reg_test

// -----------------------------------------------------------------------------
// Interrupt Test: CLINT and PLIC Assertion & Deassertion
// -----------------------------------------------------------------------------
class soc_interrupt_test extends soc_base_test;

    `uvm_component_utils(soc_interrupt_test)

    function new(string name = "soc_interrupt_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        axi_wr_rd_seq seq;
        phase.raise_objection(this, get_type_name());

        `uvm_info(get_type_name(), "==========================================", UVM_LOW)
        `uvm_info(get_type_name(), "=== Starting Extended soc_interrupt_test ===", UVM_LOW)
        `uvm_info(get_type_name(), "==========================================", UVM_LOW)

        // 1. Assert CLINT IRQ
        seq = axi_wr_rd_seq::type_id::create("seq_clint_on");
        seq.addr = 32'h0000_1000; seq.data = 32'h0000_0001;
        seq.start(env.axi_agent_inst.sequencer);

        // 2. Assert PLIC IRQ
        seq = axi_wr_rd_seq::type_id::create("seq_plic_on");
        seq.addr = 32'h0000_2000; seq.data = 32'h0000_0001;
        seq.start(env.axi_agent_inst.sequencer);

        // 3. Clear CLINT IRQ
        seq = axi_wr_rd_seq::type_id::create("seq_clint_off");
        seq.addr = 32'h0000_1000; seq.data = 32'h0000_0000;
        seq.start(env.axi_agent_inst.sequencer);

        // 4. Clear PLIC IRQ
        seq = axi_wr_rd_seq::type_id::create("seq_plic_off");
        seq.addr = 32'h0000_2000; seq.data = 32'h0000_0000;
        seq.start(env.axi_agent_inst.sequencer);

        #100ns;
        `uvm_info(get_type_name(), "=== Ending Extended soc_interrupt_test ===", UVM_LOW)
        phase.drop_objection(this, get_type_name());
    endtask

endclass : soc_interrupt_test

// -----------------------------------------------------------------------------
// Full System Test: Comprehensive Stress Test Suite (20+ Transactions)
// -----------------------------------------------------------------------------
class soc_full_system_test extends soc_base_test;

    `uvm_component_utils(soc_full_system_test)

    function new(string name = "soc_full_system_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        axi_wr_rd_seq seq;
        phase.raise_objection(this, get_type_name());

        `uvm_info(get_type_name(), "============================================", UVM_LOW)
        `uvm_info(get_type_name(), "=== Starting Extended soc_full_system_test ===", UVM_LOW)
        `uvm_info(get_type_name(), "============================================", UVM_LOW)

        // 1. SRAM Sweep (16 locations)
        for (int i = 0; i < 16; i++) begin
            seq = axi_wr_rd_seq::type_id::create($sformatf("seq_sys_sram_%0d", i));
            seq.addr = 32'h0000_0000 + (i * 4);
            seq.data = 32'h1000_0000 + (i * 32'h0101_0101);
            seq.start(env.axi_agent_inst.sequencer);
        end

        // 2. Peripheral Registers Sweep
        for (int p = 1; p <= 8; p++) begin
            seq = axi_wr_rd_seq::type_id::create($sformatf("seq_sys_periph_%0d", p));
            seq.addr = 32'h0000_0000 + (p * 32'h0000_1000);
            seq.data = 32'hBEEF_0000 + p;
            seq.start(env.axi_agent_inst.sequencer);
        end

        #100ns;
        `uvm_info(get_type_name(), "=== Ending Extended soc_full_system_test ===", UVM_LOW)
        phase.drop_objection(this, get_type_name());
    endtask

endclass : soc_full_system_test

`endif // SOC_TESTS_SV
