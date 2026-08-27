`timescale 1ns/1ps
`include "myCPU.h"

module tb_pipeline_registers;
    reg clk;
    reg reset;
    reg if_to_id_valid;
    reg branch_flush;
    reg issue_slot0;
    reg [`IF_TO_ID_BUS_WD-1:0] if_to_id_bus;
    wire [`IF_TO_ID_BUS_WD-1:0] if_to_id_reg_data;
    wire [`IF_TO_ID_BUS_WD-1:0] if_to_id_reg_data1;
    wire id_valid;
    wire id_valid1;
    wire if_allow_in;

    reg id_to_exe_valid;
    reg exe_allow_in;
    reg [`ID_TO_EXE_BUS_WD-1:0] id_to_exe_bus;
    wire [`ID_TO_EXE_BUS_WD-1:0] id_to_exe_reg_data;
    wire exe_valid;

    reg exe_to_mem_valid;
    reg mem_allow_in;
    reg [`EXE_TO_MEM_BUS_WD-1:0] exe_to_mem_bus;
    wire [`EXE_TO_MEM_BUS_WD-1:0] exe_to_mem_reg_data;
    wire mem_valid;

    reg mem_to_wb_valid;
    reg wb_allow_in;
    reg [`MEM_TO_WB_BUS_WD-1:0] mem_to_wb_bus;
    wire [`MEM_TO_WB_BUS_WD-1:0] mem_to_wb_reg_data;
    wire wb_valid;

    ID_reg dut_id (
        .clk(clk), .reset(reset),
        .IF_to_ID_valid(if_to_id_valid), .IF_to_ID_valid1(1'b0),
        .issue_slot0(issue_slot0), .issue_slot1(1'b0),
        .br_taken_cancel(branch_flush),
        .IF_to_ID_bus(if_to_id_bus), .IF_to_ID_bus1({`IF_TO_ID_BUS_WD{1'b0}}),
        .IF_to_ID_reg_data(if_to_id_reg_data),
        .IF_to_ID_reg_data1(if_to_id_reg_data1),
        .ID_valid(id_valid), .ID_valid1(id_valid1),
        .IF_allow_in(if_allow_in)
    );

    EXE_reg dut_exe (
        .clk(clk), .reset(reset),
        .ID_to_EXE_valid(id_to_exe_valid), .EXE_allow_in(exe_allow_in),
        .ID_to_EXE_bus(id_to_exe_bus),
        .ID_to_EXE_reg_data(id_to_exe_reg_data), .EXE_valid(exe_valid)
    );

    MEM_reg dut_mem (
        .clk(clk), .reset(reset),
        .EXE_to_MEM_valid(exe_to_mem_valid), .MEM_allow_in(mem_allow_in),
        .EXE_to_MEM_bus(exe_to_mem_bus),
        .EXE_to_MEM_reg_data(exe_to_mem_reg_data), .MEM_valid(mem_valid)
    );

    WB_reg dut_wb (
        .clk(clk), .reset(reset),
        .MEM_to_WB_valid(mem_to_wb_valid), .WB_allow_in(wb_allow_in),
        .MEM_to_WB_bus(mem_to_wb_bus),
        .MEM_to_WB_reg_data(mem_to_wb_reg_data), .WB_valid(wb_valid)
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
        if_to_id_valid = 0;
        branch_flush = 0;
        issue_slot0 = 0;
        if_to_id_bus = 0;
        id_to_exe_valid = 0;
        exe_allow_in = 0;
        id_to_exe_bus = 0;
        exe_to_mem_valid = 0;
        mem_allow_in = 0;
        exe_to_mem_bus = 0;
        mem_to_wb_valid = 0;
        wb_allow_in = 0;
        mem_to_wb_bus = 0;
        tick();
        reset = 0;

        if_to_id_valid = 1;
        if_to_id_bus = {`IF_TO_ID_BUS_WD{1'b1}};
        id_to_exe_valid = 1;
        exe_allow_in = 1;
        id_to_exe_bus = {`ID_TO_EXE_BUS_WD{1'b1}};
        exe_to_mem_valid = 1;
        mem_allow_in = 1;
        exe_to_mem_bus = {`EXE_TO_MEM_BUS_WD{1'b1}};
        mem_to_wb_valid = 1;
        wb_allow_in = 1;
        mem_to_wb_bus = {`MEM_TO_WB_BUS_WD{1'b1}};
        tick();

        if (id_valid !== 1 || id_valid1 !== 0 || exe_valid !== 1 ||
            mem_valid !== 1 || wb_valid !== 1)
            $fatal(1, "valid bits did not advance with accepted payloads");
        if (&if_to_id_reg_data !== 1 || &id_to_exe_reg_data !== 1 ||
            &exe_to_mem_reg_data !== 1 || &mem_to_wb_reg_data !== 1)
            $fatal(1, "payloads did not advance with valid bits");

        exe_allow_in = 0;
        mem_allow_in = 0;
        wb_allow_in = 0;
        if_to_id_valid = 0;
        id_to_exe_valid = 0;
        exe_to_mem_valid = 0;
        mem_to_wb_valid = 0;
        if_to_id_bus = 0;
        id_to_exe_bus = 0;
        exe_to_mem_bus = 0;
        mem_to_wb_bus = 0;
        tick();

        if (id_valid !== 1 || exe_valid !== 1 || mem_valid !== 1 || wb_valid !== 1)
            $fatal(1, "stall changed a valid bit");
        if (&if_to_id_reg_data !== 1 || &id_to_exe_reg_data !== 1 ||
            &exe_to_mem_reg_data !== 1 || &mem_to_wb_reg_data !== 1)
            $fatal(1, "stall changed a held payload");

        branch_flush = 1;
        tick();
        if (id_valid !== 0 || id_valid1 !== 0)
            $fatal(1, "branch flush did not invalidate both ID slots");
        if (if_to_id_reg_data !== 0)
            $fatal(1, "flush did not reset ID payload in dual-entry queue");

        branch_flush = 0;
        exe_allow_in = 1;
        mem_allow_in = 1;
        wb_allow_in = 1;
        tick();
        if (id_valid !== 0 || exe_valid !== 0 || mem_valid !== 0 || wb_valid !== 0)
            $fatal(1, "accepted bubbles did not clear valid bits");

        $display("PASS: pipeline register stall/flush alignment tests");
        $finish;
    end
endmodule
