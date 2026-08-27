`timescale 1ns / 1ps

module tb_cache_meta_ram_split;
    reg clk;
    reg [10:0] rd_set;
    wire [38:0] rd_meta;
    reg [10:0] wr_set;
    reg wr_tag0_en;
    reg [16:0] wr_tag0;
    reg wr_tag1_en;
    reg [16:0] wr_tag1;
    reg wr_status_en;
    reg [4:0] wr_status;

    localparam [10:0] SET_A = 11'h12a;
    localparam [10:0] SET_B = 11'h355;
    localparam [16:0] TAG_A0 = 17'h01234;
    localparam [16:0] TAG_A1 = 17'h15678;
    localparam [16:0] TAG_B0 = 17'h0abcd;
    localparam [16:0] TAG_B1 = 17'h10123;

    cache_meta_ram_2048x39 dut(
        .clk(clk),
        .rd_set(rd_set),
        .rd_meta(rd_meta),
        .wr_set(wr_set),
        .wr_tag0_en(wr_tag0_en),
        .wr_tag0(wr_tag0),
        .wr_tag1_en(wr_tag1_en),
        .wr_tag1(wr_tag1),
        .wr_status_en(wr_status_en),
        .wr_status(wr_status)
    );

    always #5 clk = ~clk;

    task step;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task disable_writes;
        begin
            wr_tag0_en = 1'b0;
            wr_tag1_en = 1'b0;
            wr_status_en = 1'b0;
        end
    endtask

    task expect_meta;
        input [16:0] expected_tag0;
        input [16:0] expected_tag1;
        input [4:0] expected_status;
        reg [38:0] expected;
        begin
            expected = {expected_status[4], expected_status[3],
                        expected_status[2], expected_tag1,
                        expected_status[1], expected_status[0],
                        expected_tag0};
            if (rd_meta !== expected) begin
                $display("FAIL meta=%h expected=%h", rd_meta, expected);
                $fatal(1);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rd_set = SET_A;
        wr_set = SET_A;
        wr_tag0_en = 1'b1;
        wr_tag0 = TAG_A0;
        wr_tag1_en = 1'b1;
        wr_tag1 = TAG_A1;
        wr_status_en = 1'b1;
        wr_status = 5'b1_10_10;

        // Install a complete entry.  The synchronous read returns it on the
        // following edge, matching the inferred block-RAM behavior.
        step();
        disable_writes();
        step();
        expect_meta(TAG_A0, TAG_A1, 5'b1_10_10);

        // A status-only hit update must not rewrite either tag RAM.
        wr_status_en = 1'b1;
        wr_status = 5'b0_11_11;
        step();
        disable_writes();
        step();
        expect_meta(TAG_A0, TAG_A1, 5'b0_11_11);

        // Refill way 0 while updating status; way 1 remains untouched.
        wr_tag0_en = 1'b1;
        wr_tag0 = TAG_B0;
        wr_status_en = 1'b1;
        wr_status = 5'b1_11_10;
        step();
        disable_writes();
        step();
        expect_meta(TAG_B0, TAG_A1, 5'b1_11_10);

        // A different set has independent tags and status.
        wr_set = SET_B;
        rd_set = SET_B;
        wr_tag0_en = 1'b1;
        wr_tag0 = TAG_A0;
        wr_tag1_en = 1'b1;
        wr_tag1 = TAG_B1;
        wr_status_en = 1'b1;
        wr_status = 5'b0_10_01;
        step();
        disable_writes();
        step();
        expect_meta(TAG_A0, TAG_B1, 5'b0_10_01);

        // Re-reading set A proves that the set and field write enables did not
        // disturb its way-0 refill or preserved way-1 tag.
        rd_set = SET_A;
        step();
        expect_meta(TAG_B0, TAG_A1, 5'b1_11_10);

        $display("PASS tb_cache_meta_ram_split");
        $finish;
    end
endmodule
