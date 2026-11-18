// =============================================================================
// sync — Multi-stage synchronizer
// =============================================================================
// From PULP common_cells. Synchronizes an asynchronous input signal
// through a chain of flip-flops.

module sync #(
    parameter int unsigned STAGES = 2
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic serial_i,
    output logic serial_o
);

    logic [STAGES-1:0] sync_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            sync_q <= '0;
        end else begin
            sync_q <= {sync_q[STAGES-2:0], serial_i};
        end
    end

    assign serial_o = sync_q[STAGES-1];

endmodule : sync
