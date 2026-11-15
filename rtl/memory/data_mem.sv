module data_mem (
    input  logic        clk,
    input  logic        we,
    input  logic [3:0]  be,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic [31:0] rdata
);
    // Fixed byte-addressable array — XSim compatible
    logic [7:0] mem [0:4095];

    assign rdata = {mem[{addr[11:2], 2'b11}],
                    mem[{addr[11:2], 2'b10}],
                    mem[{addr[11:2], 2'b01}],
                    mem[{addr[11:2], 2'b00}]};

    always_ff @(posedge clk) begin
        if (we) begin
            if (be[0]) mem[{addr[11:2], 2'b00}] <= wdata[ 7: 0];
            if (be[1]) mem[{addr[11:2], 2'b01}] <= wdata[15: 8];
            if (be[2]) mem[{addr[11:2], 2'b10}] <= wdata[23:16];
            if (be[3]) mem[{addr[11:2], 2'b11}] <= wdata[31:24];
        end
    end
endmodule
