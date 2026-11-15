// ============================================================================
// axi4_imem_slave.sv   AXI4 Instruction Memory Slave (Testbench)
//
// Full AXI4 AR+R channels (read-only, no AW/W/B).
// Memory array exposed as mem[0:1023] for direct TB access.
//
// delay_en = 0 : fully combinational / zero-latency
//            1 : random 0-2 cycle ARREADY delay (for Suite 14)
// ============================================================================
`timescale 1ns / 1ps

module axi4_imem_slave #(
    parameter MEM_DEPTH = 1024   // words (4 kB)
)(
    input  logic        clk,
    input  logic        rst_n,

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
    // Memory array TB writes via  u_imem.mem[word_idx] = ...
    // ================================================================
    localparam ADDR_W = $clog2(MEM_DEPTH);  // address bits needed
    logic [31:0] mem [0:MEM_DEPTH-1];

    integer _i;
    initial begin
        for (_i = 0; _i < MEM_DEPTH; _i++) mem[_i] = 32'h0000_0013;
    end

    // ================================================================
    // State machine (delay_en = 1)
    // ================================================================
    typedef enum logic [1:0] {
        S_IDLE   = 2'b00,
        S_DELAY  = 2'b01,
        S_RVALID = 2'b10
    } state_t;

    state_t      state_r;
    logic [31:0] addr_latch_r;
    logic [ 1:0] delay_cnt_r, delay_tgt_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r      <= S_IDLE;
            addr_latch_r <= 32'd0;
            delay_cnt_r  <= 2'd0;
            delay_tgt_r  <= 2'd0;
        end else begin
            case (state_r)
                S_IDLE: begin
                    if (arvalid && delay_en) begin
                        addr_latch_r <= araddr;
                        delay_tgt_r  <= 2'($urandom_range(0, 2));
                        delay_cnt_r  <= 2'd0;
                        state_r      <= S_DELAY;
                    end
                end
                S_DELAY: begin
                    if (delay_cnt_r >= delay_tgt_r) state_r <= S_RVALID;
                    else delay_cnt_r <= delay_cnt_r + 1'b1;
                end
                S_RVALID: begin
                    if (rvalid && rready) state_r <= S_IDLE;
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end

    // ================================================================
    // Output mux
    // ================================================================
    always_comb begin
        if (!delay_en) begin
            arready = 1'b1;
            rvalid  = arvalid;
            rdata   = mem[araddr[ADDR_W+1:2]];
        end else begin
            arready = (state_r == S_IDLE);
            rvalid  = (state_r == S_RVALID);
            rdata   = mem[addr_latch_r[ADDR_W+1:2]];
        end
    end

    assign rlast = 1'b1;
    assign rresp = 2'b00;

endmodule
