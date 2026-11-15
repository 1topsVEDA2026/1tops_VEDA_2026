`timescale 1ns / 1ps
module imm_gen
    import rv32_pkg::*;
(
    input  logic [31:0] inst,
    input  imm_type_t   imm_type,
    output logic [31:0] imm_ext
);

    always_comb begin
        case (imm_type)
            IMM_I:   imm_ext = {{20{inst[31]}}, inst[31:20]};
            IMM_S:   imm_ext = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            IMM_B:   imm_ext = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
            IMM_U:   imm_ext = {inst[31:12], 12'b0};
            IMM_J:   imm_ext = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
            default: imm_ext = 32'b0;
        endcase
    end

endmodule
