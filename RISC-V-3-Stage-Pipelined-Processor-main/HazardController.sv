module HazardController (
input  logic        clk,rst,reg_wr,Stall_MW,csr_reg_rd,csr_reg_wr,is_mretF,
input  logic [1:0]  wb_sel,
input  logic [31:0] InstF,
output logic        reg_wrMW,csr_reg_rdMW,csr_reg_wrMW,is_mretMW,
output logic [1:0]  wb_selMW,
output logic [2:0]  InstF_MW_funct3,
output logic [6:0]  InstF_MW_opcode
);

always_ff @ ( posedge clk ) begin 
    if ( rst ) begin
        InstF_MW_funct3 <= 3'b0;
        InstF_MW_opcode <= 7'b0;
        wb_selMW        <= 2'bx;
        reg_wrMW        <= 1'b0;  
        csr_reg_wrMW    <= 1'b0;
        csr_reg_rdMW    <= 1'b0;
        is_mretMW       <= 1'b0;
    end

     else if ( Stall_MW ) begin
        InstF_MW_funct3 <= InstF_MW_funct3;
        InstF_MW_opcode <= InstF_MW_opcode;
        wb_selMW        <= wb_selMW; 
        reg_wrMW        <= reg_wrMW;    
        csr_reg_wrMW    <= csr_reg_wrMW;
        csr_reg_rdMW    <= csr_reg_rdMW;  
        is_mretMW       <= is_mretMW;   
    end

    else begin
        InstF_MW_funct3 <= InstF [14:12];
        InstF_MW_opcode <= InstF [6:0];
        wb_selMW        <= wb_sel;
        reg_wrMW        <= reg_wr;
        csr_reg_wrMW    <= csr_reg_wr;
        csr_reg_rdMW    <= csr_reg_rd; 
        is_mretMW       <= is_mretF;
    end
end


endmodule