`default_nettype none

module myCPU_top (
    input  wire        clk,
    input  wire        reset,

    inout  wire [31:0] base_ram_data,
    output wire [19:0] base_ram_addr,
    output wire [ 3:0] base_ram_be_n,
    output wire        base_ram_ce_n,
    output wire        base_ram_oe_n,
    output wire        base_ram_we_n,

    inout  wire [31:0] ext_ram_data,
    output wire [19:0] ext_ram_addr,
    output wire [ 3:0] ext_ram_be_n,
    output wire        ext_ram_ce_n,
    output wire        ext_ram_oe_n,
    output wire        ext_ram_we_n,

    output wire        txd,
    input  wire        rxd
);

    wire        inst_req;
    wire [ 3:0] inst_we;
    wire [31:0] inst_addr;
    wire [31:0] inst_wdata;
    wire [31:0] inst_rdata;
    wire [31:0] inst_rdata1;
    wire        inst_rdata1_valid;
    wire        inst_addr_ok;
    wire        inst_data_ok;
    wire        inst_resp_ready;

    wire        data_req;
    wire        data_prefetch_hint;
    wire [ 3:0] data_we;
    wire [31:0] data_addr;
    wire [31:0] data_pc;
    wire [ 2:0] data_size;
    wire [31:0] data_wdata;
    wire [31:0] data_rdata;
    wire        data_addr_ok;
    wire        data_data_ok;
    wire        data_id_forward_ok;
    wire [31:0] data_id_forward_data;

    wire        cacheop_valid;
    wire [ 4:0] cacheop_code;
    wire [31:0] cacheop_addr;
    wire        cacheop_ready;

    wire        cache_enable;
    wire [ 3:0] arid;
    wire [31:0] araddr;
    wire [ 7:0] arlen;
    wire [ 2:0] arsize;
    wire [ 1:0] arburst;
    wire        arvalid;
    wire        arready;
    wire [ 3:0] rid;
    wire [31:0] rdata;
    wire [ 1:0] rresp;
    wire        rlast;
    wire        rvalid;
    wire        rready;
    wire [ 3:0] awid;
    wire [31:0] awaddr;
    wire [ 7:0] awlen;
    wire [ 2:0] awsize;
    wire [ 1:0] awburst;
    wire        awvalid;
    wire        awready;
    wire [31:0] wdata;
    wire [ 3:0] wstrb;
    wire        wlast;
    wire        wvalid;
    wire        wready;
    wire [ 3:0] bid;
    wire [ 1:0] bresp;
    wire        bvalid;
    wire        bready;

    YK_Core u_core (
        .clk(clk),
        .reset(reset),
        .inst_sram_en(inst_req),
        .inst_sram_we(inst_we),
        .inst_sram_addr(inst_addr),
        .inst_sram_wdata(inst_wdata),
        .inst_sram_rdata(inst_rdata),
        .inst_sram_rdata1(inst_rdata1),
        .inst_sram_rdata1_valid(inst_rdata1_valid),
        .inst_sram_addr_ok(inst_addr_ok),
        .inst_sram_data_ok(inst_data_ok),
        .inst_sram_resp_ready(inst_resp_ready),
        .data_sram_en(data_req),
        .data_sram_prefetch_hint(data_prefetch_hint),
        .data_sram_we(data_we),
        .data_sram_addr(data_addr),
        .data_sram_pc(data_pc),
        .data_sram_size(data_size),
        .data_sram_wdata(data_wdata),
        .data_sram_rdata(data_rdata),
        .data_sram_addr_ok(data_addr_ok),
        .data_sram_data_ok(data_data_ok),
        .data_sram_id_forward_ok(data_id_forward_ok),
        .data_sram_id_forward_data(data_id_forward_data),
        .cacheop_valid(cacheop_valid),
        .cacheop_code(cacheop_code),
        .cacheop_addr(cacheop_addr),
        .cacheop_ready(cacheop_ready),
        .cache_enable(cache_enable),
        .sel_strcture_hazard(1'b0)
    );

    cache_axi_master u_cache_axi (
        .clk(clk), .reset(reset),
        .inst_req(inst_req), .inst_addr(inst_addr),
        .inst_addr_ok(inst_addr_ok), .inst_data_ok(inst_data_ok), .inst_rdata(inst_rdata),
        .inst_rdata1(inst_rdata1), .inst_rdata1_valid(inst_rdata1_valid),
        .inst_resp_ready(inst_resp_ready),
        .data_req(data_req), .data_we(data_we), .data_addr(data_addr),
        .data_prefetch_hint(data_prefetch_hint),
        .data_pc(data_pc), .data_size(data_size), .data_wdata(data_wdata),
        .data_addr_ok(data_addr_ok), .data_data_ok(data_data_ok), .data_rdata(data_rdata),
        .data_id_forward_ok(data_id_forward_ok),
        .data_id_forward_data(data_id_forward_data),
        .cacheop_valid(cacheop_valid),
        .cacheop_code(cacheop_code),
        .cacheop_addr(cacheop_addr), .cacheop_ready(cacheop_ready),
        .cache_enable(cache_enable),
        .m_arid(arid), .m_araddr(araddr), .m_arlen(arlen), .m_arsize(arsize),
        .m_arburst(arburst), .m_arvalid(arvalid), .m_arready(arready),
        .m_rid(rid), .m_rdata(rdata), .m_rresp(rresp), .m_rlast(rlast),
        .m_rvalid(rvalid), .m_rready(rready),
        .m_awid(awid), .m_awaddr(awaddr), .m_awlen(awlen), .m_awsize(awsize),
        .m_awburst(awburst), .m_awvalid(awvalid), .m_awready(awready),
        .m_wdata(wdata), .m_wstrb(wstrb), .m_wlast(wlast), .m_wvalid(wvalid), .m_wready(wready),
        .m_bid(bid), .m_bresp(bresp), .m_bvalid(bvalid), .m_bready(bready)
    );

    axi_soc_bridge #(
        .CLK_FREQ_HZ(105_468_750),
        .SRAM_READ_ACCESS_CYCLES(2),
        .SRAM_WRITE_ACCESS_CYCLES(1)
    ) u_axi_soc (
        .clk(clk), .reset(reset),
        .s_arid(arid), .s_araddr(araddr), .s_arlen(arlen), .s_arsize(arsize),
        .s_arburst(arburst), .s_arvalid(arvalid), .s_arready(arready),
        .s_rid(rid), .s_rdata(rdata), .s_rresp(rresp), .s_rlast(rlast),
        .s_rvalid(rvalid), .s_rready(rready),
        .s_awid(awid), .s_awaddr(awaddr), .s_awlen(awlen), .s_awsize(awsize),
        .s_awburst(awburst), .s_awvalid(awvalid), .s_awready(awready),
        .s_wdata(wdata), .s_wstrb(wstrb), .s_wlast(wlast), .s_wvalid(wvalid), .s_wready(wready),
        .s_bid(bid), .s_bresp(bresp), .s_bvalid(bvalid), .s_bready(bready),
        .base_ram_data(base_ram_data), .base_ram_addr(base_ram_addr),
        .base_ram_be_n(base_ram_be_n), .base_ram_ce_n(base_ram_ce_n),
        .base_ram_oe_n(base_ram_oe_n), .base_ram_we_n(base_ram_we_n),
        .ext_ram_data(ext_ram_data), .ext_ram_addr(ext_ram_addr),
        .ext_ram_be_n(ext_ram_be_n), .ext_ram_ce_n(ext_ram_ce_n),
        .ext_ram_oe_n(ext_ram_oe_n), .ext_ram_we_n(ext_ram_we_n),
        .txd(txd), .rxd(rxd)
    );

endmodule

`default_nettype wire
