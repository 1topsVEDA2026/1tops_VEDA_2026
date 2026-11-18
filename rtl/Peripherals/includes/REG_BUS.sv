// Stub: REG_BUS interface
// Matches PULP register_interface REG_BUS definition.

interface REG_BUS #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32
)(
    input logic clk_i
);

    logic                     valid;
    logic [ADDR_WIDTH-1:0]    addr;
    logic                     write;
    logic [DATA_WIDTH/8-1:0]  wstrb;
    logic [DATA_WIDTH-1:0]    wdata;
    logic [DATA_WIDTH-1:0]    rdata;
    logic                     error;
    logic                     ready;

    modport in  (input  valid, addr, write, wstrb, wdata,
                 output rdata, error, ready);
    modport out (output valid, addr, write, wstrb, wdata,
                 input  rdata, error, ready);

endinterface : REG_BUS
