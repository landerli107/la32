`timescale 1ns/1ps

module tb_core_cacheop_serial;
    reg clk;
    reg reset;
    reg cacheop_ready;
    reg [31:0] inst_rdata;
    reg [31:0] inst_rdata1;

    wire inst_en;
    wire [3:0] inst_we;
    wire [31:0] inst_addr;
    wire [31:0] inst_wdata;
    wire inst_resp_ready;
    wire data_en;
    wire [3:0] data_we;
    wire [31:0] data_addr;
    wire [31:0] data_pc;
    wire [2:0] data_size;
    wire [31:0] data_wdata;
    wire cacheop_valid;
    wire [4:0] cacheop_code;
    wire [31:0] cacheop_addr;
    wire cache_enable;

    localparam [31:0] BASE = 32'h1c00_0000;
    integer timeout_cycles;
    integer cacheop_handshakes;

    wire [31:0] word_index = (inst_addr - BASE) >> 2;
    wire inst_rdata1_valid = inst_en && (word_index == 32'd0);

    always @(*) begin
        inst_rdata  = 32'h0280_0000;
        inst_rdata1 = 32'h0280_0000;
        case (word_index)
            32'd0: begin
                // cacop 0x01, rj=0, si12=0
                inst_rdata  = 32'h0600_0001;
                // A second CACOP exercises the completion-token fallback.
                inst_rdata1 = 32'h0600_0001;
            end
            32'd1: inst_rdata = 32'h0600_0001;
            // addi.w r1,r0,5 must execute only after both CACOPs complete.
            32'd2: inst_rdata = 32'h0280_1401;
            default: begin end
        endcase
    end

    YK_Core dut(
        .clk(clk), .reset(reset),
        .inst_sram_en(inst_en), .inst_sram_we(inst_we),
        .inst_sram_addr(inst_addr), .inst_sram_wdata(inst_wdata),
        .inst_sram_rdata(inst_rdata), .inst_sram_rdata1(inst_rdata1),
        .inst_sram_rdata1_valid(inst_rdata1_valid),
        .inst_sram_addr_ok(1'b1), .inst_sram_data_ok(inst_en),
        .inst_sram_resp_ready(inst_resp_ready),
        .data_sram_en(data_en), .data_sram_we(data_we),
        .data_sram_addr(data_addr), .data_sram_pc(data_pc),
        .data_sram_size(data_size), .data_sram_wdata(data_wdata),
        .data_sram_rdata(32'b0), .data_sram_addr_ok(1'b1),
        .data_sram_data_ok(1'b1), .data_sram_id_forward_ok(1'b0),
        .data_sram_id_forward_data(32'b0),
        .cacheop_valid(cacheop_valid), .cacheop_code(cacheop_code),
        .cacheop_addr(cacheop_addr), .cacheop_ready(cacheop_ready),
        .cache_enable(cache_enable), .sel_strcture_hazard(1'b0)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset && cacheop_valid && cacheop_ready)
            cacheop_handshakes <= cacheop_handshakes + 1;
    end

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        cacheop_ready = 1'b0;
        cacheop_handshakes = 0;
        timeout_cycles = 0;

        repeat (3) @(posedge clk);
        reset = 1'b0;

        while (!cacheop_valid && timeout_cycles < 30) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        #1;
        if (!cacheop_valid)
            $fatal(1, "CACOP request was never presented");
        if (cacheop_code !== 5'h01 || cacheop_addr !== 32'd0)
            $fatal(1, "CACOP payload mismatch code=%h addr=%h",
                   cacheop_code, cacheop_addr);

        repeat (2) begin
            @(posedge clk);
            #1;
            if (!cacheop_valid)
                $fatal(1, "CACOP request was not held while ready was low");
        end

        cacheop_ready = 1'b1;
        #1;
        if (!dut.ID_issue_slot0)
            $fatal(1, "ready CACOP did not issue on its handshake cycle");
        @(posedge clk);
        #1;
        cacheop_ready = 1'b0;
        if (cacheop_valid)
            $fatal(1, "CACOP request remained valid after handshake");
        if (dut.id_run.cacheop_complete)
            $fatal(1, "unblocked CACOP paid an unnecessary completion cycle");

        // The next CACOP is allowed to handshake while EXE is blocked.  The
        // token must then retain architectural completion until EXE reopens.
        timeout_cycles = 0;
        while (!cacheop_valid && timeout_cycles < 30) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        if (!cacheop_valid)
            $fatal(1, "second CACOP request was never presented");
        force dut.EXE_allow_in = 1'b0;
        cacheop_ready = 1'b1;
        @(posedge clk);
        #1;
        cacheop_ready = 1'b0;
        if (!dut.id_run.cacheop_complete)
            $fatal(1, "blocked CACOP completion token was not registered");
        release dut.EXE_allow_in;

        timeout_cycles = 0;
        while ((dut.id_run.RF.Reg_File0[1] !== 32'd5) &&
               (timeout_cycles < 30)) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        #1;
        if (dut.id_run.RF.Reg_File0[1] !== 32'd5)
            $fatal(1, "instruction after CACOP did not commit");
        if (cacheop_handshakes != 2)
            $fatal(1, "CACOP handshake count=%0d expected=2",
                   cacheop_handshakes);

        $display("PASS tb_core_cacheop_serial");
        $finish;
    end
endmodule
