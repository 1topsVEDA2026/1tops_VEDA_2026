// ============================================================================
// booth_multiplier_radix4.sv Parameterized Radix-4 Booth Multiplier
//
// Computes: product = $signed(a) * $signed(b)
// Both operands treated as signed WIDTH-bit two's complement.
// Output: 2*WIDTH-bit signed product.
//
// Portable: pure combinational RTL, synthesizes in Vivado, Questa (sim),
// and Synopsys DC (where the tool will further compress the adder tree
// using PDK-optimal compressors for TSMC/ASAP7).
//
// Architecture:
//   1. Radix-4 Booth encoding of multiplier (b): groups 2 bits at a time
//       ceil((WIDTH+1)/2) partial products instead of WIDTH
//   2. Each partial product is one of: 0, ±A, ±2A
//   3. Balanced binary adder tree sums all aligned partial products
//   4. DC/Genus will restructure into Wallace/Dadda compressor tree
// ============================================================================

`timescale 1ns / 1ps

module booth_multiplier_radix4 #(
    parameter int WIDTH = 33
) (
    input  logic [WIDTH-1:0]   a,
    input  logic [WIDTH-1:0]   b,
    output logic [2*WIDTH-1:0] product
);

    // ----------------------------------------------------------------
    // Number of Radix-4 groups (each covers 2 bits of b)
    // ----------------------------------------------------------------
    localparam int NUM_PP     = (WIDTH + 1 + 1) / 2;   // ceil((WIDTH+1)/2)
    localparam int EXT_WIDTH  = 2*NUM_PP + 1;           // bits needed in b_ext
    localparam int SIGN_EXT   = EXT_WIDTH - 1 - WIDTH;  // extra sign bits on b

    // ----------------------------------------------------------------
    // Extend b: sign-extend to EXT_WIDTH-1 bits, then append LSB '0'
    // (the appended 0 makes group 0 read {b[1], b[0], 0})
    // ----------------------------------------------------------------
    logic [EXT_WIDTH-1:0] b_ext;
    assign b_ext = { {SIGN_EXT{b[WIDTH-1]}}, b, 1'b0 };

    // ----------------------------------------------------------------
    // 2*A, needed for the "+2A"/"-2A" cases. WIDTH+1 bits avoids overflow.
    // ----------------------------------------------------------------
    logic signed [WIDTH:0] a_sext, a_x2;
    assign a_sext = {a[WIDTH-1], a};            // sign-extended A
    assign a_x2   = a_sext <<< 1;               // 2A (no overflow)

    // ----------------------------------------------------------------
    // Per-group Booth decode -> signed partial product (WIDTH+1 bits)
    // ----------------------------------------------------------------
    logic signed [WIDTH:0] booth_pp [NUM_PP-1:0];

    genvar i;
    generate
        for (i = 0; i < NUM_PP; i++) begin : g_booth_decode
            logic [2:0] grp;
            assign grp = b_ext[2*i+2 -: 3];   // {b[2i+1], b[2i], b[2i-1]}

            always @(*) begin
                unique case (grp)
                    3'b000, 3'b111: booth_pp[i] =  '0;
                    3'b001, 3'b010: booth_pp[i] =  a_sext;
                    3'b011:         booth_pp[i] =  a_x2;
                    3'b100:         booth_pp[i] = -a_x2;
                    3'b101, 3'b110: booth_pp[i] = -a_sext;
                    default:        booth_pp[i] =  '0;
                endcase
            end
        end
    endgenerate

    // ----------------------------------------------------------------
    // Align each PP to full product width (2*WIDTH bits), sign-extended,
    // shifted left by 2*i.
    // ----------------------------------------------------------------
    logic signed [2*WIDTH-1:0] pp_aligned [NUM_PP-1:0];

    generate
        for (i = 0; i < NUM_PP; i++) begin : g_align
            localparam int SHIFT     = 2*i;
            localparam int EXT_BITS  = 2*WIDTH - (WIDTH+1) - SHIFT;

            if (EXT_BITS > 0) begin : g_extend
                assign pp_aligned[i] = { {EXT_BITS{booth_pp[i][WIDTH]}},
                                          booth_pp[i],
                                          {SHIFT{1'b0}} };
            end else begin : g_trunc
                // Last group can overflow into the top bit exactly truncate safely
                assign pp_aligned[i] = { booth_pp[i], {SHIFT{1'b0}} } [2*WIDTH-1:0];
            end
        end
    endgenerate

    // ----------------------------------------------------------------
    // Sum all partial products balanced binary reduction tree.
    // Written explicitly so every synthesis tool sees the parallelism
    // and restructures into a compressor tree.
    // ----------------------------------------------------------------
    localparam int TREE_DEPTH = $clog2(NUM_PP);

    // We use a flattened 2-D array for the reduction stages.
    // stage[0][*] = pp_aligned, stage[d][*] = reduced partial sums.
    // Max entries at any stage = NUM_PP.
    logic signed [2*WIDTH-1:0] tree_stage [0:TREE_DEPTH][0:NUM_PP-1];

    // Seed stage 0
    generate
        for (i = 0; i < NUM_PP; i++) begin : g_seed
            assign tree_stage[0][i] = pp_aligned[i];
        end
    endgenerate

    // Reduction stages
    generate
        for (genvar d = 0; d < TREE_DEPTH; d++) begin : g_tree_depth
            localparam int N_IN  = (NUM_PP + (1 << d) - 1) >> d; // entries at this stage
            localparam int N_OUT = (N_IN + 1) / 2;                // entries after pairing

            for (genvar k = 0; k < N_OUT; k++) begin : g_tree_add
                if (2*k + 1 < N_IN) begin : g_pair
                    assign tree_stage[d+1][k] = tree_stage[d][2*k] + tree_stage[d][2*k+1];
                end else begin : g_pass
                    assign tree_stage[d+1][k] = tree_stage[d][2*k];
                end
            end
        end
    endgenerate

    assign product = tree_stage[TREE_DEPTH][0];

endmodule
