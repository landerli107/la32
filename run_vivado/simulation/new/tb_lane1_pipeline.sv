`timescale 1ns/1ps
`include "myCPU.h"

module tb_lane1_pipeline;
    reg clk;
    reg reset;
    reg id_valid;
    reg id_valid1;
    reg [`IF_TO_ID_BUS_WD-1:0] id_data0;
    reg [`IF_TO_ID_BUS_WD-1:0] id_data1;
    wire [`ID_TO_EXE_BUS_WD-1:0] id_bus0;
    wire [`ID1_TO_EXE_BUS_WD-1:0] id_bus1;
    wire id_to_exe_valid0;
    wire id_to_exe_valid1;
    wire issue0;
    wire issue1;
    wire id_allow;
    wire id_ready;

    reg [`BY_TO_ID_BUS_WD-1:0] by0;
    wire [`EXE_TO_BY_BUS_WD-1:0] exe1_by;
    wire [`EXE_TO_BY_BUS_WD-1:0] mem1_by;
    wire [`EXE_TO_BY_BUS_WD-1:0] wb1_by;
    reg [`WB_to_ID_bus_WD-1:0] wb_bus;

    wire [`ID1_TO_EXE_BUS_WD-1:0] exe1_reg_data;
    wire exe1_valid;
    wire [`EXE1_TO_MEM_BUS_WD-1:0] exe1_to_mem;
    wire exe1_to_mem_valid;
    wire [`EXE_TO_BY_BUS_WD-1:0] exe1_forward;
    wire [`EXE1_TO_MEM_BUS_WD-1:0] mem1_reg_data;
    wire mem1_valid;
    wire [`MEM1_TO_WB_BUS_WD-1:0] mem1_to_wb;
    wire mem1_to_wb_valid;
    wire [`EXE_TO_BY_BUS_WD-1:0] mem1_forward;
    wire [`MEM1_TO_WB_BUS_WD-1:0] wb1_reg_data;
    wire wb1_valid;
    wire [37:0] wb1_to_rf;
    wire [`EXE_TO_BY_BUS_WD-1:0] wb1_forward;
    assign exe1_by = exe1_forward;
    assign mem1_by = mem1_forward;
    assign wb1_by = wb1_forward;

    wire cacheop_valid;
    wire [4:0] cacheop_code;
    wire [31:0] cacheop_addr;

    localparam [31:0] ADDI_R1_R0_5 = 32'h0280_1401;
    localparam [31:0] ADDI_R2_R0_7 = 32'h0280_1c02;
    localparam [31:0] ADDI_R2_R1_1 = 32'h0280_0422;

    function [`IF_TO_ID_BUS_WD-1:0] make_id;
        input [31:0] pc;
        input [31:0] inst;
        begin
            make_id = {pc + 32'd4, pc + 32'd4, pc + 32'd4, pc, inst};
        end
    endfunction

    id_run decode (
        .clk(clk), .reset(reset),
        .IF_to_ID_reg_data(id_data0), .IF_to_ID_reg_data1(id_data1),
        .ID_valid(id_valid), .ID_valid1(id_valid1),
        .ID_to_EXE_bus(id_bus0), .ID1_to_EXE_bus(id_bus1),
        .WB_to_ID_bus(wb_bus), .BY_to_ID_bus(by0),
        .EXE1_to_ID_bus(exe1_by), .MEM1_to_ID_bus(mem1_by),
        .WB1_to_ID_bus(wb1_by),
        .EXE_allow_in(1'b1),
        .rob_can_alloc1(1'b1), .rob_can_alloc2(1'b1),
        .rob_rollback_busy(1'b0), .ID_allow_in(id_allow),
        .ID_to_EXE_valid(id_to_exe_valid0),
        .ID1_to_EXE_valid(id_to_exe_valid1), .ID_ready_go(id_ready),
        .pipeline_flush(1'b0), .issue_slot0(issue0), .issue_slot1(issue1),
        .cacheop_valid(cacheop_valid), .cacheop_code(cacheop_code),
        .cacheop_addr(cacheop_addr), .cacheop_ready(1'b1)
    );

    EXE1_reg exe_reg(
        .clk(clk), .reset(reset), .ID1_to_EXE_valid(id_to_exe_valid1),
        .EXE_allow_in(1'b1), .ID1_to_EXE_bus(id_bus1),
        .ID1_to_EXE_reg_data(exe1_reg_data), .EXE1_valid(exe1_valid)
    );
    exe1_run execute(
        .ID1_to_EXE_reg_data(exe1_reg_data), .EXE1_valid(exe1_valid),
        .EXE1_to_MEM_bus(exe1_to_mem), .EXE1_to_MEM_valid(exe1_to_mem_valid),
        .EXE1_to_ID_bus(exe1_forward)
    );
    MEM1_reg mem_reg(
        .clk(clk), .reset(reset), .EXE1_to_MEM_valid(exe1_to_mem_valid),
        .MEM_allow_in(1'b1), .EXE1_to_MEM_bus(exe1_to_mem),
        .EXE1_to_MEM_reg_data(mem1_reg_data), .MEM1_valid(mem1_valid)
    );
    mem1_run memory_stage(
        .EXE1_to_MEM_reg_data(mem1_reg_data), .MEM1_valid(mem1_valid),
        .MEM1_to_WB_bus(mem1_to_wb), .MEM1_to_WB_valid(mem1_to_wb_valid),
        .MEM1_to_ID_bus(mem1_forward)
    );
    WB1_reg wb_reg(
        .clk(clk), .reset(reset), .MEM1_to_WB_valid(mem1_to_wb_valid),
        .WB_allow_in(1'b1), .MEM1_to_WB_bus(mem1_to_wb),
        .MEM1_to_WB_reg_data(wb1_reg_data), .WB1_valid(wb1_valid)
    );
    wb1_run writeback(
        .MEM1_to_WB_reg_data(wb1_reg_data), .WB1_valid(wb1_valid),
        .WB1_to_RF_bus(wb1_to_rf), .WB1_to_ID_bus(wb1_forward)
    );

    always #5 clk = ~clk;

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk = 0;
        reset = 1;
        id_valid = 0;
        id_valid1 = 0;
        id_data0 = 0;
        id_data1 = 0;
        by0 = 0;
        wb_bus = 0;
        tick();
        reset = 0;

        // Independent simple ALU instructions pair and lane1 computes 7.
        id_valid = 1;
        id_valid1 = 1;
        id_data0 = make_id(32'h1c00_0000, ADDI_R1_R0_5);
        id_data1 = make_id(32'h1c00_0004, ADDI_R2_R0_7);
        #1;
        if (!issue0 || !issue1 || !id_to_exe_valid1)
            $fatal(1, "independent simple ALU pair did not dual issue");
        tick();
        if (!exe1_valid || exe1_to_mem[68:37] !== 32'd7 || exe1_to_mem[36:32] !== 5'd2)
            $fatal(1, "lane1 EXE result mismatch");

        // The next pair may consume the immediately preceding lane1 result.
        // slot0 = addi r3,r2,1 must see 7 from lane1 EXE forwarding.
        id_data0 = make_id(32'h1c00_0008, 32'h0280_0443);
        id_data1 = make_id(32'h1c00_000c, 32'h0280_0404);
        #1;
        if (!issue1 || id_bus0[63:32] !== 32'd7)
            $fatal(1, "lane1 EXE result did not forward to next slot0");

        // Same-cycle slot0->slot1 RAW must serialize.
        id_data0 = make_id(32'h1c00_0000, ADDI_R1_R0_5);
        id_data1 = make_id(32'h1c00_0004, ADDI_R2_R1_1);
        #1;
        if (issue1 || id_to_exe_valid1)
            $fatal(1, "slot0-to-slot1 RAW pair was not serialized");

        // Drain the earlier lane1 result and verify its ordered write port.
        id_valid = 0;
        id_valid1 = 0;
        tick();
        tick();
        if (!wb1_valid || wb1_to_rf !== {1'b1, 32'd7, 5'd2})
            $fatal(1, "lane1 writeback payload mismatch: %h", wb1_to_rf);

        $display("PASS: lane1 pairing, ALU pipeline and writeback tests");
        $finish;
    end
endmodule
