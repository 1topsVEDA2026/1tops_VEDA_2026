`timescale 1ns/1ps

module tb_simple;

    // Parameters - ASCON-128
    parameter k = 128;
    parameter r = 64; 
    parameter a = 12; 
    parameter b = 6;  
    parameter l = 40; 
    parameter y = 40;

    reg clk = 0;
    reg rst;

    reg  [k-1:0]  key;
    reg  [127:0]  nonce;
    reg  [l-1:0]  associated_data;
    reg  [y-1:0]  plain_text;
    reg           encryption_start;
    reg           decryption_start;

    wire [y-1:0]  cipher_text;
    wire [127:0]  tag;
    wire [y-1:0]  dec_plain_text;
    wire [127:0]  dec_tag;
    wire          encryption_ready;
    wire          decryption_ready;
    wire          message_authentication;

    always #5 clk = ~clk; // 100MHz clock

    Ascon #(
        .k(k), .r(r), .a(a), .b(b), .l(l), .y(y)
    ) dut (
        .clk(clk),
        .rst(rst),
        .key(key),
        .nonce(nonce),
        .associated_data(associated_data),
        .plain_text(plain_text),
        .encryption_start(encryption_start),
        .decryption_start(decryption_start),
        .cipher_text(cipher_text),
        .tag(tag),
        .dec_plain_text(dec_plain_text),
        .dec_tag(dec_tag),
        .encryption_ready(encryption_ready),
        .decryption_ready(decryption_ready),
        .message_authentication(message_authentication)
    );

    initial begin
        // Reset
        rst = 1;
        encryption_start = 0;
        decryption_start = 0;
        key = 0;
        nonce = 0;
        associated_data = 0;
        plain_text = 0;

        #20;
        rst = 0;
        #10;

        // Apply Inputs
        key             = 128'h99b0d3fae7f24b668037c6dbce7f8699;
        nonce           = 128'hbfab0eb2731a26c6c44903bc6a54fe12;
        associated_data = 40'h4153434f4e;
        plain_text      = 40'h6173636f6e;

        // ===================================
        // 1. Run Encryption
        // ===================================
        $display("\n--- ENCRYPTION START ---");
        $display("Input PT:   %h", plain_text);
        $display("Input AD:   %h", associated_data);
        
        encryption_start = 1;
        #10;
        encryption_start = 0;

        wait(encryption_ready);
        #10;
        $display("Output CT:  %h", cipher_text);
        $display("Output TAG: %h", tag);
        
        // ===================================
        // 2. Run Decryption
        // ===================================
        $display("\n--- DECRYPTION START ---");
        // Note: Ascon module internally loops CT to decryption input
        decryption_start = 1;
        #10;
        decryption_start = 0;

        wait(decryption_ready);
        #10;
        $display("Output PT:  %h", dec_plain_text);
        $display("Output TAG: %h", dec_tag);
        $display("Auth Pass:  %b\n", message_authentication);

        #40;
        $finish;
    end

endmodule
