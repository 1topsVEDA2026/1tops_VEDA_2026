`timescale 1ns / 1ps
//==============================================================================
// soc_no_core_coverage.sv  -- FIXED VERSION v2
//
// UVM Coverage Model Subscriber for SoC Verification Without Core
// Fixes applied:
//  1. Address bins changed from 0x1000_XXXX / 0x8000_XXXX -> 0x0000_XXXX
//     (matches soc_no_core_dut.sv address decode: addr & 32'h0000_F000)
//  2. tr_item.data -> tr_item.wdata  (correct field name in axi_transaction)
//  3. Added field-level coverpoints for GPIO dir, UART char, Timer enable,
//     SPI CPOL/CPHA, SysCtrl mode, IRQ assert/deassert
//==============================================================================

`ifndef SOC_NO_CORE_COVERAGE_SV
`define SOC_NO_CORE_COVERAGE_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_agent_pkg::*;

class soc_no_core_coverage extends uvm_subscriber #(axi_transaction);

    `uvm_component_utils(soc_no_core_coverage)

    axi_transaction tr_item;

    // -------------------------------------------------------------------------
    // Primary covergroup: operation x address-space cross coverage
    // -------------------------------------------------------------------------
    covergroup cg_soc_axi;
        option.per_instance = 1;
        option.name = "cg_soc_axi_coverage";

        // READ or WRITE operation
        cp_op: coverpoint tr_item.kind {
            bins write_op = {axi_transaction::AXI_WRITE};
            bins read_op  = {axi_transaction::AXI_READ};
        }

        // Address-space bins FIXED to match DUT (addr & 32'h0000_F000 decode)
        cp_addr_space: coverpoint (tr_item.addr & 32'h0000_F000) {
            bins sram_mem    = {32'h0000_0000};  // 0x0000_0000 - 0x0000_0FFF
            bins clint_reg   = {32'h0000_1000};  // 0x0000_1000
            bins plic_reg    = {32'h0000_2000};  // 0x0000_2000
            bins gpio_reg    = {32'h0000_3000};  // 0x0000_3000
            bins uart_reg    = {32'h0000_4000};  // 0x0000_4000
            bins i2c_reg     = {32'h0000_5000};  // 0x0000_5000
            bins timer_reg   = {32'h0000_6000};  // 0x0000_6000
            bins spi_reg     = {32'h0000_7000};  // 0x0000_7000
            bins sysctrl_reg = {32'h0000_8000};  // 0x0000_8000
            bins unmapped    = default;
        }

        // Cross: every op type must hit every address space
        cross_op_addr: cross cp_op, cp_addr_space;

    endgroup

    // -------------------------------------------------------------------------
    // Field-level covergroup: data written to peripheral control registers
    // Uses tr_item.wdata (the correct field name in axi_transaction)
    // -------------------------------------------------------------------------
    covergroup cg_field_coverage;
        option.per_instance = 1;
        option.name = "cg_field_level_coverage";

        // GPIO direction register (0x0000_3000): bit-mask combinations
        cp_gpio_dir_mask: coverpoint tr_item.wdata[7:0] iff
            ((tr_item.addr & 32'h0000_F000) == 32'h0000_3000 &&
              tr_item.kind == axi_transaction::AXI_WRITE) {
            bins all_input    = {8'h00};
            bins all_output   = {8'hFF};
            bins mixed_low    = {[8'h01 : 8'h0F]};
            bins mixed_high   = {[8'hF0 : 8'hFE]};
            bins mixed_mid    = {[8'h10 : 8'hEF]};
        }

        // UART TX register (0x0000_4000): character value ranges
        cp_uart_char: coverpoint tr_item.wdata[7:0] iff
            ((tr_item.addr & 32'h0000_F000) == 32'h0000_4000 &&
              tr_item.kind == axi_transaction::AXI_WRITE) {
            bins ctrl_chars  = {[8'h00 : 8'h1F]};  // control chars
            bins printable   = {[8'h20 : 8'h7E]};  // printable ASCII
            bins extended    = {[8'h7F : 8'hFF]};  // extended
        }

        // Timer control register (0x0000_6000): bit7=enable, bit[6:0]=prescaler
        cp_timer_enable: coverpoint tr_item.wdata[7] iff
            ((tr_item.addr & 32'h0000_F000) == 32'h0000_6000 &&
              tr_item.kind == axi_transaction::AXI_WRITE) {
            bins timer_on  = {1'b1};
            bins timer_off = {1'b0};
        }

        cp_timer_prescaler: coverpoint tr_item.wdata[6:0] iff
            ((tr_item.addr & 32'h0000_F000) == 32'h0000_6000 &&
              tr_item.kind == axi_transaction::AXI_WRITE) {
            bins zero       = {7'h00};
            bins low_range  = {[7'h01 : 7'h1F]};
            bins mid_range  = {[7'h20 : 7'h5F]};
            bins high_range = {[7'h60 : 7'h7F]};
        }

        // SPI control register (0x0000_7000): bit1=CPOL, bit0=CPHA (4 modes)
        cp_spi_mode: coverpoint tr_item.wdata[1:0] iff
            ((tr_item.addr & 32'h0000_F000) == 32'h0000_7000 &&
              tr_item.kind == axi_transaction::AXI_WRITE) {
            bins mode0 = {2'b00};  // CPOL=0 CPHA=0
            bins mode1 = {2'b01};  // CPOL=0 CPHA=1
            bins mode2 = {2'b10};  // CPOL=1 CPHA=0
            bins mode3 = {2'b11};  // CPOL=1 CPHA=1
        }

        // SysCtrl register (0x0000_8000)
        cp_sysctrl_mode: coverpoint tr_item.wdata[7:0] iff
            ((tr_item.addr & 32'h0000_F000) == 32'h0000_8000 &&
              tr_item.kind == axi_transaction::AXI_WRITE) {
            bins boot_normal = {8'h01};
            bins boot_debug  = {8'h02};
            bins all_en      = {8'hFF};
            bins other       = default;
        }

        // CLINT / PLIC: assert then deassert sequence
        cp_irq_assert: coverpoint tr_item.wdata[0] iff
            ((tr_item.addr & 32'h0000_F000) inside {32'h0000_1000, 32'h0000_2000} &&
              tr_item.kind == axi_transaction::AXI_WRITE) {
            bins irq_set   = {1'b1};
            bins irq_clear = {1'b0};
        }

    endgroup

    function new(string name = "soc_no_core_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_soc_axi        = new();
        cg_field_coverage = new();
    endfunction

    virtual function void write(axi_transaction t);
        tr_item = t;
        cg_soc_axi.sample();
        cg_field_coverage.sample();
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(),
            $sformatf("FUNCTIONAL COVERAGE REPORT:\n  Address-Space Coverage : %0.2f%%\n  Field-Level Coverage   : %0.2f%%",
                cg_soc_axi.get_coverage(),
                cg_field_coverage.get_coverage()),
            UVM_LOW)
    endfunction

endclass : soc_no_core_coverage

`endif // SOC_NO_CORE_COVERAGE_SV
