`timescale 1ns / 1ps
module alu
    import rv32_pkg::*;
(
    input  logic [31:0] opr_a,
    input  logic [31:0] opr_b,
    input  alu_func_t   alu_func,
    output logic [31:0] opr_res
);



    always_comb begin
        case (alu_func)
            ALU_ADD:    opr_res = opr_a + opr_b;
            ALU_SUB:    opr_res = opr_a - opr_b;
            ALU_SLL:    opr_res = opr_a << opr_b[4:0];
            ALU_SLT:    opr_res = {31'b0, $signed(opr_a) < $signed(opr_b)};
            ALU_SLTU:   opr_res = {31'b0, opr_a < opr_b};
            ALU_XOR:    opr_res = opr_a ^ opr_b;
            ALU_SRL:    opr_res = opr_a >> opr_b[4:0];
            ALU_SRA:    opr_res = $unsigned($signed(opr_a) >>> opr_b[4:0]);
            ALU_OR:     opr_res = opr_a | opr_b;
            ALU_AND:    opr_res = opr_a & opr_b;
            ALU_PASS_B: opr_res = opr_b;
            default:    opr_res = 32'd0;
        endcase
    end

endmodule
