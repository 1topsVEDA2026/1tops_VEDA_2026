`timescale 1ns / 1ps

module csr_regfile (
    input  logic        clk,
    input  logic        rst_n,

    // ----------------------------------------------------------------
    // Read port (DE stage — combinational)
    // ----------------------------------------------------------------
    input  logic [11:0] csr_raddr,
    output logic [31:0] csr_rdata,

    // ----------------------------------------------------------------
    // Write port (MW stage — clocked)
    // Regular CSR writes from CSRRW/CSRRS/CSRRC instructions
    // ----------------------------------------------------------------
    input  logic [11:0] csr_waddr,
    input  logic [31:0] csr_wdata,
    input  logic        csr_we,

    // ----------------------------------------------------------------
    // Trap handling (DE stage — clocked at posedge)
    // Priority: trap > mret > regular CSR write
    // ----------------------------------------------------------------
    input  logic        epc_taken_IF,
    input  logic [31:0] trap_pc,        // PC of trapping instruction → mepc
    input  logic [31:0] trap_cause,     // Cause code → mcause

    // ----------------------------------------------------------------
    // MRET (DE stage — clocked at posedge)
    // ----------------------------------------------------------------
    input  logic        is_mret,

    // ----------------------------------------------------------------
    // Outputs for PC mux
    // ----------------------------------------------------------------
    output logic [31:0] epc_pc,
    output logic [31:0] mtvec_out,

    // ----------------------------------------------------------------
    // External interrupt lines
    // ----------------------------------------------------------------
    input  logic        irq_external,
    input  logic        irq_timer,
    input  logic        irq_software
);

    // ================================================================
    // CSR Address Map (Machine Mode)
    // ================================================================
    localparam logic [11:0] ADDR_MSTATUS  = 12'h300;
    localparam logic [11:0] ADDR_MISA     = 12'h301;
    localparam logic [11:0] ADDR_MIE      = 12'h304;
    localparam logic [11:0] ADDR_MTVEC    = 12'h305;
    localparam logic [11:0] ADDR_MSCRATCH = 12'h340;
    localparam logic [11:0] ADDR_MEPC     = 12'h341;
    localparam logic [11:0] ADDR_MCAUSE   = 12'h342;
    localparam logic [11:0] ADDR_MTVAL    = 12'h343;
    localparam logic [11:0] ADDR_MIP      = 12'h344;

    // ================================================================
    // CSR Registers
    // ================================================================
    logic [31:0] mstatus;
    logic [31:0] mie;
    logic [31:0] mtvec;
    logic [31:0] mscratch;
    logic [31:0] mepc;
    logic [31:0] mcause;
    logic [31:0] mtval;
    logic [31:0] mip;

    // MISA: RV32IM, read-only
    localparam logic [31:0] MISA_VAL = {2'b01,             // MXL = 32-bit
                                        4'b0000,           // reserved
                                        26'b00000000000001000100000000}; // I + M

    // ================================================================
    // Combinational read port
    // ================================================================
    always_comb begin
        case (csr_raddr)
            ADDR_MSTATUS:  csr_rdata = mstatus;
            ADDR_MISA:     csr_rdata = MISA_VAL;
            ADDR_MIE:      csr_rdata = mie;
            ADDR_MTVEC:    csr_rdata = mtvec;
            ADDR_MSCRATCH: csr_rdata = mscratch;
            ADDR_MEPC:     csr_rdata = mepc;
            ADDR_MCAUSE:   csr_rdata = mcause;
            ADDR_MTVAL:    csr_rdata = mtval;
            ADDR_MIP:      csr_rdata = mip;
            default:       csr_rdata = 32'd0;
        endcase
    end

    // ================================================================
    // Output assignments
    // ================================================================
    assign epc_pc  = mepc;
    assign mtvec_out = mtvec;

    // ================================================================
    // Clocked write logic
    // Priority: epc_taken_IF > is_mret > regular csr_we
    // ================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus  <= 32'd0;
            mie      <= 32'd0;
            mtvec    <= 32'd0;
            mscratch <= 32'd0;
            mepc     <= 32'd0;
            mcause   <= 32'd0;
            mtval    <= 32'd0;
            mip      <= 32'd0;
        end else begin
            // --------------------------------------------------------
            // Interrupt pending bits (directly wired)
            // --------------------------------------------------------
            mip[11] <= irq_external;   // MEIP — Machine External
            mip[7]  <= irq_timer;      // MTIP — Machine Timer
            mip[3]  <= irq_software;   // MSIP — Machine Software

            // --------------------------------------------------------
            // Trap entry — highest priority
            // --------------------------------------------------------
            if (epc_taken_IF) begin
                mepc              <= trap_pc;
                mcause            <= trap_cause;
                mstatus[7]        <= mstatus[3];      // MPIE <= MIE
                mstatus[3]        <= 1'b0;             // MIE  <= 0 (disable interrupts)
                mstatus[12:11]    <= 2'b11;            // MPP  <= Machine mode
            end
            // --------------------------------------------------------
            // MRET — restore interrupt state
            // --------------------------------------------------------
            else if (is_mret) begin
                mstatus[3]        <= mstatus[7];      // MIE  <= MPIE
                mstatus[7]        <= 1'b1;             // MPIE <= 1
                mstatus[12:11]    <= 2'b00;            // MPP  <= lowest privilege
            end
            // --------------------------------------------------------
            // Regular CSR write (from CSRRW/CSRRS/CSRRC in MW)
            // --------------------------------------------------------
            else if (csr_we) begin
                case (csr_waddr)
                    ADDR_MSTATUS:  mstatus  <= csr_wdata;
                    ADDR_MIE:      mie      <= csr_wdata;
                    ADDR_MTVEC:    mtvec    <= csr_wdata;
                    ADDR_MSCRATCH: mscratch <= csr_wdata;
                    ADDR_MEPC:     mepc     <= csr_wdata;
                    ADDR_MCAUSE:   mcause   <= csr_wdata;
                    ADDR_MTVAL:    mtval    <= csr_wdata;
                    default: ;
                endcase
            end
        end
    end

endmodule
