`ifndef AXI_IF_SV
`define AXI_IF_SV
//==============================================================================
// axi_if — AXI4-Lite pin-level interface
//
// Matches the signal set used in your axi4lite_slave_mem.sv / _ro.sv models:
// 32-bit ADDR/DATA, 3-bit PROT, 2-bit RESP, no ID/LEN/BURST (AXI4-Lite has none).
// Provides three views:
//   MASTER  - drives AW/W/AR + BREADY/RREADY, samples READY/RESP/RDATA
//   SLAVE   - drives READY/RESP/RDATA, samples AW/W/AR + BREADY/RREADY
//   MONITOR - fully passive, samples everything
//==============================================================================

interface axi_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic clk,
    input logic rst_n
);

    // Write address channel
    logic [ADDR_WIDTH-1:0]     awaddr;
    logic [2:0]                awprot;
    logic                      awvalid;
    logic                      awready;

    // Write data channel
    logic [DATA_WIDTH-1:0]     wdata;
    logic [DATA_WIDTH/8-1:0]   wstrb;
    logic                      wvalid;
    logic                      wready;

    // Write response channel
    logic [1:0]                bresp;
    logic                      bvalid;
    logic                      bready;

    // Read address channel
    logic [ADDR_WIDTH-1:0]     araddr;
    logic [2:0]                arprot;
    logic                      arvalid;
    logic                      arready;

    // Read data channel
    logic [DATA_WIDTH-1:0]     rdata;
    logic [1:0]                rresp;
    logic                      rvalid;
    logic                      rready;

    // ---- MASTER view: TB drives AW/W/AR + BREADY/RREADY -----------------
    // NOTE: per your documented AXI4-Lite DUT-family quirk, AWREADY/WREADY/
    // ARREADY may be held high by default and BVALID/RVALID can self-clear
    // the same cycle if the ready is already asserted. The driver built on
    // top of this clocking block must wait for BVALID/RVALID before it
    // asserts BREADY/RREADY - do NOT pre-assert them in Phase 3.
    clocking master_cb @(posedge clk);
        output awaddr, awprot, awvalid;
        input  awready;
        output wdata, wstrb, wvalid;
        input  wready;
        input  bresp, bvalid;
        output bready;
        output araddr, arprot, arvalid;
        input  arready;
        input  rdata, rresp, rvalid;
        output rready;
    endclocking

    // ---- SLAVE view: TB acts as the peripheral side ----------------------
    clocking slave_cb @(posedge clk);
        input  awaddr, awprot, awvalid;
        output awready;
        input  wdata, wstrb, wvalid;
        output wready;
        output bresp, bvalid;
        input  bready;
        input  araddr, arprot, arvalid;
        output arready;
        output rdata, rresp, rvalid;
        input  rready;
    endclocking

    // ---- MONITOR view: fully passive -------------------------------------
    clocking mon_cb @(posedge clk);
        input awaddr, awprot, awvalid, awready;
        input wdata, wstrb, wvalid, wready;
        input bresp, bvalid, bready;
        input araddr, arprot, arvalid, arready;
        input rdata, rresp, rvalid, rready;
    endclocking

    modport MASTER  (clocking master_cb, input clk, rst_n);
    modport SLAVE   (clocking slave_cb,  input clk, rst_n);
    modport MONITOR (clocking mon_cb,    input clk, rst_n);

endinterface : axi_if

`endif
