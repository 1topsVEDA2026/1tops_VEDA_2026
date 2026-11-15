`timescale 1ns / 1ps
module controller
    import rv32_pkg::*;
(
    input  exec_class_t exec_class,
    input  alu_func_t   alu_func_in,
    input  mdu_func_t   mdu_func_in,  // M-extension operation
    input  csr_cmd_t    csr_cmd_in,
    input  logic        br_taken,
    input  logic [ 4:0] rs1_addr,

    output alu_func_t   aluop,
    output mdu_func_t   mdu_func_out, // Passed through to MDU
    output logic        rf_en,
    output logic        sel_a,       // 0 = PC,  1 = RS1
    output logic        sel_b,       // 0 = RS2, 1 = IMM
    output logic        rd_en,       // Load enable
    output logic        wr_en,       // Store enable
    output wb_sel_t     wb_sel,
    output logic        br_take,
    output logic        csr_rd,
    output logic        csr_wr,
    output logic        csr_imm_sel, // 1 = use zimm, 0 = use RS1 data
    output logic        is_mret,
    output logic        trap_illegal
);

    always_comb begin
        // Secure defaults — no side effects
        aluop        = ALU_ADD;
        mdu_func_out = mdu_func_in;  // Always pass through
        rf_en        = 1'b0;
        sel_a        = 1'b1;    // RS1
        sel_b        = 1'b0;    // RS2
        rd_en        = 1'b0;
        wr_en        = 1'b0;
        wb_sel       = WB_ALU;
        br_take      = 1'b0;
        csr_rd       = 1'b0;
        csr_wr       = 1'b0;
        csr_imm_sel  = 1'b0;
        is_mret      = 1'b0;
        trap_illegal = 1'b0;

        case (exec_class)
            EXEC_ALU: begin
                rf_en = 1'b1;
                aluop = alu_func_in;
            end

            EXEC_MDU: begin
                // M-extension: result comes from MDU (bypasses ALU).
                // sel_a=1 (RS1), sel_b=0 (RS2) — both register operands.
                // wb_sel=WB_ALU: MDU result is muxed onto opr_res_DE.
                rf_en  = 1'b1;
                sel_a  = 1'b1;
                sel_b  = 1'b0;
                wb_sel = WB_ALU;
            end

            EXEC_ALU_IMM: begin
                rf_en = 1'b1;
                sel_b = 1'b1;
                aluop = alu_func_in;
            end

            EXEC_LOAD: begin
                rf_en  = 1'b1;
                sel_b  = 1'b1;
                rd_en  = 1'b1;
                wb_sel = WB_MEM;
                aluop  = ALU_ADD;
            end

            EXEC_STORE: begin
                sel_b = 1'b1;
                wr_en = 1'b1;
                aluop = ALU_ADD;
            end

            EXEC_BRANCH: begin
                sel_a   = 1'b0; // PC
                sel_b   = 1'b1;
                br_take = br_taken;
                aluop   = ALU_ADD;
            end

            EXEC_LUI: begin
                rf_en = 1'b1;
                sel_b = 1'b1;
                aluop = ALU_PASS_B;
            end

            EXEC_AUIPC: begin
                rf_en = 1'b1;
                sel_a = 1'b0; // PC
                sel_b = 1'b1;
                aluop = ALU_ADD;
            end

            EXEC_JAL: begin
                rf_en   = 1'b1;
                sel_a   = 1'b0; // PC
                sel_b   = 1'b1;
                wb_sel  = WB_PC4;
                br_take = 1'b1;
                aluop   = ALU_ADD;
            end

            EXEC_JALR: begin
                rf_en   = 1'b1;
                sel_a   = 1'b1; // RS1
                sel_b   = 1'b1;
                wb_sel  = WB_PC4;
                br_take = 1'b1;
                aluop   = ALU_ADD;
            end

            EXEC_SYS: begin
                if (csr_cmd_in == CSR_MRET) begin
                    is_mret = 1'b1;
                    br_take = 1'b1;
                end else if (csr_cmd_in != CSR_NONE) begin
                    rf_en  = 1'b1;
                    wb_sel = WB_CSR;
                    csr_rd = 1'b1;

                    if (csr_cmd_in == CSR_RWI || csr_cmd_in == CSR_RSI || csr_cmd_in == CSR_RCI)
                        csr_imm_sel = 1'b1;

                    if (csr_cmd_in == CSR_RW || csr_cmd_in == CSR_RWI || rs1_addr != 5'b00000)
                        csr_wr = 1'b1;
                end
            end

            EXEC_ILL: begin
                trap_illegal = 1'b1;
            end

            default: begin
                trap_illegal = 1'b1;
            end
        endcase
    end

endmodule
