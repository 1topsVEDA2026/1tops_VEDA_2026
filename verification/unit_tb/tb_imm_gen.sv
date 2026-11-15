`timescale 1ns / 1ps
// ============================================================
// tb_imm_gen.sv — Phase-1 Immediate Generator TB (XSim-safe)
// ============================================================
module tb_imm_gen
    import rv32_pkg::*;
();

    logic [31:0] inst;
    imm_type_t   imm_type;
    logic [31:0] imm_ext;

    imm_gen u_dut (.*);

    integer pass_cnt = 0, fail_cnt = 0;

    // ---- Golden reference ----
    function automatic logic [31:0] imm_ref(
        input logic [31:0] i, input imm_type_t t
    );
        case (t)
            IMM_I:   return {{20{i[31]}}, i[31:20]};
            IMM_S:   return {{20{i[31]}}, i[31:25], i[11:7]};
            IMM_B:   return {{20{i[31]}}, i[7], i[30:25], i[11:8], 1'b0};
            IMM_U:   return {i[31:12], 12'b0};
            IMM_J:   return {{12{i[31]}}, i[19:12], i[20], i[30:21], 1'b0};
            default: return 32'b0;
        endcase
    endfunction

    // ---- Covergroup ----
    covergroup cg_imm @(inst);
        cp_type: coverpoint imm_type {
            bins types[] = {IMM_I, IMM_S, IMM_B, IMM_U, IMM_J, IMM_NONE};
        }
        cp_sign: coverpoint inst[31] {
            bins positive = {1'b0};
            bins negative = {1'b1};
        }
    endgroup

    cg_imm cov = new();

    // ---- Scoreboard ----
    task automatic check(input string desc);
        logic [31:0] exp;
        exp = imm_ref(inst, imm_type);
        #1;
        if (imm_ext === exp) begin
            pass_cnt++;
            if (desc != "") $display("  [PASS] %s  imm=0x%08H", desc, imm_ext);
        end else begin
            $display("  [FAIL] %s: inst=0x%08H type=%0d  got=0x%08H exp=0x%08H",
                     desc, inst, imm_type, imm_ext, exp);
            fail_cnt++;
        end
    endtask

    // ---- Loop variables at module scope for XSim ----
    integer ri, ti;
    localparam int NUM_TYPES = 6;
    imm_type_t type_list [0:NUM_TYPES-1];
    integer tp, tf;

    initial begin
        type_list[0] = IMM_I; type_list[1] = IMM_S; type_list[2] = IMM_B;
        type_list[3] = IMM_U; type_list[4] = IMM_J; type_list[5] = IMM_NONE;

        $display("\n========== Immediate Generator Unit Testbench ==========");

        // ---- I-Type ----
        $display("\n--- Directed: I-Type ---");
        imm_type = IMM_I;
        inst = 32'h00700093; check("I: +7");
        inst = 32'hFFF00093; check("I: -1");
        inst = 32'h00000093; check("I: 0");
        inst = 32'h7FF00093; check("I: +2047");
        inst = 32'h80000093; check("I: -2048");

        // ---- S-Type ----
        $display("\n--- Directed: S-Type ---");
        imm_type = IMM_S;
        inst = 32'h00212823; check("S: +16");
        inst = {7'b1111111, 5'd2, 5'd1, 3'b010, 5'b11100, 7'b0100011};
        check("S: -4");
        inst = {7'b0000000, 5'd2, 5'd1, 3'b010, 5'b00000, 7'b0100011};
        check("S: 0");

        // ---- B-Type ----
        $display("\n--- Directed: B-Type ---");
        imm_type = IMM_B;
        inst = 32'h00208463; check("B: +8");
        inst = 32'hFE209EE3; check("B: negative");
        inst = {1'b0, 6'b000000, 5'd0, 5'd0, 3'b000, 4'b0000, 1'b0, 7'b1100011};
        check("B: 0");

        // ---- U-Type ----
        $display("\n--- Directed: U-Type ---");
        imm_type = IMM_U;
        inst = 32'hABCDE0B7; check("U: 0xABCDE000");
        inst = {20'h00000, 5'd1, 7'b0110111}; check("U: 0");
        inst = {20'hFFFFF, 5'd1, 7'b0110111}; check("U: 0xFFFFF000");

        // ---- J-Type ----
        $display("\n--- Directed: J-Type ---");
        imm_type = IMM_J;
        inst = {1'b0, 10'b0, 1'b0, 8'b0, 5'd1, 7'b1101111}; check("J: 0");
        inst = 32'h7FFFF0EF; check("J: large+");
        inst = 32'hFFFFF0EF; check("J: neg");

        // ---- IMM_NONE ----
        $display("\n--- Directed: IMM_NONE ---");
        imm_type = IMM_NONE;
        inst = 32'hDEADBEEF; check("NONE: 0");

        // ---- Random (300 vectors/type) ----
        $display("\n--- Constrained-Random Tests ---");
        $display("  (300 random instructions per imm type, with sign/corner injection)");
        for (ti = 0; ti < NUM_TYPES; ti = ti + 1) begin
            string tname;
            tp = pass_cnt; tf = fail_cnt;
            imm_type = type_list[ti];
            case (type_list[ti])
                IMM_I:    tname = "IMM_I";
                IMM_S:    tname = "IMM_S";
                IMM_B:    tname = "IMM_B";
                IMM_U:    tname = "IMM_U";
                IMM_J:    tname = "IMM_J";
                IMM_NONE: tname = "IMM_NONE";
                default:  tname = "???";
            endcase
            for (ri = 0; ri < 300; ri = ri + 1) begin
                inst = $urandom;
                if (ri < 10) inst[31] = 1'b1;
                if (ri >= 10 && ri < 20) inst[31] = 1'b0;
                if (ri == 20) inst = 32'h0;
                if (ri == 21) inst = 32'hFFFFFFFF;
                check("");
            end
            $display("  [PASS] %-8s : 300 random vectors, %0d pass, %0d fail",
                     tname, pass_cnt - tp, fail_cnt - tf);
        end

        // ---- Summary ----
        $display("\n========================================");
        $display("  IMM_GEN FINAL: %0d PASS, %0d FAIL (of %0d)",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        $display("========================================");
        if (fail_cnt > 0) $display("  *** FAILURES DETECTED ***");
        else              $display("  *** ALL TESTS PASSED ***");
        #10; $finish;
    end

endmodule
