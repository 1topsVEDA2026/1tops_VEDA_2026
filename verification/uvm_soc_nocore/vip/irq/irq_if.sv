`timescale 1ns / 1ps
//==============================================================================
// irq_if.sv - IRQ Interface for CLINT and PLIC Interrupt Monitoring
//==============================================================================
interface irq_if (
    input logic clk,
    input logic rst_n
);
    logic irq_clint;
    logic irq_plic;

    clocking cb @(posedge clk);
        default input #1step output #1step;
        input irq_clint;
        input irq_plic;
    endclocking
endinterface
