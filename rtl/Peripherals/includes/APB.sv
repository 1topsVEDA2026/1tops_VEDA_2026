// Stub: APB interface (PULP-style)
// Matches PULP apb/APB interface definition.

interface APB #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32
)(
    input logic clk_i
);

    logic                     psel;
    logic                     penable;
    logic                     pwrite;
    logic [ADDR_WIDTH-1:0]    paddr;
    logic [2:0]               pprot;
    logic [DATA_WIDTH-1:0]    pwdata;
    logic [DATA_WIDTH/8-1:0]  pstrb;
    logic [DATA_WIDTH-1:0]    prdata;
    logic                     pready;
    logic                     pslverr;

    modport Slave  (input  psel, penable, pwrite, paddr, pprot, pwdata, pstrb,
                    output prdata, pready, pslverr);
    modport Master (output psel, penable, pwrite, paddr, pprot, pwdata, pstrb,
                    input  prdata, pready, pslverr);

endinterface : APB
