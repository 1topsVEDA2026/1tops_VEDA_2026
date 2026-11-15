`timescale 1ns/1ps
// =============================================================================
// APB Interface Definition
// =============================================================================
// Reusable APB interface for all TOPS peripheral verification.
// Follows AMBA APB (APB3/APB4) protocol.
// Reference: ARM AMBA APB Protocol Specification v2.0

interface apb_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input logic clk,
    input logic rstn
);

    logic                    psel;
    logic                    penable;
    logic                    pwrite;
    logic [ADDR_WIDTH-1:0]   paddr;
    logic [DATA_WIDTH-1:0]   pwdata;
    logic [DATA_WIDTH/8-1:0] pstrb;
    logic [DATA_WIDTH-1:0]   prdata;
    logic                    pready;
    logic                    pslverr;

    // =========================================================================
    // Clocking Blocks
    // =========================================================================
    clocking master_cb @(posedge clk);
        default input #1 output #1;
        output psel, penable, pwrite, paddr, pwdata, pstrb;
        input  prdata, pready, pslverr;
    endclocking

    clocking monitor_cb @(posedge clk);
        default input #1;
        input psel, penable, pwrite, paddr, pwdata, pstrb;
        input prdata, pready, pslverr;
    endclocking

    // =========================================================================
    // Modports
    // =========================================================================
    modport master  (clocking master_cb,  input clk, rstn);
    modport slave   (input psel, penable, pwrite, paddr, pwdata, pstrb,
                     output prdata, pready, pslverr,
                     input clk, rstn);
    modport monitor (clocking monitor_cb, input clk, rstn);

endinterface : apb_if
