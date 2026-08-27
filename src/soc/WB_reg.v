/**
 * @file WB_reg.v
 * @author refactored (5-stage version)
 * @brief WB阶段流水线寄存器：MEM_to_WB_reg和WB_valid寄存器
 */
`include "myCPU.h"
module WB_reg(
    input  wire          clk,
    input  wire          reset,

    // 流水线控制
    input  wire           MEM_to_WB_valid,
    input  wire           WB_allow_in,
    input  wire [`MEM_TO_WB_BUS_WD-1:0] MEM_to_WB_bus,

    // 输出
    output reg  [`MEM_TO_WB_BUS_WD-1:0] MEM_to_WB_reg_data,
    output reg           WB_valid
);

    always@(posedge clk) begin
        if(reset)
            WB_valid <= 1'b0;
        else if(WB_allow_in)
            WB_valid <= MEM_to_WB_valid;
    end

    always@(posedge clk) begin
        if(reset)
            MEM_to_WB_reg_data <= 0;
        else if(MEM_to_WB_valid & WB_allow_in)
            MEM_to_WB_reg_data <= MEM_to_WB_bus;
        else
            MEM_to_WB_reg_data <= MEM_to_WB_reg_data;
    end

endmodule
