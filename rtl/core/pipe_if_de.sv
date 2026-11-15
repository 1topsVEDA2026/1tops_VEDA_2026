`timescale 1ns / 1ps

// ============================================================
// pipe_if_de - Pipeline Register: IF → DE  (FIRST REG)
//
// Pipeline handshake: valid_IF + ready_DE
//   Data transfers when valid_IF=1 AND ready_DE=1
//
// valid_DE rules:
//   flush_DE=1  → valid_DE = 0      (insert NOP bubble)
//   ready_DE=0  → valid_DE HOLDS    (freeze - do not clear)
//   ready_DE=1  → valid_DE = valid_IF (latch from memory)
//
// This ensures a real instruction being held during a stall
// is not incorrectly treated as a bubble.
// ============================================================

module pipe_if_de (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ready_DE,       // DE stage ready to accept (= !stall_IF)
    input  logic        flush_DE,

    // IF stage inputs
    input  logic [31:0] pc_out_IF,
    input  logic [31:0] pc_next_IF,
    input  logic [31:0] instr_IF,
    input  logic        valid_IF,       // imem_rvalid - instruction on bus is real

    // DE stage outputs
    output logic [31:0] pc_out_DE,
    output logic [31:0] pc_next_DE,
    output logic [31:0] inst_DE,
    output logic        valid_DE        // this instruction in DE is real
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out_DE  <= 32'h0;
            pc_next_DE <= 32'h4;
            inst_DE    <= 32'h0000_0013; // NOP
            valid_DE   <= 1'b0;
        end
        else if (flush_DE) begin
            // Branch/jump taken or trap - insert bubble
            inst_DE    <= 32'h0000_0013;
            valid_DE   <= 1'b0;
            // PC values can be anything during flush - DE is being killed
            pc_out_DE  <= pc_out_DE;
            pc_next_DE <= pc_next_DE;
        end
        else if (ready_DE) begin
            // Handshake: DE ready to accept → latch IF outputs
            pc_out_DE  <= pc_out_IF;
            pc_next_DE <= pc_next_IF;
            inst_DE    <= instr_IF;
            valid_DE   <= valid_IF;     // instruction valid = imem_rvalid
        end
        // ready_DE=0 and no flush: all outputs HOLD - including valid_DE
        // This is the critical case: instruction being held is still real
    end

endmodule