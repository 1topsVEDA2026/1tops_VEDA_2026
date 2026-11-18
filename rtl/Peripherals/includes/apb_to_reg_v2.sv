// =============================================================================
// apb_to_reg_v2 — APB to Register Interface Bridge (struct-based)
// =============================================================================
// Used by CLINT's clic_apb to convert APB to reg_req_t/reg_rsp_t structs.
// Note: pstrb_i is optional (defaults to all-ones if not connected).

module apb_to_reg_v2 #(
    parameter type reg_req_t = logic,
    parameter type reg_rsp_t = logic,
    parameter bit  Feedthrough = 1'b0
)(
    input  logic clk_i,
    input  logic rst_ni,

    // APB slave side (flat signals)
    input  logic        penable_i,
    input  logic        pwrite_i,
    input  logic [31:0] paddr_i,
    input  logic        psel_i,
    input  logic [31:0] pwdata_i,
    output logic [31:0] prdata_o,
    output logic        pready_o,
    output logic        pslverr_o,

    // Register interface (struct-based)
    output reg_req_t    reg_req_o,
    input  reg_rsp_t    reg_rsp_i
);

    // APB state machine
    typedef enum logic {IDLE, ACCESS} apb_state_t;
    apb_state_t state_q, state_d;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            state_q <= IDLE;
        else
            state_q <= state_d;
    end

    always_comb begin
        state_d          = state_q;
        reg_req_o.valid  = 1'b0;
        reg_req_o.addr   = paddr_i;
        reg_req_o.write  = pwrite_i;
        reg_req_o.wdata  = pwdata_i;
        reg_req_o.wstrb  = 4'hF;
        prdata_o         = reg_rsp_i.rdata;
        pready_o         = 1'b0;
        pslverr_o        = 1'b0;

        unique case (state_q)
            IDLE: begin
                if (psel_i && !penable_i) begin
                    state_d         = ACCESS;
                    reg_req_o.valid = 1'b1;
                end
            end
            ACCESS: begin
                reg_req_o.valid = 1'b1;
                if (reg_rsp_i.ready) begin
                    pready_o  = 1'b1;
                    pslverr_o = reg_rsp_i.error;
                    prdata_o  = reg_rsp_i.rdata;
                    state_d   = IDLE;
                end
            end
            default: state_d = IDLE;
        endcase
    end

endmodule : apb_to_reg_v2
