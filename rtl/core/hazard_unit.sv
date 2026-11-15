`timescale 1ns / 1ps

// ================================================================
// Hazard Unit - Forwarding, Stalls, Flushes
//
// Stall sources:
//   1. Load-use hazard (rd_en_MW && dependency)
//   2. Instruction memory stall (imem_stall)
//   3. Data memory stall (dmem_stall)
//
// Priority: mem_stall suppresses load-use flush
// ================================================================

module hazard_unit (
    // ---- DE stage register addresses ----
    input  logic [ 4:0] rs1_addr_DE,
    input  logic [ 4:0] rs2_addr_DE,

    // ---- MW stage writeback info ----
    input  logic [ 4:0] rd_addr_MW,
    input  logic        rf_en_MW,
    input  logic        rd_en_MW,

    // ---- Control flow events (DE stage) ----
    input  logic        br_take_DE,
    input  logic        is_mret_DE,
    input  logic        epc_taken_IF,

    // ---- Memory handshake stalls ----
    input  logic        imem_stall,
    input  logic        dmem_stall,
    input  logic        mdu_stall,   // MDU multi-cycle stall

    // ---- Outputs ----
    output logic        forward_a,
    output logic        forward_b,
    output logic        stall_IF,
    output logic        stall_MW,
    output logic        flush_DE,
    output logic        flush_MW
);

    // ================================================================
    // MW → DE Forwarding (non-load instructions only)
    // ================================================================
    assign forward_a = !rd_en_MW && rf_en_MW &&
                       (rs1_addr_DE != 5'd0) &&
                       (rs1_addr_DE == rd_addr_MW);

    assign forward_b = !rd_en_MW && rf_en_MW &&
                       (rs2_addr_DE != 5'd0) &&
                       (rs2_addr_DE == rd_addr_MW);

    // ================================================================
    // Load-use hazard detection
    // ================================================================
    wire load_use = rd_en_MW && rf_en_MW &&
                    ((rs1_addr_DE != 5'd0 && rs1_addr_DE == rd_addr_MW) ||
                     (rs2_addr_DE != 5'd0 && rs2_addr_DE == rd_addr_MW));

    // ================================================================
    // Memory stall (any memory interface not ready, or MDU busy)
    // ================================================================
    wire mem_stall = imem_stall || dmem_stall || mdu_stall;

    // ================================================================
    // Pipeline control
    // ================================================================

    // Stall IF: freeze PC + FIRST REG
    //   - load-use: 1-cycle stall for data forwarding
    //   - mem_stall: freeze until memory responds
    assign stall_IF = load_use || mem_stall;

    // Stall MW: freeze SEC REG (hold MW outputs)
    //   - only during memory stalls (load-use uses flush_MW instead)
    assign stall_MW = mem_stall;

    // Flush DE: kill instruction in FIRST REG (insert NOP)
    //   - branch/jump/trap redirect, suppressed during stall
    assign flush_DE = (br_take_DE || is_mret_DE || epc_taken_IF) && !stall_IF;

    // Flush MW: insert bubble in SEC REG
    //   - load-use: DE re-executes, MW gets bubble
    //   - suppressed during memory stall (SEC REG must hold)
    assign flush_MW = load_use && !mem_stall;

endmodule
