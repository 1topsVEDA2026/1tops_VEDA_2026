`timescale 1ns / 1ps
module Decryption #(
    parameter k = 128,      // Key size (128 bits for ASCON-128)
    parameter r = 64,       // Rate (64 bits for ASCON-128)
    parameter a = 12,       // Number of rounds in initialization/finalization
    parameter b = 6,        // Number of rounds in intermediate permutation
    parameter l = 40,       // Length of associated data (in bits)
    parameter y = 40        // Length of ciphertext (in bits)
)(
    input           clk,
    input           rst,
    input  [k-1:0]  key,
    input  [127:0]  nonce,
    input  [l-1:0]  associated_data,
    input  [y-1:0]  cipher_text,
    input           decryption_start,

    output [y-1:0]  plain_text,
    output [127:0]  tag,
    output          decryption_ready
);

    // Internal Constants
    localparam c     = 320 - r;
    localparam nz_ad = ((l+1)%r == 0) ? 0 : r-((l+1)%r);
    localparam L     = l + 1 + nz_ad;
    localparam s     = L / r;
    localparam nz_p  = ((y+1)%r == 0) ? 0 : r-((y+1)%r);
    localparam Y     = y + 1 + nz_p;
    localparam t     = Y / r;

    // FSM State Encoding
    localparam IDLE            = 'd0,
               INITIALIZE      = 'd1,
               ASSOCIATED_DATA = 'd2,
               CTPT            = 'd3,
               FINALIZE        = 'd4,
               DONE            = 'd5;

    reg [2:0] state;

    // Internal Signals and Registers
    reg  [4:0]       rounds;
    reg  [127:0]     Tag;
    reg  [127:0]     Tag_d;
    reg              decryption_ready_1;

    // FIX 1: IV is always 64 bits for ASCON-128
    wire [63:0]      IV;
    reg  [319:0]     S;
    wire [r-1:0]     Sr;
    wire [c-1:0]     Sc;

    reg  [319:0]     P_in;
    wire [319:0]     P_out;
    wire             permutation_ready;
    reg              permutation_start;

    wire [L-1:0]     A;
    wire [Y-1:0]     C;
    reg  [Y-1:0]     P;
    reg  [Y-1:0]     P_d;

    reg  [t:0]       block_ctr;
    wire [4:0]       ctr;

    // FIX 1: Correct 64-bit IV per ASCON-128 spec
    assign IV              = {8'd128, 8'd64, 8'd12, 8'd6, 32'd0};
    assign {Sr, Sc}        = S;
    assign decryption_ready = decryption_ready_1;
    assign A               = {associated_data, 1'b1, {nz_ad{1'b0}}};
    assign C               = {cipher_text, 1'b1, {nz_p{1'b0}}};
    assign tag             = (decryption_ready_1) ? Tag : 0;
    assign plain_text      = (decryption_ready_1 && y > 0) ? P[Y-1 : Y-y] : 0;

    // Sequential Block
    always @(posedge clk) begin
        if(rst) begin
            state     <= IDLE;
            S         <= 0;
            Tag       <= 0;
            P         <= 0;
            block_ctr <= 0;
        end
        else begin
            case(state)

                IDLE: begin
                    // FIX 1: Correct initial state = IV || Key || Nonce = 320 bits
                    S <= {IV, key, nonce};
                    if(decryption_start)
                        state <= INITIALIZE;
                end

                INITIALIZE: begin
                    if(permutation_ready) begin
                        if (l != 0)
                            state <= ASSOCIATED_DATA;
                        else if (l == 0 && y != 0)
                            state <= CTPT;
                        else
                            state <= FINALIZE;
                        S <= P_out ^ {{(320-k){1'b0}}, key};
                    end
                end

                ASSOCIATED_DATA: begin
                    if(permutation_ready && block_ctr == s-1) begin
                        if (y != 0)
                            state <= CTPT;
                        else
                            state <= FINALIZE;
                        S <= P_out ^ ({{319{1'b0}}, 1'b1});
                    end
                    else if(permutation_ready && block_ctr != s)
                        S <= P_out;

                    if (permutation_ready && block_ctr == s-1)
                        block_ctr <= 0;
                    else if(permutation_ready && block_ctr != s)
                        block_ctr <= block_ctr + 1;
                end

                CTPT: begin
                    if(block_ctr == t-1) begin
                        state <= FINALIZE;
                        if (y > 0 && y%r != 0)
                            S <= {(Sr ^ {P_d[r-1 -: y%r], 1'b1, {(r-1-y%r){1'b0}}}), Sc};
                        else if (y > 0 && y%r == 0)
                            S <= {(Sr ^ {1'b0, 1'b1, {(r-2){1'b0}}}), Sc};
                        P <= P | P_d;       // FIX 2: bitwise OR, not addition
                    end
                    else if(permutation_ready && block_ctr != t) begin
                        S <= P_out;
                        P <= P | P_d;       // FIX 2: bitwise OR
                    end

                    if (permutation_ready && block_ctr == t-1)
                        block_ctr <= 0;
                    else if(permutation_ready && block_ctr != t)
                        block_ctr <= block_ctr + 1;
                end

                FINALIZE: begin
                    if(permutation_ready) begin
                        S     <= P_out;
                        state <= DONE;
                        Tag   <= Tag_d;
                    end
                end

                DONE: begin
                    if(decryption_start)
                        state <= IDLE;
                end

                default:
                    state <= IDLE;

            endcase
        end
    end

    // Combinational Block
    always @(*) begin
        P_d                = 0;
        Tag_d              = 0;
        decryption_ready_1 = 0;
        permutation_start  = 0;
        rounds             = a;
        P_in               = S;

        case (state)

            IDLE: begin
                P_d                = 0;
                Tag_d              = 0;
                decryption_ready_1 = 0;
                permutation_start  = 0;
                rounds             = a;
                P_in               = S;
            end

            INITIALIZE: begin
                P_d                = 0;
                Tag_d              = 0;
                decryption_ready_1 = 0;
                rounds             = a;
                permutation_start  = (permutation_ready) ? 1'b0 : 1'b1;
                P_in               = S;
            end

            ASSOCIATED_DATA: begin
                P_d                = 0;
                Tag_d              = 0;
                decryption_ready_1 = 0;
                rounds             = b;
                permutation_start  = (permutation_ready && block_ctr == (s-1)) ? 0 : 1;
                P_in               = {Sr ^ A[L-1-(block_ctr*r) -: r], Sc};
            end

            CTPT: begin
                P_d                = 0;
                Tag_d              = 0;
                decryption_ready_1 = 0;
                rounds             = b;
                P_d[Y-1-(block_ctr*r) -: r] = Sr ^ C[Y-1-(block_ctr*r) -: r];
                P_in               = {C[Y-1-(block_ctr*r) -: r], Sc};
                permutation_start  = (block_ctr == (t-1)) ? 0 : 1;
            end

            FINALIZE: begin
                P_d                = 0;
                decryption_ready_1 = 0;
                rounds             = a;
                P_in               = S ^ ({{r{1'b0}}, key, {(c-k){1'b0}}});
                permutation_start  = (permutation_ready) ? 1'b0 : 1'b1;
                Tag_d              = P_out[k-1:0] ^ key;
            end

            DONE: begin
                P_d                = 0;
                Tag_d              = 0;
                decryption_ready_1 = 1;
                rounds             = a;
                P_in               = 0;
                permutation_start  = 0;
            end

            default: begin
                P_d                = 0;
                Tag_d              = 0;
                rounds             = 0;
                P_in               = S;
                permutation_start  = 0;
                decryption_ready_1 = 0;
            end

        endcase
    end

    // Permutation Instance
    Permutation p1(
        .clk    (clk),
        .reset  (rst),
        .S      (P_in),
        .out    (P_out),
        .done   (permutation_ready),
        .ctr    (ctr),
        .rounds (rounds),
        .start  (permutation_start)
    );

    // Round Counter Instance
    RoundCounter RC(
        .clk               (clk),
        .rst               (rst),
        .permutation_start (permutation_start),
        .permutation_ready (permutation_ready),
        .counter           (ctr)
    );

endmodule
