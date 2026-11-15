module instr_mem (
    input  logic [31:0] addr,
    output logic [31:0] rdata
);
    // Fixed array — XSim compatible, pre-initialized to NOP
    logic [31:0] mem [0:1023];

    assign rdata = mem[addr[11:2]];
endmodule
