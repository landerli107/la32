`timescale 1ns/1ps
`include "myCPU.h"

module tb_x0_forward;
    reg clk;
    reg reset;
    reg [`IF_TO_ID_BUS_WD-1:0] if_to_id_reg_data;
    reg id_valid;
    wire [`ID_TO_EXE_BUS_WD-1:0] id_to_exe_bus;
    wire [`ID1_TO_EXE_BUS_WD-1:0] id1_to_exe_bus;
    wire id1_to_exe_valid;
    reg [`WB_to_ID_bus_WD-1:0] wb_to_id_bus;
    reg [`BY_TO_ID_BUS_WD-1:0] by_to_id_bus;
    reg exe_allow_in;
    wire id_allow_in;
    wire id_to_exe_valid;
    wire id_ready_go;
    wire issue_slot0;
    wire issue_slot1;
    reg pipeline_flush;
    wire cacheop_valid;
    wire [4:0] cacheop_code;
    wire [31:0] cacheop_addr;
    reg cacheop_ready;

    // addi.w r1, r0, 1.  The architectural value of r0 is zero even if an
    // older valid instruction nominally targets r0 with nonzero result data.
    localparam [31:0] ADDI_R1_R0_1 = 32'h0280_0401;

    id_run dut (
        .clk(clk),
        .reset(reset),
        .IF_to_ID_reg_data(if_to_id_reg_data),
        .IF_to_ID_reg_data1({`IF_TO_ID_BUS_WD{1'b0}}),
        .ID_valid(id_valid), .ID_valid1(1'b0),
        .ID_to_EXE_bus(id_to_exe_bus),
        .ID1_to_EXE_bus(id1_to_exe_bus),
        .WB_to_ID_bus(wb_to_id_bus),
        .BY_to_ID_bus(by_to_id_bus),
        .EXE1_to_ID_bus({`EXE_TO_BY_BUS_WD{1'b0}}),
        .MEM1_to_ID_bus({`EXE_TO_BY_BUS_WD{1'b0}}),
        .WB1_to_ID_bus({`EXE_TO_BY_BUS_WD{1'b0}}),
        .EXE_allow_in(exe_allow_in),
        .rob_can_alloc1(1'b1), .rob_can_alloc2(1'b1),
        .rob_rollback_busy(1'b0),
        .ID_allow_in(id_allow_in),
        .ID_to_EXE_valid(id_to_exe_valid),
        .ID1_to_EXE_valid(id1_to_exe_valid),
        .ID_ready_go(id_ready_go),
        .pipeline_flush(pipeline_flush),
        .issue_slot0(issue_slot0),
        .issue_slot1(issue_slot1),
        .cacheop_valid(cacheop_valid),
        .cacheop_code(cacheop_code),
        .cacheop_addr(cacheop_addr),
        .cacheop_ready(cacheop_ready)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;
        id_valid = 0;
        if_to_id_reg_data = 0;
        wb_to_id_bus = 0;
        by_to_id_bus = 0;
        exe_allow_in = 1;
        pipeline_flush = 0;
        cacheop_ready = 1;

        #12;
        reset = 0;
        id_valid = 1;
        if_to_id_reg_data = {
            32'h1c00_0004,
            32'h1c00_0004,
            32'h1c00_0004,
            32'h1c00_0000,
            ADDI_R1_R0_1
        };
        by_to_id_bus = {
            5'd0, 32'hdead_beef, 1'b1, 1'b1, 1'b1,
            5'd0, 32'h0000_0000, 1'b0, 1'b0, 1'b0,
            5'd0, 32'h0000_0000, 1'b0, 1'b0, 1'b0
        };

        #1;
        if (id_ready_go !== 1'b1)
            $fatal(1, "x0 pseudo-producer incorrectly stalled decode");
        if (id_to_exe_valid !== 1'b1)
            $fatal(1, "addi.w using r0 did not issue");
        if (id_to_exe_bus[63:32] !== 32'b0)
            $fatal(1, "x0 forwarded nonzero data: %08x", id_to_exe_bus[63:32]);

        $display("PASS: x0 forwarding remains architecturally zero");
        $finish;
    end
endmodule
