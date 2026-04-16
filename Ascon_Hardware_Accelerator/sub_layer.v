`timescale 1ns / 1ps
module sub_layer (
    input  [63:0] x0, x1, x2, x3, x4,
    output [63:0] sl0, sl1, sl2, sl3, sl4
);
    assign sl0 = (x4 & x1) ^ x3 ^ (x2 & x1) ^ x2 ^ (x1 & x0) ^ x1 ^ x0;      
    assign sl1 = x4 ^ (x3 & x2) ^ (x3 & x1) ^ x3 ^ x2 ^ x1 ^ x0 ^ (x2 & x1);
    assign sl2 = (x4 & x3) ^ x4 ^ x2 ^ x1 ^ 64'hffffffffffffffff;               
    assign sl3 = (x4 & x0) ^ (x3 & x0) ^ x4 ^ x3 ^ x2 ^ x1 ^ x0;                 
    assign sl4 = (x4 & x1) ^ x4 ^ x3 ^ (x1 & x0) ^ x1;                          
endmodule