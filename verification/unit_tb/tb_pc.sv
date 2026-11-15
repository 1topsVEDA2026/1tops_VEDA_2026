`timescale 1ns / 1ps
// ============================================================================
// tb_pc.sv — Phase-1 Unit-Level Program Counter (PC) Testbench (XSim-safe)
//
// Sign-off Criteria Verified:
//   - Parameterized RESET_PC (0x0000_0000 and 0x8000_0000)
//   - Redirect priority hierarchy: Trap > MRET > Branch/Jump > Sequential PC+4
//   - Pipeline stall freeze (!ready_IF / stall_IF)
//   - Jump target halfword/word alignment ({target[31:1], 1'b0})
//   - Comprehensive directed test suite and code/functional coverage
// ============================================================================

module tb_pc ();

    // Clock & Reset
    logic        clk;
    logic        rst_n;
    localparam CLK_PERIOD = 10;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // DUT Signals (Default RESET_PC = 0x0000_0000)
    logic        ready_IF;
    logic        trap_illegal;
    logic [31:0] mtvec_out;
    logic        is_mret_DE;
    logic        valid_DE;
    logic [31:0] epc_pc;
    logic        br_take_DE;
    logic [31:0] opr_res_DE;

    logic [31:0] pc_out_IF;
    logic [31:0] pc_next_IF;
    logic [31:0] nxt_pc;
    logic        epc_taken_IF;

    // DUT Instantiation (Default RESET_PC)
    pc_unit #(
        .RESET_PC(32'h0000_0000)
    ) u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .ready_IF     (ready_IF),
        .trap_illegal (trap_illegal),
        .mtvec_out    (mtvec_out),
        .is_mret_DE   (is_mret_DE),
        .valid_DE     (valid_DE),
        .epc_pc       (epc_pc),
        .br_take_DE   (br_take_DE),
        .opr_res_DE   (opr_res_DE),
        .pc_out_IF    (pc_out_IF),
        .pc_next_IF   (pc_next_IF),
        .nxt_pc       (nxt_pc),
        .epc_taken_IF (epc_taken_IF)
    );

    // Secondary DUT Instantiation with Alternate RESET_PC (0x8000_0000)
    logic [31:0] pc_out_alt, pc_next_alt, nxt_pc_alt;
    logic        epc_taken_alt;

    pc_unit #(
        .RESET_PC(32'h8000_0000)
    ) u_dut_alt (
        .clk          (clk),
        .rst_n        (rst_n),
        .ready_IF     (ready_IF),
        .trap_illegal (trap_illegal),
        .mtvec_out    (mtvec_out),
        .is_mret_DE   (is_mret_DE),
        .valid_DE     (valid_DE),
        .epc_pc       (epc_pc),
        .br_take_DE   (br_take_DE),
        .opr_res_DE   (opr_res_DE),
        .pc_out_IF    (pc_out_alt),
        .pc_next_IF   (pc_next_alt),
        .nxt_pc       (nxt_pc_alt),
        .epc_taken_IF (epc_taken_alt)
    );

    integer pass_cnt = 0, fail_cnt = 0, test_cnt = 0;

    // ========================================================================
    // COVERGROUP
    // ========================================================================
    covergroup cg_pc @(posedge clk);
        cp_ready: coverpoint ready_IF {
            bins active = {1'b1};
            bins stall  = {1'b0};
        }
        cp_trap: coverpoint trap_illegal {
            bins no_trap = {1'b0};
            bins trap    = {1'b1};
        }
        cp_mret: coverpoint is_mret_DE {
            bins no_mret = {1'b0};
            bins mret    = {1'b1};
        }
        cp_branch: coverpoint br_take_DE {
            bins no_br = {1'b0};
            bins br    = {1'b1};
        }
        cp_pc_val: coverpoint pc_out_IF {
            bins reset_zero = {32'h0000_0000};
            bins low_range  = {[32'h0000_0004 : 32'h0000_00FF]};
            bins mid_range  = {[32'h0000_1000 : 32'h0000_FFFF]};
            bins high_range = {[32'h8000_0000 : 32'h8000_FFFF]};
        }
        // Cross priorities
        cx_trap_br:   cross cp_trap, cp_branch;
        cx_trap_mret: cross cp_trap, cp_mret;
        cx_mret_br:   cross cp_mret, cp_branch;
    endgroup

    cg_pc cov = new();

    // ========================================================================
    // REFERENCE MODEL
    // ========================================================================
    function automatic logic [31:0] pc_ref(
        input logic        rdy,
        input logic        trap,
        input logic [31:0] mtvec,
        input logic        mret,
        input logic        v_de,
        input logic [31:0] epc,
        input logic        br,
        input logic [31:0] target,
        input logic [31:0] current_pc
    );
        logic epc_take;
        epc_take = trap & rdy;
        if (epc_take)
            return mtvec;
        else if (mret & v_de & rdy)
            return epc;
        else if (br & v_de & rdy)
            return {target[31:1], 1'b0};
        else
            return current_pc + 32'd4;
    endfunction

    // ========================================================================
    // CHECK TASKS
    // ========================================================================
    task automatic check_pc(input logic [31:0] exp_pc, input string desc);
        test_cnt++;
        if (pc_out_IF === exp_pc) begin
            pass_cnt++;
            $display("  [PASS] %-40s | got=0x%08H exp=0x%08H", desc, pc_out_IF, exp_pc);
        end else begin
            fail_cnt++;
            $display("  [FAIL] %-40s | got=0x%08H exp=0x%08H", desc, pc_out_IF, exp_pc);
        end
    endtask

    task automatic check_nxt(input logic [31:0] exp_nxt, input string desc);
        test_cnt++;
        if (nxt_pc === exp_nxt) begin
            pass_cnt++;
            $display("  [PASS] (Next-PC) %-31s | got=0x%08H exp=0x%08H", desc, nxt_pc, exp_nxt);
        end else begin
            fail_cnt++;
            $display("  [FAIL] (Next-PC) %-31s | got=0x%08H exp=0x%08H", desc, nxt_pc, exp_nxt);
        end
    endtask

    // ========================================================================
    // TEST SUITES
    // ========================================================================
    initial begin
        $display("==================================================================");
        $display("  tb_pc: Program Counter Unit Verification");
        $display("==================================================================");

        // Signal default initialization
        rst_n        = 0;
        ready_IF     = 1;
        trap_illegal = 0;
        mtvec_out    = 32'h0000_0000;
        is_mret_DE   = 0;
        valid_DE     = 0;
        epc_pc       = 32'h0000_0000;
        br_take_DE   = 0;
        opr_res_DE   = 32'h0000_0000;

        // --------------------------------------------------------------------
        // Test 1: Parameterized Reset Verification
        // --------------------------------------------------------------------
        $display("\n--- Test 1: Parameterized Reset Verification ---");
        repeat (3) @(posedge clk);
        #1;
        check_pc(32'h0000_0000, "Reset PC (Default = 0x0000_0000)");

        test_cnt++;
        if (pc_out_alt === 32'h8000_0000) begin
            pass_cnt++;
            $display("  [PASS] %-40s | got=0x%08H exp=0x%08H", "Reset PC (Param = 0x8000_0000)", pc_out_alt, 32'h8000_0000);
        end else begin
            fail_cnt++;
            $display("  [FAIL] %-40s | got=0x%08H exp=0x%08H", "Reset PC (Param = 0x8000_0000)", pc_out_alt, 32'h8000_0000);
        end

        // Deassert Reset
        @(negedge clk);
        rst_n = 1;

        // --------------------------------------------------------------------
        // Test 2: Sequential PC Fetch (+4 Each Cycle)
        // --------------------------------------------------------------------
        $display("\n--- Test 2: Sequential PC Fetch ---");
        @(posedge clk); #1; check_pc(32'h0000_0004, "Seq Step 1 (PC = 0x0004)");
        @(posedge clk); #1; check_pc(32'h0000_0008, "Seq Step 2 (PC = 0x0008)");
        @(posedge clk); #1; check_pc(32'h0000_000C, "Seq Step 3 (PC = 0x000C)");
        @(posedge clk); #1; check_pc(32'h0000_0010, "Seq Step 4 (PC = 0x0010)");

        // --------------------------------------------------------------------
        // Test 3: Pipeline Stall Hold (!ready_IF / stall_IF)
        // --------------------------------------------------------------------
        $display("\n--- Test 3: Pipeline Stall Hold ---");
        @(negedge clk);
        ready_IF = 0; // Assert stall
        @(posedge clk); #1; check_pc(32'h0000_0010, "Stall Cycle 1 (Hold 0x0010)");
        @(posedge clk); #1; check_pc(32'h0000_0010, "Stall Cycle 2 (Hold 0x0010)");
        @(negedge clk);
        ready_IF = 1; // Release stall
        @(posedge clk); #1; check_pc(32'h0000_0014, "Stall Release (Resume 0x0014)");

        // --------------------------------------------------------------------
        // Test 4: Branch / Jump Target Redirect
        // --------------------------------------------------------------------
        $display("\n--- Test 4: Branch / Jump Target Redirect ---");
        @(negedge clk);
        br_take_DE = 1;
        valid_DE   = 1;
        opr_res_DE = 32'h0000_1050;
        #1;
        check_nxt(32'h0000_1050, "Mux Select: Branch Target 0x1050");
        @(posedge clk); #1;
        check_pc(32'h0000_1050, "PC Updated to Branch Target 0x1050");

        // Test alignment enforcement: bit 0 cleared
        @(negedge clk);
        opr_res_DE = 32'h0000_2041; // Unaligned jump address
        #1;
        check_nxt(32'h0000_2040, "Alignment Check: Bit 0 Cleared (0x2040)");
        @(posedge clk); #1;
        check_pc(32'h0000_2040, "PC Updated to Aligned Address 0x2040");

        @(negedge clk);
        br_take_DE = 0;
        valid_DE   = 0;

        // --------------------------------------------------------------------
        // Test 5: MRET Context Restore Redirect
        // --------------------------------------------------------------------
        $display("\n--- Test 5: MRET Exception Return Redirect ---");
        @(negedge clk);
        is_mret_DE = 1;
        valid_DE   = 1;
        epc_pc     = 32'h0000_3080;
        #1;
        check_nxt(32'h0000_3080, "Mux Select: MRET Target epc_pc");
        @(posedge clk); #1;
        check_pc(32'h0000_3080, "PC Restored to epc_pc (0x3080)");

        @(negedge clk);
        is_mret_DE = 0;
        valid_DE   = 0;

        // --------------------------------------------------------------------
        // Test 6: Trap / Exception Vector Redirect
        // --------------------------------------------------------------------
        $display("\n--- Test 6: Trap Vector Redirect ---");
        @(negedge clk);
        trap_illegal = 1;
        mtvec_out    = 32'h0000_0100;
        #1;
        check_nxt(32'h0000_0100, "Mux Select: Trap mtvec_out (0x0100)");

        test_cnt++;
        if (epc_taken_IF === 1'b1) begin
            pass_cnt++;
            $display("  [PASS] epc_taken_IF Asserted on Active Trap");
        end else begin
            fail_cnt++;
            $display("  [FAIL] epc_taken_IF Not Asserted on Active Trap");
        end

        @(posedge clk); #1;
        check_pc(32'h0000_0100, "PC Jumped to Trap Handler mtvec (0x0100)");

        @(negedge clk);
        trap_illegal = 0;

        // --------------------------------------------------------------------
        // Test 7: Strict Redirect Priority Hierarchy
        //   Priority: Trap > MRET > Branch/Jump > Sequential
        // --------------------------------------------------------------------
        $display("\n--- Test 7: Redirect Priority Hierarchy ---");

        // Conflict 1: Trap vs Branch
        @(negedge clk);
        trap_illegal = 1;
        mtvec_out    = 32'h0000_0200;
        br_take_DE   = 1;
        valid_DE     = 1;
        opr_res_DE   = 32'h0000_9900;
        #1;
        check_nxt(32'h0000_0200, "Priority 1: Trap > Branch (mtvec selected)");
        @(posedge clk); #1;
        check_pc(32'h0000_0200, "PC Latched Trap Target over Branch");

        // Conflict 2: Trap vs MRET
        @(negedge clk);
        trap_illegal = 1;
        mtvec_out    = 32'h0000_0300;
        is_mret_DE   = 1;
        valid_DE     = 1;
        epc_pc       = 32'h0000_8800;
        br_take_DE   = 0;
        #1;
        check_nxt(32'h0000_0300, "Priority 2: Trap > MRET (mtvec selected)");
        @(posedge clk); #1;
        check_pc(32'h0000_0300, "PC Latched Trap Target over MRET");

        // Conflict 3: Trap vs MRET vs Branch (All Asserted)
        @(negedge clk);
        trap_illegal = 1;
        mtvec_out    = 32'h0000_0400;
        is_mret_DE   = 1;
        valid_DE     = 1;
        epc_pc       = 32'h0000_8800;
        br_take_DE   = 1;
        opr_res_DE   = 32'h0000_9900;
        #1;
        check_nxt(32'h0000_0400, "Priority 3: Trap > MRET > Branch (mtvec selected)");
        @(posedge clk); #1;
        check_pc(32'h0000_0400, "PC Latched Trap Target under Full Contention");

        // Conflict 4: MRET vs Branch
        @(negedge clk);
        trap_illegal = 0;
        is_mret_DE   = 1;
        valid_DE     = 1;
        epc_pc       = 32'h0000_5500;
        br_take_DE   = 1;
        opr_res_DE   = 32'h0000_6600;
        #1;
        check_nxt(32'h0000_5500, "Priority 4: MRET > Branch (epc selected)");
        @(posedge clk); #1;
        check_pc(32'h0000_5500, "PC Latched MRET Target over Branch");

        // Clear redirect signals
        @(negedge clk);
        is_mret_DE = 0;
        br_take_DE = 0;
        valid_DE   = 0;

        // Resume sequential after priority resolution
        @(posedge clk); #1;
        check_pc(32'h0000_5504, "Resume Sequential PC+4 (0x5504)");

        // --------------------------------------------------------------------
        // Test 8: High Memory Address Wrap & Corner Space
        // --------------------------------------------------------------------
        $display("\n--- Test 8: High Address Boundaries ---");
        @(negedge clk);
        br_take_DE = 1;
        valid_DE   = 1;
        opr_res_DE = 32'hFFFFFFFC;
        @(posedge clk); #1;
        check_pc(32'hFFFFFFFC, "Jump to Upper Boundary (0xFFFFFFFC)");

        @(negedge clk);
        br_take_DE = 0;
        valid_DE   = 0;
        @(posedge clk); #1;
        check_pc(32'h00000000, "Address Wrap-around to 0x00000000");

        // --------------------------------------------------------------------
        // Final Summary
        // --------------------------------------------------------------------
        $display("\n==================================================================");
        $display("  PC UNIT VERIFICATION SUMMARY");
        $display("    Total Tests : %0d", test_cnt);
        $display("    PASSED      : %0d", pass_cnt);
        $display("    FAILED      : %0d", fail_cnt);
        if (fail_cnt == 0)
            $display("  >>> ALL PC UNIT TESTS PASSED <<<");
        else
            $display("  >>> PC UNIT VERIFICATION FAILED <<<");
        $display("==================================================================");

        $finish;
    end

endmodule
