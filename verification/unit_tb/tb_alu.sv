`timescale 1ns / 1ps
// ============================================================
// tb_alu.sv — Phase-1 Unit-Level ALU Testbench (XSim-safe)
// ============================================================
module tb_alu
    import rv32_pkg::*;
();

    logic [31:0] opr_a, opr_b, opr_res;
    alu_func_t   alu_func;

    alu u_dut (.*);

    integer pass_cnt = 0, fail_cnt = 0, test_cnt = 0;

    // ============================================================
    // GOLDEN REFERENCE MODEL — XSim-safe (no ternary on division)
    // ============================================================
    function automatic logic [31:0] alu_ref(
        input logic [31:0] a, input logic [31:0] b, input alu_func_t func
    );
        logic signed [31:0] sa, sb;
        logic signed [63:0] mul_ss, mul_su;
        logic        [63:0] mul_uu;
        logic        [31:0] result;
        sa = $signed(a); sb = $signed(b);

        case (func)
            ALU_ADD:    result = a + b;
            ALU_SUB:    result = a - b;
            ALU_SLL:    result = a << b[4:0];
            ALU_SLT:    result = {31'b0, sa < sb};
            ALU_SLTU:   result = {31'b0, a < b};
            ALU_XOR:    result = a ^ b;
            ALU_SRL:    result = a >> b[4:0];
            ALU_SRA:    result = $unsigned(sa >>> b[4:0]);
            ALU_OR:     result = a | b;
            ALU_AND:    result = a & b;
            ALU_PASS_B: result = b;
            default: result = 32'd0;
        endcase
        return result;
    endfunction

    // ============================================================
    // COVERGROUP
    // ============================================================
    covergroup cg_alu @(test_cnt);
        cp_func: coverpoint alu_func {
            bins base_ops[] = {ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
                               ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR, ALU_AND, ALU_PASS_B};
        }
        cp_a_sign: coverpoint opr_a[31] {
            bins positive = {1'b0};
            bins negative = {1'b1};
        }
        cp_b_sign: coverpoint opr_b[31] {
            bins positive = {1'b0};
            bins negative = {1'b1};
        }
        cp_a_corner: coverpoint opr_a {
            bins zero     = {32'h0};
            bins one      = {32'h1};
            bins max_pos  = {32'h7FFFFFFF};
            bins min_neg  = {32'h80000000};
            bins all_ones = {32'hFFFFFFFF};
            bins others   = default;
        }
        cp_b_corner: coverpoint opr_b {
            bins zero     = {32'h0};
            bins one      = {32'h1};
            bins max_pos  = {32'h7FFFFFFF};
            bins min_neg  = {32'h80000000};
            bins all_ones = {32'hFFFFFFFF};
            bins others   = default;
        }
        cx_func_signs: cross cp_func, cp_a_sign, cp_b_sign;
    endgroup

    cg_alu cov = new();

    // ============================================================
    // SCOREBOARD
    // ============================================================
    task automatic check(input string desc);
        logic [31:0] expected;
        expected = alu_ref(opr_a, opr_b, alu_func);
        #1;
        test_cnt++;
        if (opr_res === expected) begin
            pass_cnt++;
            if (desc != "") $display("  [PASS] %s  (0x%08H)", desc, opr_res);
        end else begin
            $display("  [FAIL] %s: func=%0d a=0x%08H b=0x%08H  got=0x%08H exp=0x%08H",
                     desc, alu_func, opr_a, opr_b, opr_res, expected);
            fail_cnt++;
        end
    endtask

    // ============================================================
    // DIRECTED TESTS
    // ============================================================
    task automatic run_directed();
        $display("\n--- Directed Tests ---");

        // ADD
        alu_func = ALU_ADD;
        opr_a = 32'h7FFFFFFF; opr_b = 32'h1;        check("ADD overflow");
        opr_a = 32'h80000000; opr_b = 32'hFFFFFFFF;  check("ADD underflow");
        opr_a = 32'h0;        opr_b = 32'h0;         check("ADD zero+zero");
        opr_a = 32'hFFFFFFFF; opr_b = 32'h1;         check("ADD wrap");

        // SUB
        alu_func = ALU_SUB;
        opr_a = 32'h80000000; opr_b = 32'h1;         check("SUB underflow");
        opr_a = 32'h0;        opr_b = 32'h0;         check("SUB zero-zero");
        opr_a = 32'h7FFFFFFF; opr_b = 32'hFFFFFFFF;  check("SUB pos-neg");

        // SLL
        alu_func = ALU_SLL;
        opr_a = 32'hDEADBEEF; opr_b = 32'd0;        check("SLL by 0");
        opr_a = 32'hDEADBEEF; opr_b = 32'd1;        check("SLL by 1");
        opr_a = 32'h1;        opr_b = 32'd31;        check("SLL by 31");
        opr_a = 32'hDEADBEEF; opr_b = 32'd32;        check("SLL by 32(masked=0)");
        opr_a = 32'hDEADBEEF; opr_b = 32'd33;        check("SLL by 33(masked=1)");

        // SRL / SRA
        alu_func = ALU_SRL;
        opr_a = 32'h80000000; opr_b = 32'd1;         check("SRL sign-bit");
        opr_a = 32'hFFFFFFFF; opr_b = 32'd31;        check("SRL max shift");
        alu_func = ALU_SRA;
        opr_a = 32'h80000000; opr_b = 32'd1;         check("SRA sign-ext");
        opr_a = 32'h80000000; opr_b = 32'd31;        check("SRA max shift");
        opr_a = 32'h7FFFFFFF; opr_b = 32'd31;        check("SRA pos max");

        // SLT / SLTU
        alu_func = ALU_SLT;
        opr_a = 32'hFFFFFFFF; opr_b = 32'h0;         check("SLT -1<0");
        opr_a = 32'h0;        opr_b = 32'hFFFFFFFF;  check("SLT 0<-1");
        opr_a = 32'h80000000; opr_b = 32'h7FFFFFFF;  check("SLT MIN<MAX");
        alu_func = ALU_SLTU;
        opr_a = 32'hFFFFFFFF; opr_b = 32'h0;         check("SLTU max<0");
        opr_a = 32'h0;        opr_b = 32'hFFFFFFFF;  check("SLTU 0<max");
        opr_a = 32'h0;        opr_b = 32'h0;         check("SLTU equal");

        // Logical
        alu_func = ALU_XOR;
        opr_a = 32'hFFFFFFFF; opr_b = 32'hFFFFFFFF;  check("XOR self=0");
        opr_a = 32'hAAAAAAAA; opr_b = 32'h55555555;  check("XOR complement");
        alu_func = ALU_OR;
        opr_a = 32'h0;        opr_b = 32'h0;         check("OR zero");
        alu_func = ALU_AND;
        opr_a = 32'hFFFFFFFF; opr_b = 32'h12345678;  check("AND with -1");

        // PASS_B
        alu_func = ALU_PASS_B;
        opr_a = 32'hDEADBEEF; opr_b = 32'hCAFEBABE;  check("PASS_B");

        $display("  Directed: %0d pass, %0d fail", pass_cnt, fail_cnt);
    endtask

    // ============================================================
    // CONSTRAINED-RANDOM TESTS (XSim-safe: no queues)
    // ============================================================
    localparam int NUM_FUNCS = 11;
    alu_func_t func_list [0:NUM_FUNCS-1];

    task automatic run_random();
        int op_pass, op_fail;
        string fname;

        func_list[0]  = ALU_ADD;    func_list[1]  = ALU_SUB;
        func_list[2]  = ALU_SLL;    func_list[3]  = ALU_SLT;
        func_list[4]  = ALU_SLTU;   func_list[5]  = ALU_XOR;
        func_list[6]  = ALU_SRL;    func_list[7]  = ALU_SRA;
        func_list[8]  = ALU_OR;     func_list[9]  = ALU_AND;
        func_list[10] = ALU_PASS_B;

        $display("\n--- Constrained-Random Tests ---");
        $display("  (500 random input pairs per operation, with corner-value injection)");
        for (int i = 0; i < NUM_FUNCS; i++) begin
            op_pass = pass_cnt; op_fail = fail_cnt;
            alu_func = func_list[i];

            case (func_list[i])
                ALU_ADD:    fname = "ADD";
                ALU_SUB:    fname = "SUB";
                ALU_SLL:    fname = "SLL";
                ALU_SLT:    fname = "SLT";
                ALU_SLTU:   fname = "SLTU";
                ALU_XOR:    fname = "XOR";
                ALU_SRL:    fname = "SRL";
                ALU_SRA:    fname = "SRA";
                ALU_OR:     fname = "OR";
                ALU_AND:    fname = "AND";
                ALU_PASS_B: fname = "PASS_B";
                default:    fname = "???";
            endcase

            for (int j = 0; j < 500; j++) begin
                opr_a = $urandom;
                opr_b = $urandom;
                // Inject corners 10% of the time
                if (j < 25) begin
                    case (j % 5)
                        0: opr_a = 32'h0;
                        1: opr_a = 32'hFFFFFFFF;
                        2: opr_a = 32'h80000000;
                        3: opr_a = 32'h7FFFFFFF;
                        4: opr_b = 32'h0;
                    endcase
                end
                check("");
            end
            $display("  [PASS] %-7s : 500 random vectors, %0d pass, %0d fail",
                     fname, pass_cnt - op_pass, fail_cnt - op_fail);
        end
    endtask

    // ============================================================
    // MAIN
    // ============================================================
    initial begin
        $display("\n========== ALU Unit Testbench ==========");
        run_directed();
        run_random();

        $display("\n========================================");
        $display("  ALU FINAL: %0d PASS, %0d FAIL (of %0d)",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        $display("========================================");

        if (fail_cnt > 0) $display("  *** FAILURES DETECTED ***");
        else              $display("  *** ALL TESTS PASSED ***");

        #10; $finish;
    end

endmodule
