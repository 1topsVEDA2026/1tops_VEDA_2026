// ============================================================================
// axi4_dmem_slave.sv  —  AXI4 Data Memory Slave (Testbench)
//
// Full AXI4 AW+W+B+AR+R channels.
// Byte-addressable array exposed as mem[0:4095] for direct TB access.
//
// delay_en = 0 : zero-latency (combinational reads, 1-cycle write)
//            1 : random 0-2 cycle READY delay on all channels
// ============================================================================
`timescale 1ns / 1ps

module axi4_dmem_slave #(
    parameter MEM_BYTES = 4096
)(
    input  logic        clk,
    input  logic        rst_n,

    // ---- AXI4 AW channel ----
    input  logic [31:0] awaddr,
    input  logic        awvalid,
    output logic        awready,
    input  logic [ 7:0] awlen,
    input  logic [ 2:0] awsize,
    input  logic [ 1:0] awburst,
    input  logic [ 3:0] awcache,
    input  logic [ 2:0] awprot,
    input  logic        awlock,

    // ---- AXI4 W channel ----
    input  logic [31:0] wdata,
    input  logic [ 3:0] wstrb,
    input  logic        wvalid,
    input  logic        wlast,
    output logic        wready,

    // ---- AXI4 B channel ----
    output logic        bvalid,
    output logic [ 1:0] bresp,
    input  logic        bready,

    // ---- AXI4 AR channel ----
    input  logic [31:0] araddr,
    input  logic        arvalid,
    output logic        arready,
    input  logic [ 7:0] arlen,
    input  logic [ 2:0] arsize,
    input  logic [ 1:0] arburst,
    input  logic [ 3:0] arcache,
    input  logic [ 2:0] arprot,
    input  logic        arlock,

    // ---- AXI4 R channel ----
    output logic [31:0] rdata,
    output logic        rvalid,
    output logic        rlast,
    output logic [ 1:0] rresp,
    input  logic        rready,

    // ---- Mode control ----
    input  logic        delay_en
);

    // ================================================================
    // Byte-addressable memory — TB accesses u_dmem.mem[byte_addr]
    // ================================================================
    localparam ADDR_W = $clog2(MEM_BYTES);
    logic [7:0] mem [0:MEM_BYTES-1];

    integer _i;
    initial begin
        for (_i = 0; _i < MEM_BYTES; _i++) mem[_i] = 8'h00;
    end

    // ================================================================
    // WRITE FSM (AW + W → B)
    // ================================================================
    // We buffer AW and W independently; write fires when both received.
    // For zero-latency: awready=wready=1 immediately, bvalid=1 after write.

    typedef enum logic [1:0] {
        WR_IDLE  = 2'b00,
        WR_DELAY = 2'b01,   // delay_en: waiting before accepting AW/W
        WR_BRESP = 2'b10    // both AW+W accepted, driving bvalid
    } wr_state_t;

    wr_state_t   wr_state_r;
    logic [31:0] aw_addr_r;
    logic [31:0] w_data_r;
    logic [ 3:0] w_strb_r;
    logic        aw_got_r, w_got_r;
    logic [ 1:0] wr_dly_cnt_r, wr_dly_tgt_r;

    // Helper: both AW and W accepted?
    wire wr_both_done = aw_got_r && w_got_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state_r   <= WR_IDLE;
            aw_addr_r    <= 32'd0;
            w_data_r     <= 32'd0;
            w_strb_r     <= 4'd0;
            aw_got_r     <= 1'b0;
            w_got_r      <= 1'b0;
            wr_dly_cnt_r <= 2'd0;
            wr_dly_tgt_r <= 2'd0;
        end else begin
            case (wr_state_r)
                WR_IDLE: begin
                    // Latch AW when accepted
                    if (awvalid && awready) begin
                        aw_addr_r <= awaddr;
                        aw_got_r  <= 1'b1;
                    end
                    // Latch W when accepted
                    if (wvalid && wready) begin
                        w_data_r <= wdata;
                        w_strb_r <= wstrb;
                        w_got_r  <= 1'b1;
                    end
                    // When both received, do the write and move to BRESP
                    if ((aw_got_r || (awvalid && awready)) &&
                        (w_got_r  || (wvalid  && wready ))) begin
                        // Capture any last-moment values
                        if (awvalid && awready) aw_addr_r <= awaddr;
                        if (wvalid  && wready ) begin w_data_r <= wdata; w_strb_r <= wstrb; end
                        wr_state_r <= WR_BRESP;
                        aw_got_r   <= 1'b0;
                        w_got_r    <= 1'b0;
                    end
                end
                WR_BRESP: begin
                    // Execute write
                    if (w_strb_r[0]) mem[{aw_addr_r[ADDR_W-1:2], 2'b00}] <= w_data_r[ 7: 0];
                    if (w_strb_r[1]) mem[{aw_addr_r[ADDR_W-1:2], 2'b01}] <= w_data_r[15: 8];
                    if (w_strb_r[2]) mem[{aw_addr_r[ADDR_W-1:2], 2'b10}] <= w_data_r[23:16];
                    if (w_strb_r[3]) mem[{aw_addr_r[ADDR_W-1:2], 2'b11}] <= w_data_r[31:24];
                    if (bvalid && bready) wr_state_r <= WR_IDLE;
                end
                default: wr_state_r <= WR_IDLE;
            endcase
        end
    end

    // ================================================================
    // READ FSM (AR → R)
    // ================================================================
    typedef enum logic [1:0] {
        RD_IDLE  = 2'b00,
        RD_DELAY = 2'b01,
        RD_RVALID = 2'b10
    } rd_state_t;

    rd_state_t   rd_state_r;
    logic [31:0] ar_addr_r;
    logic [ 1:0] rd_dly_cnt_r, rd_dly_tgt_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state_r   <= RD_IDLE;
            ar_addr_r    <= 32'd0;
            rd_dly_cnt_r <= 2'd0;
            rd_dly_tgt_r <= 2'd0;
        end else begin
            case (rd_state_r)
                RD_IDLE: begin
                    if (arvalid) begin
                        ar_addr_r <= araddr;
                        if (!delay_en)
                            rd_state_r <= RD_RVALID;
                        else begin
                            rd_dly_tgt_r <= 2'($urandom_range(0, 2));
                            rd_dly_cnt_r <= 2'd0;
                            rd_state_r   <= RD_DELAY;
                        end
                    end
                end
                RD_DELAY: begin
                    if (rd_dly_cnt_r >= rd_dly_tgt_r) rd_state_r <= RD_RVALID;
                    else rd_dly_cnt_r <= rd_dly_cnt_r + 1'b1;
                end
                RD_RVALID: begin
                    if (rvalid && rready) rd_state_r <= RD_IDLE;
                end
                default: rd_state_r <= RD_IDLE;
            endcase
        end
    end

    // ================================================================
    // Combinational read data
    // ================================================================
    wire [31:0] rd_word_comb = {mem[{araddr[ADDR_W-1:2],  2'b11}],
                                mem[{araddr[ADDR_W-1:2],  2'b10}],
                                mem[{araddr[ADDR_W-1:2],  2'b01}],
                                mem[{araddr[ADDR_W-1:2],  2'b00}]};

    wire [31:0] rd_word_lat  = {mem[{ar_addr_r[ADDR_W-1:2], 2'b11}],
                                mem[{ar_addr_r[ADDR_W-1:2], 2'b10}],
                                mem[{ar_addr_r[ADDR_W-1:2], 2'b01}],
                                mem[{ar_addr_r[ADDR_W-1:2], 2'b00}]};

    // ================================================================
    // Output mux: zero-latency vs delayed
    // ================================================================
    always_comb begin
        if (!delay_en) begin
            // Zero-latency read: fully combinational
            arready = 1'b1;
            rvalid  = arvalid;
            rdata   = rd_word_comb;
            // Writes: accept immediately
            awready = 1'b1;
            wready  = 1'b1;
            bvalid  = (wr_state_r == WR_BRESP);
        end else begin
            arready = (rd_state_r == RD_IDLE);
            rvalid  = (rd_state_r == RD_RVALID);
            rdata   = rd_word_lat;
            // Delayed write: accept only in IDLE
            awready = (wr_state_r == WR_IDLE) && !aw_got_r;
            wready  = (wr_state_r == WR_IDLE) && !w_got_r;
            bvalid  = (wr_state_r == WR_BRESP);
        end
    end

    assign rlast = 1'b1;
    assign rresp = 2'b00;
    assign bresp = 2'b00;

endmodule
