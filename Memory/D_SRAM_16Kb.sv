module d_sram_16kb #(
  parameter DATA_WIDTH = 32,
  parameter ADDR_WIDTH = 12,   // 4096 locations x 32-bit = 16 KB
  parameter BE_WIDTH   = 4     // Byte-enable: 1 bit per byte lane
) (
  // ---- Clock & Reset -----------------------------------------
  input  logic                  clk,
  input  logic                  rst_n,         // Active-low reset
 
  // ---- CPU / AHB-Lite Bus Interface --------------------------
  input  logic                  cs_n,          // Chip Select (active low)
  input  logic                  we_n,          // Write Enable (active low)
  input  logic [ADDR_WIDTH-1:0] addr,          // Word address
  input  logic [DATA_WIDTH-1:0] wdata,         // Write data
  input  logic [BE_WIDTH-1:0]   be,            // Byte enable (1 bit per byte)
  output logic [DATA_WIDTH-1:0] rdata,         // Read data (1-cycle latency)
  output logic                  ready,         // Transaction complete
 
  // ---- Power Management Interface ----------------------------
  input  logic                  mem_sleep,     // Request sleep/power-down
  input  logic                  mem_retain,    // Retention mode (content held)
  output logic                  mem_sleep_ack, // Sleep acknowledged
 
  // ---- ECC Interface -----------------------------------------
  output logic                  ecc_single,    // Single-bit correctable error
  output logic                  ecc_double     // Double-bit uncorrectable error
);
 
  // ------------------------------------------------------------------
  //  Memory array
  //  (* ram_style = "block" *) forces Vivado to use BRAM primitives
  //  and prevents the "dissolve to bits" fallback that causes
  //  [Synth 8-3391] when a non-standard write pattern is used.
  // ------------------------------------------------------------------
  (* ram_style = "block" *)
  logic [DATA_WIDTH-1:0] mem_array [0:(2**ADDR_WIDTH)-1];
 
  // ------------------------------------------------------------------
  //  ECC syndrome (stub - full ECC engine is memory-compiler supplied)
  // ------------------------------------------------------------------
  logic [6:0] syndrome_r;
 
  // ------------------------------------------------------------------
  //  Power / control FSM
  // ------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ready         <= 1'b0;
      mem_sleep_ack <= 1'b0;
    end else if (mem_sleep) begin
      // Enter sleep - de-assert ready, acknowledge
      mem_sleep_ack <= 1'b1;
      ready         <= 1'b0;
    end else begin
      mem_sleep_ack <= 1'b0;
      ready         <= 1'b1;
    end
  end
 
  // ------------------------------------------------------------------
  //  Write port - Vivado BRAM byte-enable inference template
  //  A generate-for loop over each byte lane is the only pattern
  //  that Vivado reliably infers as BRAM with byte enables.
  //  Do NOT use conditional partial-word assignments outside a
  //  generate block - that triggers [Synth 8-3391].
  // ------------------------------------------------------------------
  genvar i;
  generate
    for (i = 0; i < BE_WIDTH; i++) begin : gen_byte_write
      always_ff @(posedge clk) begin
        if (!cs_n && !we_n && !mem_sleep && !mem_retain) begin
          if (be[i])
            mem_array[addr][i*8 +: 8] <= wdata[i*8 +: 8];
        end
      end
    end
  endgenerate
 
  // ------------------------------------------------------------------
  //  Read port - synchronous, 1-cycle latency
  //  Must be in a separate always block from the write port so that
  //  Vivado correctly identifies the read-first / write-first mode.
  // ------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rdata <= '0;
    end else if (!cs_n && we_n && !mem_sleep) begin
      rdata <= mem_array[addr];
    end else begin
      rdata <= '0;
    end
  end
 
  // ------------------------------------------------------------------
  //  ECC outputs - Hamming syndrome decode stub
  //  In a real flow the memory compiler wraps the array with a
  //  full SEC-DED encoder/decoder; syndrome_r is driven by that
  //  wrapper.  Here we expose the ports cleanly for integration.
  // ------------------------------------------------------------------
  assign syndrome_r  = 7'h0;           // driven by ECC wrapper in full flow
  assign ecc_single  = (syndrome_r != 7'h0) &&  $onehot(syndrome_r);
  assign ecc_double  = (syndrome_r != 7'h0) && !$onehot(syndrome_r);
 
endmodule
