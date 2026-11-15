`timescale 1ns / 1ps
//==============================================================================
// uart_if.sv - UART Interface
//==============================================================================
interface uart_if (
    input logic clk,
    input logic rst_n
);
    logic uart_tx;
    logic uart_rx;

    clocking cb @(posedge clk);
        default input #1step output #1step;
        input  uart_tx;
        output uart_rx;
    endclocking
endinterface
