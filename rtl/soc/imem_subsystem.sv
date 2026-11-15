// =============================================================================
// imem_subsystem.sv
//
// AXI4-slave wrapper around the 16 KB Instruction SRAM macro (`i_sram_16kb`).
// Bridges the core's AXI4 IMEM master interface to the I-SRAM custom port
// protocol.
//
// Project    : 1-TOPS VEDA Secure IoT RISC-V SoC
// Instance   : u_imem in soc_top
// Interface  : AXI4 slave (read-only), 32-bit, single-beat (arlen=0)
// Memory     : 16 KB × 32 b (4096 words), 12-bit internal address
// Latency    : 1 cycle (SRAM registered read)
//
// Address mapping (within 16 KB IMEM region):
//   AXI4 araddr[13:2]  -->  i_sram_16kb.if_addr[11:0]
//   (araddr[1:0] ignored - all fetches are word-aligned)
//
// Note: Since the core's IMEM master only drives the AR + R channels,
// only those AXI4 channels are implemented here. Write channels are
// tied to always-not-ready.
// =============================================================================

module imem_subsystem #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32,
    // Local SRAM address width (16 KB / 4 B per word = 4096 words = 12 b)
    parameter int unsigned SRAM_AW    = 12
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // ---------------- AXI4 slave - AR channel ----------------
    input  logic [ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic                  s_axi_arvalid,
    output logic                  s_axi_arready,
    input  logic [7:0]            s_axi_arlen,     // expect 0
    input  logic [2:0]            s_axi_arsize,    // expect 3'b010
    input  logic [1:0]            s_axi_arburst,   // expect 2'b01 (INCR)

    // ---------------- AXI4 slave - R channel -----------------
    output logic [DATA_WIDTH-1:0] s_axi_rdata,
    output logic                  s_axi_rvalid,
    input  logic                  s_axi_rready,
    output logic [1:0]            s_axi_rresp,
    output logic                  s_axi_rlast,

    // ---------------- Debug / firmware-load port -------------
    // Used by on-chip debug or by the testbench to pre-load
    // firmware before reset release.
    input  logic                  dbg_we,
    input  logic [SRAM_AW-1:0]    dbg_addr,
    input  logic [DATA_WIDTH-1:0] dbg_wdata,
    output logic                  dbg_ack,

    // ---------------- Side-band from system control ----------
    input  logic                  prefetch_en,
    input  logic                  mem_sleep,
    output logic                  mem_sleep_ack,
    output logic                  parity_err
);

    // ------------------------------------------------------------------
    // FSM states
    // ------------------------------------------------------------------
    typedef enum logic [1:0] {
        IDLE    = 2'd0,  // waiting for AR
        READ    = 2'd1,  // if_req high, SRAM read in progress
        RESP    = 2'd2   // RVALID asserted, waiting for RREADY
    } state_e;

    state_e state, state_n;

    // Address latched from AXI AR
    logic [SRAM_AW-1:0]    if_addr_lat;
    logic [DATA_WIDTH-1:0] if_rdata_q;
    logic                  if_valid_q;

    // ------------------------------------------------------------------
    // SRAM interface signals
    // ------------------------------------------------------------------
    logic                  if_req;
    logic [SRAM_AW-1:0]    if_addr;
    logic [DATA_WIDTH-1:0] if_rdata;
    logic                  if_valid;

    // ------------------------------------------------------------------
    // SRAM instance
    // ------------------------------------------------------------------
    i_sram_16kb #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (SRAM_AW)
    ) u_i_sram (
        .clk           (clk),
        .rst_n         (rst_n),
        .if_req        (if_req),
        .if_addr       (if_addr),
        .if_rdata      (if_rdata),
        .if_valid      (if_valid),
        .dbg_we        (dbg_we),
        .dbg_addr      (dbg_addr),
        .dbg_wdata     (dbg_wdata),
        .dbg_ack       (dbg_ack),
        .prefetch_en   (prefetch_en),
        .mem_sleep     (mem_sleep),
        .mem_sleep_ack (mem_sleep_ack),
        .parity_err    (parity_err)
    );

    // ------------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------------
    always_comb begin
        state_n = state;
        unique case (state)
            IDLE: if (s_axi_arvalid) state_n = READ;
            READ: if (if_valid)      state_n = RESP;
            RESP: if (s_axi_rready)  state_n = IDLE;
            default: state_n = IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= state_n;
    end

    // Latch address on AR handshake
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_addr_lat <= '0;
        end else if (state == IDLE && s_axi_arvalid) begin
            // araddr[13:2] -> SRAM word address (araddr[1:0] assumed 00)
            if_addr_lat <= s_axi_araddr[SRAM_AW+1:2];
        end
    end

    // Latch SRAM read data when valid
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_rdata_q <= '0;
            if_valid_q <= 1'b0;
        end else if (state == READ && if_valid) begin
            if_rdata_q <= if_rdata;
            if_valid_q <= 1'b1;
        end else if (state == RESP && s_axi_rready) begin
            if_valid_q <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // Drive SRAM port
    // ------------------------------------------------------------------
    assign if_req  = (state == IDLE && s_axi_arvalid) || (state == READ && !if_valid);
    assign if_addr = (state == IDLE) ? s_axi_araddr[SRAM_AW+1:2] : if_addr_lat;

    // ------------------------------------------------------------------
    // AXI4 outputs
    // ------------------------------------------------------------------
    assign s_axi_arready = (state == IDLE);
    assign s_axi_rvalid  = (state == RESP);
    assign s_axi_rdata   = if_rdata_q;
    assign s_axi_rresp   = parity_err ? 2'b10 : 2'b00;  // SLVERR on parity, else OKAY
    assign s_axi_rlast   = 1'b1;                        // single beat always last

    // ------------------------------------------------------------------
    // Protocol assertions (sim-only)
    // ------------------------------------------------------------------
    // synopsys translate_off
    always_ff @(posedge clk) begin
        if (rst_n && s_axi_arvalid) begin
            assert (s_axi_arlen  == 8'd0)   else $error("imem_subsystem: only single-beat (arlen=0) supported");
            assert (s_axi_arsize == 3'b010) else $error("imem_subsystem: only 4-byte accesses (arsize=010) supported");
            assert (s_axi_araddr[1:0] == 2'b00) else $error("imem_subsystem: unaligned araddr");
        end
    end
    // synopsys translate_on

endmodule
