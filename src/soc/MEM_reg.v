/**
 * @file MEM_reg.v
 * @brief EXE/MEM pipeline register.
 */
`include "myCPU.h"

module MEM_reg(
    input  wire          clk,
    input  wire          reset,
    input  wire          EXE_to_MEM_valid,
    input  wire          MEM_allow_in,
    input  wire [`EXE_TO_MEM_BUS_WD-1:0] EXE_to_MEM_bus,

    (* extract_enable = "yes" *)
    output reg  [`EXE_TO_MEM_BUS_WD-1:0] EXE_to_MEM_reg_data,
    (* extract_enable = "yes" *)
    output reg           MEM_valid
);

    always @(posedge clk) begin
        if (reset)
            MEM_valid <= 1'b0;
        else if (MEM_allow_in)
            MEM_valid <= EXE_to_MEM_valid;
    end

    always @(posedge clk) begin
        if (reset)
            EXE_to_MEM_reg_data <= 0;
        else if (EXE_to_MEM_valid & MEM_allow_in)
            EXE_to_MEM_reg_data <= EXE_to_MEM_bus;
    end

endmodule
