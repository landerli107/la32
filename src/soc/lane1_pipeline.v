`include "myCPU.h"

module EXE1_reg(
    input wire clk,
    input wire reset,
    input wire ID1_to_EXE_valid,
    input wire EXE_allow_in,
    input wire [`ID1_TO_EXE_BUS_WD-1:0] ID1_to_EXE_bus,
    output reg [`ID1_TO_EXE_BUS_WD-1:0] ID1_to_EXE_reg_data,
    output reg EXE1_valid
);
    always @(posedge clk) begin
        if (reset)
            EXE1_valid <= 1'b0;
        else if (EXE_allow_in)
            EXE1_valid <= ID1_to_EXE_valid;
    end

    always @(posedge clk) begin
        if (reset)
            ID1_to_EXE_reg_data <= {`ID1_TO_EXE_BUS_WD{1'b0}};
        else if (EXE_allow_in)
            ID1_to_EXE_reg_data <= ID1_to_EXE_bus;
    end
endmodule

module exe1_run(
    input wire [`ID1_TO_EXE_BUS_WD-1:0] ID1_to_EXE_reg_data,
    input wire EXE1_valid,
    output wire [`EXE1_TO_MEM_BUS_WD-1:0] EXE1_to_MEM_bus,
    output wire EXE1_to_MEM_valid,
    output wire [`EXE_TO_BY_BUS_WD-1:0] EXE1_to_ID_bus
);
    wire [18:0] alu_op;
    wire [31:0] src2;
    wire [31:0] src1;
    wire [4:0] rd;
    wire [31:0] pc;
    wire [31:0] result;
    wire [31:0] unused_fast_result;

    assign {alu_op, src2, src1, rd, pc} = ID1_to_EXE_reg_data;

    alu lane1_alu(
        .alu_op(alu_op), .alu_src1(src1), .alu_src2(src2),
        .alu_result(result), .alu_fast_result(unused_fast_result)
    );

    assign EXE1_to_MEM_valid = EXE1_valid;
    assign EXE1_to_MEM_bus = {result, rd, pc};
    assign EXE1_to_ID_bus = {rd, result, EXE1_valid, EXE1_valid, EXE1_valid};
endmodule

module MEM1_reg(
    input wire clk,
    input wire reset,
    input wire EXE1_to_MEM_valid,
    input wire MEM_allow_in,
    input wire [`EXE1_TO_MEM_BUS_WD-1:0] EXE1_to_MEM_bus,
    output reg [`EXE1_TO_MEM_BUS_WD-1:0] EXE1_to_MEM_reg_data,
    output reg MEM1_valid
);
    always @(posedge clk) begin
        if (reset)
            MEM1_valid <= 1'b0;
        else if (MEM_allow_in)
            MEM1_valid <= EXE1_to_MEM_valid;
    end

    always @(posedge clk) begin
        if (reset)
            EXE1_to_MEM_reg_data <= {`EXE1_TO_MEM_BUS_WD{1'b0}};
        else if (EXE1_to_MEM_valid && MEM_allow_in)
            EXE1_to_MEM_reg_data <= EXE1_to_MEM_bus;
    end
endmodule

module mem1_run(
    input wire [`EXE1_TO_MEM_BUS_WD-1:0] EXE1_to_MEM_reg_data,
    input wire MEM1_valid,
    output wire [`MEM1_TO_WB_BUS_WD-1:0] MEM1_to_WB_bus,
    output wire MEM1_to_WB_valid,
    output wire [`EXE_TO_BY_BUS_WD-1:0] MEM1_to_ID_bus
);
    wire [31:0] result;
    wire [4:0] rd;
    wire [31:0] pc;

    assign {result, rd, pc} = EXE1_to_MEM_reg_data;
    assign MEM1_to_WB_bus = EXE1_to_MEM_reg_data;
    assign MEM1_to_WB_valid = MEM1_valid;
    assign MEM1_to_ID_bus = {rd, result, MEM1_valid, MEM1_valid, MEM1_valid};
endmodule

module WB1_reg(
    input wire clk,
    input wire reset,
    input wire MEM1_to_WB_valid,
    input wire WB_allow_in,
    input wire [`MEM1_TO_WB_BUS_WD-1:0] MEM1_to_WB_bus,
    output reg [`MEM1_TO_WB_BUS_WD-1:0] MEM1_to_WB_reg_data,
    output reg WB1_valid
);
    always @(posedge clk) begin
        if (reset)
            WB1_valid <= 1'b0;
        else if (WB_allow_in)
            WB1_valid <= MEM1_to_WB_valid;
    end

    always @(posedge clk) begin
        if (reset)
            MEM1_to_WB_reg_data <= {`MEM1_TO_WB_BUS_WD{1'b0}};
        else if (MEM1_to_WB_valid && WB_allow_in)
            MEM1_to_WB_reg_data <= MEM1_to_WB_bus;
    end
endmodule

module wb1_run(
    input wire [`MEM1_TO_WB_BUS_WD-1:0] MEM1_to_WB_reg_data,
    input wire WB1_valid,
    output wire [37:0] WB1_to_RF_bus,
    output wire [`EXE_TO_BY_BUS_WD-1:0] WB1_to_ID_bus
);
    wire [31:0] result;
    wire [4:0] rd;
    wire [31:0] pc;
    wire write_enable;

    assign {result, rd, pc} = MEM1_to_WB_reg_data;
    assign write_enable = WB1_valid & (rd != 5'b0);
    assign WB1_to_RF_bus = {write_enable, result, rd};
    assign WB1_to_ID_bus = {rd, result, WB1_valid, WB1_valid, WB1_valid};
endmodule
