`timescale 1ns / 1ps
// ============================================================================
// rv32_core_sanity_tb.sv — Phase-2 Core Sanity Testbench (Self-Checking)
//
// Covers all RV32I + RV32M instruction verification requirements:
//   Suite  1:  Reset sequence (PC = 0x0)
//   Suite  2:  R-type ALU (ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND + FENCE)
//   Suite  3:  I-type ALU (ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI)
//   Suite  3b: Arithmetic Corner Cases (overflow/underflow/wrap/signed-unsigned)
//   Suite  4:  LUI / AUIPC
//   Suite  5:  JAL / JALR
//   Suite  6:  All Load/Store sizes (LB/LH/LW/LBU/LHU + SB/SH/SW)
//   Suite  7:  All Branch types (BEQ/BNE/BLT/BGE/BLTU/BGEU) taken + not-taken
//   Suite  8:  CSR Instructions (CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI)
//   Suite  9:  Trap Entry (ECALL/EBREAK -> trap_illegal) + MRET
//   Suite 10:  Data Hazards (RAW/WAW/WAR)
//   Suite 11:  Control Hazards (branch-after-branch, jump-after-branch)
//   Suite 12:  Load-Use Hazard (pipeline stall)
//   Suite 13:  Forwarding Stress (store-fwd, branch on forwarded value)
//   Suite 14:  Re-run under random-delay AXI4 READY
//   Suite 15:  M-Extension (MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU)
// ============================================================================
module rv32_core_sanity_tb
    import rv32_pkg::*;
();
    // ================================================================
    // Clock & Reset
    // ================================================================
    logic clk, rst_n;
    localparam CLK_PERIOD = 10;
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ================================================================
    // AXI4 DUT Signals — IMEM (AR + R, read-only)
    // ================================================================
    logic [31:0] imem_araddr;
    logic        imem_arvalid, imem_arready;
    logic [ 7:0] imem_arlen;
    logic [ 2:0] imem_arsize;
    logic [ 1:0] imem_arburst;
    logic [ 3:0] imem_arcache;
    logic [ 2:0] imem_arprot;
    logic        imem_arlock;
    logic [31:0] imem_rdata;
    logic        imem_rvalid, imem_rready;
    logic [ 1:0] imem_rresp;
    logic        imem_rlast;

    // ================================================================
    // AXI4 DUT Signals — DMEM (AW + W + B + AR + R)
    // ================================================================
    // AW
    logic [31:0] dmem_awaddr;
    logic        dmem_awvalid, dmem_awready;
    logic [ 7:0] dmem_awlen;
    logic [ 2:0] dmem_awsize;
    logic [ 1:0] dmem_awburst;
    logic [ 3:0] dmem_awcache;
    logic [ 2:0] dmem_awprot;
    logic        dmem_awlock;
    // W
    logic [31:0] dmem_wdata;
    logic [ 3:0] dmem_wstrb;
    logic        dmem_wvalid, dmem_wready, dmem_wlast;
    // B
    logic        dmem_bvalid, dmem_bready;
    logic [ 1:0] dmem_bresp;
    // AR
    logic [31:0] dmem_araddr;
    logic        dmem_arvalid, dmem_arready;
    logic [ 7:0] dmem_arlen;
    logic [ 2:0] dmem_arsize;
    logic [ 1:0] dmem_arburst;
    logic [ 3:0] dmem_arcache;
    logic [ 2:0] dmem_arprot;
    logic        dmem_arlock;
    // R
    logic [31:0] dmem_rdata;
    logic        dmem_rvalid, dmem_rready, dmem_rlast;
    logic [ 1:0] dmem_rresp;

    // Interrupts
    logic irq_external, irq_timer, irq_software;

    // ================================================================
    // DUT Instantiation
    // ================================================================
    rv32_core_top u_dut (
        .clk            (clk),
        .rst_n          (rst_n),
        // IMEM AR
        .imem_araddr    (imem_araddr),
        .imem_arvalid   (imem_arvalid),
        .imem_arready   (imem_arready),
        .imem_arlen     (imem_arlen),
        .imem_arsize    (imem_arsize),
        .imem_arburst   (imem_arburst),
        .imem_arcache   (imem_arcache),
        .imem_arprot    (imem_arprot),
        .imem_arlock    (imem_arlock),
        // IMEM R
        .imem_rdata     (imem_rdata),
        .imem_rvalid    (imem_rvalid),
        .imem_rready    (imem_rready),
        .imem_rresp     (imem_rresp),
        .imem_rlast     (imem_rlast),
        // DMEM AW
        .dmem_awaddr    (dmem_awaddr),
        .dmem_awvalid   (dmem_awvalid),
        .dmem_awready   (dmem_awready),
        .dmem_awlen     (dmem_awlen),
        .dmem_awsize    (dmem_awsize),
        .dmem_awburst   (dmem_awburst),
        .dmem_awcache   (dmem_awcache),
        .dmem_awprot    (dmem_awprot),
        .dmem_awlock    (dmem_awlock),
        // DMEM W
        .dmem_wdata     (dmem_wdata),
        .dmem_wstrb     (dmem_wstrb),
        .dmem_wvalid    (dmem_wvalid),
        .dmem_wlast     (dmem_wlast),
        .dmem_wready    (dmem_wready),
        // DMEM B
        .dmem_bvalid    (dmem_bvalid),
        .dmem_bresp     (dmem_bresp),
        .dmem_bready    (dmem_bready),
        // DMEM AR
        .dmem_araddr    (dmem_araddr),
        .dmem_arvalid   (dmem_arvalid),
        .dmem_arready   (dmem_arready),
        .dmem_arlen     (dmem_arlen),
        .dmem_arsize    (dmem_arsize),
        .dmem_arburst   (dmem_arburst),
        .dmem_arcache   (dmem_arcache),
        .dmem_arprot    (dmem_arprot),
        .dmem_arlock    (dmem_arlock),
        // DMEM R
        .dmem_rdata     (dmem_rdata),
        .dmem_rvalid    (dmem_rvalid),
        .dmem_rready    (dmem_rready),
        .dmem_rresp     (dmem_rresp),
        .dmem_rlast     (dmem_rlast),
        // IRQ
        .irq_external   (irq_external),
        .irq_timer      (irq_timer),
        .irq_software   (irq_software)
    );

    // ================================================================
    // AXI4 Memory Slaves
    // u_imem.mem[word_idx] and u_dmem.mem[byte_idx] for direct TB access
    // delay_en=0: zero-latency | delay_en=1: random 0-2 cycle READY delay
    // ================================================================
    logic axi_delay_en;
    initial axi_delay_en = 1'b0;

    axi4_imem_slave u_imem (
        .clk        (clk),
        .rst_n      (rst_n),
        .araddr     (imem_araddr),
        .arvalid    (imem_arvalid),
        .arready    (imem_arready),
        .arlen      (imem_arlen),
        .arsize     (imem_arsize),
        .arburst    (imem_arburst),
        .arcache    (imem_arcache),
        .arprot     (imem_arprot),
        .arlock     (imem_arlock),
        .rdata      (imem_rdata),
        .rvalid     (imem_rvalid),
        .rlast      (imem_rlast),
        .rresp      (imem_rresp),
        .rready     (imem_rready),
        .delay_en   (axi_delay_en)
    );

    axi4_dmem_slave u_dmem (
        .clk        (clk),
        .rst_n      (rst_n),
        .awaddr     (dmem_awaddr),
        .awvalid    (dmem_awvalid),
        .awready    (dmem_awready),
        .awlen      (dmem_awlen),
        .awsize     (dmem_awsize),
        .awburst    (dmem_awburst),
        .awcache    (dmem_awcache),
        .awprot     (dmem_awprot),
        .awlock     (dmem_awlock),
        .wdata      (dmem_wdata),
        .wstrb      (dmem_wstrb),
        .wvalid     (dmem_wvalid),
        .wlast      (dmem_wlast),
        .wready     (dmem_wready),
        .bvalid     (dmem_bvalid),
        .bresp      (dmem_bresp),
        .bready     (dmem_bready),
        .araddr     (dmem_araddr),
        .arvalid    (dmem_arvalid),
        .arready    (dmem_arready),
        .arlen      (dmem_arlen),
        .arsize     (dmem_arsize),
        .arburst    (dmem_arburst),
        .arcache    (dmem_arcache),
        .arprot     (dmem_arprot),
        .arlock     (dmem_arlock),
        .rdata      (dmem_rdata),
        .rvalid     (dmem_rvalid),
        .rlast      (dmem_rlast),
        .rresp      (dmem_rresp),
        .rready     (dmem_rready),
        .delay_en   (axi_delay_en)
    );

    // ================================================================
    // Handshake mode: 0=zero-latency, 1=random-delay AXI4 READY
    // ================================================================
    int handshake_mode = 0;
    always_comb axi_delay_en = (handshake_mode != 0);

    // ================================================================
    // Instruction Retirement Log
    // ================================================================
    localparam LOG_DEPTH = 4096;
    logic [31:0] ret_pc  [0:LOG_DEPTH-1];
    logic [ 4:0] ret_rd  [0:LOG_DEPTH-1];
    logic [31:0] ret_val [0:LOG_DEPTH-1];
    integer      retire_cnt;
    logic [31:0] retire_pc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            retire_cnt <= 0;
            retire_pc  <= 32'd0;
        end else begin
            if (u_dut.rf_en_MW && u_dut.rd_addr_MW != 5'd0) begin
                ret_pc [retire_cnt] <= u_dut.pc_out_MW;
                ret_rd [retire_cnt] <= u_dut.rd_addr_MW;
                ret_val[retire_cnt] <= u_dut.wdata;
                retire_cnt <= retire_cnt + 1;
                retire_pc  <= u_dut.pc_out_MW;
            end
            else if (u_dut.wr_en_MW) begin
                ret_pc [retire_cnt] <= u_dut.pc_out_MW;
                ret_rd [retire_cnt] <= 5'd0;
                ret_val[retire_cnt] <= u_dut.dmem_wdata;
                retire_cnt <= retire_cnt + 1;
                retire_pc  <= u_dut.pc_out_MW;
            end
            else if (u_dut.rd_en_MW) begin
                retire_cnt <= retire_cnt + 1;
                retire_pc  <= u_dut.pc_out_MW;
            end
        end
    end

    // ================================================================
    // Core Execution Log (Spike-compatible format)
    // ================================================================
    integer core_log_fd;
    logic   core_log_en;

    initial begin
        core_log_fd = $fopen("core_sanity_exec.log", "w");
        core_log_en = 0;
    end

    always_ff @(posedge clk) begin
        if (rst_n && core_log_en) begin
            if (u_dut.rf_en_MW && u_dut.rd_addr_MW != 5'd0) begin
                $fwrite(core_log_fd, "core 0: 0x%08h (0x%08h) x%0d 0x%08h\n",
                    u_dut.pc_out_MW,
                    u_imem.mem[u_dut.pc_out_MW[11:2]],
                    u_dut.rd_addr_MW,
                    u_dut.wdata);
            end
            else if (u_dut.wr_en_MW) begin
                $fwrite(core_log_fd, "core 0: 0x%08h (0x%08h) mem 0x%08h\n",
                    u_dut.pc_out_MW,
                    u_imem.mem[u_dut.pc_out_MW[11:2]],
                    u_dut.dmem_awaddr);  // AXI4: write address on AW channel
            end
        end
    end

    // ================================================================
    // Counters & Helpers
    // ================================================================
    integer pass_cnt, fail_cnt;
    integer suite_pass, suite_fail;

    // --- Suite Isolation ---
    // Each suite calls clear_mem() then do_reset() to guarantee a clean slate:
    //   clear_mem() : fills ALL imem with NOP (0x00000013), ALL dmem with 0x00
    //   do_reset()  : asserts rst_n=0 for 5 cycles → the RTL IF-stage resets
    //                 pc_out_IF to 0x00000000. After rst_n=1, PC starts at 0.
    // This means every suite begins execution from PC=0x0 with a fresh program.

    task automatic do_reset();
        irq_external = 0; irq_timer = 0; irq_software = 0;
        rst_n = 0;
        retire_cnt = 0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
    endtask

    task automatic clear_mem();
        for (int i = 0; i < 1024; i++) u_imem.mem[i] = 32'h0000_0013; // NOP
        for (int i = 0; i < 4096; i++) u_dmem.mem[i] = 8'h00;
    endtask

    task automatic suite_start(input string name);
        suite_pass = pass_cnt;
        suite_fail = fail_cnt;
        $display("\n========== %s ==========", name);
    endtask

    task automatic suite_end(input string name);
        integer sp, sf;
        sp = pass_cnt - suite_pass;
        sf = fail_cnt - suite_fail;
        $display("  [INFO] Retired %0d instructions, last PC = 0x%08H", retire_cnt, retire_pc);
        $display("  [%s] %s: %0d PASS, %0d FAIL",
                 (sf == 0) ? "PASS" : "FAIL", name, sp, sf);
    endtask

    // ---- Retirement-based register check ----
    task automatic check_reg(input int rn, input logic [31:0] exp, input string desc);
        integer i;
        logic found;
        logic [31:0] actual_val, actual_pc;

        if (rn == 0) begin
            if (u_dut.u_regfile.regs[0] === exp) begin
                $display("  [PASS] x0  = 0x%08H  (hardwired)  %s", u_dut.u_regfile.regs[0], desc);
                pass_cnt++;
            end else begin
                $display("  [FAIL] x0  = 0x%08H  (exp 0x%08H, hardwired)  %s", u_dut.u_regfile.regs[0], exp, desc);
                fail_cnt++;
            end
            return;
        end

        found = 0;
        for (i = retire_cnt - 1; i >= 0; i--) begin
            if (ret_rd[i] == rn) begin
                actual_val = ret_val[i];
                actual_pc  = ret_pc[i];
                found = 1;
                break;
            end
        end
        if (found) begin
            if (actual_val === exp) begin
                $display("  [PASS] x%-2d = 0x%08H  retired@PC=0x%04H  %s", rn, actual_val, actual_pc, desc);
                pass_cnt++;
            end else begin
                $display("  [FAIL] x%-2d = 0x%08H  (exp 0x%08H)  retired@PC=0x%04H  %s", rn, actual_val, exp, actual_pc, desc);
                fail_cnt++;
            end
        end else begin
            if (u_dut.u_regfile.regs[rn] === exp) begin
                $display("  [PASS] x%-2d = 0x%08H  (no retire, hw-check)  %s", rn, u_dut.u_regfile.regs[rn], desc);
                pass_cnt++;
            end else begin
                $display("  [FAIL] x%-2d = 0x%08H  (exp 0x%08H, never retired)  %s", rn, u_dut.u_regfile.regs[rn], exp, desc);
                fail_cnt++;
            end
        end
    endtask

    // ---- Memory check ----
    task automatic check_mem(input int addr, input logic [31:0] exp, input string desc);
        logic [31:0] act;
        act = {u_dmem.mem[addr+3], u_dmem.mem[addr+2], u_dmem.mem[addr+1], u_dmem.mem[addr]};
        if (act === exp) begin
            $display("  [PASS] MEM[0x%03H] = 0x%08H  %s", addr, act, desc);
            pass_cnt++;
        end else begin
            $display("  [FAIL] MEM[0x%03H] = 0x%08H  (exp 0x%08H)  %s", addr, act, exp, desc);
            fail_cnt++;
        end
    endtask

    // ---- Memory byte check ----
    task automatic check_mem_byte(input int addr, input logic [7:0] exp, input string desc);
        logic [7:0] act;
        act = u_dmem.mem[addr];
        if (act === exp) begin
            $display("  [PASS] MEM[0x%03H] = 0x%02H  %s", addr, act, desc);
            pass_cnt++;
        end else begin
            $display("  [FAIL] MEM[0x%03H] = 0x%02H  (exp 0x%02H)  %s", addr, act, exp, desc);
            fail_cnt++;
        end
    endtask

    // ---- Memory half check ----
    task automatic check_mem_half(input int addr, input logic [15:0] exp, input string desc);
        logic [15:0] act;
        act = {u_dmem.mem[addr+1], u_dmem.mem[addr]};
        if (act === exp) begin
            $display("  [PASS] MEM[0x%03H] = 0x%04H  %s", addr, act, desc);
            pass_cnt++;
        end else begin
            $display("  [FAIL] MEM[0x%03H] = 0x%04H  (exp 0x%04H)  %s", addr, act, exp, desc);
            fail_cnt++;
        end
    endtask

    // ---- CSR check (direct hierarchy access) ----
    task automatic check_csr(input string name, input logic [31:0] got, input logic [31:0] exp, input string desc);
        if (got === exp) begin
            $display("  [PASS] %s = 0x%08H  %s", name, got, desc);
            pass_cnt++;
        end else begin
            $display("  [FAIL] %s = 0x%08H  (exp 0x%08H)  %s", name, got, exp, desc);
            fail_cnt++;
        end
    endtask

    // ================================================================
    // Coverage Groups
    // ================================================================
    // Use combinational signals to avoid race condition with covergroup sampling
    logic [6:0] retired_opcode;
    logic [2:0] retired_funct3;
    logic       retire_valid;

    // Track MW-stage PC changes to detect ALL instruction completions,
    // including no-writeback instructions like FENCE (EXEC_NOP) which
    // don't trigger rf_en_MW / wr_en_MW / rd_en_MW.
    logic [31:0] prev_pc_MW;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) prev_pc_MW <= 32'hFFFFFFFF;
        else        prev_pc_MW <= u_dut.pc_out_MW;
    end

    assign retire_valid   = rst_n && (u_dut.rf_en_MW || u_dut.wr_en_MW || u_dut.rd_en_MW
                                      || (u_dut.pc_out_MW != prev_pc_MW));
    assign retired_opcode = u_imem.mem[u_dut.pc_out_MW[11:2]][6:0];
    assign retired_funct3 = u_imem.mem[u_dut.pc_out_MW[11:2]][14:12];

    covergroup cg_opcode @(posedge clk);
        cp_opcode: coverpoint retired_opcode iff (retire_valid) {
            bins r_type  = {7'b0110011}; // covers both ALU and MDU (disambiguated by funct7)
            bins i_alu   = {7'b0010011};
            bins load    = {7'b0000011};
            bins store   = {7'b0100011};
            bins branch  = {7'b1100011};
            bins jal     = {7'b1101111};
            bins jalr    = {7'b1100111};
            bins lui     = {7'b0110111};
            bins auipc   = {7'b0010111};
            bins system  = {7'b1110011};
            bins fence   = {7'b0001111};
        }
        cp_load_size: coverpoint retired_funct3 iff (retire_valid && retired_opcode == 7'b0000011) {
            bins lb  = {3'b000};
            bins lh  = {3'b001};
            bins lw  = {3'b010};
            bins lbu = {3'b100};
            bins lhu = {3'b101};
        }
        cp_store_size: coverpoint retired_funct3 iff (retire_valid && retired_opcode == 7'b0100011) {
            bins sb = {3'b000};
            bins sh = {3'b001};
            bins sw = {3'b010};
        }
        cp_branch_type: coverpoint retired_funct3 iff (retire_valid && retired_opcode == 7'b1100011) {
            bins beq  = {3'b000};
            bins bne  = {3'b001};
            bins blt  = {3'b100};
            bins bge  = {3'b101};
            bins bltu = {3'b110};
            bins bgeu = {3'b111};
        }
    endgroup

    // ---- M-extension dedicated coverage ----
    // retired_funct7: top 7 bits of the retired instruction word
    logic [6:0] retired_funct7;
    assign retired_funct7 = u_imem.mem[u_dut.pc_out_MW[11:2]][31:25];

    covergroup cg_mext @(posedge clk);
        cp_mdu_op: coverpoint retired_funct3
            iff (retire_valid && retired_opcode == 7'b0110011 && retired_funct7 == 7'b0000001) {
            bins mul    = {3'b000};
            bins mulh   = {3'b001};
            bins mulhsu = {3'b010};
            bins mulhu  = {3'b011};
            bins div    = {3'b100};
            bins divu   = {3'b101};
            bins rem    = {3'b110};
            bins remu   = {3'b111};
        }
    endgroup

    cg_opcode cov_op  = new();
    cg_mext   cov_mex = new();

    // ================================================================
    // SUITE 1: Reset Sequence
    // ================================================================
    task automatic run_suite1_reset();
        suite_start("SUITE 1: Reset Sequence");
        clear_mem(); do_reset();
        // After reset, PC should be 0x00000000
        if (u_dut.pc_out_IF === 32'h0000_0000) begin
            $display("  [PASS] PC after reset = 0x%08H", u_dut.pc_out_IF);
            pass_cnt++;
        end else begin
            $display("  [FAIL] PC after reset = 0x%08H (exp 0x00000000)", u_dut.pc_out_IF);
            fail_cnt++;
        end
        // First imem_addr should be 0
        if (imem_addr === 32'h0000_0000) begin
            $display("  [PASS] First fetch address = 0x%08H", imem_addr);
            pass_cnt++;
        end else begin
            $display("  [FAIL] First fetch address = 0x%08H (exp 0x00000000)", imem_addr);
            fail_cnt++;
        end
        // x0 should be 0
        check_reg(0, 32'd0, "x0 hardwired after reset");
        suite_end("SUITE 1");
    endtask

    // ================================================================
    // SUITE 2: R-type ALU
    // Encodes all 10 R-type ops, stores results to memory, checks
    // ================================================================
    task automatic run_suite2_rtype();
        suite_start("SUITE 2: R-type ALU");
        clear_mem(); do_reset();
        // x1 = 7, x2 = 3, x3 = -4 (0xFFFFFFFC)
        u_imem.mem[0]  = 32'h00700093; // ADDI x1, x0, 7
        u_imem.mem[1]  = 32'h00300113; // ADDI x2, x0, 3
        u_imem.mem[2]  = 32'hFFC00193; // ADDI x3, x0, -4
        u_imem.mem[3]  = 32'h00000013; // NOP (pipeline settle)
        // R-type operations
        u_imem.mem[4]  = 32'h00208233; // ADD  x4, x1, x2     -> 10
        u_imem.mem[5]  = 32'h402082B3; // SUB  x5, x1, x2     -> 4
        u_imem.mem[6]  = 32'h00209333; // SLL  x6, x1, x2     -> 56 (7<<3)
        u_imem.mem[7]  = 32'h0031A3B3; // SLT  x7, x3, x3     -> 0  (-4<-4 is false)
        u_imem.mem[8]  = 32'h0010A3B3; // SLT  x7, x1, x1     -> 0  (7<7 false, overwrite)
        // Actually test: SLT x7, x3, x1 -> 1 (-4 < 7)
        u_imem.mem[7]  = 32'h0011A3B3; // SLT  x7, x3, x1     -> 1
        u_imem.mem[8]  = 32'h0020B433; // SLTU x8, x1, x2     -> 0  (7 < 3 unsigned = false)
        u_imem.mem[9]  = 32'h0020C4B3; // XOR  x9, x1, x2     -> 4
        u_imem.mem[10] = 32'h0020D533; // SRL  x10, x1, x2    -> 0  (7>>3)
        u_imem.mem[11] = 32'h4021D5B3; // SRA  x11, x3, x2    -> -1 (0xFFFFFFFF)
        u_imem.mem[12] = 32'h0020E633; // OR   x12, x1, x2    -> 7
        u_imem.mem[13] = 32'h0FF0000F; // FENCE (iorw, iorw) — treated as NOP by this core
        u_imem.mem[14] = 32'h0020F6B3; // AND  x13, x1, x2    -> 3
        u_imem.mem[15] = 32'h00000013; // NOP
        u_imem.mem[16] = 32'hFFDFF06F; // JAL x0, -4 (spin)
        repeat (60) @(posedge clk);
        check_reg(4,  32'd10,         "ADD: 7+3=10");
        check_reg(5,  32'd4,          "SUB: 7-3=4");
        check_reg(6,  32'd56,         "SLL: 7<<3=56");
        check_reg(7,  32'd1,          "SLT: -4<7=1");
        check_reg(8,  32'd0,          "SLTU: 7<3=0 (unsigned)");
        check_reg(9,  32'd4,          "XOR: 7^3=4");
        check_reg(10, 32'd0,          "SRL: 7>>3=0");
        check_reg(11, 32'hFFFFFFFF,   "SRA: -4>>>3=-1");
        check_reg(12, 32'd7,          "OR:  7|3=7");
        check_reg(13, 32'd3,          "AND: 7&3=3 (FENCE between OR and AND)");
        suite_end("SUITE 2");
    endtask

    // ================================================================
    // SUITE 3: I-type ALU
    // ================================================================
    task automatic run_suite3_itype();
        suite_start("SUITE 3: I-type ALU");
        clear_mem(); do_reset();
        // x1 = 7, x2 = -4
        u_imem.mem[0]  = 32'h00700093; // ADDI x1, x0, 7
        u_imem.mem[1]  = 32'hFFC00113; // ADDI x2, x0, -4
        u_imem.mem[2]  = 32'h00000013; // NOP
        // I-type ALU ops on x1
        u_imem.mem[3]  = 32'h00A08193; // ADDI  x3, x1, 10     -> 17
        u_imem.mem[4]  = 32'h0000A213; // SLTI  x4, x1, 0      -> 0  (7<0=false)
        u_imem.mem[5]  = 32'h0080A293; // SLTI  x5, x1, 8      -> 1  (7<8=true)
        u_imem.mem[6]  = 32'h0080B313; // SLTIU x6, x1, 8      -> 1  (7<8 unsigned)
        u_imem.mem[7]  = 32'h00F0C393; // XORI  x7, x1, 15     -> 8  (7^15=8)
        u_imem.mem[8]  = 32'h0300E413; // ORI   x8, x1, 48     -> 55 (7|48=55)
        u_imem.mem[9]  = 32'h0030F493; // ANDI  x9, x1, 3      -> 3  (7&3=3)
        u_imem.mem[10] = 32'h00209513; // SLLI  x10, x1, 2     -> 28 (7<<2)
        u_imem.mem[11] = 32'h0020D593; // SRLI  x11, x1, 2     -> 1  (7>>2)
        u_imem.mem[12] = 32'h40215613; // SRAI  x12, x2, 2     -> -1 (-4>>>2)
        u_imem.mem[13] = 32'h00000013; // NOP
        u_imem.mem[14] = 32'hFFDFF06F; // spin
        repeat (60) @(posedge clk);
        check_reg(3,  32'd17,         "ADDI: 7+10=17");
        check_reg(4,  32'd0,          "SLTI: 7<0=0");
        check_reg(5,  32'd1,          "SLTI: 7<8=1");
        check_reg(6,  32'd1,          "SLTIU: 7<8=1 (unsigned)");
        check_reg(7,  32'd8,          "XORI: 7^15=8");
        check_reg(8,  32'd55,         "ORI:  7|48=55");
        check_reg(9,  32'd3,          "ANDI: 7&3=3");
        check_reg(10, 32'd28,         "SLLI: 7<<2=28");
        check_reg(11, 32'd1,          "SRLI: 7>>2=1");
        check_reg(12, 32'hFFFFFFFF,   "SRAI: -4>>>2=-1");
        suite_end("SUITE 3");
    endtask

    // ================================================================
    // SUITE 3b: Arithmetic Corner Cases
    //   Overflow, underflow, wrap-around, signed/unsigned boundaries,
    //   shift edge values — all cases where RV32I wraps silently.
    // ================================================================
    task automatic run_suite3b_corner_cases();
        suite_start("SUITE 3b: Arithmetic Corner Cases");
        clear_mem(); do_reset();

        // ---- Setup: load boundary constants ----
        // x1 = 0x80000000 (MIN_NEG / INT32_MIN)
        u_imem.mem[0]  = 32'h800000B7; // LUI  x1, 0x80000      -> x1 = 0x80000000
        // x2 = 0x7FFFFFFF (MAX_POS / INT32_MAX)
        u_imem.mem[1]  = 32'hFFF08113; // ADDI x2, x1, -1       -> x2 = 0x7FFFFFFF
        // x3 = 1
        u_imem.mem[2]  = 32'h00100193; // ADDI x3, x0, 1        -> x3 = 1
        // x4 = -1 (0xFFFFFFFF)
        u_imem.mem[3]  = 32'hFFF00213; // ADDI x4, x0, -1       -> x4 = 0xFFFFFFFF
        u_imem.mem[4]  = 32'h00000013; // NOP (pipeline settle)

        // ---- ADD overflow / wrap-around ----
        // MAX_POS + 1 = 0x80000000 (signed overflow)
        u_imem.mem[5]  = 32'h003102B3; // ADD  x5, x2, x3       -> 0x7FFFFFFF + 1 = 0x80000000

        // 0xFFFFFFFF + 1 = 0x00000000 (unsigned wrap)
        u_imem.mem[6]  = 32'h00320333; // ADD  x6, x4, x3       -> 0xFFFFFFFF + 1 = 0x00000000

        // MIN_NEG + MIN_NEG = 0x00000000 (negative overflow)
        u_imem.mem[7]  = 32'h001083B3; // ADD  x7, x1, x1       -> 0x80000000 + 0x80000000 = 0x0

        // ---- SUB underflow / wrap-around ----
        // MIN_NEG - 1 = 0x7FFFFFFF (signed underflow)
        u_imem.mem[8]  = 32'h40308433; // SUB  x8, x1, x3       -> 0x80000000 - 1 = 0x7FFFFFFF

        // 0 - 1 = 0xFFFFFFFF (unsigned wrap)
        u_imem.mem[9]  = 32'h403004B3; // SUB  x9, x0, x3       -> 0 - 1 = 0xFFFFFFFF

        // MAX_POS - MIN_NEG = 0xFFFFFFFF (overflow)
        u_imem.mem[10] = 32'h40110533; // SUB  x10, x2, x1      -> 0x7FFFFFFF - 0x80000000 = 0xFFFFFFFF

        // ---- ADDI overflow ----
        // MAX_POS + 1 (immediate) = 0x80000000
        u_imem.mem[11] = 32'h00110593; // ADDI x11, x2, 1       -> 0x7FFFFFFF + 1 = 0x80000000

        // 0 + (-2048) = 0xFFFFF800 (min negative immediate)
        u_imem.mem[12] = 32'h80000613; // ADDI x12, x0, -2048   -> 0xFFFFF800

        // ---- SLT vs SLTU: signed/unsigned comparison edges ----
        // SLT: -1 < MAX_POS (signed) -> 1
        u_imem.mem[13] = 32'h002226B3; // SLT  x13, x4, x2     -> (-1 < 0x7FFFFFFF) = 1

        // SLTU: MAX_POS < 0xFFFFFFFF (unsigned) -> 1
        u_imem.mem[14] = 32'h00413733; // SLTU x14, x2, x4     -> (0x7FFFFFFF < 0xFFFFFFFF) = 1

        // SLT: MIN_NEG < -1 (signed) -> 1
        u_imem.mem[15] = 32'h0040A7B3; // SLT  x15, x1, x4     -> (-2147483648 < -1) = 1

        // SLTU: 0xFFFFFFFF < 0x80000000 (unsigned) -> 0
        u_imem.mem[16] = 32'h00123833; // SLTU x16, x4, x1     -> (0xFFFFFFFF < 0x80000000) = 0

        // SLTU: 0 < 1 (unsigned) -> 1  (SNEZ pattern)
        u_imem.mem[17] = 32'h003038B3; // SLTU x17, x0, x3     -> (0 < 1) = 1

        // ---- Shift edge cases ----
        // SLL by 31: 1 << 31 = 0x80000000
        u_imem.mem[18] = 32'h01F19913; // SLLI x18, x3, 31     -> 1 << 31 = 0x80000000

        // SRL by 31: 0x80000000 >> 31 = 1 (logical, no sign-ext)
        u_imem.mem[19] = 32'h01F0D993; // SRLI x19, x1, 31     -> 0x80000000 >> 31 = 1

        // SRA by 31: 0x80000000 >>> 31 = 0xFFFFFFFF (arithmetic, sign-extended)
        u_imem.mem[20] = 32'h41F0DA13; // SRAI x20, x1, 31     -> 0x80000000 >>> 31 = 0xFFFFFFFF

        // SRA by 5: -1 >>> 5 = -1 (all-ones stays all-ones)
        u_imem.mem[21] = 32'h40525A93; // SRAI x21, x4, 5      -> 0xFFFFFFFF >>> 5 = 0xFFFFFFFF

        // SLL by 0: no shift, value unchanged
        u_imem.mem[22] = 32'h00011B13; // SLLI x22, x2, 0      -> 0x7FFFFFFF << 0 = 0x7FFFFFFF

        // ---- SLTIU boundary ----
        // SLTIU x23, x4, 1: (0xFFFFFFFF < 1 unsigned) -> 0
        u_imem.mem[23] = 32'h00123B93; // SLTIU x23, x4, 1     -> 0

        // SLTIU x24, x0, 1: (0 < 1 unsigned) -> 1  (SEQZ pattern)
        u_imem.mem[24] = 32'h00103C13; // SLTIU x24, x0, 1     -> 1

        u_imem.mem[25] = 32'h00000013; // NOP
        u_imem.mem[26] = 32'hFFDFF06F; // spin

        repeat (80) @(posedge clk);

        // ADD overflow/wrap
        check_reg(5,  32'h80000000, "ADD overflow: MAX_POS+1 = MIN_NEG");
        check_reg(6,  32'h00000000, "ADD wrap: 0xFFFFFFFF+1 = 0");
        check_reg(7,  32'h00000000, "ADD neg overflow: MIN_NEG+MIN_NEG = 0");

        // SUB underflow/wrap
        check_reg(8,  32'h7FFFFFFF, "SUB underflow: MIN_NEG-1 = MAX_POS");
        check_reg(9,  32'hFFFFFFFF, "SUB wrap: 0-1 = 0xFFFFFFFF");
        check_reg(10, 32'hFFFFFFFF, "SUB overflow: MAX_POS-MIN_NEG = -1");

        // ADDI overflow
        check_reg(11, 32'h80000000, "ADDI overflow: MAX_POS+1 = MIN_NEG");
        check_reg(12, 32'hFFFFF800, "ADDI min imm: 0+(-2048) = 0xFFFFF800");

        // Signed vs unsigned comparison edges
        check_reg(13, 32'd1,        "SLT: -1 < MAX_POS (signed) = 1");
        check_reg(14, 32'd1,        "SLTU: MAX_POS < 0xFFFFFFFF (unsigned) = 1");
        check_reg(15, 32'd1,        "SLT: MIN_NEG < -1 (signed) = 1");
        check_reg(16, 32'd0,        "SLTU: 0xFFFFFFFF < MIN_NEG (unsigned) = 0");
        check_reg(17, 32'd1,        "SLTU: 0 < 1 (SNEZ pattern) = 1");

        // Shift edge cases
        check_reg(18, 32'h80000000, "SLLI: 1<<31 = 0x80000000");
        check_reg(19, 32'h00000001, "SRLI: 0x80000000>>31 = 1 (logical)");
        check_reg(20, 32'hFFFFFFFF, "SRAI: 0x80000000>>>31 = 0xFFFFFFFF (arithmetic)");
        check_reg(21, 32'hFFFFFFFF, "SRAI: -1>>>5 = -1 (all-ones preserved)");
        check_reg(22, 32'h7FFFFFFF, "SLLI: MAX_POS<<0 = MAX_POS (no shift)");

        // SLTIU boundary
        check_reg(23, 32'd0,        "SLTIU: 0xFFFFFFFF < 1 (unsigned) = 0");
        check_reg(24, 32'd1,        "SLTIU: 0 < 1 (SEQZ pattern) = 1");

        suite_end("SUITE 3b");
    endtask

    // ================================================================
    // SUITE 4: LUI / AUIPC
    // ================================================================
    task automatic run_suite4_lui_auipc();
        suite_start("SUITE 4: LUI / AUIPC");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'hABCDE0B7; // LUI   x1, 0xABCDE    -> 0xABCDE000
        u_imem.mem[1] = 32'h00001117; // AUIPC x2, 1           -> PC(4)+0x1000=0x1004
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'hFFDFF06F; // spin
        repeat (30) @(posedge clk);
        check_reg(1, 32'hABCDE000, "LUI: 0xABCDE000");
        check_reg(2, 32'h00001004, "AUIPC: PC(4)+0x1000");
        suite_end("SUITE 4");
    endtask

    // ================================================================
    // SUITE 5: JAL / JALR
    // ================================================================
    task automatic run_suite5_jal_jalr();
        suite_start("SUITE 5: JAL / JALR");
        clear_mem(); do_reset();
        // Addr 0x00: JAL x1, +8    -> x1 = 0x04 (return addr), jump to 0x08
        // Addr 0x04: ADDI x3, x0, 99 (should be skipped by JAL)
        // Addr 0x08: ADDI x4, x0, 1  (landed here from JAL)
        // Addr 0x0C: AUIPC x5, 0     -> x5 = 0x0C
        // Addr 0x10: JALR x2, x5, 12 -> x2 = 0x14, jump to x5+12=0x18
        // Addr 0x14: ADDI x7, x0, 77 (should be skipped by JALR)
        // Addr 0x18: ADDI x6, x0, 1  (landed here from JALR)
        u_imem.mem[0] = 32'h008000EF; // JAL  x1, +8
        u_imem.mem[1] = 32'h06300193; // ADDI x3, x0, 99 (skipped by JAL)
        u_imem.mem[2] = 32'h00100213; // ADDI x4, x0, 1  (JAL target)
        u_imem.mem[3] = 32'h00000297; // AUIPC x5, 0      -> x5=0x0C
        u_imem.mem[4] = 32'h00C28167; // JALR x2, x5, 12  -> jump to 0x18, x2=0x14
        u_imem.mem[5] = 32'h04D00393; // ADDI x7, x0, 77 (skipped by JALR)
        u_imem.mem[6] = 32'h00100313; // ADDI x6, x0, 1  (JALR target)
        u_imem.mem[7] = 32'h00000013; // NOP
        u_imem.mem[8] = 32'hFFDFF06F; // spin
        repeat (40) @(posedge clk);
        check_reg(1, 32'h04,   "JAL: link address x1=0x04");
        check_reg(4, 32'd1,    "JAL: landed at target (x4=1)");
        check_reg(2, 32'h14,   "JALR: link address x2=0x14");
        check_reg(6, 32'd1,    "JALR: landed at target (x6=1)");
        check_reg(3, 32'd0,    "JAL: skipped instruction (x3=0)");
        check_reg(7, 32'd0,    "JALR: skipped instruction (x7=0)");
        suite_end("SUITE 5");
    endtask

    // ================================================================
    // SUITE 6: All Load/Store Sizes
    // ================================================================
    task automatic run_suite6_load_store();
        suite_start("SUITE 6: All Load/Store Sizes");
        clear_mem(); do_reset();

        // Pre-load memory with known pattern for load tests
        // MEM[0x100..0x103] = 0xDEAD_BEEF (little-endian: EF BE AD DE)
        u_dmem.mem[256] = 8'hEF;
        u_dmem.mem[257] = 8'hBE;
        u_dmem.mem[258] = 8'hAD;
        u_dmem.mem[259] = 8'hDE;

        // x1 = 0x100 (base address for loads)
        u_imem.mem[0]  = 32'h10000093; // ADDI x1, x0, 0x100

        // ---- Loads from MEM[0x100] = 0xDEADBEEF ----
        u_imem.mem[1]  = 32'h00000013; // NOP
        u_imem.mem[2]  = 32'h0000A103; // LW  x2, 0(x1)       -> 0xDEADBEEF
        u_imem.mem[3]  = 32'h00000013; // NOP
        u_imem.mem[4]  = 32'h00009183; // LH  x3, 0(x1)       -> 0xFFFFBEEF (sign-ext)
        u_imem.mem[5]  = 32'h00000013; // NOP
        u_imem.mem[6]  = 32'h0000D203; // LHU x4, 0(x1)       -> 0x0000BEEF (zero-ext)
        u_imem.mem[7]  = 32'h00000013; // NOP
        u_imem.mem[8]  = 32'h00008283; // LB  x5, 0(x1)       -> 0xFFFFFFEF (sign-ext)
        u_imem.mem[9]  = 32'h00000013; // NOP
        u_imem.mem[10] = 32'h0000C303; // LBU x6, 0(x1)       -> 0x000000EF (zero-ext)
        u_imem.mem[11] = 32'h00000013; // NOP

        // Load from offset +1 byte (addr 0x101): byte = 0xBE
        u_imem.mem[12] = 32'h00108383; // LB  x7, 1(x1)       -> 0xFFFFFFBE (sign-ext)
        u_imem.mem[13] = 32'h00000013; // NOP
        // Load from offset +2 half (addr 0x102): half = 0xDEAD
        u_imem.mem[14] = 32'h00209403; // LH  x8, 2(x1)       -> 0xFFFFDEAD (sign-ext)
        u_imem.mem[15] = 32'h00000013; // NOP

        // ---- Stores: write known values to MEM[0x200..] ----
        // x10 = 0x200 (store base), x11 = 0x12345678
        u_imem.mem[16] = 32'h20000513; // ADDI x10, x0, 0x200
        u_imem.mem[17] = 32'h12345637; // LUI  x12, 0x12345    -> 0x12345000
        u_imem.mem[18] = 32'h67860613; // ADDI x12, x12, 0x678 -> 0x12345678
        u_imem.mem[19] = 32'h00000013; // NOP

        // SW: store word at MEM[0x200]
        u_imem.mem[20] = 32'h00C52023; // SW x12, 0(x10)       -> MEM[0x200]=0x12345678
        u_imem.mem[21] = 32'h00000013; // NOP

        // SH: store half at MEM[0x210]
        u_imem.mem[22] = 32'h00C51823; // SH x12, 16(x10)      -> MEM[0x210]=0x5678
        u_imem.mem[23] = 32'h00000013; // NOP

        // SB: store byte at MEM[0x220]
        u_imem.mem[24] = 32'h02C50023; // SB x12, 32(x10)      -> MEM[0x220]=0x78
        u_imem.mem[25] = 32'h00000013; // NOP
        u_imem.mem[26] = 32'hFFDFF06F; // spin

        repeat (100) @(posedge clk);

        // Load checks
        check_reg(2, 32'hDEADBEEF,   "LW:  MEM[0x100] = 0xDEADBEEF");
        check_reg(3, 32'hFFFFBEEF,   "LH:  sign-ext 0xBEEF -> 0xFFFFBEEF");
        check_reg(4, 32'h0000BEEF,   "LHU: zero-ext 0xBEEF -> 0x0000BEEF");
        check_reg(5, 32'hFFFFFFEF,   "LB:  sign-ext 0xEF -> 0xFFFFFFEF");
        check_reg(6, 32'h000000EF,   "LBU: zero-ext 0xEF -> 0x000000EF");
        check_reg(7, 32'hFFFFFFBE,   "LB@+1: sign-ext 0xBE -> 0xFFFFFFBE");
        check_reg(8, 32'hFFFFDEAD,   "LH@+2: sign-ext 0xDEAD -> 0xFFFFDEAD");

        // Store checks
        check_mem(32'h200, 32'h12345678, "SW: MEM[0x200]=0x12345678");
        check_mem_half(32'h210, 16'h5678, "SH: MEM[0x210]=0x5678");
        check_mem_byte(32'h220, 8'h78,    "SB: MEM[0x220]=0x78");
        suite_end("SUITE 6");
    endtask

    // ================================================================
    // SUITE 7: All Branch Types (taken + not-taken)
    // ================================================================
    task automatic run_suite7_branches();
        suite_start("SUITE 7: All Branch Types");
        clear_mem(); do_reset();
        // Setup:  x1=5, x2=5, x3=3, x4=-1 (0xFFFFFFFF)
        u_imem.mem[0]  = 32'h00500093; // ADDI x1, x0, 5
        u_imem.mem[1]  = 32'h00500113; // ADDI x2, x0, 5
        u_imem.mem[2]  = 32'h00300193; // ADDI x3, x0, 3
        u_imem.mem[3]  = 32'hFFF00213; // ADDI x4, x0, -1
        u_imem.mem[4]  = 32'h00000013; // NOP (pipeline settle)

        // --- BEQ taken: x1==x2, skip to +8 (PC+8) ---
        // PC=0x14: BEQ x1,x2,+8 → taken → skip mem[6], land at mem[7]
        u_imem.mem[5]  = 32'h00208463; // BEQ x1, x2, +8
        u_imem.mem[6]  = 32'h00100293; // ADDI x5, x0, 1 (skipped if taken)
        u_imem.mem[7]  = 32'h00000013; // NOP (landed here)

        // --- BNE not-taken: x1==x2 → not taken ---
        u_imem.mem[8]  = 32'h00209463; // BNE x1, x2, +8
        u_imem.mem[9]  = 32'h00100313; // ADDI x6, x0, 1 (NOT skipped, BNE not taken)
        u_imem.mem[10] = 32'h00000013; // NOP

        // --- BLT taken: x4(-1) < x1(5) signed ---
        u_imem.mem[11] = 32'h00124463; // BLT x4, x1, +8
        u_imem.mem[12] = 32'h00100393; // ADDI x7, x0, 1 (skipped if taken)
        u_imem.mem[13] = 32'h00000013; // NOP

        // --- BGE taken: x1(5) >= x3(3) signed ---
        u_imem.mem[14] = 32'h0030D463; // BGE x1, x3, +8
        u_imem.mem[15] = 32'h00100413; // ADDI x8, x0, 1 (skipped if taken)
        u_imem.mem[16] = 32'h00000013; // NOP

        // --- BLTU not-taken: x1(5) < x3(3) unsigned → false ---
        u_imem.mem[17] = 32'h0030E463; // BLTU x1, x3, +8
        u_imem.mem[18] = 32'h00100493; // ADDI x9, x0, 1 (NOT skipped, BLTU not taken)
        u_imem.mem[19] = 32'h00000013; // NOP

        // --- BGEU taken: x4(0xFFFFFFFF) >= x1(5) unsigned ---
        u_imem.mem[20] = 32'h0012F463; // BGEU x4, x1, +8   (adjusted: x4 >= x1 unsigned → true since x4=0xFFFFFFFF)
        // fix: BGEU uses funct3=111, opcode 1100011
        u_imem.mem[20] = {7'b0000000, 5'd1, 5'd4, 3'b111, 5'b01000, 7'b1100011}; // BGEU x4, x1, +8
        u_imem.mem[21] = 32'h00100513; // ADDI x10, x0, 1 (skipped if taken)
        u_imem.mem[22] = 32'h00000013; // NOP
        u_imem.mem[23] = 32'hFFDFF06F; // spin

        repeat (80) @(posedge clk);
        check_reg(5,  32'd0, "BEQ taken: skipped instruction x5=0");
        check_reg(6,  32'd1, "BNE not-taken: executed x6=1");
        check_reg(7,  32'd0, "BLT taken: skipped instruction x7=0");
        check_reg(8,  32'd0, "BGE taken: skipped instruction x8=0");
        check_reg(9,  32'd1, "BLTU not-taken: executed x9=1");
        check_reg(10, 32'd0, "BGEU taken: skipped instruction x10=0");
        suite_end("SUITE 7");
    endtask

    // ================================================================
    // SUITE 8: CSR Instructions
    // ================================================================
    task automatic run_suite8_csr();
        suite_start("SUITE 8: CSR Instructions");
        clear_mem(); do_reset();
        // Test CSRRW, CSRRS, CSRRC on mscratch (0x340)
        // Test CSRRWI, CSRRSI, CSRRCI on mscratch
        // x1 = 0x55
        u_imem.mem[0]  = 32'h05500093; // ADDI x1, x0, 0x55

        u_imem.mem[1]  = 32'h00000013; // NOP

        // CSRRW mscratch, x1 → x2 = old mscratch (0), mscratch = 0x55
        u_imem.mem[2]  = 32'h34009173; // CSRRW x2, 0x340, x1  (funct3=001)

        u_imem.mem[3]  = 32'h00000013; // NOP

        // CSRRS mscratch, x1 → x3 = mscratch (0x55), mscratch |= 0x55 = 0x55
        // Use x9 = 0xFF
        u_imem.mem[4]  = 32'h0FF00493; // ADDI x9, x0, 0xFF
        u_imem.mem[5]  = 32'h00000013; // NOP
        u_imem.mem[6]  = 32'h3404A1F3; // CSRRS x3, 0x340, x9  -> x3=0x55, mscratch |= 0xFF = 0xFF

        u_imem.mem[7]  = 32'h00000013; // NOP

        // CSRRC mscratch, x1 → x4 = mscratch (0xFF), mscratch &= ~0x55 = 0xAA
        u_imem.mem[8]  = 32'h3400B273; // CSRRC x4, 0x340, x1  -> x4=0xFF, mscratch = 0xFF & ~0x55 = 0xAA

        u_imem.mem[9]  = 32'h00000013; // NOP

        // CSRRWI mscratch, zimm=0x1F → x5 = old mscratch (0xAA), mscratch = 0x1F
        u_imem.mem[10] = 32'h340FD2F3; // CSRRWI x5, 0x340, 0x1F  (funct3=101, rs1=11111=0x1F)

        u_imem.mem[11] = 32'h00000013; // NOP

        // Read mscratch into x6
        u_imem.mem[12] = 32'h34002373; // CSRRS x6, 0x340, x0  (read-only, x0 doesn't set bits)

        u_imem.mem[13] = 32'h00000013; // NOP

        // --- CSRRSI: mscratch=0x1F, zimm=0x0A → x7=0x1F(old), mscratch |= 0x0A → still 0x1F ---
        //   (0x1F=0b11111, 0x0A=0b01010, 0x1F|0x0A=0x1F)
        //   But first reset to a value where the set is visible:
        //   CSRRWI x0, mscratch, 0x0A → mscratch = 0x0A
        u_imem.mem[14] = 32'h34055073; // CSRRWI x0, 0x340, 0x0A  (funct3=101, zimm=01010=0x0A)

        u_imem.mem[15] = 32'h00000013; // NOP

        // CSRRSI x7, mscratch, 0x15 → x7 = 0x0A (old), mscratch |= 0x15 → 0x0A|0x15 = 0x1F
        u_imem.mem[16] = 32'h340AE3F3; // CSRRSI x7, 0x340, 0x15  (funct3=110, zimm=10101=0x15)

        u_imem.mem[17] = 32'h00000013; // NOP

        // CSRRCI x8, mscratch, 0x0A → x8 = 0x1F (old), mscratch &= ~0x0A → 0x1F & ~0x0A = 0x15
        u_imem.mem[18] = 32'h34057473; // CSRRCI x8, 0x340, 0x0A  (funct3=111, zimm=01010=0x0A)

        u_imem.mem[19] = 32'h00000013; // NOP
        u_imem.mem[20] = 32'hFFDFF06F; // spin

        repeat (80) @(posedge clk);
        check_reg(2,  32'h00000000, "CSRRW: old mscratch=0");
        check_reg(3,  32'h00000055, "CSRRS: read mscratch=0x55 before set");
        check_reg(4,  32'h000000FF, "CSRRC: read mscratch=0xFF before clear");
        check_reg(5,  32'h000000AA, "CSRRWI: old mscratch=0xAA");
        check_reg(6,  32'h0000001F, "CSRRWI result: mscratch=0x1F");
        check_reg(7,  32'h0000000A, "CSRRSI: old mscratch=0x0A (before set 0x15)");
        check_reg(8,  32'h0000001F, "CSRRCI: old mscratch=0x1F (before clear 0x0A)");
        suite_end("SUITE 8");
    endtask

    // ================================================================
    // SUITE 9: Trap Entry (Illegal Instruction) + MRET Flow
    //
    // NOTE: This core only supports trap_illegal (EXEC_ILL) as the
    //       trap source. The IRQ inputs (irq_external/timer/software)
    //       update mip bits but do NOT generate traps — there is no
    //       mstatus.MIE && mie && mip logic in rv32_core_top.
    //       We test the actual trap path: illegal instruction → mtvec.
    // ================================================================
    task automatic run_suite9_interrupt();
        suite_start("SUITE 9: Trap (Illegal Instr) + MRET");
        clear_mem(); do_reset();

        // ---- Main program ----
        // Setup mtvec = 0x100 (trap handler address)
        u_imem.mem[0]  = 32'h10000093; // ADDI x1, x0, 0x100
        u_imem.mem[1]  = 32'h00000013; // NOP
        u_imem.mem[2]  = 32'h30509073; // CSRRW x0, mtvec(0x305), x1  -> mtvec = 0x100
        u_imem.mem[3]  = 32'h00000013; // NOP

        // Pre-trap marker
        u_imem.mem[4]  = 32'h00100513; // ADDI x10, x0, 1   (x10=1, pre-trap marker)
        u_imem.mem[5]  = 32'h00000013; // NOP

        // ECALL (0x00000073) — decodes as EXEC_ILL, triggers trap_illegal
        // mepc = PC of this instruction (0x18)
        u_imem.mem[6]  = 32'h00000073; // ECALL -> trap

        // Post-MRET landing (PC = 0x1C): MRET handler will advance mepc to here
        u_imem.mem[7]  = 32'h00200593; // ADDI x11, x0, 2   (x11=2, post-MRET marker)
        u_imem.mem[8]  = 32'h00000013; // NOP
        u_imem.mem[9]  = 32'hFFDFF06F; // spin

        // ---- Trap handler at 0x100 (word index 64) ----
        // Handler: mark arrival, read mepc, add 4 (skip ECALL), write back, MRET
        u_imem.mem[64] = 32'h06300713; // ADDI x14, x0, 99        (handler marker)
        u_imem.mem[65] = 32'h341027F3; // CSRRS x15, mepc(0x341), x0  -> x15 = mepc
        u_imem.mem[66] = 32'h00000013; // NOP
        u_imem.mem[67] = 32'h00478793; // ADDI x15, x15, 4        -> x15 = mepc+4
        u_imem.mem[68] = 32'h00000013; // NOP
        u_imem.mem[69] = 32'h34179073; // CSRRW x0, mepc(0x341), x15  -> mepc = mepc+4
        u_imem.mem[70] = 32'h00000013; // NOP
        u_imem.mem[71] = 32'h30200073; // MRET -> return to mepc (0x1C)
        u_imem.mem[72] = 32'h00000013; // NOP
        u_imem.mem[73] = 32'hFFDFF06F; // spin (should not reach)

        repeat (80) @(posedge clk);

        // Checks
        check_reg(10, 32'd1,    "TRAP: pre-trap marker x10=1");
        check_reg(14, 32'd99,   "TRAP: handler reached (x14=99)");
        check_csr("mtvec", u_dut.u_csr.mtvec, 32'h00000100, "mtvec = 0x100");
        check_reg(15, 32'h001C, "TRAP: mepc was 0x18, advanced to 0x1C");
        check_reg(11, 32'd2,    "MRET: returned, post-trap x11=2");

        // mcause should be 2 (hardcoded illegal instruction cause)
        check_csr("mcause", u_dut.u_csr.mcause, 32'd2, "mcause = 2 (illegal instr)");

        // mstatus after MRET: MPIE should be 1 (restored), MIE = previous MPIE (was 0)
        if (u_dut.u_csr.mstatus[7] === 1'b1) begin
            $display("  [PASS] mstatus.MPIE = 1  (restored after MRET)");
            pass_cnt++;
        end else begin
            $display("  [FAIL] mstatus.MPIE = %b  (expected 1)", u_dut.u_csr.mstatus[7]);
            fail_cnt++;
        end

        // ---- EBREAK test ----
        // EBREAK (0x00100073) also decodes as EXEC_ILL, same trap path as ECALL.
        // Re-run with EBREAK instead of ECALL to verify both system trap instructions.
        $display("  -- Testing EBREAK trap --");
        clear_mem(); do_reset();

        u_imem.mem[0]  = 32'h10000093; // ADDI x1, x0, 0x100
        u_imem.mem[1]  = 32'h00000013; // NOP
        u_imem.mem[2]  = 32'h30509073; // CSRRW x0, mtvec, x1  -> mtvec = 0x100
        u_imem.mem[3]  = 32'h00000013; // NOP
        u_imem.mem[4]  = 32'h00100073; // EBREAK -> trap
        u_imem.mem[5]  = 32'h00300613; // ADDI x12, x0, 3  (post-MRET marker)
        u_imem.mem[6]  = 32'h00000013; // NOP
        u_imem.mem[7]  = 32'hFFDFF06F; // spin

        // Trap handler at 0x100: mark + advance mepc + MRET
        u_imem.mem[64] = 32'h06400693; // ADDI x13, x0, 100  (handler marker)
        u_imem.mem[65] = 32'h341027F3; // CSRRS x15, mepc, x0
        u_imem.mem[66] = 32'h00000013; // NOP
        u_imem.mem[67] = 32'h00478793; // ADDI x15, x15, 4
        u_imem.mem[68] = 32'h00000013; // NOP
        u_imem.mem[69] = 32'h34179073; // CSRRW x0, mepc, x15
        u_imem.mem[70] = 32'h00000013; // NOP
        u_imem.mem[71] = 32'h30200073; // MRET
        u_imem.mem[72] = 32'h00000013; // NOP
        u_imem.mem[73] = 32'hFFDFF06F; // spin

        repeat (80) @(posedge clk);
        check_reg(13, 32'd100,  "EBREAK: handler reached (x13=100)");
        check_reg(12, 32'd3,    "EBREAK+MRET: returned, post-trap x12=3");

        suite_end("SUITE 9");
    endtask

    // ================================================================
    // SUITE 10: Data Hazards (RAW / WAW / WAR)
    // ================================================================
    task automatic run_suite10_data_hazards();
        suite_start("SUITE 10: Data Hazards (RAW/WAW/WAR)");
        clear_mem(); do_reset();

        // --- RAW (Read After Write): x1 written, immediately read ---
        u_imem.mem[0]  = 32'h00A00093; // ADDI x1, x0, 10    ; x1 = 10
        u_imem.mem[1]  = 32'h00508133; // ADD  x2, x1, x5    ; x2 = x1+0 = 10 (RAW on x1)
        u_imem.mem[2]  = 32'h00000013; // NOP

        // --- RAW chain: x3 = x2 + 5 (depends on x2 from prev) ---
        u_imem.mem[3]  = 32'h005101B3; // ADD  x3, x2, x5    ; x3 = x2+0 = 10 (chain RAW)
        u_imem.mem[4]  = 32'h00000013; // NOP

        // --- WAW (Write After Write): both write x4 ---
        u_imem.mem[5]  = 32'h00A00213; // ADDI x4, x0, 10    ; x4 = 10
        u_imem.mem[6]  = 32'h01400213; // ADDI x4, x0, 20    ; x4 = 20 (WAW, last write wins)
        u_imem.mem[7]  = 32'h00000013; // NOP

        // --- WAR (Write After Read): read x5 then write x5 ---
        u_imem.mem[8]  = 32'h01E00293; // ADDI x5, x0, 30    ; x5 = 30
        u_imem.mem[9]  = 32'h00000013; // NOP
        u_imem.mem[10] = 32'h00528333; // ADD  x6, x5, x5    ; x6 = 30+30 = 60 (read x5)
        u_imem.mem[11] = 32'h02800293; // ADDI x5, x0, 40    ; x5 = 40 (WAR: write after read)
        u_imem.mem[12] = 32'h00000013; // NOP
        u_imem.mem[13] = 32'hFFDFF06F; // spin

        repeat (60) @(posedge clk);
        check_reg(2,  32'd10, "RAW: x2 = x1(10) + 0 = 10");
        check_reg(3,  32'd10, "RAW chain: x3 = x2(10) + 0 = 10");
        check_reg(4,  32'd20, "WAW: last write wins x4=20");
        check_reg(6,  32'd60, "WAR: x6 = x5(30)+x5(30) = 60");
        check_reg(5,  32'd40, "WAR: x5 overwritten to 40 after read");
        suite_end("SUITE 10");
    endtask

    // ================================================================
    // SUITE 11: Control Hazards
    // ================================================================
    task automatic run_suite11_control_hazards();
        suite_start("SUITE 11: Control Hazards");
        clear_mem(); do_reset();

        // x1 = 1 (flag), x2 = 0
        u_imem.mem[0]  = 32'h00100093; // ADDI x1, x0, 1
        u_imem.mem[1]  = 32'h00000113; // ADDI x2, x0, 0
        u_imem.mem[2]  = 32'h00000013; // NOP

        // Branch-after-branch: BEQ taken, BNE in delay slot should be flushed
        // PC=0x0C: BEQ x1, x1, +8  → taken, jump to 0x14 (mem[5])
        u_imem.mem[3]  = 32'h00108463; // BEQ x1, x1, +8   (taken: x1==x1)
        u_imem.mem[4]  = 32'h00100193; // ADDI x3, x0, 1   (flushed/skipped)
        u_imem.mem[5]  = 32'h00200213; // ADDI x4, x0, 2   (landed here)
        u_imem.mem[6]  = 32'h00000013; // NOP

        // Jump-after-ALU: ALU result immediately used in a branch
        // x5 = x4 (should be 2)
        u_imem.mem[7]  = 32'h00020293; // ADDI x5, x4, 0   (x5 = x4 = 2, forwarded)
        u_imem.mem[8]  = 32'h00000013; // NOP

        // BNE x5, x0, +8 → taken (x5=2 != 0)
        u_imem.mem[9]  = 32'h00029463; // BNE x5, x0, +8
        u_imem.mem[10] = 32'h00100313; // ADDI x6, x0, 1   (skipped)
        u_imem.mem[11] = 32'h00300393; // ADDI x7, x0, 3   (landed here)
        u_imem.mem[12] = 32'h00000013; // NOP
        u_imem.mem[13] = 32'hFFDFF06F; // spin

        repeat (60) @(posedge clk);
        check_reg(3,  32'd0, "Branch flush: x3 not executed (flushed)");
        check_reg(4,  32'd2, "Branch target: x4=2");
        check_reg(6,  32'd0, "BNE taken: x6 not executed");
        check_reg(7,  32'd3, "BNE target: x7=3");
        suite_end("SUITE 11");
    endtask

    // ================================================================
    // SUITE 12: Load-Use Hazard (Pipeline Stall)
    // ================================================================
    task automatic run_suite12_load_use();
        suite_start("SUITE 12: Load-Use Hazard");
        clear_mem(); do_reset();

        // Pre-load MEM[0x80] = 42
        u_dmem.mem[128] = 8'd42;
        u_dmem.mem[129] = 8'd0;
        u_dmem.mem[130] = 8'd0;
        u_dmem.mem[131] = 8'd0;

        // x1 = 0x80 (address)
        u_imem.mem[0]  = 32'h08000093; // ADDI x1, x0, 0x80

        u_imem.mem[1]  = 32'h00000013; // NOP

        // Load x2 from MEM[0x80], then immediately use x2
        u_imem.mem[2]  = 32'h0000A103; // LW x2, 0(x1)      -> x2 = 42
        // Dependent instruction immediately after load (triggers load-use stall)
        u_imem.mem[3]  = 32'h00510133; // ADD x2, x2, x5    -> x2 = 42+0 = 42 (load-use)
        // Actually let's add a meaningful dependent: x3 = x2 + 10
        u_imem.mem[3]  = 32'h00A10193; // ADDI x3, x2, 10   -> x3 = 42+10 = 52

        u_imem.mem[4]  = 32'h00000013; // NOP

        // Another load-use: load then store-forwarding
        // Store x3 to MEM[0x90], then load it back
        u_imem.mem[5]  = 32'h09000213; // ADDI x4, x0, 0x90
        u_imem.mem[6]  = 32'h00000013; // NOP
        u_imem.mem[7]  = 32'h00322023; // SW x3, 0(x4)      -> MEM[0x90] = 52
        u_imem.mem[8]  = 32'h00000013; // NOP
        u_imem.mem[9]  = 32'h00022283; // LW x5, 0(x4)      -> x5 = 52
        u_imem.mem[10] = 32'h00528333; // ADD x6, x5, x5    -> x6 = 52+52 = 104 (load-use)
        u_imem.mem[11] = 32'h00000013; // NOP
        u_imem.mem[12] = 32'hFFDFF06F; // spin

        repeat (60) @(posedge clk);
        check_reg(3,  32'd52,  "Load-use: x3=42+10=52 (stall resolved)");
        check_reg(5,  32'd52,  "Store-then-load: x5=52");
        check_reg(6,  32'd104, "Load-use chain: x6=52+52=104");
        suite_end("SUITE 12");
    endtask

    // ================================================================
    // SUITE 13: Forwarding Stress
    // ================================================================
    task automatic run_suite13_fwd_stress();
        suite_start("SUITE 13: Forwarding Stress");
        clear_mem(); do_reset();

        // Back-to-back forwarding chain: x1→x2→x3→x4
        u_imem.mem[0]  = 32'h00A00093; // ADDI x1, x0, 10
        u_imem.mem[1]  = 32'h00108133; // ADD  x2, x1, x1   -> 20 (fwd from x1)
        u_imem.mem[2]  = 32'h002101B3; // ADD  x3, x2, x2   -> 40 (fwd from x2)
        u_imem.mem[3]  = 32'h00318233; // ADD  x4, x3, x3   -> 80 (fwd from x3)
        u_imem.mem[4]  = 32'h00000013; // NOP

        // Store operand forwarding: compute then immediately store
        u_imem.mem[5]  = 32'h10000293; // ADDI x5, x0, 0x100
        u_imem.mem[6]  = 32'h00000013; // NOP
        u_imem.mem[7]  = 32'h0042A023; // SW x4, 0(x5)      -> MEM[0x100] = 80 (fwd x4 to store)
        u_imem.mem[8]  = 32'h00000013; // NOP

        // Branch dependent on forwarded result
        u_imem.mem[9]  = 32'h05000313; // ADDI x6, x0, 80
        u_imem.mem[10] = 32'h00630463; // BEQ  x6, x6, +8   -> taken (x6==x6)
        u_imem.mem[11] = 32'h00100393; // ADDI x7, x0, 1    (skipped)
        u_imem.mem[12] = 32'h00200413; // ADDI x8, x0, 2    (landed)
        u_imem.mem[13] = 32'h00000013; // NOP
        u_imem.mem[14] = 32'hFFDFF06F; // spin

        repeat (60) @(posedge clk);
        check_reg(2,  32'd20,  "FWD chain: x2=20");
        check_reg(3,  32'd40,  "FWD chain: x3=40");
        check_reg(4,  32'd80,  "FWD chain: x4=80");
        check_mem(32'h100, 32'd80, "Store fwd: MEM[0x100]=80");
        check_reg(7,  32'd0,   "Branch on fwd: x7 skipped");
        check_reg(8,  32'd2,   "Branch on fwd: x8=2 (target)");
        suite_end("SUITE 13");
    endtask

    // ================================================================
    // SUITE 14: Re-run key suites under random-delay AXI4 READY
    // ================================================================
    task automatic run_suite14_random_delay();
        suite_start("SUITE 14: Random-Delay AXI4 Re-run");
        handshake_mode = 1;

        // Re-run R-type ALU under random delay
        $display("  -- Re-running R-type ALU with random AXI4 READY --");
        clear_mem(); do_reset();
        // Same program as Suite 2
        u_imem.mem[0]  = 32'h00700093; u_imem.mem[1]  = 32'h00300113;
        u_imem.mem[2]  = 32'hFFC00193; u_imem.mem[3]  = 32'h00000013;
        u_imem.mem[4]  = 32'h00208233; u_imem.mem[5]  = 32'h402082B3;
        u_imem.mem[6]  = 32'h00209333; u_imem.mem[7]  = 32'h0011A3B3;
        u_imem.mem[8]  = 32'h0020B433; u_imem.mem[9]  = 32'h0020C4B3;
        u_imem.mem[10] = 32'h0020D533; u_imem.mem[11] = 32'h4021D5B3;
        u_imem.mem[12] = 32'h0020E633; u_imem.mem[13] = 32'h0020F6B3;
        u_imem.mem[14] = 32'h00000013; u_imem.mem[15] = 32'hFFDFF06F;
        repeat (150) @(posedge clk);
        check_reg(4,  32'd10,         "RND-ALU ADD: 7+3=10");
        check_reg(5,  32'd4,          "RND-ALU SUB: 7-3=4");
        check_reg(6,  32'd56,         "RND-ALU SLL: 7<<3=56");
        check_reg(12, 32'd7,          "RND-ALU OR:  7|3=7");
        check_reg(13, 32'd3,          "RND-ALU AND: 7&3=3");

        // Re-run load-use under random delay
        $display("  -- Re-running Load-Use with random AXI4 READY --");
        clear_mem(); do_reset();
        u_dmem.mem[128] = 8'd42; u_dmem.mem[129] = 8'd0;
        u_dmem.mem[130] = 8'd0;  u_dmem.mem[131] = 8'd0;
        u_imem.mem[0]  = 32'h08000093;
        u_imem.mem[1]  = 32'h00000013;
        u_imem.mem[2]  = 32'h0000A103;
        u_imem.mem[3]  = 32'h00A10193;
        u_imem.mem[4]  = 32'h00000013;
        u_imem.mem[5]  = 32'hFFDFF06F;
        repeat (100) @(posedge clk);
        check_reg(3,  32'd52,  "RND-LU: x3=42+10=52");

        // Re-run branch taken/not-taken under random delay
        $display("  -- Re-running Branch with random AXI4 READY --");
        clear_mem(); do_reset();
        u_imem.mem[0]  = 32'h00500093; // ADDI x1, x0, 5
        u_imem.mem[1]  = 32'h00500113; // ADDI x2, x0, 5
        u_imem.mem[2]  = 32'h00300193; // ADDI x3, x0, 3
        u_imem.mem[3]  = 32'h00000013; // NOP
        u_imem.mem[4]  = 32'h00208463; // BEQ x1, x2, +8  (taken)
        u_imem.mem[5]  = 32'h00100213; // ADDI x4, x0, 1  (skipped)
        u_imem.mem[6]  = 32'h00209463; // BNE x1, x2, +8  (not taken)
        u_imem.mem[7]  = 32'h00100293; // ADDI x5, x0, 1  (executed)
        u_imem.mem[8]  = 32'h00000013; // NOP
        u_imem.mem[9]  = 32'hFFDFF06F; // spin
        repeat (100) @(posedge clk);
        check_reg(4,  32'd0, "RND-BEQ taken: x4=0 (skipped)");
        check_reg(5,  32'd1, "RND-BNE not-taken: x5=1 (executed)");

        handshake_mode = 0;
        suite_end("SUITE 14");
    endtask

    // ================================================================
    // SUITE 15 — M-Extension  (comprehensive tapeout coverage)
    //
    // Encoding reference:
    //   funct7=0000001, opcode=0110011, funct3 = operation
    //   MUL=000 MULH=001 MULHSU=010 MULHU=011
    //   DIV=100 DIVU=101 REM=110  REMU=111
    //
    // Helper: every sub-test loads x1/x2, executes MDU op into x3,
    //         copies x3→x4 via ADDI x4,x3,0 to force retirement,
    //         then spins.
    // ================================================================
    task automatic run_suite15_mext();
        suite_start("SUITE 15 — M-Extension");

        // ===============================================================
        // MUL variants
        // ===============================================================

        // 15-1: MUL positive × positive
        $display("  -- 15-1a: MUL 7*3=21 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h00700093; // addi x1,x0,7
        u_imem.mem[1] = 32'h00300113; // addi x2,x0,3
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h02208033; // MUL  x3,x1,x2
        u_imem.mem[4] = 32'h00018213; // addi x4,x3,0
        u_imem.mem[5] = 32'hFFFFF06F; // spin
        repeat (200) @(posedge clk);
        check_reg(4, 32'd21, "MUL: 7*3=21");

        // 15-1b: MUL negative × positive  →  lower 32 of signed product
        $display("  -- 15-1b: MUL -4*3=-12 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'hFFC00093; // addi x1,x0,-4
        u_imem.mem[1] = 32'h00300113; // addi x2,x0,3
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h02208033; // MUL  x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (200) @(posedge clk);
        check_reg(4, 32'hFFFFFFF4, "MUL: -4*3=-12 (0xFFFFFFF4)");

        // 15-1c: MUL negative × negative  →  lower 32 of signed product
        $display("  -- 15-1c: MUL -4*-3=12 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'hFFC00093; // addi x1,x0,-4
        u_imem.mem[1] = 32'hFFD00113; // addi x2,x0,-3
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h02208033; // MUL x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (200) @(posedge clk);
        check_reg(4, 32'd12, "MUL: (-4)*(-3)=12");

        // 15-1d: MUL zero
        $display("  -- 15-1d: MUL 0*anything=0 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h00000093; // addi x1,x0,0
        u_imem.mem[1] = 32'hFFF00113; // addi x2,x0,-1
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h02208033; // MUL x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (200) @(posedge clk);
        check_reg(4, 32'd0, "MUL: 0*(-1)=0");

        // 15-1e: MUL INT32_MAX * INT32_MAX  → lower 32
        //  0x7FFFFFFF * 0x7FFFFFFF = 0x3FFFFFFF_00000001 → lower = 0x00000001
        $display("  -- 15-1e: MUL INT32_MAX*INT32_MAX lower --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h7FFFF0B7; // lui  x1,0x7FFFF
        u_imem.mem[1] = 32'hFFF08093; // addi x1,x1,-1   → x1=0x7FFFFFFF
        u_imem.mem[2] = 32'h00108113; // addi x2,x1,1    → x2=0x80000000 (INT32_MIN)
        // Actually test INT32_MAX * INT32_MAX:
        u_imem.mem[2] = 32'h00008113; // addi x2,x1,0    → x2=x1=0x7FFFFFFF
        u_imem.mem[3] = 32'h00000013; // NOP
        u_imem.mem[4] = 32'h02208033; // MUL x3,x1,x2
        u_imem.mem[5] = 32'h00018213;
        u_imem.mem[6] = 32'hFFFFF06F;
        repeat (200) @(posedge clk);
        check_reg(5, 32'h00000001, "MUL: INT32_MAX*INT32_MAX lower=0x00000001");

        // ---------------------------------------------------------------
        // 15-2: MULH  (signed × signed → upper 32)
        // ---------------------------------------------------------------
        // 15-2a: small positive product — upper=0
        $display("  -- 15-2a: MULH 5*3 upper=0 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h00500093; // addi x1,x0,5
        u_imem.mem[1] = 32'h00300113; // addi x2,x0,3
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h02209033; // MULH x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (200) @(posedge clk);
        check_reg(4, 32'd0, "MULH: 5*3 upper=0");

        // 15-2b: (-1)*(-1)=+1 → upper=0
        $display("  -- 15-2b: MULH (-1)*(-1) upper=0 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'hFFF00093; // addi x1,x0,-1
        u_imem.mem[1] = 32'hFFF00113; // addi x2,x0,-1
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h02209033; // MULH x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (200) @(posedge clk);
        check_reg(4, 32'd0, "MULH: (-1)*(-1) upper=0");

        // 15-2c: INT32_MIN * INT32_MIN → upper = 0x40000000
        //  (-2^31)*(-2^31) = 2^62; upper 32 of 64-bit = 0x40000000
        $display("  -- 15-2c: MULH INT32_MIN*INT32_MIN upper=0x40000000 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h800000B7; // lui x1,0x80000  → x1=0x80000000
        u_imem.mem[1] = 32'h00008113; // addi x2,x1,0    → x2=0x80000000
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h02209033; // MULH x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (200) @(posedge clk);
        check_reg(4, 32'h40000000, "MULH: INT32_MIN*INT32_MIN upper=0x40000000");

        // 15-2d: INT32_MAX * INT32_MAX → upper = 0x3FFFFFFF
        //  (2^31-1)^2 = 2^62 - 2^32 + 1; upper = 0x3FFFFFFF
        $display("  -- 15-2d: MULH INT32_MAX*INT32_MAX upper=0x3FFFFFFF --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h7FFFF0B7; // lui  x1,0x7FFFF
        u_imem.mem[1] = 32'hFFF08093; // addi x1,x1,-1 → x1=0x7FFFFFFF
        u_imem.mem[2] = 32'h00008113; // addi x2,x1,0  → x2=0x7FFFFFFF
        u_imem.mem[3] = 32'h00000013; // NOP
        u_imem.mem[4] = 32'h02209033; // MULH x3,x1,x2
        u_imem.mem[5] = 32'h00018213;
        u_imem.mem[6] = 32'hFFFFF06F;
        repeat (200) @(posedge clk);
        check_reg(5, 32'h3FFFFFFF, "MULH: INT32_MAX*INT32_MAX upper=0x3FFFFFFF");

        // 15-2e: positive × negative upper sign-extends
        //  7 * (-3) = -21 → 64-bit = 0xFFFFFFFF_FFFFFFEB → upper = 0xFFFFFFFF
        $display("  -- 15-2e: MULH 7*(-3) upper=0xFFFFFFFF --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h00700093; // addi x1,x0,7
        u_imem.mem[1] = 32'hFFD00113; // addi x2,x0,-3
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h02209033; // MULH x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (200) @(posedge clk);
        check_reg(4, 32'hFFFFFFFF, "MULH: 7*(-3) upper=0xFFFFFFFF");

        // ---------------------------------------------------------------
        // 15-3: MULHSU (signed rs1 × unsigned rs2 → upper 32)
        // ---------------------------------------------------------------
        // 15-3a: 5 * 3 upper = 0 (fits in 32 bits)
        $display("  -- 15-3a: MULHSU 5*3 upper=0 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h00500093; // addi x1,x0,5
        u_imem.mem[1] = 32'h00300113; // addi x2,x0,3
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220A033; // MULHSU x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (200) @(posedge clk);
        check_reg(4, 32'd0, "MULHSU: 5*3 upper=0");

        // 15-3b: -1 (signed) * 0xFFFFFFFF (unsigned)
        //  (-1) signed = -1; 0xFFFFFFFF unsigned = 4294967295
        //  product = -4294967295 (64-bit signed)
        //  = 0xFFFFFFFF_00000001 → upper = 0xFFFFFFFF
        $display("  -- 15-3b: MULHSU (-1)*0xFFFFFFFF upper=0xFFFFFFFF --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'hFFF00093; // addi x1,x0,-1  (signed -1)
        u_imem.mem[1] = 32'hFFF00113; // addi x2,x0,-1  (unsigned 0xFFFFFFFF)
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220A033; // MULHSU x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (200) @(posedge clk);
        check_reg(4, 32'hFFFFFFFF, "MULHSU: (-1)*0xFFFFFFFF upper=0xFFFFFFFF");

        // 15-3c: INT32_MIN (signed) * 0xFFFFFFFF (unsigned)
        //  (-2^31) * (2^32-1) = -2^63 + 2^31
        //  64-bit = 0x80000000_80000000 → upper = 0x80000000
        $display("  -- 15-3c: MULHSU INT32_MIN*0xFFFFFFFF upper=0x80000000 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h800000B7; // lui x1,0x80000 → x1=0x80000000 (INT32_MIN)
        u_imem.mem[1] = 32'hFFF00113; // addi x2,x0,-1  (unsigned 0xFFFFFFFF)
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220A033; // MULHSU x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (200) @(posedge clk);
        check_reg(4, 32'h80000000, "MULHSU: INT32_MIN*0xFFFFFFFF upper=0x80000000");

        // ---------------------------------------------------------------
        // 15-4: MULHU (unsigned × unsigned → upper 32)
        // ---------------------------------------------------------------
        // 15-4a: 65536 * 65536 = 2^32, upper=1
        $display("  -- 15-4a: MULHU 65536*65536 upper=1 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h000100B7; // lui x1,0x10  → x1=0x00010000
        u_imem.mem[1] = 32'h00010137; // lui x2,0x10  → x2=0x00010000
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220B033; // MULHU x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (200) @(posedge clk);
        check_reg(4, 32'd1, "MULHU: 65536*65536 upper=1");

        // 15-4b: 0xFFFFFFFF * 0xFFFFFFFF
        //  (2^32-1)^2 = 2^64 - 2^33 + 1 → upper 32 = 0xFFFFFFFE
        $display("  -- 15-4b: MULHU 0xFFFFFFFF*0xFFFFFFFF upper=0xFFFFFFFE --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'hFFF00093; // addi x1,x0,-1 → x1=0xFFFFFFFF (unsigned)
        u_imem.mem[1] = 32'hFFF00113; // addi x2,x0,-1 → x2=0xFFFFFFFF (unsigned)
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220B033; // MULHU x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (200) @(posedge clk);
        check_reg(4, 32'hFFFFFFFE, "MULHU: 0xFFFFFFFF*0xFFFFFFFF upper=0xFFFFFFFE");

        // 15-4c: 0 * anything = 0
        $display("  -- 15-4c: MULHU 0*0xFFFFFFFF=0 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h00000093; // addi x1,x0,0
        u_imem.mem[1] = 32'hFFF00113; // addi x2,x0,-1
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220B033; // MULHU x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (200) @(posedge clk);
        check_reg(4, 32'd0, "MULHU: 0*0xFFFFFFFF=0");

        // ===============================================================
        // DIV / DIVU variants
        // ===============================================================

        // 15-5a: DIV positive / positive
        $display("  -- 15-5a: DIV 20/4=5 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h01400093; // addi x1,x0,20
        u_imem.mem[1] = 32'h00400113; // addi x2,x0,4
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220C033; // DIV x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (300) @(posedge clk);
        check_reg(4, 32'd5, "DIV: 20/4=5");

        // 15-5b: DIV negative / positive  (truncates toward zero)
        $display("  -- 15-5b: DIV -20/4=-5 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'hFEC00093; // addi x1,x0,-20
        u_imem.mem[1] = 32'h00400113; // addi x2,x0,4
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220C033; // DIV x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (300) @(posedge clk);
        check_reg(4, 32'hFFFFFFFB, "DIV: -20/4=-5 (0xFFFFFFFB)");

        // 15-5c: DIV positive / negative
        //  7 / (-3) = -2 (truncate toward zero)
        $display("  -- 15-5c: DIV 7/(-3)=-2 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h00700093; // addi x1,x0,7
        u_imem.mem[1] = 32'hFFD00113; // addi x2,x0,-3
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220C033; // DIV x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (300) @(posedge clk);
        check_reg(4, 32'hFFFFFFFE, "DIV: 7/(-3)=-2 (0xFFFFFFFE)");

        // 15-5d: DIV negative / negative
        //  -7 / -3 = 2 (truncate toward zero)
        $display("  -- 15-5d: DIV -7/(-3)=2 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'hFF900093; // addi x1,x0,-7
        u_imem.mem[1] = 32'hFFD00113; // addi x2,x0,-3
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220C033; // DIV x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (300) @(posedge clk);
        check_reg(4, 32'd2, "DIV: (-7)/(-3)=2");

        // 15-5e: DIV by zero  →  quotient = -1 (0xFFFFFFFF)
        $display("  -- 15-5e: DIV 7/0 spec: quotient=-1 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h00700093; // addi x1,x0,7
        u_imem.mem[1] = 32'h00000113; // addi x2,x0,0
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220C033; // DIV x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (100) @(posedge clk);
        check_reg(4, 32'hFFFFFFFF, "DIV: 7/0=-1 (spec)");

        // 15-5f: DIV INT32_MIN / -1  →  INT32_MIN (overflow, no exception)
        $display("  -- 15-5f: DIV INT32_MIN/-1=INT32_MIN (overflow spec) --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h800000B7; // lui x1,0x80000 → x1=INT32_MIN
        u_imem.mem[1] = 32'hFFF00113; // addi x2,x0,-1
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220C033; // DIV x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (100) @(posedge clk);
        check_reg(4, 32'h80000000, "DIV: INT32_MIN/-1=INT32_MIN (overflow)");

        // 15-6a: DIVU positive / positive
        $display("  -- 15-6a: DIVU 20/4=5 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h01400093; // addi x1,x0,20
        u_imem.mem[1] = 32'h00400113; // addi x2,x0,4
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220D033; // DIVU x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (300) @(posedge clk);
        check_reg(4, 32'd5, "DIVU: 20/4=5");

        // 15-6b: DIVU by zero  →  quotient = 0xFFFFFFFF
        $display("  -- 15-6b: DIVU 5/0=0xFFFFFFFF (spec) --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h00500093; // addi x1,x0,5
        u_imem.mem[1] = 32'h00000113; // x2=0
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220D033; // DIVU x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (100) @(posedge clk);
        check_reg(4, 32'hFFFFFFFF, "DIVU: 5/0=0xFFFFFFFF (spec)");

        // 15-6c: DIVU treats bits as unsigned (INT32_MIN / 2 = 0x40000000)
        $display("  -- 15-6c: DIVU 0x80000000/2=0x40000000 (unsigned) --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h800000B7; // lui x1,0x80000 → x1=0x80000000
        u_imem.mem[1] = 32'h00200113; // addi x2,x0,2
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220D033; // DIVU x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (300) @(posedge clk);
        check_reg(4, 32'h40000000, "DIVU: 0x80000000/2=0x40000000 (unsigned)");

        // ===============================================================
        // REM / REMU variants
        // ===============================================================

        // 15-7a: REM positive
        $display("  -- 15-7a: REM 20 rem 6=2 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h01400093; // addi x1,x0,20
        u_imem.mem[1] = 32'h00600113; // addi x2,x0,6
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220E033; // REM x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (300) @(posedge clk);
        check_reg(4, 32'd2, "REM: 20 rem 6=2");

        // 15-7b: REM sign follows dividend
        //  -20 rem 6 = -2
        $display("  -- 15-7b: REM -20 rem 6=-2 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'hFEC00093; // addi x1,x0,-20
        u_imem.mem[1] = 32'h00600113; // addi x2,x0,6
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220E033; // REM x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (300) @(posedge clk);
        check_reg(4, 32'hFFFFFFFE, "REM: -20 rem 6=-2 (sign follows dividend)");

        // 15-7c: REM positive dividend, negative divisor  →  sign follows dividend
        //  7 rem (-3) = 1
        $display("  -- 15-7c: REM 7 rem (-3)=1 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h00700093; // addi x1,x0,7
        u_imem.mem[1] = 32'hFFD00113; // addi x2,x0,-3
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220E033; // REM x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (300) @(posedge clk);
        check_reg(4, 32'd1, "REM: 7 rem (-3)=1");

        // 15-7d: REM by zero  →  remainder = rs1
        $display("  -- 15-7d: REM 7 rem 0=7 (spec) --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h00700093; // addi x1,x0,7
        u_imem.mem[1] = 32'h00000113; // x2=0
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220E033; // REM x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (100) @(posedge clk);
        check_reg(4, 32'd7, "REM: 7 rem 0=7 (spec)");

        // 15-7e: REM INT32_MIN / -1  →  remainder = 0 (overflow spec)
        $display("  -- 15-7e: REM INT32_MIN rem (-1)=0 (overflow spec) --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h800000B7; // lui x1,0x80000 → x1=INT32_MIN
        u_imem.mem[1] = 32'hFFF00113; // addi x2,x0,-1
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220E033; // REM x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (100) @(posedge clk);
        check_reg(4, 32'd0, "REM: INT32_MIN rem (-1)=0 (overflow spec)");

        // 15-8a: REMU basic
        $display("  -- 15-8a: REMU 20 rem 6=2 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h01400093; // addi x1,x0,20
        u_imem.mem[1] = 32'h00600113; // addi x2,x0,6
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220F033; // REMU x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (300) @(posedge clk);
        check_reg(4, 32'd2, "REMU: 20 rem 6=2");

        // 15-8b: REMU by zero  →  remainder = rs1
        $display("  -- 15-8b: REMU 5 rem 0=5 (spec) --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h00500093; // addi x1,x0,5
        u_imem.mem[1] = 32'h00000113; // x2=0
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220F033; // REMU x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (100) @(posedge clk);
        check_reg(4, 32'd5, "REMU: 5 rem 0=5 (spec)");

        // 15-8c: REMU treats both as unsigned
        //  0x80000000 rem 0x3 = 0x80000000 mod 3 = 2 (since 0x80000000=2147483648, 2147483648%3=2)
        $display("  -- 15-8c: REMU 0x80000000 rem 3=2 (unsigned) --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h800000B7; // lui x1,0x80000
        u_imem.mem[1] = 32'h00300113; // addi x2,x0,3
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220F033; // REMU x3,x1,x2
        u_imem.mem[4] = 32'h00018213;
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (300) @(posedge clk);
        check_reg(4, 32'd2, "REMU: 0x80000000 rem 3=2 (unsigned)");

        // ===============================================================
        // Pipeline hazard tests with MDU
        // ===============================================================

        // 15-9: MUL result forwarded to next ADDI (stall resolves)
        $display("  -- 15-9: MDU hazard: MUL then ADDI on result --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h00700093; // addi x1,x0,7
        u_imem.mem[1] = 32'h00300113; // addi x2,x0,3
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h02208033; // MUL x3,x1,x2   (x3=21, stalls 3 cycles)
        u_imem.mem[4] = 32'h00A18213; // addi x4,x3,10  (x4=31, uses x3 after stall)
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (300) @(posedge clk);
        check_reg(4, 32'd31, "MDU hazard: MUL(7*3=21) then ADDI+10=31");

        // 15-10: DIV result used in STORE
        $display("  -- 15-10: DIV result in STORE --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h01400093; // addi x1,x0,20
        u_imem.mem[1] = 32'h00400113; // addi x2,x0,4
        u_imem.mem[2] = 32'h00000013; // NOP
        u_imem.mem[3] = 32'h0220C033; // DIV x3,x1,x2   (x3=5)
        u_imem.mem[4] = 32'h00302023; // sw x3,0(x0)     (MEM[0]=5)
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (400) @(posedge clk);
        check_mem(0, 32'd5, "DIV result stored: MEM[0]=5");

        // 15-11: Back-to-back MDU ops (MUL then DIV, each on different regs)
        //  x1=12, x2=4 → MUL x3=48, DIV x4=x1/x2=3
        $display("  -- 15-11: Back-to-back MUL then DIV --");
        clear_mem(); do_reset();
        u_imem.mem[0]  = 32'h00C00093; // addi x1,x0,12
        u_imem.mem[1]  = 32'h00400113; // addi x2,x0,4
        u_imem.mem[2]  = 32'h00000013; // NOP
        u_imem.mem[3]  = 32'h02208133; // MUL x2,x1,x2  — WAIT: use different regs
        // MUL x5,x1,x2 first:
        u_imem.mem[3]  = 32'h022082B3; // MUL x5,x1,x2  (x5=48)
        u_imem.mem[4]  = 32'h00400113; // addi x2,x0,4  (restore x2=4 while MUL stalls)
        u_imem.mem[5]  = 32'h0220C333; // DIV x6,x1,x2  (x6=12/4=3)
        u_imem.mem[6]  = 32'h00028213; // addi x4,x5,0  (copy MUL result)
        u_imem.mem[7]  = 32'h00030293; // addi x5,x6,0  (copy DIV result)
        u_imem.mem[8]  = 32'h00000013; // NOP
        u_imem.mem[9]  = 32'hFFFFF06F;
        repeat (500) @(posedge clk);
        check_reg(4, 32'd48, "Back-to-back: MUL(12*4=48) correct");
        check_reg(5, 32'd3,  "Back-to-back: DIV(12/4=3) correct");

        // 15-12: MDU stall with forwarding — MUL result forwarded to subsequent MUL
        //  x1=3, MUL x3=x1*x1=9, then MUL x4=x3*x3=81
        $display("  -- 15-12: Chained MUL: 3→9→81 --");
        clear_mem(); do_reset();
        u_imem.mem[0] = 32'h00300093; // addi x1,x0,3
        u_imem.mem[1] = 32'h00000013; // NOP
        u_imem.mem[2] = 32'h02108133; // MUL x2,x1,x1  (x2=9)
        u_imem.mem[3] = 32'h022101B3; // MUL x3,x2,x2  (x3=81, stall waits for x2)
        u_imem.mem[4] = 32'h00018213; // addi x4,x3,0
        u_imem.mem[5] = 32'hFFFFF06F;
        repeat (400) @(posedge clk);
        check_reg(4, 32'd81, "Chained MUL: 3*3=9, 9*9=81");

        suite_end("SUITE 15");
    endtask

    // ================================================================
    // MAIN
    // ================================================================
    initial begin
        $dumpfile("rv32_core_sanity_tb.vcd");
        $dumpvars(0, rv32_core_sanity_tb);
        pass_cnt = 0; fail_cnt = 0;
        core_log_en = 1;

        run_suite1_reset();
        run_suite2_rtype();
        run_suite3_itype();
        run_suite3b_corner_cases();
        run_suite4_lui_auipc();
        run_suite5_jal_jalr();
        run_suite6_load_store();
        run_suite7_branches();
        run_suite8_csr();
        run_suite9_interrupt();
        run_suite10_data_hazards();
        run_suite11_control_hazards();
        run_suite12_load_use();
        run_suite13_fwd_stress();
        run_suite14_random_delay();
        run_suite15_mext();

        // ---- Coverage Report ----
        $display("\n========== Coverage Report ==========");
        $display("  Opcode Coverage : %.2f%%", cov_op.get_coverage());
        $display("  M-Ext Coverage  : %.2f%%", cov_mex.get_coverage());
        $display("=====================================");

        // ---- Final Summary ----
        $display("\n================================================");
        $display("  CORE SANITY TB FINAL: %0d PASS, %0d FAIL (of %0d)",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0)
            $display("  STATUS: ALL TESTS PASSED");
        else
            $display("  STATUS: %0d TESTS FAILED", fail_cnt);
        $display("================================================\n");

        $fclose(core_log_fd);
        $display("[INFO] Core execution log: core_sanity_exec.log");
        $finish;
    end

endmodule
