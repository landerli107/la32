`timescale 1ns / 1ps
`include "myCPU.h"

module tb_fetch_response_slice;
    reg clk;
    reg reset;
    reg flush;
    reg in_valid0;
    reg in_valid1;
    reg [`IF_TO_ID_BUS_WD-1:0] in_data0;
    reg [`IF_TO_ID_BUS_WD-1:0] in_data1;
    wire in_allow;
    wire out_valid0;
    wire out_valid1;
    wire [`IF_TO_ID_BUS_WD-1:0] out_data0;
    wire [`IF_TO_ID_BUS_WD-1:0] out_data1;
    reg out_allow;

    localparam [`IF_TO_ID_BUS_WD-1:0] A0 =
        {{(`IF_TO_ID_BUS_WD-32){1'b0}}, 32'h0000_00a0};
    localparam [`IF_TO_ID_BUS_WD-1:0] A1 =
        {{(`IF_TO_ID_BUS_WD-32){1'b0}}, 32'h0000_00a1};
    localparam [`IF_TO_ID_BUS_WD-1:0] B0 =
        {{(`IF_TO_ID_BUS_WD-32){1'b0}}, 32'h0000_00b0};
    localparam [`IF_TO_ID_BUS_WD-1:0] B1 =
        {{(`IF_TO_ID_BUS_WD-32){1'b0}}, 32'h0000_00b1};
    localparam [`IF_TO_ID_BUS_WD-1:0] C0 =
        {{(`IF_TO_ID_BUS_WD-32){1'b0}}, 32'h0000_00c0};
    localparam [`IF_TO_ID_BUS_WD-1:0] C1 =
        {{(`IF_TO_ID_BUS_WD-32){1'b0}}, 32'h0000_00c1};

    fetch_response_slice dut(
        .clk(clk), .reset(reset), .flush(flush),
        .in_valid0(in_valid0), .in_valid1(in_valid1),
        .in_data0(in_data0), .in_data1(in_data1), .in_allow(in_allow),
        .out_valid0(out_valid0), .out_valid1(out_valid1),
        .out_data0(out_data0), .out_data1(out_data1),
        .out_allow(out_allow)
    );

    always #5 clk = ~clk;

    task step;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task expect_packet;
        input expected_valid0;
        input expected_valid1;
        input [`IF_TO_ID_BUS_WD-1:0] expected_data0;
        input [`IF_TO_ID_BUS_WD-1:0] expected_data1;
        begin
            if (out_valid0 !== expected_valid0 ||
                out_valid1 !== expected_valid1 ||
                (expected_valid0 && out_data0 !== expected_data0) ||
                (expected_valid1 && out_data1 !== expected_data1)) begin
                $display("FAIL valid=%b/%b data=%h/%h expected=%b/%b %h/%h",
                         out_valid0, out_valid1, out_data0, out_data1,
                         expected_valid0, expected_valid1,
                         expected_data0, expected_data1);
                $fatal(1);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        flush = 1'b0;
        in_valid0 = 1'b0;
        in_valid1 = 1'b0;
        in_data0 = A0;
        in_data1 = A1;
        out_allow = 1'b1;

        step();
        reset = 1'b0;
        step();

        // Empty state is transparent: no mandatory register cycle.
        in_valid0 = 1'b1;
        in_valid1 = 1'b1;
        #1;
        if (in_allow !== 1'b1)
            $fatal(1, "empty skid did not accept input");
        expect_packet(1'b1, 1'b1, A0, A1);
        step();

        // A blocked downstream captures one complete packet.
        out_allow = 1'b0;
        in_data0 = B0;
        in_data1 = B1;
        #1;
        expect_packet(1'b1, 1'b1, B0, B1);
        step();

        // The held B packet is stable; younger C is backpressured.
        in_data0 = C0;
        in_data1 = C1;
        #1;
        if (in_allow !== 1'b0)
            $fatal(1, "occupied skid accepted a younger packet");
        expect_packet(1'b1, 1'b1, B0, B1);
        step();

        // Drain B without making ready combinationally depend on out_allow.
        out_allow = 1'b1;
        #1;
        if (in_allow !== 1'b0)
            $fatal(1, "skid ready depends on downstream allow");
        step();
        if (in_allow !== 1'b1)
            $fatal(1, "skid did not reopen after drain");
        expect_packet(1'b1, 1'b1, C0, C1);

        // C is consumed transparently on the next edge.
        step();
        in_valid0 = 1'b0;
        in_valid1 = 1'b0;
        #1;
        expect_packet(1'b0, 1'b0, C0, C1);

        // A one-instruction packet must not expose slot 1.
        in_valid0 = 1'b1;
        in_valid1 = 1'b0;
        in_data0 = A0;
        #1;
        expect_packet(1'b1, 1'b0, A0, C1);

        // Flush discards a held wrong-path packet and overrides backpressure.
        out_allow = 1'b0;
        step();
        if (in_allow !== 1'b0)
            $fatal(1, "single packet was not captured");
        flush = 1'b1;
        #1;
        if (in_allow !== 1'b1)
            $fatal(1, "flush did not override backpressure");
        expect_packet(1'b0, 1'b0, A0, C1);
        step();
        flush = 1'b0;
        in_valid0 = 1'b0;
        #1;
        expect_packet(1'b0, 1'b0, A0, C1);

        $display("PASS tb_fetch_response_slice");
        $finish;
    end
endmodule
