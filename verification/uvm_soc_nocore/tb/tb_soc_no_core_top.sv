`timescale 1ns / 1ps
//==============================================================================
// tb_soc_no_core_top.sv
//
// Top-Level Testbench for RISC-V SoC Verification Without Core
// Instantiates:
// - Clock and Reset Generator
// - Interface Instances: AXI, IRQ, GPIO, UART, I2C, SPI
// - DUT Instance: soc_no_core_dut
// - UVM config_db setup & run_test() call
//==============================================================================

import uvm_pkg::*;
`include "uvm_macros.svh"

import axi_agent_pkg::*;
import irq_agent_pkg::*;
import gpio_agent_pkg::*;
import uart_agent_pkg::*;
import i2c_agent_pkg::*;
import spi_agent_pkg::*;

`include "soc_tests.sv"

module tb_soc_no_core_top;

    // -------------------------------------------------------------------------
    // Clock and Reset Generator
    // -------------------------------------------------------------------------
    localparam int CLK_PERIOD_NS = 10;
    logic clk = 0;
    logic rst_n = 0;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    initial begin
        rst_n = 1'b0;
        #(CLK_PERIOD_NS * 5);
        rst_n = 1'b1;
        $display("[%0tns] Top TB: System Reset Released", $time);
    end

    // -------------------------------------------------------------------------
    // Interface Instances
    // -------------------------------------------------------------------------
    axi_if  axi_bus ( .clk(clk), .rst_n(rst_n) );
    irq_if  irq_bus ( .clk(clk), .rst_n(rst_n) );
    gpio_if gpio_bus( .clk(clk), .rst_n(rst_n) );
    uart_if uart_bus( .clk(clk), .rst_n(rst_n) );
    i2c_if  i2c_bus ( .clk(clk), .rst_n(rst_n) );
    spi_if  spi_bus ( .clk(clk), .rst_n(rst_n) );

    // -------------------------------------------------------------------------
    // DUT Instantiation: SoC - NoCore Top
    // -------------------------------------------------------------------------
    soc_no_core_dut #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) u_soc_dut (
        .clk          (clk),
        .rst_n        (rst_n),

        // AXI Slave Interface
        .s_axi_awaddr (axi_bus.awaddr),
        .s_axi_awprot (axi_bus.awprot),
        .s_axi_awvalid(axi_bus.awvalid),
        .s_axi_awready(axi_bus.awready),

        .s_axi_wdata  (axi_bus.wdata),
        .s_axi_wstrb  (axi_bus.wstrb),
        .s_axi_wvalid (axi_bus.wvalid),
        .s_axi_wready (axi_bus.wready),

        .s_axi_bresp  (axi_bus.bresp),
        .s_axi_bvalid (axi_bus.bvalid),
        .s_axi_bready (axi_bus.bready),

        .s_axi_araddr (axi_bus.araddr),
        .s_axi_arprot (axi_bus.arprot),
        .s_axi_arvalid(axi_bus.arvalid),
        .s_axi_arready(axi_bus.arready),

        .s_axi_rdata  (axi_bus.rdata),
        .s_axi_rresp  (axi_bus.rresp),
        .s_axi_rvalid (axi_bus.rvalid),
        .s_axi_rready (axi_bus.rready),

        // Peripheral I/O Connections
        .irq_clint    (irq_bus.irq_clint),
        .irq_plic     (irq_bus.irq_plic),
        .gpio_in      (gpio_bus.gpio_in),
        .gpio_out     (gpio_bus.gpio_out),
        .uart_tx      (uart_bus.uart_tx),
        .uart_rx      (uart_bus.uart_rx),
        .i2c_sda      (i2c_bus.sda),
        .i2c_scl      (i2c_bus.scl),
        .spi_cs       (spi_bus.cs_n),
        .spi_sclk     (spi_bus.sclk),
        .spi_mosi     (spi_bus.mosi),
        .spi_miso     (spi_bus.miso)
    );

    // -------------------------------------------------------------------------
    // UVM Config DB Setup and Test Launcher
    // -------------------------------------------------------------------------
    initial begin
        // Pass virtual interface handles to UVM components
        uvm_config_db#(virtual axi_if)::set(null, "*", "vif", axi_bus);
        uvm_config_db#(virtual irq_if)::set(null, "*.irq_vif_agent*", "vif", irq_bus);
        uvm_config_db#(virtual gpio_if)::set(null, "*.gpio_vif_agent*", "vif", gpio_bus);
        uvm_config_db#(virtual uart_if)::set(null, "*.uart_vif_agent*", "vif", uart_bus);
        uvm_config_db#(virtual i2c_if)::set(null, "*.i2c_vif_agent*", "vif", i2c_bus);
        uvm_config_db#(virtual spi_if)::set(null, "*.spi_vif_agent*", "vif", spi_bus);

        // Run default UVM test (can be overridden via +UVM_TESTNAME=<test_name>)
        run_test("soc_sanity_test");
    end

    // -------------------------------------------------------------------------
    // Waveform Dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_soc_no_core_top.vcd");
        $dumpvars(0, tb_soc_no_core_top);
    end

endmodule
