`timescale 1ns / 1ps

module register_file (
    input  logic        clk,
    input  logic        rst_n,

    // Read Port 1 (asynchronous)
    input  logic [ 4:0] rs1_addr,
    output logic [31:0] rsdata1,

    // Read Port 2 (asynchronous)
    input  logic [ 4:0] rs2_addr,
    output logic [31:0] rsdata2,

    // Write Port (synchronous, posedge)
    input  logic [ 4:0] rd_addr,
    input  logic [31:0] wdata,
    input  logic        rf_en
);

    logic [31:0] regs [0:31];

    // Asynchronous read with write-through bypass
    assign rsdata1 = (rs1_addr == 5'd0) ? 32'd0 :
                     (rf_en && rd_addr != 5'd0 && rd_addr == rs1_addr) ? wdata :
                     regs[rs1_addr];

    assign rsdata2 = (rs2_addr == 5'd0) ? 32'd0 :
                     (rf_en && rd_addr != 5'd0 && rd_addr == rs2_addr) ? wdata :
                     regs[rs2_addr];

    // Synchronous write
    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else if (rf_en && rd_addr != 5'd0) begin
            regs[rd_addr] <= wdata;
        end
    end

endmodule
