`timescale 1ns / 1ps
//==============================================================================
// axi4lite_slave_mem
//
// Minimal single-cycle-access AXI4-Lite SLAVE memory model for simulation.
// Accepts AW+W together (matches obi_to_axi4lite_master's behavior of
// issuing both simultaneously), single outstanding transaction at a time
// (sufficient since the core issues one memory op at a time).
//
// Word-addressed internally; MEM_DEPTH_WORDS * 4 bytes total capacity.
// Loads its contents from MEM_INIT_FILE (a $readmemh-format hex file, one
// 32-bit word per line) at time 0 if MEM_INIT_FILE is non-empty.
//==============================================================================

module axi4lite_slave_mem #(
    parameter int    ADDR_WIDTH      = 32,
    parameter int    DATA_WIDTH      = 32,
    parameter int    MEM_DEPTH_WORDS = 16384,          // 64 KB default
    parameter string MEM_INIT_FILE   = ""
) (
    input  logic                            clk,
    input  logic                            rst_n,

    // Write address channel
    input  logic [ADDR_WIDTH-1:0]           s_axi_awaddr,
    input  logic [2:0]                      s_axi_awprot,
    input  logic                            s_axi_awvalid,
    output logic                            s_axi_awready,
    // Write data channel
    input  logic [DATA_WIDTH-1:0]           s_axi_wdata,
    input  logic [DATA_WIDTH/8-1:0]         s_axi_wstrb,
    input  logic                            s_axi_wvalid,
    output logic                            s_axi_wready,
    // Write response channel
    output logic [1:0]                      s_axi_bresp,
    output logic                            s_axi_bvalid,
    input  logic                            s_axi_bready,
    // Read address channel
    input  logic [ADDR_WIDTH-1:0]           s_axi_araddr,
    input  logic [2:0]                      s_axi_arprot,
    input  logic                            s_axi_arvalid,
    output logic                            s_axi_arready,
    // Read data channel
    output logic [DATA_WIDTH-1:0]           s_axi_rdata,
    output logic [1:0]                      s_axi_rresp,
    output logic                            s_axi_rvalid,
    input  logic                            s_axi_rready
);

    logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH_WORDS-1];

    initial begin
        if (MEM_INIT_FILE != "") begin
            $display("[%0t] axi4lite_slave_mem: loading %s", $time, MEM_INIT_FILE);
            $readmemh(MEM_INIT_FILE, mem);
        end
    end

    //------------------------------------------------------------------
    // Write path
    //------------------------------------------------------------------
    logic bvalid_r;
    logic [1:0] bresp_r;

    assign s_axi_awready = ~bvalid_r;
    assign s_axi_wready  = ~bvalid_r;
    assign s_axi_bvalid  = bvalid_r;
    assign s_axi_bresp   = bresp_r;

    wire [ADDR_WIDTH-1:0] wr_word_idx = s_axi_awaddr >> 2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bvalid_r <= 1'b0;
            bresp_r  <= 2'b00;
        end else begin
            if (s_axi_awvalid && s_axi_wvalid && !bvalid_r) begin
                if (wr_word_idx < MEM_DEPTH_WORDS) begin
                    if (s_axi_wstrb[0]) mem[wr_word_idx][ 7: 0] <= s_axi_wdata[ 7: 0];
                    if (s_axi_wstrb[1]) mem[wr_word_idx][15: 8] <= s_axi_wdata[15: 8];
                    if (s_axi_wstrb[2]) mem[wr_word_idx][23:16] <= s_axi_wdata[23:16];
                    if (s_axi_wstrb[3]) mem[wr_word_idx][31:24] <= s_axi_wdata[31:24];
                    bresp_r <= 2'b00; // OKAY
                end else begin
                    bresp_r <= 2'b10; // SLVERR - out of range
                end
                bvalid_r <= 1'b1;
            end else if (bvalid_r && s_axi_bready) begin
                bvalid_r <= 1'b0;
            end
        end
    end

    //------------------------------------------------------------------
    // Read path
    //------------------------------------------------------------------
    logic rvalid_r;
    logic [1:0] rresp_r;
    logic [DATA_WIDTH-1:0] rdata_r;

    assign s_axi_arready = ~rvalid_r;
    assign s_axi_rvalid  = rvalid_r;
    assign s_axi_rresp   = rresp_r;
    assign s_axi_rdata   = rdata_r;

    wire [ADDR_WIDTH-1:0] rd_word_idx = s_axi_araddr >> 2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid_r <= 1'b0;
            rresp_r  <= 2'b00;
            rdata_r  <= '0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                if (rd_word_idx < MEM_DEPTH_WORDS) begin
                    rdata_r <= mem[rd_word_idx];
                    rresp_r <= 2'b00; // OKAY
                end else begin
                    rdata_r <= '0;
                    rresp_r <= 2'b10; // SLVERR
                end
                rvalid_r <= 1'b1;
            end else if (rvalid_r && s_axi_rready) begin
                rvalid_r <= 1'b0;
            end
        end
    end

endmodule