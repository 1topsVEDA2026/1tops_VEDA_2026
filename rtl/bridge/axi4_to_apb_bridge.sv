`timescale 1ns / 1ps
// ============================================================================
// axi4_to_apb_bridge.sv — AXI4 Master to APB Slave Protocol Bridge
//
// Converts AXI4 memory read/write requests from the RISC-V Core DMEM Master
// into 2-cycle APB bus transactions for the Peripheral Subsystem.
// ============================================================================

module axi4_to_apb_bridge (
    input  logic        clk,
    input  logic        rst_n,

    // ====================================================================
    // AXI4 Slave Interface (from RISC-V Core DMEM Master)
    // ====================================================================
    // AW Channel
    input  logic [31:0] axi_awaddr,
    input  logic        axi_awvalid,
    output logic        axi_awready,
    input  logic [ 2:0] axi_awsize,
    // W Channel
    input  logic [31:0] axi_wdata,
    input  logic [ 3:0] axi_wstrb,
    input  logic        axi_wvalid,
    output logic        axi_wready,
    // B Channel
    output logic        axi_bvalid,
    output logic [ 1:0] axi_bresp,
    input  logic        axi_bready,
    // AR Channel
    input  logic [31:0] axi_araddr,
    input  logic        axi_arvalid,
    output logic        axi_arready,
    input  logic [ 2:0] axi_arsize,
    // R Channel
    output logic [31:0] axi_rdata,
    output logic        axi_rvalid,
    output logic [ 1:0] axi_rresp,
    output logic        axi_rlast,
    input  logic        axi_rready,

    // ====================================================================
    // APB Master Interface (to Peripheral Subsystem)
    // ====================================================================
    output logic [31:0] apb_paddr,
    output logic [31:0] apb_pwdata,
    output logic        apb_pwrite,
    output logic        apb_psel,
    output logic        apb_penable,
    input  logic [31:0] apb_prdata,
    input  logic        apb_pready,
    input  logic        apb_pslverr
);

    typedef enum logic [2:0] {
        ST_IDLE      = 3'b000,
        ST_APB_SETUP = 3'b001,
        ST_APB_EN    = 3'b010,
        ST_AXI_RRESP = 3'b011,
        ST_AXI_BRESP = 3'b100
    } bridge_state_t;

    bridge_state_t state, next_state;

    logic [31:0] addr_reg;
    logic [31:0] wdata_reg;
    logic        write_req_reg;
    logic [31:0] rdata_reg;
    logic        err_reg;

    // FSM State Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            addr_reg      <= 32'd0;
            wdata_reg     <= 32'd0;
            write_req_reg <= 1'b0;
            rdata_reg     <= 32'd0;
            err_reg       <= 1'b0;
        end else begin
            state <= next_state;

            if (state == ST_IDLE) begin
                if (axi_awvalid && axi_wvalid) begin
                    addr_reg      <= axi_awaddr;
                    wdata_reg     <= axi_wdata;
                    write_req_reg <= 1'b1;
                end else if (axi_arvalid) begin
                    addr_reg      <= axi_araddr;
                    write_req_reg <= 1'b0;
                end
            end

            if (state == ST_APB_EN && apb_pready) begin
                rdata_reg <= apb_prdata;
                err_reg   <= apb_pslverr;
            end
        end
    end

    // FSM Next State Logic
    always_comb begin
        next_state = state;
        case (state)
            ST_IDLE: begin
                if (axi_awvalid && axi_wvalid)
                    next_state = ST_APB_SETUP;
                else if (axi_arvalid)
                    next_state = ST_APB_SETUP;
            end

            ST_APB_SETUP: begin
                next_state = ST_APB_EN;
            end

            ST_APB_EN: begin
                if (apb_pready) begin
                    if (write_req_reg)
                        next_state = ST_AXI_BRESP;
                    else
                        next_state = ST_AXI_RRESP;
                end
            end

            ST_AXI_RRESP: begin
                if (axi_rready)
                    next_state = ST_IDLE;
            end

            ST_AXI_BRESP: begin
                if (axi_bready)
                    next_state = ST_IDLE;
            end

            default: next_state = ST_IDLE;
        endcase
    end

    // AXI Output Handshakes
    assign axi_awready = (state == ST_IDLE) && axi_awvalid && axi_wvalid;
    assign axi_wready  = (state == ST_IDLE) && axi_awvalid && axi_wvalid;
    assign axi_arready = (state == ST_IDLE) && !axi_awvalid && axi_arvalid;

    assign axi_rvalid  = (state == ST_AXI_RRESP);
    assign axi_rdata   = rdata_reg;
    assign axi_rresp   = err_reg ? 2'b10 : 2'b00; // SLVERR = 2'b10, OKAY = 2'b00
    assign axi_rlast   = 1'b1;

    assign axi_bvalid  = (state == ST_AXI_BRESP);
    assign axi_bresp   = err_reg ? 2'b10 : 2'b00;

    // APB Master Outputs
    assign apb_paddr   = addr_reg;
    assign apb_pwdata  = wdata_reg;
    assign apb_pwrite  = write_req_reg;
    assign apb_psel    = (state == ST_APB_SETUP) || (state == ST_APB_EN);
    assign apb_penable = (state == ST_APB_EN);

endmodule
