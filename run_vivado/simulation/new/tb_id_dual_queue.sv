`timescale 1ns/1ps
`include "myCPU.h"

module tb_id_dual_queue;
    reg clk;
    reg reset;
    reg fetch_valid0;
    reg fetch_valid1;
    reg issue0;
    reg issue1;
    reg flush;
    reg [`IF_TO_ID_BUS_WD-1:0] fetch_data0;
    reg [`IF_TO_ID_BUS_WD-1:0] fetch_data1;
    wire [`IF_TO_ID_BUS_WD-1:0] data0;
    wire [`IF_TO_ID_BUS_WD-1:0] data1;
    wire valid0;
    wire valid1;
    wire fetch_allow;

    localparam [`IF_TO_ID_BUS_WD-1:0] INST_A = {{(`IF_TO_ID_BUS_WD-32){1'b0}}, 32'h0000_00a1};
    localparam [`IF_TO_ID_BUS_WD-1:0] INST_B = {{(`IF_TO_ID_BUS_WD-32){1'b0}}, 32'h0000_00b2};
    localparam [`IF_TO_ID_BUS_WD-1:0] INST_C = {{(`IF_TO_ID_BUS_WD-32){1'b0}}, 32'h0000_00c3};
    localparam [`IF_TO_ID_BUS_WD-1:0] INST_D = {{(`IF_TO_ID_BUS_WD-32){1'b0}}, 32'h0000_00d4};

    ID_reg dut (
        .clk(clk), .reset(reset),
        .IF_to_ID_valid(fetch_valid0),
        .IF_to_ID_valid1(fetch_valid1),
        .issue_slot0(issue0), .issue_slot1(issue1),
        .br_taken_cancel(flush),
        .IF_to_ID_bus(fetch_data0), .IF_to_ID_bus1(fetch_data1),
        .IF_to_ID_reg_data(data0), .IF_to_ID_reg_data1(data1),
        .ID_valid(valid0), .ID_valid1(valid1),
        .IF_allow_in(fetch_allow)
    );

    always #5 clk = ~clk;

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task check_queue;
        input expected_valid0;
        input expected_valid1;
        input [`IF_TO_ID_BUS_WD-1:0] expected_data0;
        input [`IF_TO_ID_BUS_WD-1:0] expected_data1;
        begin
            if (valid0 !== expected_valid0 || valid1 !== expected_valid1)
                $fatal(1, "valid mismatch: got %b%b expected %b%b",
                       valid1, valid0, expected_valid1, expected_valid0);
            if (expected_valid0 && data0 !== expected_data0)
                $fatal(1, "slot0 data mismatch: got %h expected %h", data0, expected_data0);
            if (expected_valid1 && data1 !== expected_data1)
                $fatal(1, "slot1 data mismatch: got %h expected %h", data1, expected_data1);
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        fetch_valid0 = 1'b0;
        fetch_valid1 = 1'b0;
        issue0 = 1'b0;
        issue1 = 1'b0;
        flush = 1'b0;
        fetch_data0 = {`IF_TO_ID_BUS_WD{1'b0}};
        fetch_data1 = {`IF_TO_ID_BUS_WD{1'b0}};
        tick();
        reset = 1'b0;

        // A two-instruction fetch fills both ordered entries.
        fetch_valid0 = 1'b1;
        fetch_valid1 = 1'b1;
        fetch_data0 = INST_A;
        fetch_data1 = INST_B;
        if (fetch_allow !== 1'b1)
            $fatal(1, "empty queue rejected two-entry fetch");
        tick();
        check_queue(1'b1, 1'b1, INST_A, INST_B);

        // A full stalled queue must not accept or overwrite another response.
        fetch_data0 = INST_C;
        fetch_data1 = INST_D;
        if (fetch_allow !== 1'b0)
            $fatal(1, "full queue accepted fetch without issue space");
        tick();
        check_queue(1'b1, 1'b1, INST_A, INST_B);

        // Consume only A.  B shifts to slot0 and C appends in the same cycle.
        issue0 = 1'b1;
        issue1 = 1'b0;
        fetch_valid1 = 1'b0;
        fetch_data0 = INST_C;
        #1;
        if (fetch_allow !== 1'b1)
            $fatal(1, "single pop did not create one append slot");
        tick();
        check_queue(1'b1, 1'b1, INST_B, INST_C);

        // Consume both B and C while accepting D as the next oldest entry.
        issue1 = 1'b1;
        fetch_data0 = INST_D;
        tick();
        check_queue(1'b1, 1'b0, INST_D, {`IF_TO_ID_BUS_WD{1'b0}});

        // No pop: retain D exactly, even when the fetch side is idle.
        issue0 = 1'b0;
        issue1 = 1'b0;
        fetch_valid0 = 1'b0;
        tick();
        check_queue(1'b1, 1'b0, INST_D, {`IF_TO_ID_BUS_WD{1'b0}});

        // Pop the final entry and leave a bubble.
        issue0 = 1'b1;
        tick();
        check_queue(1'b0, 1'b0, {`IF_TO_ID_BUS_WD{1'b0}}, {`IF_TO_ID_BUS_WD{1'b0}});

        // Refill then flush while stalled; both younger slots must be invalid.
        issue0 = 1'b0;
        fetch_valid0 = 1'b1;
        fetch_valid1 = 1'b1;
        fetch_data0 = INST_A;
        fetch_data1 = INST_B;
        tick();
        check_queue(1'b1, 1'b1, INST_A, INST_B);
        fetch_valid0 = 1'b0;
        fetch_valid1 = 1'b0;
        flush = 1'b1;
        tick();
        check_queue(1'b0, 1'b0, {`IF_TO_ID_BUS_WD{1'b0}}, {`IF_TO_ID_BUS_WD{1'b0}});

        $display("PASS: ordered dual-entry IF/ID queue tests");
        $finish;
    end
endmodule
