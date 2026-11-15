`timescale 1ns / 1ps
// ============================================================
// tb_branch_cmp.sv — Phase-1 Branch Comparator TB (XSim-safe)
// ============================================================
module tb_branch_cmp
    import rv32_pkg::*;
();

    logic [31:0] rs1_data, rs2_data;
    br_type_t    br_type;
    logic        is_branch, is_taken;

    branch_cmp u_dut (.*);

    integer pass_cnt = 0, fail_cnt = 0;

    // ---- Golden reference ----
    function automatic logic br_ref(
        input logic [31:0] a, input logic [31:0] b,
        input br_type_t bt, input logic ib
    );
        logic cmp;
        case (bt)
            BR_BEQ:  cmp = (a == b);
            BR_BNE:  cmp = (a != b);
            BR_BLT:  cmp = ($signed(a) <  $signed(b));
            BR_BGE:  cmp = ($signed(a) >= $signed(b));
            BR_BLTU: cmp = (a <  b);
            BR_BGEU: cmp = (a >= b);
            default: cmp = 0;
        endcase
        return ib & cmp;
    endfunction

    // ---- Covergroup ----
    covergroup cg_br @(rs1_data);
        cp_type: coverpoint br_type {
            bins types[] = {BR_BEQ, BR_BNE, BR_BLT, BR_BGE, BR_BLTU, BR_BGEU};
        }
        cp_result: coverpoint is_taken {
            bins taken = {1}; bins not_taken = {0};
        }
    endgroup

    cg_br cov = new();

    task automatic check(input string desc);
        logic exp;
        exp = br_ref(rs1_data, rs2_data, br_type, is_branch);
        #1;
        if (is_taken === exp) begin
            pass_cnt++;
            if (desc != "") $display("  [PASS] %s  taken=%0b", desc, is_taken);
        end else begin
            $display("  [FAIL] %s: rs1=0x%08H rs2=0x%08H type=%0d is_br=%0b  got=%0b exp=%0b",
                     desc, rs1_data, rs2_data, br_type, is_branch, is_taken, exp);
            fail_cnt++;
        end
    endtask

    integer ri;

    initial begin
        $display("\n========== Branch Comparator Unit Testbench ==========");
        is_branch = 1;

        // ---- BEQ ----
        $display("\n--- BEQ ---");
        br_type = BR_BEQ;
        rs1_data = 32'd5;  rs2_data = 32'd5;  check("BEQ equal");
        rs1_data = 32'd5;  rs2_data = 32'd6;  check("BEQ not-equal");
        rs1_data = 32'h0;  rs2_data = 32'h0;  check("BEQ zero");

        // ---- BNE ----
        $display("\n--- BNE ---");
        br_type = BR_BNE;
        rs1_data = 32'd5;  rs2_data = 32'd6;  check("BNE not-equal");
        rs1_data = 32'd5;  rs2_data = 32'd5;  check("BNE equal");

        // ---- BLT (signed) ----
        $display("\n--- BLT ---");
        br_type = BR_BLT;
        rs1_data = 32'hFFFFFFFF; rs2_data = 32'h0;        check("BLT -1<0");
        rs1_data = 32'h0;        rs2_data = 32'hFFFFFFFF;  check("BLT 0<-1");
        rs1_data = 32'h80000000; rs2_data = 32'h7FFFFFFF;  check("BLT MIN<MAX");
        rs1_data = 32'h7FFFFFFF; rs2_data = 32'h80000000;  check("BLT MAX<MIN");
        rs1_data = 32'd5;        rs2_data = 32'd5;         check("BLT equal");

        // ---- BGE (signed) ----
        $display("\n--- BGE ---");
        br_type = BR_BGE;
        rs1_data = 32'h0;        rs2_data = 32'hFFFFFFFF;  check("BGE 0>=-1");
        rs1_data = 32'hFFFFFFFF; rs2_data = 32'h0;         check("BGE -1>=0");
        rs1_data = 32'd5;        rs2_data = 32'd5;         check("BGE equal");

        // ---- BLTU (unsigned) ----
        $display("\n--- BLTU ---");
        br_type = BR_BLTU;
        rs1_data = 32'h0;        rs2_data = 32'hFFFFFFFF;  check("BLTU 0<MAX");
        rs1_data = 32'hFFFFFFFF; rs2_data = 32'h0;         check("BLTU MAX<0");
        rs1_data = 32'd5;        rs2_data = 32'd5;         check("BLTU equal");

        // ---- BGEU (unsigned) ----
        $display("\n--- BGEU ---");
        br_type = BR_BGEU;
        rs1_data = 32'hFFFFFFFF; rs2_data = 32'h0;         check("BGEU MAX>=0");
        rs1_data = 32'h0;        rs2_data = 32'hFFFFFFFF;  check("BGEU 0>=MAX");
        rs1_data = 32'd5;        rs2_data = 32'd5;         check("BGEU equal");

        // ---- is_branch=0 suppression ----
        $display("\n--- is_branch=0 ---");
        is_branch = 0;
        br_type = BR_BEQ; rs1_data = 32'd5; rs2_data = 32'd5;
        check("not-branch suppressed");

        // ---- Random (300 vectors) ----
        $display("\n--- Random (300 vectors) ---");
        is_branch = 1;
        for (ri = 0; ri < 300; ri = ri + 1) begin
            rs1_data = $urandom;
            if (ri < 30) rs2_data = rs1_data; // ensure some equals
            else         rs2_data = $urandom;
            case ($urandom_range(0, 5))
                0: br_type = BR_BEQ;
                1: br_type = BR_BNE;
                2: br_type = BR_BLT;
                3: br_type = BR_BGE;
                4: br_type = BR_BLTU;
                5: br_type = BR_BGEU;
                default: br_type = BR_BEQ;
            endcase
            check("");
        end

        $display("\n========================================");
        $display("  BRANCH_CMP FINAL: %0d PASS, %0d FAIL (of %0d)",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        $display("========================================");
        if (fail_cnt > 0) $display("  *** FAILURES DETECTED ***");
        else              $display("  *** ALL TESTS PASSED ***");
        #10; $finish;
    end

endmodule
