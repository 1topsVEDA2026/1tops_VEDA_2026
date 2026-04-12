module HazardUnit (
    input  logic       reg_wrMW,br_taken,valid,         //instead of br_taken,I have used PCSrc here
    input  logic [1:0] wb_selMW,                //used to check the stalling condition
    input  logic [4:0] raddr1,raddr2,waddr_MW, //instead of giving InstF as an input,I have used raddr1 and raddr2 directly
    output logic       For_A, For_B,Stall,Stall_MW,Flush
    
);

// Check the validity of the source operands from EXE stage
  logic rs1_valid;
  logic rs2_valid;
  assign rs1_valid = |raddr1;
  assign rs2_valid = |raddr2;

// Hazard detection for forwarding 
  always_comb begin
    if (((raddr1 == waddr_MW) & (reg_wrMW)) & (rs1_valid)  & (valid==0)) begin
      For_A = 1'b0;
    end
    else begin
      For_A = 1'b1;
    end

  end

  always_comb begin
    if (((raddr2 == waddr_MW) & (reg_wrMW)) & (rs2_valid) & ( valid == 0) ) begin
      For_B = 1'b0;
    end
    else begin
      For_B = 1'b1;
    end

  end
  
// Hazard detection for Stalling
  logic lwStall;
  assign  lwStall  = ( wb_selMW[1] & (( raddr1 == waddr_MW ) | ( raddr2 == waddr_MW )) & ( valid == 0) & (reg_wrMW));
  assign  Stall    = lwStall;
  assign  Stall_MW = lwStall;  

//Flush When a branch is taken or a load initroduces a bubble
always_comb begin
  if (br_taken)
      Flush  = 1'b1;
  else Flush = 1'b0;
end

endmodule