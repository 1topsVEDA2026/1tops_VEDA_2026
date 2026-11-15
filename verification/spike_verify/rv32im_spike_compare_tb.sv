`timescale 1ns / 1ps
// ============================================================================
// rv32im_spike_compare_tb.sv — AXI4 RTL TB for Spike ISS Comparison
//
// Target: rv32_core_top (AXI4 interfaces, Booth multiplier MDU)
//
// Loads a program from rtl_prog_word.hex into the AXI4 memory slaves,
// runs it on the core, and generates a Spike-compatible execution log.
//
// Log output: rtl_spike_exec.log
// Compare:    python3 compare_spike_rtl.py spike_golden.log rtl_spike_exec.log
// ============================================================================

module rv32im_spike_compare_tb
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
    // AXI4 Signals
    // ================================================================
    // IMEM AXI4 (AR + R)
    logic [31:0] imem_araddr;   logic        imem_arvalid, imem_arready;
    logic [ 7:0] imem_arlen;    logic [ 2:0] imem_arsize;
    logic [ 1:0] imem_arburst;  logic [ 3:0] imem_arcache;
    logic [ 2:0] imem_arprot;   logic        imem_arlock;
    logic [31:0] imem_rdata;    logic        imem_rvalid, imem_rready;
    logic [ 1:0] imem_rresp;    logic        imem_rlast;

    // DMEM AXI4 (AW + W + B + AR + R)
    logic [31:0] dmem_awaddr;   logic        dmem_awvalid, dmem_awready;
    logic [ 7:0] dmem_awlen;    logic [ 2:0] dmem_awsize;
    logic [ 1:0] dmem_awburst;  logic [ 3:0] dmem_awcache;
    logic [ 2:0] dmem_awprot;   logic        dmem_awlock;
    logic [31:0] dmem_wdata;    logic [ 3:0] dmem_wstrb;
    logic        dmem_wvalid, dmem_wready, dmem_wlast;
    logic        dmem_bvalid;   logic [ 1:0] dmem_bresp;
    logic        dmem_bready;
    logic [31:0] dmem_araddr;   logic        dmem_arvalid, dmem_arready;
    logic [ 7:0] dmem_arlen;    logic [ 2:0] dmem_arsize;
    logic [ 1:0] dmem_arburst;  logic [ 3:0] dmem_arcache;
    logic [ 2:0] dmem_arprot;   logic        dmem_arlock;
    logic [31:0] dmem_rdata;    logic        dmem_rvalid, dmem_rready;
    logic [ 1:0] dmem_rresp;    logic        dmem_rlast;

    // Interrupts
    logic irq_external, irq_timer, irq_software;
    assign irq_external = 0;
    assign irq_timer    = 0;
    assign irq_software = 0;

    // Zero-latency AXI (no random delay for comparison runs)
    logic delay_en;
    initial delay_en = 1'b0;

    // ================================================================
    // DUT — AXI4 Master
    // ================================================================
    rv32_core_top u_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .imem_araddr   (imem_araddr),  .imem_arvalid  (imem_arvalid),
        .imem_arready  (imem_arready), .imem_arlen    (imem_arlen),
        .imem_arsize   (imem_arsize),  .imem_arburst  (imem_arburst),
        .imem_arcache  (imem_arcache), .imem_arprot   (imem_arprot),
        .imem_arlock   (imem_arlock),
        .imem_rdata    (imem_rdata),   .imem_rvalid   (imem_rvalid),
        .imem_rready   (imem_rready),  .imem_rresp    (imem_rresp),
        .imem_rlast    (imem_rlast),
        .dmem_awaddr   (dmem_awaddr),  .dmem_awvalid  (dmem_awvalid),
        .dmem_awready  (dmem_awready), .dmem_awlen    (dmem_awlen),
        .dmem_awsize   (dmem_awsize),  .dmem_awburst  (dmem_awburst),
        .dmem_awcache  (dmem_awcache), .dmem_awprot   (dmem_awprot),
        .dmem_awlock   (dmem_awlock),
        .dmem_wdata    (dmem_wdata),   .dmem_wstrb    (dmem_wstrb),
        .dmem_wvalid   (dmem_wvalid),  .dmem_wlast    (dmem_wlast),
        .dmem_wready   (dmem_wready),
        .dmem_bvalid   (dmem_bvalid),  .dmem_bresp    (dmem_bresp),
        .dmem_bready   (dmem_bready),
        .dmem_araddr   (dmem_araddr),  .dmem_arvalid  (dmem_arvalid),
        .dmem_arready  (dmem_arready), .dmem_arlen    (dmem_arlen),
        .dmem_arsize   (dmem_arsize),  .dmem_arburst  (dmem_arburst),
        .dmem_arcache  (dmem_arcache), .dmem_arprot   (dmem_arprot),
        .dmem_arlock   (dmem_arlock),
        .dmem_rdata    (dmem_rdata),   .dmem_rvalid   (dmem_rvalid),
        .dmem_rready   (dmem_rready),  .dmem_rresp    (dmem_rresp),
        .dmem_rlast    (dmem_rlast),
        .irq_external  (irq_external), .irq_timer     (irq_timer),
        .irq_software  (irq_software)
    );

    // ================================================================
    // AXI4 Memory Slaves
    // ================================================================
    axi4_imem_slave #(.MEM_DEPTH(1024)) u_imem (
        .clk(clk), .rst_n(rst_n),
        .araddr(imem_araddr), .arvalid(imem_arvalid), .arready(imem_arready),
        .arlen(imem_arlen), .arsize(imem_arsize), .arburst(imem_arburst),
        .arcache(imem_arcache), .arprot(imem_arprot), .arlock(imem_arlock),
        .rdata(imem_rdata), .rvalid(imem_rvalid), .rlast(imem_rlast),
        .rresp(imem_rresp), .rready(imem_rready),
        .delay_en(delay_en)
    );

    axi4_dmem_slave #(.MEM_BYTES(4096)) u_dmem (
        .clk(clk), .rst_n(rst_n),
        .awaddr(dmem_awaddr), .awvalid(dmem_awvalid), .awready(dmem_awready),
        .awlen(dmem_awlen), .awsize(dmem_awsize), .awburst(dmem_awburst),
        .awcache(dmem_awcache), .awprot(dmem_awprot), .awlock(dmem_awlock),
        .wdata(dmem_wdata), .wstrb(dmem_wstrb), .wvalid(dmem_wvalid),
        .wlast(dmem_wlast), .wready(dmem_wready),
        .bvalid(dmem_bvalid), .bresp(dmem_bresp), .bready(dmem_bready),
        .araddr(dmem_araddr), .arvalid(dmem_arvalid), .arready(dmem_arready),
        .arlen(dmem_arlen), .arsize(dmem_arsize), .arburst(dmem_arburst),
        .arcache(dmem_arcache), .arprot(dmem_arprot), .arlock(dmem_arlock),
        .rdata(dmem_rdata), .rvalid(dmem_rvalid), .rlast(dmem_rlast),
        .rresp(dmem_rresp), .rready(dmem_rready),
        .delay_en(delay_en)
    );

    // ================================================================
    // Load program into instruction memory
    // ================================================================
    initial begin
        for (int i = 0; i < 1024; i++) u_imem.mem[i] = 32'h0000_0013;
        for (int i = 0; i < 4096; i++) u_dmem.mem[i] = 8'h00;
        $readmemh("/home/vlsiuser/Downloads/design_rtl_booth_mul_restoring_div/spike_verify/build/test_mext_corner/sim/rtl_prog_word.hex", u_imem.mem);
        $display("[INFO] Program loaded from rtl_prog_word.hex");
    end

    // ================================================================
    // Execution Log (Spike-compatible format)
    // ================================================================
    integer log_fd;
    logic [31:0] prev_pc;

    initial begin
        log_fd = $fopen("/home/vlsiuser/Downloads/design_rtl_booth_mul_restoring_div/spike_verify/build/test_mext_corner/sim/rtl_spike_exec.log", "w");
        if (log_fd == 0) begin
            $display("[ERROR] Cannot open rtl_spike_exec.log");
            $finish;
        end
    end

    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (u_dut.rf_en_MW && u_dut.rd_addr_MW != 5'd0) begin
                $fwrite(log_fd, "core 0: 0x%08h (0x%08h) x%0d 0x%08h\n",
                    u_dut.pc_out_MW,
                    u_imem.mem[u_dut.pc_out_MW[11:2]],
                    u_dut.rd_addr_MW,
                    u_dut.wdata);
            end
            else if (u_dut.wr_en_MW) begin
                $fwrite(log_fd, "core 0: 0x%08h (0x%08h) mem 0x%08h\n",
                    u_dut.pc_out_MW,
                    u_imem.mem[u_dut.pc_out_MW[11:2]],
                    dmem_awaddr);
            end
            else if (u_dut.pc_out_MW != prev_pc) begin
                $fwrite(log_fd, "core 0: 0x%08h (0x%08h)\n",
                    u_dut.pc_out_MW,
                    u_imem.mem[u_dut.pc_out_MW[11:2]]);
            end
            prev_pc <= u_dut.pc_out_MW;
        end
    end

    // ================================================================
    // Spin detection: PC stuck for 100 cycles → program done
    // ================================================================
    integer spin_cnt, cycle_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spin_cnt  <= 0;
            cycle_cnt <= 0;
        end else begin
            cycle_cnt <= cycle_cnt + 1;
            if (u_dut.pc_out_MW == prev_pc)
                spin_cnt <= spin_cnt + 1;
            else
                spin_cnt <= 0;

            if (spin_cnt > 100) begin
                $display("[INFO] Spin detected at PC=0x%08h, stopping after %0d cycles",
                         u_dut.pc_out_MW, cycle_cnt);
                $fclose(log_fd);
                $finish;
            end

            if (cycle_cnt > 50000) begin
                $display("[TIMEOUT] Stopping after %0d cycles", cycle_cnt);
                $fclose(log_fd);
                $finish;
            end
        end
    end

    // ================================================================
    // Reset & Run
    // ================================================================
    initial begin
        $dumpfile("rv32im_spike_compare.vcd");
        $dumpvars(0, rv32im_spike_compare_tb);
        rst_n = 0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
    end

endmodule
