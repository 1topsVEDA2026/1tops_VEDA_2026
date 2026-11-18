// =============================================================================
// APB Address Decoder / Interconnect
// =============================================================================
// Routes APB transactions from a single master port to multiple slave
// peripherals based on address decoding.
//
// Address Map (4KB per peripheral, configurable base):
//   Slot 0: 0x0000_0000 — UART
//   Slot 1: 0x0000_1000 — SPI
//   Slot 2: 0x0000_2000 — GPIO
//   Slot 3: 0x0000_3000 — Timer
//   Slot 4: 0x0000_4000 — Watchdog Timer
//   Slot 5: 0x0000_5000 — PLIC
//   Slot 6: 0x0000_6000 — CLINT (needs >4KB but first 4KB accessed here)
//
// Each peripheral is allocated 4KB (12-bit offset within slot).
// Bits [14:12] of the address select the peripheral.

module apb_interconnect #(
    parameter int NUM_SLAVES    = 7,
    parameter int ADDR_WIDTH    = 32,
    parameter int DATA_WIDTH    = 32,
    parameter int SLOT_ADDR_BITS = 12   // 4KB per slot
)(
    // =========================================================================
    // APB Master Port (from core / AXI-to-APB bridge / VIP)
    // =========================================================================
    input  logic                    psel_i,
    input  logic                    penable_i,
    input  logic                    pwrite_i,
    input  logic [ADDR_WIDTH-1:0]  paddr_i,
    input  logic [DATA_WIDTH-1:0]  pwdata_i,
    input  logic [DATA_WIDTH/8-1:0] pstrb_i,
    output logic [DATA_WIDTH-1:0]  prdata_o,
    output logic                    pready_o,
    output logic                    pslverr_o,

    // =========================================================================
    // APB Slave Ports (to peripherals)
    // =========================================================================
    output logic [NUM_SLAVES-1:0]                   psel_o,
    output logic                                    penable_o,
    output logic                                    pwrite_o,
    output logic [ADDR_WIDTH-1:0]                   paddr_o,
    output logic [DATA_WIDTH-1:0]                    pwdata_o,
    output logic [DATA_WIDTH/8-1:0]                  pstrb_o,
    input  logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0]   prdata_i,
    input  logic [NUM_SLAVES-1:0]                   pready_i,
    input  logic [NUM_SLAVES-1:0]                   pslverr_i
);

    // =========================================================================
    // Address Decode
    // =========================================================================
    // Use bits above the slot offset to select the peripheral.
    // With SLOT_ADDR_BITS=12 and NUM_SLAVES=7, we need 3 bits → [14:12]
    localparam SLAVE_SEL_BITS = $clog2(NUM_SLAVES);
    logic [SLAVE_SEL_BITS-1:0] slave_sel;

    assign slave_sel = paddr_i[SLOT_ADDR_BITS + SLAVE_SEL_BITS - 1 : SLOT_ADDR_BITS];

    // =========================================================================
    // PSEL Decode — one-hot select to peripherals
    // =========================================================================
    always_comb begin
        psel_o = '0;
        if (psel_i && slave_sel < NUM_SLAVES) begin
            psel_o[slave_sel] = 1'b1;
        end
    end

    // =========================================================================
    // Pass-through signals (shared bus)
    // =========================================================================
    assign penable_o = penable_i;
    assign pwrite_o  = pwrite_i;
    assign paddr_o   = paddr_i;       // Full address passed; peripheral uses lower bits
    assign pwdata_o  = pwdata_i;
    assign pstrb_o   = pstrb_i;

    // =========================================================================
    // Response Mux — select response from active peripheral
    // =========================================================================
    always_comb begin
        prdata_o  = '0;
        pready_o  = 1'b1;     // Default ready (no peripheral selected)
        pslverr_o = 1'b0;

        if (psel_i && slave_sel < NUM_SLAVES) begin
            prdata_o  = prdata_i[slave_sel];
            pready_o  = pready_i[slave_sel];
            pslverr_o = pslverr_i[slave_sel];
        end
    end

endmodule : apb_interconnect
