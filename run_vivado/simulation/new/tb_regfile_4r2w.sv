`timescale 1ns/1ps

module tb_regfile_4r2w;
    reg clk;
    reg [4:0] r_addr1, r_addr2, r_addr3, r_addr4;
    wire [31:0] r_data1, r_data2, r_data3, r_data4;
    reg [31:0] w_data, w_data2;
    reg [4:0] w_addr, w_addr2;
    reg w_en, w_en2;

    RegFile dut(
        .clk(clk),
        .r_addr1(r_addr1), .r_addr2(r_addr2),
        .r_addr3(r_addr3), .r_addr4(r_addr4),
        .r_data1(r_data1), .r_data2(r_data2),
        .r_data3(r_data3), .r_data4(r_data4),
        .w_data(w_data), .w_addr(w_addr), .w_en(w_en),
        .w_data2(w_data2), .w_addr2(w_addr2), .w_en2(w_en2)
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
        r_addr1 = 0; r_addr2 = 0; r_addr3 = 0; r_addr4 = 0;
        w_data = 0; w_addr = 0; w_en = 0;
        w_data2 = 0; w_addr2 = 0; w_en2 = 0;

        w_en = 1; w_addr = 5'd3; w_data = 32'h1111_1111;
        w_en2 = 1; w_addr2 = 5'd4; w_data2 = 32'h2222_2222;
        tick();
        r_addr1 = 3; r_addr2 = 4; r_addr3 = 3; r_addr4 = 4;
        #1;
        if (r_data1 !== 32'h1111_1111 || r_data2 !== 32'h2222_2222 ||
            r_data3 !== 32'h1111_1111 || r_data4 !== 32'h2222_2222)
            $fatal(1, "independent dual writes did not reach both RF copies");

        // Younger slot1 has architectural priority if both ports target rd.
        w_addr = 5'd5; w_data = 32'haaaa_aaaa;
        w_addr2 = 5'd5; w_data2 = 32'hbbbb_bbbb;
        tick();
        r_addr1 = 5; r_addr3 = 5;
        #1;
        if (r_data1 !== 32'hbbbb_bbbb || r_data3 !== 32'hbbbb_bbbb)
            $fatal(1, "younger slot1 did not win same-address dual write");

        // Neither write port may change architectural x0.
        w_addr = 0; w_data = 32'hdead_beef;
        w_addr2 = 0; w_data2 = 32'hcafe_f00d;
        tick();
        r_addr1 = 0; r_addr3 = 0;
        #1;
        if (r_data1 !== 0 || r_data3 !== 0)
            $fatal(1, "dual write ports corrupted x0");

        $display("PASS: 4R2W register file dual-write tests");
        $finish;
    end
endmodule
