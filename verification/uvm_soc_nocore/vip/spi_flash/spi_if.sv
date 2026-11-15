`timescale 1ns / 1ps
//==============================================================================
// spi_if.sv - SPI Master / Flash Model Interface
//==============================================================================
interface spi_if (
    input logic clk,
    input logic rst_n
);
    logic cs_n;
    logic sclk;
    logic mosi;
    logic miso;
endinterface
