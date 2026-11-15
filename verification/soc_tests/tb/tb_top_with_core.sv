`timescale 1ns / 1ps
// ============================================================================
// tb_top_with_core.sv — UVM Top-Level Testbench for SoC with RISC-V Core
// ============================================================================

import uvm_pkg::*;
`include "uvm_macros.svh"

import subsystem_pkg::*;

module tb_top_with_core;

    // Clock & Reset Generation
    logic HCLK;
    logic HRESETn;

    initial begin
        HCLK = 0;
        forever #5 HCLK = ~HCLK;
    end

    initial begin
        HRESETn = 0;
        #20 HRESETn = 1;
    end

    // Subsystem IO Signals
    logic [31:0] gpio_in, gpio_out, gpio_oe;
    wire  [31:0] gpio_dir = gpio_oe;
    logic        uart_rx, uart_tx;
    logic        spi_sclk, spi_csn, spi_mosi, spi_miso;
    logic        wdt_reset_o;

    initial begin
        gpio_in  = 32'hA5A5_5A5A;
        uart_rx  = 1'b1;
        spi_miso = 1'b0;
    end

    // APB Bus Interface Instance (Passive Monitoring Mode)
    apb_if apb_bus_if (
        .clk   (HCLK),
        .rstn  (HRESETn)
    );

    // Monitoring Wires from soc_top
    logic [31:0] mon_paddr, mon_pwdata, mon_prdata;
    logic        mon_pwrite, mon_psel, mon_penable, mon_pready, mon_pslverr;

    // Connect Passive Interface Wires
    assign apb_bus_if.paddr   = mon_paddr;
    assign apb_bus_if.pwdata  = mon_pwdata;
    assign apb_bus_if.prdata  = mon_prdata;
    assign apb_bus_if.pwrite  = mon_pwrite;
    assign apb_bus_if.psel    = mon_psel;
    assign apb_bus_if.penable = mon_penable;
    assign apb_bus_if.pready  = mon_pready;
    assign apb_bus_if.pslverr = mon_pslverr;

    // Instantiate SoC Top Module
    soc_top u_soc_top (
        .clk            (HCLK),
        .rst_n          (HRESETn),

        .gpio_in        (gpio_in),
        .gpio_out       (gpio_out),
        .gpio_oe        (gpio_oe),

        .uart_rx        (uart_rx),
        .uart_tx        (uart_tx),

        .spi_sclk       (spi_sclk),
        .spi_csn        (spi_csn),
        .spi_mosi       (spi_mosi),
        .spi_miso       (spi_miso),

        .wdt_reset_o    (wdt_reset_o),

        .mon_apb_paddr  (mon_paddr),
        .mon_apb_pwdata (mon_pwdata),
        .mon_apb_prdata (mon_prdata),
        .mon_apb_pwrite (mon_pwrite),
        .mon_apb_psel   (mon_psel),
        .mon_apb_penable(mon_penable),
        .mon_apb_pready (mon_pready),
        .mon_apb_pslverr(mon_pslverr)
    );

    // Initial Configuration & Firmware Loading
    initial begin
        // Pass APB interface to UVM Config DB
        uvm_config_db#(virtual apb_if)::set(null, "*", "vif", apb_bus_if);

        // Pre-load RISC-V Core Instruction Memory with Firmware Program
        // Program: ADDI, MUL/DIV testing, and GPIO/UART peripheral writes
        // Addr 0x00: ADDI x1, x0, 10
        // Addr 0x04: ADDI x2, x0, 20
        // Addr 0x08: MUL  x3, x1, x2  (M-extension multiplication -> x3 = 200)
        // Addr 0x0C: LUI  x4, 0x00002 (GPIO base)
        // Addr 0x10: SW   x3, 0x180(x4) (Write 200 to GPIO OUT register)
        u_soc_top.u_imem.mem[0] = 32'h00A00093; // ADDI x1, x0, 10
        u_soc_top.u_imem.mem[1] = 32'h01400113; // ADDI x2, x0, 20
        u_soc_top.u_imem.mem[2] = 32'h022081B3; // MUL  x3, x1, x2 (MDU test)
        u_soc_top.u_imem.mem[3] = 32'h00002237; // LUI  x4, 0x00002
        u_soc_top.u_imem.mem[4] = 32'h18322023; // SW   x3, 0x180(x4) (GPIO Write)
        u_soc_top.u_imem.mem[5] = 32'h00000013; // NOP
        u_soc_top.u_imem.mem[6] = 32'hFFDFF06F; // Spin loop

        // Start UVM Verification Framework
        run_test();
    end

endmodule
