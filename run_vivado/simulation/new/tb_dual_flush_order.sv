`timescale 1ns/1ps
`include "myCPU.h"

module tb_dual_flush_order;
    reg clk;
    reg reset;
    reg fetch_valid0;
    reg fetch_valid1;
    reg issue0;
    reg issue1;
    reg redirect_flush;
    reg [`IF_TO_ID_BUS_WD-1:0] fetch_data0;
    reg [`IF_TO_ID_BUS_WD-1:0] fetch_data1;
    wire [`IF_TO_ID_BUS_WD-1:0] id_data0;
    wire [`IF_TO_ID_BUS_WD-1:0] id_data1;
    wire id_valid0;
    wire id_valid1;
    wire fetch_allow;

    reg older_lane1_valid;
    reg [`ID1_TO_EXE_BUS_WD-1:0] older_lane1_bus;
    wire [`ID1_TO_EXE_BUS_WD-1:0] older_exe_data;
    wire older_exe_valid;
    wire [`EXE1_TO_MEM_BUS_WD-1:0] older_exe_bus;
    wire older_exe_to_mem_valid;
    wire [`EXE_TO_BY_BUS_WD-1:0] older_exe_forward;
    wire [`EXE1_TO_MEM_BUS_WD-1:0] older_mem_data;
    wire older_mem_valid;
    wire [`MEM1_TO_WB_BUS_WD-1:0] older_mem_bus;
    wire older_mem_to_wb_valid;
    wire [`EXE_TO_BY_BUS_WD-1:0] older_mem_forward;
    wire [`MEM1_TO_WB_BUS_WD-1:0] older_wb_data;
    wire older_wb_valid;
    wire [37:0] older_wb_to_rf;
    wire [`EXE_TO_BY_BUS_WD-1:0] older_wb_forward;

    localparam [`IF_TO_ID_BUS_WD-1:0] WRONG0 =
        {{(`IF_TO_ID_BUS_WD-32){1'b0}}, 32'h0000_00a1};
    localparam [`IF_TO_ID_BUS_WD-1:0] WRONG1 =
        {{(`IF_TO_ID_BUS_WD-32){1'b0}}, 32'h0000_00b2};
    localparam [`ID1_TO_EXE_BUS_WD-1:0] OLDER =
        {19'b0000000000000000001, 32'd9, 32'd8, 5'd6, 32'h1c00_0000};

    ID_reg queue(
        .clk(clk), .reset(reset),
        .IF_to_ID_valid(fetch_valid0), .IF_to_ID_valid1(fetch_valid1),
        .issue_slot0(issue0), .issue_slot1(issue1),
        .br_taken_cancel(redirect_flush),
        .IF_to_ID_bus(fetch_data0), .IF_to_ID_bus1(fetch_data1),
        .IF_to_ID_reg_data(id_data0), .IF_to_ID_reg_data1(id_data1),
        .ID_valid(id_valid0), .ID_valid1(id_valid1),
        .IF_allow_in(fetch_allow)
    );

    EXE1_reg older_exe(
        .clk(clk), .reset(reset),
        .ID1_to_EXE_valid(older_lane1_valid), .EXE_allow_in(1'b1),
        .ID1_to_EXE_bus(older_lane1_bus),
        .ID1_to_EXE_reg_data(older_exe_data), .EXE1_valid(older_exe_valid)
    );
    exe1_run older_execute(
        .ID1_to_EXE_reg_data(older_exe_data), .EXE1_valid(older_exe_valid),
        .EXE1_to_MEM_bus(older_exe_bus),
        .EXE1_to_MEM_valid(older_exe_to_mem_valid),
        .EXE1_to_ID_bus(older_exe_forward)
    );
    MEM1_reg older_mem(
        .clk(clk), .reset(reset),
        .EXE1_to_MEM_valid(older_exe_to_mem_valid), .MEM_allow_in(1'b1),
        .EXE1_to_MEM_bus(older_exe_bus),
        .EXE1_to_MEM_reg_data(older_mem_data), .MEM1_valid(older_mem_valid)
    );
    mem1_run older_memory(
        .EXE1_to_MEM_reg_data(older_mem_data), .MEM1_valid(older_mem_valid),
        .MEM1_to_WB_bus(older_mem_bus), .MEM1_to_WB_valid(older_mem_to_wb_valid),
        .MEM1_to_ID_bus(older_mem_forward)
    );
    WB1_reg older_wb(
        .clk(clk), .reset(reset),
        .MEM1_to_WB_valid(older_mem_to_wb_valid), .WB_allow_in(1'b1),
        .MEM1_to_WB_bus(older_mem_bus),
        .MEM1_to_WB_reg_data(older_wb_data), .WB1_valid(older_wb_valid)
    );
    wb1_run older_writeback(
        .MEM1_to_WB_reg_data(older_wb_data), .WB1_valid(older_wb_valid),
        .WB1_to_RF_bus(older_wb_to_rf), .WB1_to_ID_bus(older_wb_forward)
    );

    always #5 clk = ~clk;

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk = 0; reset = 1;
        fetch_valid0 = 0; fetch_valid1 = 0;
        issue0 = 0; issue1 = 0; redirect_flush = 0;
        fetch_data0 = 0; fetch_data1 = 0;
        older_lane1_valid = 0; older_lane1_bus = 0;
        tick();
        reset = 0;

        // A lane1 instruction older than the eventual branch enters EXE.
        older_lane1_valid = 1;
        older_lane1_bus = OLDER;
        tick();
        older_lane1_valid = 0;

        // Meanwhile two younger wrong-path instructions occupy ID.
        fetch_valid0 = 1; fetch_valid1 = 1;
        fetch_data0 = WRONG0; fetch_data1 = WRONG1;
        tick();
        if (!id_valid0 || !id_valid1)
            $fatal(1, "wrong-path setup did not fill both ID slots");

        // EXE branch redirect flushes both younger ID slots.  The previously
        // issued lane1 instruction is older than that branch and must continue.
        fetch_valid0 = 0; fetch_valid1 = 0;
        redirect_flush = 1;
        tick();
        redirect_flush = 0;
        if (id_valid0 || id_valid1)
            $fatal(1, "redirect did not clear both younger ID slots");
        if (!older_wb_valid || older_wb_to_rf !== {1'b1, 32'd17, 5'd6})
            $fatal(1, "redirect incorrectly killed older lane1 instruction");

        $display("PASS: dual-issue redirect ordering tests");
        $finish;
    end
endmodule
