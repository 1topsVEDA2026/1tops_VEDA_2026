// =============================================================================
// dmem_subsystem.sv
//
// AXI4-slave wrapper around the 16 KB Data SRAM macro (`d_sram_16kb`).
// Bridges the core's AXI4 DMEM master interface to the D-SRAM custom port
// protocol (cs_n / we_n / addr / wdata / be / rdata / ready).
//
// Project    : 1-TOPS VEDA Secure IoT RISC-V SoC
// Instance   : u_dmem in soc_top
// Interface  : AXI4 slave (full R/W), 32-bit, single-beat (arlen=awlen=0)
// Memory     : 16 KB x 32 b (4096 words), 12-bit internal address, 4-bit BE
// Latency    : 1 cycle (SRAM registered read, synchronous write)
//
// Address mapping (within 16 KB DMEM region):
//   AXI4 (ar|aw)addr[13:2]  -->  d_sram_16kb.addr[11:0]
//   (addr[1:0] handled by byte-enable alignment)
//
// Read/write arbitration: writes take priority over reads (simple policy -
// the core issues at most one outstanding transaction so contention is rare).
// =============================================================================

module dmem_subsystem #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned BE_WIDTH   = 4,
    parameter int unsigned SRAM_AW    = 12
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // ---------------- AXI4 slave - AW channel ----------------
    input  logic [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic                  s_axi_awvalid,
    output logic                  s_axi_awready,
    input  logic [7:0]            s_axi_awlen,     // expect 0
    input  logic [2:0]            s_axi_awsize,
    input  logic [1:0]            s_axi_awburst,

    // ---------------- AXI4 slave - W channel -----------------
    input  logic [DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [BE_WIDTH-1:0]   s_axi_wstrb,
    input  logic                  s_axi_wvalid,
    output logic                  s_axi_wready,
    input  logic                  s_axi_wlast,

    // ---------------- AXI4 slave - B channel -----------------
    output logic                  s_axi_bvalid,
    input  logic                  s_axi_bready,
    output logic [1:0]            s_axi_bresp,

    // ---------------- AXI4 slave - AR channel ----------------
    input  logic [ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic                  s_axi_arvalid,
    output logic                  s_axi_arready,
    input  logic [7:0]            s_axi_arlen,
    input  logic [2:0]            s_axi_arsize,
    input  logic [1:0]            s_axi_arburst,

    // ---------------- AXI4 slave - R channel -----------------
    output logic [DATA_WIDTH-1:0] s_axi_rdata,
    output logic                  s_axi_rvalid,
    input  logic                  s_axi_rready,
    output logic [1:0]            s_axi_rresp,
    output logic                  s_axi_rlast,

    // ---------------- Side-band from system control ----------
    input  logic                  mem_sleep,
    input  logic                  mem_retain,
    output logic                  mem_sleep_ack,
    output logic                  ecc_single,
    output logic                  ecc_double
);

    // ------------------------------------------------------------------
    // FSM states
    // ------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE      = 3'd0,
        WR_ACCESS = 3'd1,   // SRAM write issued; wait 1 cycle for completion
        WR_RESP   = 3'd2,   // B channel handshake
        RD_ACCESS = 3'd3,   // SRAM read issued; data appears next cycle
        RD_RESP   = 3'd4    // R channel handshake
    } state_e;

    state_e state, state_n;

    // Latched transaction attributes
    logic [SRAM_AW-1:0]    addr_lat;
    logic [DATA_WIDTH-1:0] wdata_lat;
    logic [BE_WIDTH-1:0]   be_lat;

    // ------------------------------------------------------------------
    // SRAM interface
    // ------------------------------------------------------------------
    logic                  sram_cs_n;
    logic                  sram_we_n;
    logic [SRAM_AW-1:0]    sram_addr;
    logic [DATA_WIDTH-1:0] sram_wdata;
    logic [BE_WIDTH-1:0]   sram_be;
    logic [DATA_WIDTH-1:0] sram_rdata;
    logic                  sram_ready;

    // ------------------------------------------------------------------
    // SRAM instance
    // ------------------------------------------------------------------
    d_sram_16kb #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (SRAM_AW),
        .BE_WIDTH   (BE_WIDTH)
    ) u_d_sram (
        .clk           (clk),
        .rst_n         (rst_n),
        .cs_n          (sram_cs_n),
        .we_n          (sram_we_n),
        .addr          (sram_addr),
        .wdata         (sram_wdata),
        .be            (sram_be),
        .rdata         (sram_rdata),
        .ready         (sram_ready),
        .mem_sleep     (mem_sleep),
        .mem_retain    (mem_retain),
        .mem_sleep_ack (mem_sleep_ack),
        .ecc_single    (ecc_single),
        .ecc_double    (ecc_double)
    );

    // ------------------------------------------------------------------
    // Transaction arbitration (write-priority)
    // ------------------------------------------------------------------
    logic start_write, start_read;
    assign start_write = s_axi_awvalid && s_axi_wvalid;
    assign start_read  = s_axi_arvalid && !start_write;

    // ------------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------------
    always_comb begin
        state_n = state;
        unique case (state)
            IDLE:
                if (start_write)      state_n = WR_ACCESS;
                else if (start_read)  state_n = RD_ACCESS;
            WR_ACCESS: state_n = WR_RESP;
            WR_RESP:   if (s_axi_bready) state_n = IDLE;
            RD_ACCESS: state_n = RD_RESP;
            RD_RESP:   if (s_axi_rready) state_n = IDLE;
            default:   state_n = IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= state_n;
    end

    // Latch write/read attributes on transaction start
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_lat  <= '0;
            wdata_lat <= '0;
            be_lat    <= '0;
        end else if (state == IDLE) begin
            if (start_write) begin
                addr_lat  <= s_axi_awaddr[SRAM_AW+1:2];
                wdata_lat <= s_axi_wdata;
                be_lat    <= s_axi_wstrb;
            end else if (start_read) begin
                addr_lat  <= s_axi_araddr[SRAM_AW+1:2];
            end
        end
    end

    // ------------------------------------------------------------------
    // Latch read data for R-channel delivery
    // ------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] rdata_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata_q <= '0;
        end else if (state == RD_ACCESS) begin
            rdata_q <= sram_rdata;
        end
    end

    // ------------------------------------------------------------------
    // Drive SRAM signals
    // ------------------------------------------------------------------
    always_comb begin
        sram_cs_n  = 1'b1;
        sram_we_n  = 1'b1;
        sram_addr  = addr_lat;
        sram_wdata = wdata_lat;
        sram_be    = be_lat;
        unique case (state)
            WR_ACCESS: begin
                sram_cs_n = 1'b0;
                sram_we_n = 1'b0;
            end
            RD_ACCESS: begin
                sram_cs_n = 1'b0;
                sram_we_n = 1'b1;
            end
            default: ;
        endcase
    end

    // ------------------------------------------------------------------
    // AXI4 handshake outputs
    // ------------------------------------------------------------------
    // AW+W accepted together in IDLE when both valid
    assign s_axi_awready = (state == IDLE) && start_write;
    assign s_axi_wready  = (state == IDLE) && start_write;
    // AR accepted in IDLE when no write pending
    assign s_axi_arready = (state == IDLE) && start_read;

    // B channel
    assign s_axi_bvalid = (state == WR_RESP);
    assign s_axi_bresp  = ecc_double ? 2'b10 : 2'b00;

    // R channel
    assign s_axi_rvalid = (state == RD_RESP);
    assign s_axi_rdata  = rdata_q;
    assign s_axi_rresp  = ecc_double ? 2'b10 : 2'b00;
    assign s_axi_rlast  = 1'b1;

    // ------------------------------------------------------------------
    // Protocol assertions
    // ------------------------------------------------------------------
    // synopsys translate_off
    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (s_axi_arvalid) assert (s_axi_arlen == 8'd0) else $error("dmem_subsystem: only single-beat reads supported");
            if (s_axi_awvalid) assert (s_axi_awlen == 8'd0) else $error("dmem_subsystem: only single-beat writes supported");
        end
    end
    // synopsys translate_on

endmodule
