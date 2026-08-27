`timescale 1ns/1ps

module tb_dual_issue_pair;
    reg valid0, valid1, lane0_pairable, lane0_writes_rd, simple1;
    reg rs1_used1, rs2_used1;
    reg [4:0] rs1_1, rs2_1, rd0, rd1;
    wire pair_valid;

    dual_issue_pair dut(
        .valid0(valid0), .valid1(valid1),
        .lane0_pairable(lane0_pairable),
        .lane0_writes_rd(lane0_writes_rd), .simple1(simple1),
        .rs1_used1(rs1_used1), .rs2_used1(rs2_used1),
        .rs1_1(rs1_1), .rs2_1(rs2_1), .rd0(rd0), .rd1(rd1),
        .pair_valid(pair_valid)
    );

    task check_pair;
        input expected;
        input [8*64-1:0] message;
        begin
            #1;
            if (pair_valid !== expected)
                $fatal(1, "%0s: got %b", message, pair_valid);
        end
    endtask

    initial begin
        valid0=1; valid1=1; lane0_pairable=1; lane0_writes_rd=1; simple1=1;
        rs1_used1=1; rs2_used1=1; rs1_1=2; rs2_1=3; rd0=1; rd1=4;
        check_pair(1, "independent simple ALU pair must issue");

        rs1_1=1;
        check_pair(0, "slot0-to-slot1 rs1 RAW must serialize");

        rs1_1=2; rs2_1=1;
        check_pair(0, "slot0-to-slot1 rs2 RAW must serialize");

        rs2_1=3; rd1=1;
        check_pair(0, "WAW must serialize");

        rd0=0;
        check_pair(1, "x0 destination must not create RAW or WAW");

        rd0=1; rd1=1; lane0_writes_rd=0;
        check_pair(1, "store has no destination dependency and may pair");

        lane0_writes_rd=1; rd1=4; rs1_1=2; rs2_1=3;
        check_pair(1, "independent load or mul.w may pair with lane1 ALU");

        rs1_1=1;
        check_pair(0, "load or mul.w result RAW must serialize");

        rs1_1=2; lane0_pairable=0;
        check_pair(0, "branch CSR div and other lane0 operations serialize");

        lane0_pairable=1; simple1=0;
        check_pair(0, "non-simple slot1 must serialize");

        $display("PASS: asymmetric ordered dual-issue pairing tests");
        $finish;
    end
endmodule
