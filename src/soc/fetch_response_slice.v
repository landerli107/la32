`timescale 1ns / 1ps
/**
 * Zero-bubble instruction response skid buffer.
 *
 * While the downstream queue can accept a packet, the response is passed
 * through combinationally and therefore gains no pipeline cycle. If the
 * downstream queue stalls, exactly one complete one- or two-instruction
 * packet is captured. Input backpressure then depends only on hold_valid,
 * breaking the data-response -> decode-ready -> fetch-PC timing chain.
 */
`include "myCPU.h"
module fetch_response_slice(
    input  wire                              clk,
    input  wire                              reset,
    input  wire                              flush,

    input  wire                              in_valid0,
    input  wire                              in_valid1,
    input  wire [`IF_TO_ID_BUS_WD-1:0]       in_data0,
    input  wire [`IF_TO_ID_BUS_WD-1:0]       in_data1,
    output wire                              in_allow,

    output wire                              out_valid0,
    output wire                              out_valid1,
    output wire [`IF_TO_ID_BUS_WD-1:0]       out_data0,
    output wire [`IF_TO_ID_BUS_WD-1:0]       out_data1,
    input  wire                              out_allow
);
    reg                              hold_valid;
    reg                              hold_valid1;
    reg [`IF_TO_ID_BUS_WD-1:0]       hold_data0;
    reg [`IF_TO_ID_BUS_WD-1:0]       hold_data1;

    // Deliberately omit out_allow from the upstream ready path. A held packet
    // drains first; the upstream response is accepted after hold_valid clears.
    assign in_allow   = ~hold_valid | flush;
    assign out_valid0 = ~flush & (hold_valid | in_valid0);
    assign out_valid1 = out_valid0 &
                        (hold_valid ? hold_valid1 : in_valid1);
    assign out_data0  = hold_valid ? hold_data0 : in_data0;
    assign out_data1  = hold_valid ? hold_data1 : in_data1;

    wire capture = ~hold_valid & in_valid0 & ~out_allow;
    wire drain_hold = hold_valid & out_allow;

    always @(posedge clk) begin
        if (reset || flush) begin
            hold_valid  <= 1'b0;
        end else if (capture) begin
            hold_valid  <= 1'b1;
        end else if (drain_hold) begin
            hold_valid  <= 1'b0;
        end
    end

    // Payload is irrelevant while the skid is empty, so pre-sample the input
    // packet during that state and freeze it only after capture.  The 321 wide
    // register enables now depend solely on local hold_valid; neither cache
    // response validity nor the complete MEM->EXE->ID backpressure cone can
    // reach them.  Empty fall-through and the capture edge remain unchanged.
    always @(posedge clk) begin
        if (!hold_valid) begin
            hold_valid1 <= in_valid1;
            hold_data0  <= in_data0;
            hold_data1  <= in_data1;
        end
    end

`ifndef SYNTHESIS
    reg [`IF_TO_ID_BUS_WD-1:0] held_data0_q;
    reg [`IF_TO_ID_BUS_WD-1:0] held_data1_q;
    reg                         held_valid1_q;
    always @(posedge clk) begin
        if (hold_valid && !out_allow && !flush) begin
            if ((hold_data0 !== held_data0_q) ||
                (hold_data1 !== held_data1_q) ||
                (hold_valid1 !== held_valid1_q)) begin
                $display("FAIL fetch response changed while stalled");
                $fatal(1);
            end
        end
        held_data0_q  <= capture ? in_data0 : hold_data0;
        held_data1_q  <= capture ? in_data1 : hold_data1;
        held_valid1_q <= capture ? in_valid1 : hold_valid1;
    end
`endif

endmodule
