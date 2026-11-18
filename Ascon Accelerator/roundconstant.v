`timescale 1ns / 1ps
module roundconstant (
    input   [63:0]  x2,
    input   [4:0]   ctr,
    input   [4:0]   rounds,
    output  [63:0]  out
);

    reg [7:0] rc;

    always @(*) begin
        case ((5'd12 - rounds) + (ctr - 5'd1))
            5'd0:    rc = 8'hf0;
            5'd1:    rc = 8'he1;
            5'd2:    rc = 8'hd2;
            5'd3:    rc = 8'hc3;
            5'd4:    rc = 8'hb4;
            5'd5:    rc = 8'ha5;
            5'd6:    rc = 8'h96;
            5'd7:    rc = 8'h87;
            5'd8:    rc = 8'h78;
            5'd9:    rc = 8'h69;
            5'd10:   rc = 8'h5a;
            5'd11:   rc = 8'h4b;
            default: rc = 8'h00;
        endcase
    end

    assign out = x2 ^ {56'd0, rc};

endmodule
