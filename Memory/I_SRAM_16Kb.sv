module i_sram_16kb #(
  parameter DATA_WIDTH = 32,
  parameter ADDR_WIDTH = 12
) (
  input  logic                   clk,
  input  logic                   rst_n,

  // Fetch port
  input  logic                   if_req,
  input  logic [ADDR_WIDTH-1:0]  if_addr,
  output logic [DATA_WIDTH-1:0]  if_rdata,
  output logic                   if_valid,

  // Debug / DMA write
  input  logic                   dbg_we,
  input  logic [ADDR_WIDTH-1:0]  dbg_addr,
  input  logic [DATA_WIDTH-1:0]  dbg_wdata,
  output logic                   dbg_ack,

  // Prefetch enable
  input  logic                   prefetch_en,

  // Power
  input  logic                   mem_sleep,
  output logic                   mem_sleep_ack,

  // Parity
  output logic                   parity_err
);

  // ------------------------------------------------------------------
  //  Primary instruction BRAM - single write port, single read port
  //  Vivado template: exactly one always_ff write, one always_ff read,
  //  no conditions inside either block.
  // ------------------------------------------------------------------
  (* ram_style = "block" *)
  logic [DATA_WIDTH-1:0] imem [0:(2**ADDR_WIDTH)-1];

  // ------------------------------------------------------------------
  //  Prefetch shadow BRAM - identical content, read at addr+1
  //  Separate array so Vivado sees two clean single-port BRAMs
  //  rather than one dual-address read that it cannot infer.
  // ------------------------------------------------------------------
  (* ram_style = "block" *)
  logic [DATA_WIDTH-1:0] imem_pf [0:(2**ADDR_WIDTH)-1];

  // ------------------------------------------------------------------
  //  Parity array - distributed RAM (small, 4096 bits)
  // ------------------------------------------------------------------
  (* ram_style = "distributed" *)
  logic parity_arr [0:(2**ADDR_WIDTH)-1];

  // ------------------------------------------------------------------
  //  Registered outputs from both BRAMs (1-cycle latency)
  // ------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] imem_rdata;
  logic [DATA_WIDTH-1:0] pf_rdata;

  // ------------------------------------------------------------------
  //  Prefetch tracking
  // ------------------------------------------------------------------
  logic [ADDR_WIDTH-1:0] pf_addr_r;
  logic                  pf_valid_r;
  logic                  pf_hit;

  assign pf_hit = pf_valid_r && (pf_addr_r == if_addr);

  // ------------------------------------------------------------------
  //  Write port - primary BRAM
  //  Rule: address and data feed array directly, no conditions
  // ------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (dbg_we) begin
      imem[dbg_addr]    <= dbg_wdata;
      imem_pf[dbg_addr] <= dbg_wdata;   // keep shadow in sync
    end
  end

  // ------------------------------------------------------------------
  //  Write port - parity array + dbg_ack (separate block)
  // ------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dbg_ack <= 1'b0;
    end else begin
      if (dbg_we && !mem_sleep) begin
        parity_arr[dbg_addr] <= ^dbg_wdata;
        dbg_ack              <= 1'b1;
      end else begin
        dbg_ack <= 1'b0;
      end
    end
  end

  // ------------------------------------------------------------------
  //  Read port - primary BRAM (fetch word at if_addr)
  //  STRICTLY no logic - just address in, data out registered
  // ------------------------------------------------------------------
  always_ff @(posedge clk) begin
    imem_rdata <= imem[if_addr];
  end

  // ------------------------------------------------------------------
  //  Read port - prefetch BRAM (word at if_addr + 1)
  //  Again: no logic, bare array read
  // ------------------------------------------------------------------
  always_ff @(posedge clk) begin
    pf_rdata <= imem_pf[if_addr + 12'd1];
  end

  // ------------------------------------------------------------------
  //  Output control - all conditional logic here, away from BRAMs
  // ------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      if_rdata   <= '0;
      if_valid   <= 1'b0;
      pf_addr_r  <= '0;
      pf_valid_r <= 1'b0;
    end else if (mem_sleep) begin
      if_valid   <= 1'b0;
      pf_valid_r <= 1'b0;
    end else begin
      if (if_req) begin
        if_rdata  <= pf_hit ? pf_rdata : imem_rdata;
        if_valid  <= 1'b1;
        if (prefetch_en) begin
          pf_addr_r  <= if_addr + 12'd1;
          pf_valid_r <= 1'b1;
        end else begin
          pf_valid_r <= 1'b0;
        end
      end else begin
        if_valid <= 1'b0;
      end
    end
  end

  // ------------------------------------------------------------------
  //  Power FSM
  // ------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)         mem_sleep_ack <= 1'b0;
    else if (mem_sleep) mem_sleep_ack <= 1'b1;
    else                mem_sleep_ack <= 1'b0;
  end

  // ------------------------------------------------------------------
  //  Parity check - 1-cycle delayed to match BRAM read latency
  // ------------------------------------------------------------------
  logic                  if_valid_d;
  logic [ADDR_WIDTH-1:0] if_addr_d;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      if_valid_d <= 1'b0;
      if_addr_d  <= '0;
    end else begin
      if_valid_d <= if_valid;
      if_addr_d  <= if_addr;
    end
  end

  assign parity_err = if_valid_d && (^if_rdata != parity_arr[if_addr_d]);

endmodule
