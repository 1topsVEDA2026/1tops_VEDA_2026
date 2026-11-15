`timescale 1ns / 1ps
// ============================================================================
// pc_unit.sv — Parameterized Program Counter Unit with Redirect Priority
//
// Core Component of 3-Stage RV32IM Processor (IF Stage)
//
// Features:
//   - Parameterized RESET_PC (e.g. 32'h0000_0000 or 32'h8000_0000)
//   - Strict redirect priority hierarchy:
//       1. Trap / Exception redirect (trap_illegal -> mtvec_out)
//       2. MRET context restore (is_mret_DE -> epc_pc)
//       3. Branch / Jump computed target (br_take_DE -> opr_res_DE)
//       4. Sequential increment (pc_out_IF + 4)
//   - Pipeline stall freeze (!ready_IF / stall_IF)
//   - Halfword/word alignment enforcement on jump targets ({target[31:1], 1'b0})
// ============================================================================

module pc_unit #(
    parameter logic [31:0] RESET_PC = 32'h0000_0000
)(
    input  logic        clk,
    input  logic        rst_n,

    // Pipeline flow control
    input  logic        ready_IF,         // !stall_IF: enable PC advance

    // Priority 1: Trap / Exception redirect
    input  logic        trap_illegal,     // exception / illegal instruction trap
    input  logic [31:0] mtvec_out,        // trap vector base address

    // Priority 2: MRET return
    input  logic        is_mret_DE,       // MRET instruction in DE stage
    input  logic        valid_DE,         // valid instruction in DE stage
    input  logic [31:0] epc_pc,           // MEPC exception return PC

    // Priority 3: Branch / Jump target
    input  logic        br_take_DE,       // branch taken or JAL/JALR target valid
    input  logic [31:0] opr_res_DE,       // branch/jump target from ALU/adder

    // Outputs
    output logic [31:0] pc_out_IF,        // Current fetch PC
    output logic [31:0] pc_next_IF,       // Sequential PC (pc_out_IF + 4)
    output logic [31:0] nxt_pc,           // Next PC selected by priority mux
    output logic        epc_taken_IF      // Trap pulse: trap_illegal & ready_IF
);

    // Trap taken qualification with IF readiness
    assign epc_taken_IF = trap_illegal & ready_IF;

    // Sequential PC increment (+4)
    assign pc_next_IF   = pc_out_IF + 32'd4;

    // Next-PC Priority Multiplexer: Trap > MRET > Branch/Jump > Sequential PC+4
    always_comb begin
        if (epc_taken_IF)
            nxt_pc = mtvec_out;
        else if (is_mret_DE & valid_DE & ready_IF)
            nxt_pc = epc_pc;
        else if (br_take_DE & valid_DE & ready_IF)
            nxt_pc = {opr_res_DE[31:1], 1'b0};
        else
            nxt_pc = pc_next_IF;
    end

    // Sequential PC Register with active-low asynchronous reset
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_out_IF <= RESET_PC;
        else if (ready_IF)
            pc_out_IF <= nxt_pc;
    end

endmodule
