`timescale 1ns/1ps

module tb_cache_normal_word_response;
    logic clk = 1'b0;
    logic reset = 1'b1;
    always #5 clk = ~clk;

    logic inst_req = 1'b0;
    logic [31:0] inst_addr = 32'd0;
    wire inst_addr_ok, inst_data_ok;
    wire [31:0] inst_rdata, inst_rdata1;
    wire inst_rdata1_valid;
    logic inst_resp_ready = 1'b1;

    logic data_req = 1'b0;
    logic data_prefetch_hint = 1'b0;
    logic [3:0] data_we = 4'd0;
    logic [31:0] data_addr = 32'd0;
    logic [31:0] data_pc = 32'd0;
    logic [2:0] data_size = 3'd2;
    logic [31:0] data_wdata = 32'd0;
    wire data_addr_ok, data_data_ok;
    wire [31:0] data_rdata;
    wire data_id_forward_ok;
    wire [31:0] data_id_forward_data;

    logic cacheop_valid = 1'b0;
    logic [4:0] cacheop_code = 5'd0;
    logic [31:0] cacheop_addr = 32'd0;
    wire cacheop_ready;
    logic cache_enable = 1'b1;

    wire [3:0] m_arid;
    wire [31:0] m_araddr;
    wire [7:0] m_arlen;
    wire [2:0] m_arsize;
    wire [1:0] m_arburst;
    wire m_arvalid;
    logic m_arready = 1'b0;
    logic [3:0] m_rid = 4'd0;
    logic [31:0] m_rdata = 32'd0;
    logic [1:0] m_rresp = 2'd0;
    logic m_rlast = 1'b0;
    logic m_rvalid = 1'b0;
    wire m_rready;

    wire [3:0] m_awid;
    wire [31:0] m_awaddr;
    wire [7:0] m_awlen;
    wire [2:0] m_awsize;
    wire [1:0] m_awburst;
    wire m_awvalid;
    logic m_awready = 1'b0;
    wire [31:0] m_wdata;
    wire [3:0] m_wstrb;
    wire m_wlast, m_wvalid;
    logic m_wready = 1'b0;
    logic [3:0] m_bid = 4'd0;
    logic [1:0] m_bresp = 2'd0;
    logic m_bvalid = 1'b0;
    wire m_bready;

    cache_axi_master dut (.*);

    initial begin
        repeat (2) @(posedge clk);
        reset = 1'b0;
        @(negedge clk);

        // Model the unique, already accepted normal data-word transaction.
        force dut.state = 4'd2; // S_RDATA
        force dut.read_owner_data = 1'b1;
        force dut.read_refill = 1'b0;
        force dut.req_forward_mask = 4'd0;
        force dut.req_forward_data = 32'd0;

        m_rid = 4'd1;
        m_rdata = 32'hdead_beef;
        m_rlast = 1'b1;
        m_rvalid = 1'b1;
        #1;
        if (!data_data_ok || !data_id_forward_ok ||
            data_rdata !== 32'hdead_beef ||
            data_id_forward_data !== 32'hdead_beef)
            $fatal(1, "normal word response did not bypass in S_RDATA");

        // RID2 belongs to the speculative early-word transaction and must not
        // be mistaken for the normal response qualified above.
        m_rid = 4'd2;
        #1;
        if (dut.normal_word_response_now)
            $fatal(1, "RID2 incorrectly qualified as normal response");

        m_rvalid = 1'b0;
        m_rid = 4'd1;
        #1;
        if (dut.normal_word_response_now)
            $fatal(1, "invalid AXI beat qualified as normal response");

        // The early transaction captures one complete AR payload.  The
        // active bit must not remain in the live bridge address/decode path.
        release dut.state;
        release dut.read_owner_data;
        release dut.read_refill;
        data_addr = 32'h8040_1234;
        force dut.early_word_launch = 1'b1;
        @(posedge clk);
        #1;
        release dut.early_word_launch;
        if (m_arid !== 4'd2 || m_araddr !== dut.data_pa || m_arlen !== 8'd0)
            $fatal(1, "early AR payload was not captured atomically");

        // When an early response drains in front of a pending normal read,
        // promote the already registered normal payload without a new launch.
        force dut.state = 4'd1; // S_RADDR
        force dut.read_owner_data = 1'b0;
        force dut.read_addr_r = 32'h1c00_4000;
        force dut.read_len_r = 8'd3;
        force dut.early_r_fire = 1'b1;
        @(posedge clk);
        #1;
        release dut.early_r_fire;
        if (m_arid !== 4'd0 || m_araddr !== 32'h1c00_4000 ||
            m_arlen !== 8'd3)
            $fatal(1, "pending normal AR payload was not restored");

        release dut.req_forward_data;
        release dut.req_forward_mask;
        release dut.read_len_r;
        release dut.read_addr_r;
        release dut.read_owner_data;
        release dut.state;
        $display("PASS tb_cache_normal_word_response");
        $finish;
    end
endmodule
