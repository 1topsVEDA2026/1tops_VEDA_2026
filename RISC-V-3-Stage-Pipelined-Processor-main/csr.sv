module csr_reg_file 
(
    input  logic [11:0] addr,
    input  logic        clk,
    input  logic [31:0] pc,
    input  logic [31:0] interrupt,
    input  logic [31:0] inst,
    input  logic [31:0] wdata,
    output logic [31:0] rdata,
    output logic [31:0] epc
);
    logic [31:0] mip;
    logic [31:0] mepc;
    logic [31:0] mie;
    logic [31:0] mstatus;


    // asynchronous read
    always_comb 
    begin
        case (addr)
        12'h304: rdata = mie;
        12'h300: rdata = mstatus;
        12'h344: rdata = mip;
        12'h341: rdata = mepc;
        endcase
    end

    // synchronus write
    always_ff @(posedge clk) 
    begin
        case (addr)
        12'h304: mie <= rdata;
        12'h300: mstatus <= rdata;
        12'h344: mip <= rdata;
        12'h341: mepc <= rdata;
        endcase
    end

endmodule