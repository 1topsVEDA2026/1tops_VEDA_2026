// =============================================================================
// apb_to_reg — APB to Register Interface Bridge
// =============================================================================
// Used by GPIO and other PULP peripherals.
// Converts flat APB signals to a REG_BUS interface.

module apb_to_reg (
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

    // Register interface (REG_BUS)
    REG_BUS.out         reg_o
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
        state_d     = state_q;
        reg_o.valid = 1'b0;
        reg_o.addr  = paddr_i;
        reg_o.write = pwrite_i;
        reg_o.wdata = pwdata_i;
        reg_o.wstrb = 4'hF;
        prdata_o    = reg_o.rdata;
        pready_o    = 1'b0;
        pslverr_o   = 1'b0;

        unique case (state_q)
            IDLE: begin
                if (psel_i && !penable_i) begin
                    state_d     = ACCESS;
                    reg_o.valid = 1'b1;
                end
            end
            ACCESS: begin
                reg_o.valid = 1'b1;
                if (reg_o.ready) begin
                    pready_o  = 1'b1;
                    pslverr_o = reg_o.error;
                    prdata_o  = reg_o.rdata;
                    state_d   = IDLE;
                end
            end
            default: state_d = IDLE;
        endcase
    end

endmodule : apb_to_reg
