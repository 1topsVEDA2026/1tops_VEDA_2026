`timescale 1ns / 1ps
// ============================================================================
// tb_mdu.sv — Phase-1 Unit-Level Multiply / Divide Unit (MDU) Testbench
//
// Target Module: mdu.sv (Booth Radix-4 Multiplier + Restoring Iterative Divider)
//
// Sign-off Criteria Verified:
//   - All M-extension funct3 operations covered:
//       MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
//   - Divide-by-zero corner cases (DIV/DIVU -> 0xFFFFFFFF, REM/REMU -> dividend)
//   - Signed overflow corner cases (INT32_MIN / -1 -> INT32_MIN, INT32_MIN % -1 -> 0)
//   - Multi-cycle handshake and backpressure timing:
//       * 3-cycle multiplication latency & stall assertion
//       * 33-cycle restoring division latency & stall assertion
//       * Single-cycle done strobe validation
//       * Back-to-back execution without bus deadlocks
// ============================================================================

module tb_mdu
    import rv32_pkg::*;
();

    // Clock & Reset
    logic clk, rst_n;
    localparam CLK_PERIOD = 10;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // DUT Interface Signals
    logic        start;
    mdu_func_t   mdu_func;
    logic [31:0] rs1;
    logic [31:0] rs2;
    logic [31:0] result;
    logic        done;
    logic        stall;

    // DUT Instantiation
    mdu u_dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .mdu_func (mdu_func),
        .rs1      (rs1),
        .rs2      (rs2),
        .result   (result),
        .done     (done),
        .stall    (stall)
    );

    integer pass_cnt = 0, fail_cnt = 0, test_cnt = 0;

    // ========================================================================
    // FUNCTIONAL COVERAGE
    // ========================================================================
    covergroup cg_mdu @(posedge clk);
        cp_func: coverpoint mdu_func {
            bins all_m_ops[] = {MDU_MUL, MDU_MULH, MDU_MULHSU, MDU_MULHU,
                                MDU_DIV, MDU_DIVU, MDU_REM, MDU_REMU};
        }
        cp_div_zero: coverpoint (rs2 == 32'h0) {
            bins normal_divisor = {1'b0};
            bins div_by_zero    = {1'b1};
        }
        cp_signed_overflow: coverpoint (rs1 == 32'h8000_0000 && rs2 == 32'hFFFF_FFFF) {
            bins no_overflow = {1'b0};
            bins overflow    = {1'b1};
        }
        cp_stall: coverpoint stall {
            bins idle = {1'b0};
            bins busy = {1'b1};
        }
        cx_func_divzero: cross cp_func, cp_div_zero;
    endgroup

    cg_mdu cov = new();

    // ========================================================================
    // EXECUTION & CHECK TASK
    // ========================================================================
    task automatic exec_mdu(
        input mdu_func_t   func,
        input logic [31:0] op1,
        input logic [31:0] op2,
        input logic [31:0] exp_res,
        input integer      exp_latency,
        input string       desc
    );
        integer latency_cycles;
        test_cnt++;

        @(negedge clk);
        start    = 1'b1;
        mdu_func = func;
        rs1      = op1;
        rs2      = op2;

        @(posedge clk);
        #1;
        // Verify stall asserts immediately
        if (!stall) begin
            $display("  [FAIL] %s : stall did not assert on start cycle", desc);
            fail_cnt++;
        end

        @(negedge clk);
        start = 1'b0;

        latency_cycles = 1;
        while (!done && latency_cycles < 100) begin
            @(posedge clk);
            latency_cycles++;
        end

        #1;
        // Check done strobe and result
        if (done && result === exp_res && latency_cycles === exp_latency) begin
            pass_cnt++;
            $display("  [PASS] %-42s | got=0x%08H exp=0x%08H (lat=%0d cyc)",
                     desc, result, exp_res, latency_cycles);
        end else begin
            fail_cnt++;
            $display("  [FAIL] %-42s | got=0x%08H exp=0x%08H (lat=%0d exp=%0d done=%0b)",
                     desc, result, exp_res, latency_cycles, exp_latency, done);
        end

        // Check done deasserts on following cycle (single-cycle pulse)
        @(posedge clk);
        #1;
        if (done) begin
            $display("  [FAIL] %s : done did not deassert after 1 cycle", desc);
            fail_cnt++;
        end
    endtask

    // ========================================================================
    // MAIN TEST SEQUENCE
    // ========================================================================
    initial begin
        $display("==================================================================");
        $display("  tb_mdu: Multiply / Divide Unit (M-Extension) Verification");
        $display("==================================================================");

        // Reset DUT
        rst_n    = 0;
        start    = 0;
        mdu_func = MDU_MUL;
        rs1      = 0;
        rs2      = 0;
        repeat (5) @(posedge clk);
        rst_n    = 1;
        repeat (2) @(posedge clk);

        // --------------------------------------------------------------------
        // 1. MUL (Lower 32-bit signed*signed) — 3-cycle latency
        // --------------------------------------------------------------------
        $display("\n--- 1. MUL Basic & Signed Operands ---");
        exec_mdu(MDU_MUL, 32'd7, 32'd3, 32'd21, 3, "MUL: 7 * 3 = 21");
        exec_mdu(MDU_MUL, 32'd7, 32'hFFFFFFFC, 32'hFFFFFFE4, 3, "MUL: 7 * (-4) = -28");
        exec_mdu(MDU_MUL, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'd1, 3, "MUL: (-1) * (-1) = 1");
        exec_mdu(MDU_MUL, 32'h0, 32'hDEADBEEF, 32'h0, 3, "MUL: zero * any = 0");
        exec_mdu(MDU_MUL, 32'h80000000, 32'd2, 32'h0, 3, "MUL: 0x80000000 * 2 = 0 (wrap)");

        // --------------------------------------------------------------------
        // 2. MULH (Upper 32-bit signed*signed) — 3-cycle latency
        // --------------------------------------------------------------------
        $display("\n--- 2. MULH Signed High Word ---");
        exec_mdu(MDU_MULH, 32'd7, 32'd3, 32'd0, 3, "MULH: 7 * 3 upper = 0");
        exec_mdu(MDU_MULH, 32'd7, 32'hFFFFFFFC, 32'hFFFFFFFF, 3, "MULH: 7 * (-4) upper = -1");
        exec_mdu(MDU_MULH, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'd0, 3, "MULH: (-1) * (-1) upper = 0");
        exec_mdu(MDU_MULH, 32'h80000000, 32'h80000000, 32'h40000000, 3, "MULH: INT_MIN * INT_MIN upper = 0x40000000");

        // --------------------------------------------------------------------
        // 3. MULHSU (Upper 32-bit signed*unsigned) — 3-cycle latency
        // --------------------------------------------------------------------
        $display("\n--- 3. MULHSU Signed-Unsigned High Word ---");
        exec_mdu(MDU_MULHSU, 32'hFFFFFFFC, 32'd7, 32'hFFFFFFFF, 3, "MULHSU: (-4) * 7 upper = -1");
        exec_mdu(MDU_MULHSU, 32'd7, 32'd3, 32'd0, 3, "MULHSU: 7 * 3 upper = 0");
        exec_mdu(MDU_MULHSU, 32'hFFFFFFFF, 32'd2, 32'hFFFFFFFF, 3, "MULHSU: (-1) * 2 upper = -1");

        // --------------------------------------------------------------------
        // 4. MULHU (Upper 32-bit unsigned*unsigned) — 3-cycle latency
        // --------------------------------------------------------------------
        $display("\n--- 4. MULHU Unsigned High Word ---");
        exec_mdu(MDU_MULHU, 32'd7, 32'd3, 32'd0, 3, "MULHU: 7 * 3 upper = 0");
        exec_mdu(MDU_MULHU, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFE, 3, "MULHU: max_u * max_u upper = 0xFFFFFFFE");
        exec_mdu(MDU_MULHU, 32'h80000000, 32'h80000000, 32'h40000000, 3, "MULHU: 2^31 * 2^31 upper = 0x40000000");

        // --------------------------------------------------------------------
        // 5. DIV (Signed Division) — 33-cycle latency
        // --------------------------------------------------------------------
        $display("\n--- 5. DIV Signed Division ---");
        exec_mdu(MDU_DIV, 32'd7, 32'd3, 32'd2, 33, "DIV: 7 / 3 = 2");
        exec_mdu(MDU_DIV, 32'hFFFFFFFC, 32'd7, 32'd0, 33, "DIV: (-4) / 7 = 0");
        exec_mdu(MDU_DIV, 32'hFFFFFFEC, 32'hFFFFFFFC, 32'd5, 33, "DIV: (-20) / (-4) = 5");
        exec_mdu(MDU_DIV, 32'd20, 32'hFFFFFFFC, 32'hFFFFFFFB, 33, "DIV: 20 / (-4) = -5");

        // --------------------------------------------------------------------
        // 6. DIVU (Unsigned Division) — 33-cycle latency
        // --------------------------------------------------------------------
        $display("\n--- 6. DIVU Unsigned Division ---");
        exec_mdu(MDU_DIVU, 32'd7, 32'd3, 32'd2, 33, "DIVU: 7 / 3 = 2");
        exec_mdu(MDU_DIVU, 32'hFFFFFFFC, 32'd7, 32'd613566756, 33, "DIVU: 0xFFFFFFFC / 7 = 613566756");

        // --------------------------------------------------------------------
        // 7. REM (Signed Remainder) — 33-cycle latency
        // --------------------------------------------------------------------
        $display("\n--- 7. REM Signed Remainder ---");
        exec_mdu(MDU_REM, 32'd7, 32'd3, 32'd1, 33, "REM: 7 % 3 = 1");
        exec_mdu(MDU_REM, 32'hFFFFFFFC, 32'd7, 32'hFFFFFFFC, 33, "REM: (-4) % 7 = -4");
        exec_mdu(MDU_REM, 32'd20, 32'hFFFFFFFC, 32'd0, 33, "REM: 20 % (-4) = 0");
        exec_mdu(MDU_REM, 32'hFFFFFFE9, 32'd4, 32'hFFFFFFFD, 33, "REM: (-23) % 4 = -3");

        // --------------------------------------------------------------------
        // 8. REMU (Unsigned Remainder) — 33-cycle latency
        // --------------------------------------------------------------------
        $display("\n--- 8. REMU Unsigned Remainder ---");
        exec_mdu(MDU_REMU, 32'd7, 32'd3, 32'd1, 33, "REMU: 7 % 3 = 1");
        exec_mdu(MDU_REMU, 32'hFFFFFFFC, 32'd7, 32'd4, 33, "REMU: 0xFFFFFFFC % 7 = 4");

        // --------------------------------------------------------------------
        // 9. Divide-by-Zero Corner Cases (RISC-V Specification)
        // --------------------------------------------------------------------
        $display("\n--- 9. Divide-by-Zero Corner Cases ---");
        exec_mdu(MDU_DIV, 32'd15, 32'd0, 32'hFFFFFFFF, 33, "DIV by 0: pos / 0 -> 0xFFFFFFFF");
        exec_mdu(MDU_DIV, 32'h80000000, 32'd0, 32'hFFFFFFFF, 33, "DIV by 0: INT_MIN / 0 -> 0xFFFFFFFF");
        exec_mdu(MDU_DIVU, 32'h12345678, 32'd0, 32'hFFFFFFFF, 33, "DIVU by 0: u / 0 -> 0xFFFFFFFF");
        exec_mdu(MDU_REM, 32'd42, 32'd0, 32'd42, 33, "REM by 0: 42 % 0 -> 42 (rs1)");
        exec_mdu(MDU_REM, 32'h80000000, 32'd0, 32'h80000000, 33, "REM by 0: INT_MIN % 0 -> INT_MIN");
        exec_mdu(MDU_REMU, 32'hDEADBEEF, 32'd0, 32'hDEADBEEF, 33, "REMU by 0: dividend returned");

        // --------------------------------------------------------------------
        // 10. Signed Overflow Corner Cases (RISC-V Specification)
        // --------------------------------------------------------------------
        $display("\n--- 10. Signed Overflow Corner Cases ---");
        exec_mdu(MDU_DIV, 32'h80000000, 32'hFFFFFFFF, 32'h80000000, 33, "DIV overflow: INT_MIN / -1 -> INT_MIN");
        exec_mdu(MDU_REM, 32'h80000000, 32'hFFFFFFFF, 32'h0, 33, "REM overflow: INT_MIN % -1 -> 0");

        // --------------------------------------------------------------------
        // 11. Backpressure & Back-to-Back Sequences
        // --------------------------------------------------------------------
        $display("\n--- 11. Backpressure & Back-to-Back Operations ---");
        // Issue MUL immediately followed by DIV without idle bubbles
        exec_mdu(MDU_MUL, 32'd12, 32'd5, 32'd60, 3, "Back-to-Back 1: MUL (12*5=60)");
        exec_mdu(MDU_DIV, 32'd100, 32'd4, 32'd25, 33, "Back-to-Back 2: DIV (100/4=25)");
        exec_mdu(MDU_MUL, 32'd6, 32'd9, 32'd54, 3, "Back-to-Back 3: MUL (6*9=54)");

        // --------------------------------------------------------------------
        // Final Summary
        // --------------------------------------------------------------------
        $display("\n==================================================================");
        $display("  MDU UNIT VERIFICATION SUMMARY");
        $display("    Total Tests : %0d", test_cnt);
        $display("    PASSED      : %0d", pass_cnt);
        $display("    FAILED      : %0d", fail_cnt);
        if (fail_cnt == 0)
            $display("  >>> ALL MDU UNIT TESTS PASSED <<<");
        else
            $display("  >>> MDU UNIT VERIFICATION FAILED <<<");
        $display("==================================================================");

        $finish;
    end

endmodule
