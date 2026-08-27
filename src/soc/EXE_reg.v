/**
 * @file EXE_reg.v
 * @author refactored (5-stage version)
 * @brief EXE阶段流水线寄存器：ID_to_EXE_reg和EXE_valid寄存器
 */
`include "myCPU.h"
module EXE_reg(
    input  wire          clk,
    input  wire          reset,

    // 流水线控制
    input  wire          ID_to_EXE_valid,
    input  wire          EXE_allow_in,
    input  wire [`ID_TO_EXE_BUS_WD-1:0] ID_to_EXE_bus,

    // 输出
    (* extract_enable = "yes" *) output reg  [`ID_TO_EXE_BUS_WD-1:0] ID_to_EXE_reg_data,
    (* extract_enable = "yes" *) output reg           EXE_valid
);

    always@(posedge clk) begin
        if(reset)
            EXE_valid <= 1'b0;
        else if(EXE_allow_in)
            EXE_valid <= ID_to_EXE_valid;
    end

    always@(posedge clk) begin
        if(reset)
            ID_to_EXE_reg_data <= 0;
        // The payload is don't-care whenever EXE_valid is cleared.  Updating
        // it on every accepted slot avoids needlessly feeding ID_to_EXE_valid
        // into the wide register enable tree.
        else if(EXE_allow_in)
            ID_to_EXE_reg_data <= ID_to_EXE_bus;
    end

endmodule
