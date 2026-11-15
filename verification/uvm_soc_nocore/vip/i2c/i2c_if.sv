`timescale 1ns / 1ps
//==============================================================================
// i2c_if.sv - I2C Interface
//==============================================================================
interface i2c_if (
    input logic clk,
    input logic rst_n
);
    wire sda;
    wire scl;
endinterface
