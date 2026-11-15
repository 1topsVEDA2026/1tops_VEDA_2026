`timescale 1ns / 1ps
module branch_cmp
    import rv32_pkg::*;
(
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    input  br_type_t    br_type,
    input  logic        is_branch,  // 1 when exec_class == EXEC_BRANCH
    output logic        is_taken
);

    logic cmp_result;

    always_comb begin
        case (br_type)
            BR_BEQ:  cmp_result = (rs1_data == rs2_data);
            BR_BNE:  cmp_result = (rs1_data != rs2_data);
            BR_BLT:  cmp_result = ($signed(rs1_data) <  $signed(rs2_data));
            BR_BGE:  cmp_result = ($signed(rs1_data) >= $signed(rs2_data));
            BR_BLTU: cmp_result = (rs1_data <  rs2_data);
            BR_BGEU: cmp_result = (rs1_data >= rs2_data);
            default: cmp_result = 1'b0;
        endcase
    end

    // Only assert is_taken for actual branch instructions
    assign is_taken = is_branch & cmp_result;

endmodule
