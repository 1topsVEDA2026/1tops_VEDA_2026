`timescale 1ns / 1ps
module decoder
    import rv32_pkg::*;
(
    input  logic [31:0] inst,

    output logic [ 4:0] rs1_addr,
    output logic [ 4:0] rs2_addr,
    output logic [ 4:0] rd_addr,
    output logic [11:0] csr_addr,

    output imm_type_t   imm_type,
    output exec_class_t exec_class,
    output alu_func_t   alu_func,
    output mdu_func_t   mdu_func,    // M-extension operation select
    output csr_cmd_t    csr_cmd,
    output br_type_t    br_type,
    output mem_acc_t    mem_acc_mode
);

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    assign opcode   = inst[6:0];
    assign funct3   = inst[14:12];
    assign funct7   = inst[31:25];
    assign rd_addr  = inst[11:7];
    assign rs1_addr = inst[19:15];
    assign rs2_addr = inst[24:20];
    assign csr_addr = inst[31:20];

    always_comb begin
        // Safe defaults
        imm_type     = IMM_NONE;
        exec_class   = EXEC_ILL;
        alu_func     = ALU_ADD;
        mdu_func     = MDU_MUL;
        csr_cmd      = CSR_NONE;
        br_type      = BR_BEQ;
        mem_acc_mode = MEM_BYTE;

        case (opcode)
            // ---------------------------------------------------------
            // R-Type (ALU register-register  +  M-extension)
            // ---------------------------------------------------------
            7'b0110011: begin
                if (funct7 == 7'b0000001) begin
                    // ---- M-extension (MUL/DIV/REM) ----
                    exec_class = EXEC_MDU;
                    mdu_func   = mdu_func_t'(funct3); // funct3 maps 1:1 to MDU ops
                end else if (funct7 == 7'b0000000 || funct7 == 7'b0100000) begin
                    exec_class = EXEC_ALU;
                    case (funct3)
                        3'b000: alu_func = (funct7[5]) ? ALU_SUB : ALU_ADD;
                        3'b001: alu_func = ALU_SLL;
                        3'b010: alu_func = ALU_SLT;
                        3'b011: alu_func = ALU_SLTU;
                        3'b100: alu_func = ALU_XOR;
                        3'b101: alu_func = (funct7[5]) ? ALU_SRA : ALU_SRL;
                        3'b110: alu_func = ALU_OR;
                        3'b111: alu_func = ALU_AND;
                    endcase
                end
            end

            // ---------------------------------------------------------
            // I-Type (ALU register-immediate)
            // ---------------------------------------------------------
            7'b0010011: begin
                case (funct3)
                    3'b000: begin exec_class = EXEC_ALU_IMM; imm_type = IMM_I; alu_func = ALU_ADD;  end
                    3'b010: begin exec_class = EXEC_ALU_IMM; imm_type = IMM_I; alu_func = ALU_SLT;  end
                    3'b011: begin exec_class = EXEC_ALU_IMM; imm_type = IMM_I; alu_func = ALU_SLTU; end
                    3'b100: begin exec_class = EXEC_ALU_IMM; imm_type = IMM_I; alu_func = ALU_XOR;  end
                    3'b110: begin exec_class = EXEC_ALU_IMM; imm_type = IMM_I; alu_func = ALU_OR;   end
                    3'b111: begin exec_class = EXEC_ALU_IMM; imm_type = IMM_I; alu_func = ALU_AND;  end
                    3'b001: begin
                        if (funct7 == 7'b0000000) begin
                            exec_class = EXEC_ALU_IMM;
                            imm_type   = IMM_I;
                            alu_func   = ALU_SLL;
                        end
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000) begin
                            exec_class = EXEC_ALU_IMM;
                            imm_type   = IMM_I;
                            alu_func   = ALU_SRL;
                        end else if (funct7 == 7'b0100000) begin
                            exec_class = EXEC_ALU_IMM;
                            imm_type   = IMM_I;
                            alu_func   = ALU_SRA;
                        end
                    end
                endcase
            end

            // ---------------------------------------------------------
            // Loads
            // ---------------------------------------------------------
            7'b0000011: begin
                if (funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b010 ||
                    funct3 == 3'b100 || funct3 == 3'b101) begin
                    exec_class   = EXEC_LOAD;
                    imm_type     = IMM_I;
                    mem_acc_mode = mem_acc_t'(funct3);
                end
            end

            // ---------------------------------------------------------
            // Stores
            // ---------------------------------------------------------
            7'b0100011: begin
                if (funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b010) begin
                    exec_class   = EXEC_STORE;
                    imm_type     = IMM_S;
                    mem_acc_mode = mem_acc_t'(funct3);
                end
            end

            // ---------------------------------------------------------
            // Branches
            // ---------------------------------------------------------
            7'b1100011: begin
                if (funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b100 ||
                    funct3 == 3'b101 || funct3 == 3'b110 || funct3 == 3'b111) begin
                    exec_class = EXEC_BRANCH;
                    imm_type   = IMM_B;
                    br_type    = br_type_t'(funct3);
                end
            end

            // ---------------------------------------------------------
            // LUI
            // ---------------------------------------------------------
            7'b0110111: begin
                exec_class = EXEC_LUI;
                imm_type   = IMM_U;
                alu_func   = ALU_PASS_B;
            end

            // ---------------------------------------------------------
            // AUIPC
            // ---------------------------------------------------------
            7'b0010111: begin
                exec_class = EXEC_AUIPC;
                imm_type   = IMM_U;
            end

            // ---------------------------------------------------------
            // JAL
            // ---------------------------------------------------------
            7'b1101111: begin
                exec_class = EXEC_JAL;
                imm_type   = IMM_J;
            end

            // ---------------------------------------------------------
            // JALR
            // ---------------------------------------------------------
            7'b1100111: begin
                if (funct3 == 3'b000) begin
                    exec_class = EXEC_JALR;
                    imm_type   = IMM_I;
                end
            end

            // ---------------------------------------------------------
            // SYSTEM (CSR / MRET)
            // ---------------------------------------------------------
            7'b1110011: begin
                if (funct3 == 3'b000) begin
                    if (inst == 32'h30200073) begin
                        exec_class = EXEC_SYS;
                        csr_cmd    = CSR_MRET;
                    end else if (inst == 32'h00000073 || inst == 32'h00100073) begin
                        // ECALL (00000073) or EBREAK (00100073) → trap
                        exec_class = EXEC_ILL;
                    end
                end else begin
                    case (funct3)
                        3'b001: begin exec_class = EXEC_SYS; csr_cmd = CSR_RW;  imm_type = IMM_I; end
                        3'b010: begin exec_class = EXEC_SYS; csr_cmd = CSR_RS;  imm_type = IMM_I; end
                        3'b011: begin exec_class = EXEC_SYS; csr_cmd = CSR_RC;  imm_type = IMM_I; end
                        3'b101: begin exec_class = EXEC_SYS; csr_cmd = CSR_RWI; imm_type = IMM_I; end
                        3'b110: begin exec_class = EXEC_SYS; csr_cmd = CSR_RSI; imm_type = IMM_I; end
                        3'b111: begin exec_class = EXEC_SYS; csr_cmd = CSR_RCI; imm_type = IMM_I; end
                        default: ;
                    endcase
                end
            end

            // ---------------------------------------------------------
            // FENCE (treated as NOP)
            // ---------------------------------------------------------
            7'b0001111: begin
                exec_class = EXEC_ALU_IMM;
                imm_type   = IMM_I;
                alu_func   = ALU_ADD;
            end

            default: ;
        endcase
    end

endmodule
