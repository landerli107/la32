`timescale 1ns/1ps
`include "myCPU.h"

module tb_pipeline_control;
    reg         reset;
    reg  [31:0] pc;
    reg         if_valid;
    reg  [`ID_TO_IF_BUS_WD-1:0] id_to_if_bus;
    wire [`IF_TO_ID_BUS_WD-1:0] if_to_id_bus;
    wire [`IF_TO_ID_BUS_WD-1:0] if_to_id_bus1;
    wire        if_to_id_valid1;
    wire        inst_ram_en;
    wire [31:0] inst_ram_addr;
    wire [3:0]  inst_ram_w_en;
    reg  [31:0] inst_ram_r_data;
    reg  [31:0] inst_ram_r_data1;
    reg         inst_ram_r_data1_valid;
    reg         inst_ram_data_ok;
    wire        inst_ram_resp_ready;
    wire [31:0] inst_ram_w_data;
    reg         id_allow_in;
    wire        if_to_id_valid;
    wire        if_allow_in;
    reg         structure_hazard;
    wire [31:0] next_pc;
    wire        pre_to_if_valid;
    wire        br_taken_cancel;

    reg  [1:0]  sel_alu_src1;
    reg  [2:0]  sel_alu_src2;
    reg         sel_bu_src1;
    reg         sel_bu_src2;
    reg  [4:0]  rf_raddr1;
    reg  [4:0]  rf_raddr2;
    reg         sel_data_ram_we;
    reg  [`BY_TO_WK_BUS_WD-1:0] by_to_wk_bus;
    wire        alu_src_1_ready;
    wire        alu_src_2_ready;
    wire        bu_src_1_ready;
    wire        bu_src_2_ready;
    wire        mem_w_data_ready;

    integer errors;

    if_run dut_if (
        .reset(reset),
        .PC(pc),
        .IF_valid(if_valid),
        .ID_to_IF_bus(id_to_if_bus),
        .IF_to_ID_bus(if_to_id_bus),
        .IF_to_ID_bus1(if_to_id_bus1),
        .inst_ram_en(inst_ram_en),
        .inst_ram_addr(inst_ram_addr),
        .inst_ram_w_en(inst_ram_w_en),
        .inst_ram_r_data(inst_ram_r_data),
        .inst_ram_r_data1(inst_ram_r_data1),
        .inst_ram_r_data1_valid(inst_ram_r_data1_valid),
        .inst_ram_data_ok(inst_ram_data_ok),
        .inst_ram_resp_ready(inst_ram_resp_ready),
        .inst_ram_w_data(inst_ram_w_data),
        .ID_allow_in(id_allow_in),
        .IF_to_ID_valid(if_to_id_valid),
        .IF_to_ID_valid1(if_to_id_valid1),
        .IF_allow_in(if_allow_in),
        .sel_strcture_hazard(structure_hazard),
        .next_PC(next_pc),
        .Pre_to_IF_valid(pre_to_if_valid),
        .br_taken_cancel(br_taken_cancel)
    );

    WakeUP dut_wakeup (
        .sel_alu_src1(sel_alu_src1),
        .sel_alu_src2(sel_alu_src2),
        .sel_bu_src1(sel_bu_src1),
        .sel_bu_src2(sel_bu_src2),
        .RegFile_r_addr1(rf_raddr1),
        .RegFile_r_addr2(rf_raddr2),
        .sel_data_ram_we(sel_data_ram_we),
        .BY_to_WK_bus(by_to_wk_bus),
        .alu_src_1_ready(alu_src_1_ready),
        .alu_src_2_ready(alu_src_2_ready),
        .bu_src_1_ready(bu_src_1_ready),
        .bu_src_2_ready(bu_src_2_ready),
        .mem_w_data_ready(mem_w_data_ready)
    );

    task check;
        input condition;
        input [8*80-1:0] message;
        begin
            if (!condition) begin
                $display("FAIL: %0s", message);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        reset = 0;
        pc = 32'h1c00_0000;
        if_valid = 1;
        id_to_if_bus = {1'b0, 32'b0};
        inst_ram_r_data = 32'h0280_0401;
        inst_ram_r_data1 = 32'h0280_0802;
        inst_ram_r_data1_valid = 1'b0;
        inst_ram_data_ok = 1;
        id_allow_in = 1;
        structure_hazard = 1;

        sel_alu_src1 = 2'b10;
        sel_alu_src2 = 3'b000;
        sel_bu_src1 = 0;
        sel_bu_src2 = 0;
        rf_raddr1 = 0;
        rf_raddr2 = 0;
        sel_data_ram_we = 0;
        by_to_wk_bus = {5'd0, 1'b0, 1'b1, 1'b1,
                        5'd0, 1'b0, 1'b0, 1'b0,
                        5'd0, 1'b0, 1'b0, 1'b0};

        #1;
        check(if_allow_in === 1'b0,
              "structural hazard must freeze IF");
        check(if_to_id_valid === 1'b0,
              "structural hazard must not transfer IF to ID");
        check(inst_ram_resp_ready === 1'b0,
              "structural hazard must not consume instruction response");
        check(alu_src_1_ready === 1'b1,
              "a producer targeting x0 must not block a consumer of x0");

        structure_hazard = 0;
        #1;
        check(if_allow_in === 1'b1,
              "IF must advance when response and downstream are ready");
        check(if_to_id_valid === 1'b1,
              "valid response must transfer to ID");
        check(inst_ram_resp_ready === 1'b1,
              "accepted response must be acknowledged");

        id_to_if_bus = {1'b1, 32'h1c00_0100};
        #1;
        check(if_to_id_valid === 1'b0,
              "redirect must squash wrong-path response");
        check(inst_ram_resp_ready === 1'b1,
              "redirect must drain available wrong-path response");
        check(next_pc === 32'h1c00_0100,
              "redirect target must override prediction");

        id_to_if_bus = {1'b0, 32'b0};
        by_to_wk_bus = {5'd1, 1'b0, 1'b1, 1'b1,
                        5'd0, 1'b0, 1'b0, 1'b0,
                        5'd0, 1'b0, 1'b0, 1'b0};
        rf_raddr1 = 1;
        #1;
        check(alu_src_1_ready === 1'b0,
              "an unavailable nonzero EXE producer must still block RAW");

        if (errors == 0) begin
            $display("PASS: pipeline control and x0 hazard tests");
            $finish;
        end

        $fatal(1, "%0d checks failed", errors);
    end
endmodule
