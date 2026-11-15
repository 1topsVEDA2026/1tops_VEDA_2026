`timescale 1ns / 1ps

// ============================================================
// pipe_de_mw - Pipeline Register: DE → MW  (SEC REG)
//
// Pipeline handshake: ready_MW controls data transfer
//   flush_MW=1  → control enables cleared (bubble inserted)
//   ready_MW=0  → all outputs HOLD (freeze - data memory wait)
//   ready_MW=1  → latch all inputs from DE stage
// ============================================================

module pipe_de_mw
    import rv32_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush_MW,
    input  logic        ready_MW,       // MW stage ready to accept (= !stall_MW)

    // DE stage data inputs
    input  logic [31:0] opr_res_in,
    input  logic [31:0] rsdata2_in,
    input  logic [ 4:0] rd_addr_in,
    input  logic [31:0] pc_next_in,
    input  logic [31:0] pc_out_in,
    input  logic [31:0] csr_rdata_in,

    // DE stage control inputs
    input  logic        rf_en_in,
    input  wb_sel_t     wb_sel_in,
    input  logic        rd_en_in,
    input  logic        wr_en_in,
    input  mem_acc_t    mem_acc_mode_in,

    // MW stage data outputs
    output logic [31:0] opr_res_MW,
    output logic [31:0] rsdata2_MW,
    output logic [ 4:0] rd_addr_MW,
    output logic [31:0] pc_next_MW,
    output logic [31:0] pc_out_MW,
    output logic [31:0] csr_rdata_MW,

    // MW stage control outputs
    output logic        rf_en_MW,
    output wb_sel_t     wb_sel_MW,
    output logic        rd_en_MW,
    output logic        wr_en_MW,
    output mem_acc_t    mem_acc_mode_MW
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            opr_res_MW      <= 32'h0;
            rsdata2_MW      <= 32'h0;
            rd_addr_MW      <= 5'h0;
            pc_next_MW      <= 32'h4;
            pc_out_MW       <= 32'h0;
            csr_rdata_MW    <= 32'h0;
            rf_en_MW        <= 1'b0;
            wb_sel_MW       <= WB_ALU;
            rd_en_MW        <= 1'b0;
            wr_en_MW        <= 1'b0;
            mem_acc_mode_MW <= MEM_WORD;
        end
        else if (flush_MW) begin
            // Load-use hazard - kill the instruction in MW
            rf_en_MW        <= 1'b0;
            rd_en_MW        <= 1'b0;
            wr_en_MW        <= 1'b0;
            // Data fields can hold - control fields are what matter
            opr_res_MW      <= opr_res_MW;
            rsdata2_MW      <= rsdata2_MW;
            rd_addr_MW      <= rd_addr_MW;
            pc_next_MW      <= pc_next_MW;
            pc_out_MW       <= pc_out_MW;
            csr_rdata_MW    <= csr_rdata_MW;
            wb_sel_MW       <= wb_sel_MW;
            mem_acc_mode_MW <= mem_acc_mode_MW;
        end
        else if (ready_MW) begin
            // Handshake: MW ready to accept → latch DE outputs
            opr_res_MW      <= opr_res_in;
            rsdata2_MW      <= rsdata2_in;
            rd_addr_MW      <= rd_addr_in;
            pc_next_MW      <= pc_next_in;
            pc_out_MW       <= pc_out_in;
            csr_rdata_MW    <= csr_rdata_in;
            rf_en_MW        <= rf_en_in;
            wb_sel_MW       <= wb_sel_in;
            rd_en_MW        <= rd_en_in;
            wr_en_MW        <= wr_en_in;
            mem_acc_mode_MW <= mem_acc_mode_in;
        end
        // ready_MW=0 and no flush: all outputs HOLD
    end

endmodule