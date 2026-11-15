`timescale 1ns / 1ps
//==============================================================================
// gpio_if.sv - GPIO Interface
//==============================================================================
interface gpio_if (
    input logic clk,
    input logic rst_n
);
    logic [31:0] gpio_in;
    logic [31:0] gpio_out;

    clocking cb @(posedge clk);
        default input #1step output #1step;
        output gpio_in;
        input  gpio_out;
    endclocking
endinterface
