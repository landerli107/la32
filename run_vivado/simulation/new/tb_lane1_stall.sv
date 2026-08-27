`timescale 1ns/1ps
`include "myCPU.h"

module tb_lane1_stall;
    reg clk;
    reg reset;
    reg id_valid;
    reg exe_allow;
    reg mem_allow;
    reg wb_allow;
    reg [`ID1_TO_EXE_BUS_WD-1:0] id_bus;
    wire [`ID1_TO_EXE_BUS_WD-1:0] exe_data;
    wire exe_valid;
    wire [`EXE1_TO_MEM_BUS_WD-1:0] exe_bus;
    wire exe_to_mem_valid;
    wire [`EXE_TO_BY_BUS_WD-1:0] exe_forward;
    wire [`EXE1_TO_MEM_BUS_WD-1:0] mem_data;
    wire mem_valid;
    wire [`MEM1_TO_WB_BUS_WD-1:0] mem_bus;
    wire mem_to_wb_valid;
    wire [`EXE_TO_BY_BUS_WD-1:0] mem_forward;
    wire [`MEM1_TO_WB_BUS_WD-1:0] wb_data;
    wire wb_valid;

    localparam [`ID1_TO_EXE_BUS_WD-1:0] PAYLOAD_A =
        {19'b1, 32'h0000_0002, 32'h0000_0001, 5'd3, 32'h1c00_0000};
    localparam [`ID1_TO_EXE_BUS_WD-1:0] PAYLOAD_B =
        {19'b1, 32'h0000_0004, 32'h0000_0003, 5'd5, 32'h1c00_0004};

    EXE1_reg exe_reg(
        .clk(clk), .reset(reset), .ID1_to_EXE_valid(id_valid),
        .EXE_allow_in(exe_allow), .ID1_to_EXE_bus(id_bus),
        .ID1_to_EXE_reg_data(exe_data), .EXE1_valid(exe_valid)
    );
    exe1_run execute(
        .ID1_to_EXE_reg_data(exe_data), .EXE1_valid(exe_valid),
        .EXE1_to_MEM_bus(exe_bus), .EXE1_to_MEM_valid(exe_to_mem_valid),
        .EXE1_to_ID_bus(exe_forward)
    );
    MEM1_reg mem_reg(
        .clk(clk), .reset(reset), .EXE1_to_MEM_valid(exe_to_mem_valid),
        .MEM_allow_in(mem_allow), .EXE1_to_MEM_bus(exe_bus),
        .EXE1_to_MEM_reg_data(mem_data), .MEM1_valid(mem_valid)
    );
    mem1_run memory_stage(
        .EXE1_to_MEM_reg_data(mem_data), .MEM1_valid(mem_valid),
        .MEM1_to_WB_bus(mem_bus), .MEM1_to_WB_valid(mem_to_wb_valid),
        .MEM1_to_ID_bus(mem_forward)
    );
    WB1_reg wb_reg(
        .clk(clk), .reset(reset), .MEM1_to_WB_valid(mem_to_wb_valid),
        .WB_allow_in(wb_allow), .MEM1_to_WB_bus(mem_bus),
        .MEM1_to_WB_reg_data(wb_data), .WB1_valid(wb_valid)
    );

    always #5 clk = ~clk;

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk = 0; reset = 1; id_valid = 0;
        exe_allow = 0; mem_allow = 0; wb_allow = 0; id_bus = 0;
        tick();
        reset = 0;

        id_valid = 1; id_bus = PAYLOAD_A; exe_allow = 1;
        tick();
        if (!exe_valid || exe_data !== PAYLOAD_A)
            $fatal(1, "lane1 EXE did not capture accepted payload");

        // A global EXE stall must retain valid and payload together.
        id_bus = PAYLOAD_B; exe_allow = 0;
        tick();
        if (!exe_valid || exe_data !== PAYLOAD_A)
            $fatal(1, "lane1 EXE changed during stall");

        // Advance A to MEM, then hold MEM while its downstream is blocked.
        id_valid = 0; exe_allow = 1; mem_allow = 1;
        tick();
        if (!mem_valid || mem_data[36:32] !== 5'd3)
            $fatal(1, "lane1 MEM did not capture A");
        mem_allow = 0;
        tick();
        if (!mem_valid || mem_data[36:32] !== 5'd3)
            $fatal(1, "lane1 MEM changed during stall");

        // Advance into WB and verify WB also holds under backpressure.
        mem_allow = 1; wb_allow = 1;
        tick();
        if (!wb_valid || wb_data[36:32] !== 5'd3)
            $fatal(1, "lane1 WB did not capture A");
        wb_allow = 0;
        tick();
        if (!wb_valid || wb_data[36:32] !== 5'd3)
            $fatal(1, "lane1 WB changed during stall");

        $display("PASS: lane1 global backpressure alignment tests");
        $finish;
    end
endmodule
