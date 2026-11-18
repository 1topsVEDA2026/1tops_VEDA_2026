`timescale 1ns / 1ps
module Ascon #(
    parameter k = 128,
    parameter r = 64,
    parameter a = 12,
    parameter b = 6,
    parameter l = 40,
    parameter y = 40
)(
    input              clk,
    input              rst,
    input  [k-1:0]     key,
    input  [127:0]     nonce,
    input  [l-1:0]     associated_data,
    input  [y-1:0]     plain_text,
    input              encryption_start,
    input              decryption_start,

    output [y-1:0]     cipher_text,
    output [127:0]     tag,
    output [y-1:0]     dec_plain_text,
    output [127:0]     dec_tag,
    output             encryption_ready,
    output             decryption_ready,
    output             message_authentication
);

    // Encryption Instance
    Encryption #(k, r, a, b, l, y) enc_inst (
        .clk                (clk),
        .rst                (rst),
        .key                (key),
        .nonce              (nonce),
        .associated_data    (associated_data),
        .plain_text         (plain_text),
        .encryption_start   (encryption_start),
        .cipher_text        (cipher_text),
        .tag                (tag),
        .encryption_ready   (encryption_ready)
    );

    // Decryption Instance
    Decryption #(k, r, a, b, l, y) dec_inst (
        .clk                (clk),
        .rst                (rst),
        .key                (key),
        .nonce              (nonce),
        .associated_data    (associated_data),
        .cipher_text        (cipher_text),
        .decryption_start   (decryption_start),
        .plain_text         (dec_plain_text),
        .tag                (dec_tag),
        .decryption_ready   (decryption_ready)
    );

    assign message_authentication = (decryption_ready) ? (dec_tag == tag) : 0;

endmodule
