`default_nettype none

// Single-master AXI4 slave subsystem for the ThinPAD BaseRAM, ExtRAM and
// a minimal 16550-compatible UART.  It supports INCR reads (used by cache
// line fills) and single-beat writes (used by the write-through D-cache).
module axi_soc_bridge #(
    parameter CLK_FREQ_HZ = 11_059_200,
    parameter SRAM_READ_ACCESS_CYCLES = 2,
    parameter SRAM_WRITE_ACCESS_CYCLES = 1
) (
    input  wire        clk,
    input  wire        reset,

    input  wire [ 3:0] s_arid,
    input  wire [31:0] s_araddr,
    input  wire [ 7:0] s_arlen,
    input  wire [ 2:0] s_arsize,
    input  wire [ 1:0] s_arburst,
    input  wire        s_arvalid,
    output wire        s_arready,
    output wire [ 3:0] s_rid,
    output wire [31:0] s_rdata,
    output wire [ 1:0] s_rresp,
    output wire        s_rlast,
    output wire        s_rvalid,
    input  wire        s_rready,

    input  wire [ 3:0] s_awid,
    input  wire [31:0] s_awaddr,
    input  wire [ 7:0] s_awlen,
    input  wire [ 2:0] s_awsize,
    input  wire [ 1:0] s_awburst,
    input  wire        s_awvalid,
    output wire        s_awready,
    input  wire [31:0] s_wdata,
    input  wire [ 3:0] s_wstrb,
    input  wire        s_wlast,
    input  wire        s_wvalid,
    output wire        s_wready,
    output wire [ 3:0] s_bid,
    output wire [ 1:0] s_bresp,
    output wire        s_bvalid,
    input  wire        s_bready,

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

    localparam R_IDLE = 2'd0;
    localparam R_WAIT = 2'd1;
    localparam R_RESP = 2'd2;

    localparam W_IDLE   = 2'd0;
    localparam W_WAIT   = 2'd1;
    localparam W_ACCESS = 2'd2;
    localparam W_RESP   = 2'd3;

    localparam DEV_BASE = 2'd0;
    localparam DEV_EXT  = 2'd1;
    localparam DEV_UART = 2'd2;
    localparam DEV_ERR  = 2'd3;

    reg [1:0] read_state;
    reg [1:0] read_device;
    reg [3:0] read_id;
    reg [31:0] read_addr;
    reg [7:0] read_len;
    reg [7:0] read_beat;
    reg [7:0] read_wait_count;
    reg [31:0] rdata_r;
    reg [1:0] rresp_r;

    reg [1:0] write_state;
    reg [1:0] write_device;
    reg [3:0] write_id;
    reg [31:0] write_addr;
    reg [7:0] write_len;
    reg [7:0] write_beat;
    reg [7:0] write_wait_count;
    reg [31:0] wdata_r;
    reg [3:0] wstrb_r;
    reg [1:0] bresp_r;

    function [1:0] decode_device;
        input [31:0] addr;
        begin
            if ((addr >= 32'h1c00_0000) && (addr < 32'h1c40_0000))
                decode_device = DEV_BASE;
            else if ((addr >= 32'h1c40_0000) && (addr < 32'h1c80_0000))
                decode_device = DEV_EXT;
            else if ((addr >= 32'h1f00_0000) && (addr < 32'h1f00_0008))
                decode_device = DEV_UART;
            else
                decode_device = DEV_ERR;
        end
    endfunction

    // The two asynchronous SRAM chips have independent address, data and
    // control buses.  They can therefore service one read and one write at
    // the same time when the transactions select different chips.  Keep all
    // same-device and UART/error traffic ordered as before.
    function devices_independent;
        input [1:0] lhs;
        input [1:0] rhs;
        begin
            devices_independent =
                (((lhs == DEV_BASE) && (rhs == DEV_EXT)) ||
                 ((lhs == DEV_EXT) && (rhs == DEV_BASE)));
        end
    endfunction

    wire [1:0] incoming_read_device  = decode_device(s_araddr);
    wire [1:0] incoming_write_device = decode_device(s_awaddr);
    // AXI response holding does not need to reserve the physical SRAM after
    // the data has been captured/written.  A read burst is the exception:
    // R_RESP pre-presents the next beat, so it remains physically busy until
    // the final beat is being returned.
    wire read_device_busy =
        (read_state == R_WAIT) ||
        ((read_state == R_RESP) && (read_beat < read_len));
    wire write_device_busy =
        (write_state == W_WAIT) || (write_state == W_ACCESS);
    wire read_blocks_write =
        read_device_busy &&
        !devices_independent(read_device, incoming_write_device);
    wire write_blocks_read =
        write_device_busy &&
        !devices_independent(write_device, incoming_read_device);
    wire incoming_read_blocks_write =
        (read_state == R_IDLE) && s_arvalid && !write_blocks_read &&
        !devices_independent(incoming_read_device, incoming_write_device);

    wire ar_fire = s_arvalid && s_arready;
    wire aw_fire = s_awvalid && s_awready;
    wire w_fire  = s_wvalid && s_wready;
    wire r_fire  = s_rvalid && s_rready;
    wire b_fire  = s_bvalid && s_bready;

    assign s_arready = (read_state == R_IDLE) && !write_blocks_read;
    assign s_awready = (write_state == W_IDLE) && !read_blocks_write &&
                       !incoming_read_blocks_write;
    assign s_wready  = ((write_state == W_IDLE) && s_awvalid && s_awready) ||
                       (write_state == W_WAIT);
    assign s_rid     = read_id;
    assign s_rdata   = rdata_r;
    assign s_rresp   = rresp_r;
    assign s_rlast   = (read_beat == read_len);
    assign s_rvalid  = (read_state == R_RESP);
    assign s_bid     = write_id;
    assign s_bresp   = bresp_r;
    assign s_bvalid  = (write_state == W_RESP);

    // Present a newly accepted SRAM read during the AXI address handshake,
    // and pre-present later burst beats while the current response is visible.
    // Both cases count toward the configured SRAM access interval.
    wire ram_read_launch = ar_fire &&
        ((incoming_read_device == DEV_BASE) ||
         (incoming_read_device == DEV_EXT));
    wire ram_read_current =
        ((read_state == R_WAIT) ||
         ((read_state == R_RESP) && (read_beat < read_len))) &&
         ((read_device == DEV_BASE) || (read_device == DEV_EXT));
    wire ram_write_active =
        (write_state == W_ACCESS) &&
        ((write_device == DEV_BASE) || (write_device == DEV_EXT));
    wire base_read_launch  = ram_read_launch &&
                             (incoming_read_device == DEV_BASE);
    wire ext_read_launch   = ram_read_launch &&
                             (incoming_read_device == DEV_EXT);
    wire base_read_active  = base_read_launch ||
                             (ram_read_current && (read_device == DEV_BASE));
    wire ext_read_active   = ext_read_launch ||
                             (ram_read_current && (read_device == DEV_EXT));
    wire base_write_active = ram_write_active && (write_device == DEV_BASE);
    wire ext_write_active  = ram_write_active && (write_device == DEV_EXT);

    assign base_ram_addr = base_read_launch ? s_araddr[21:2] :
                           (base_read_active ? read_addr[21:2] :
                                               write_addr[21:2]);
    assign base_ram_be_n = base_write_active ? ~wstrb_r : 4'b0000;
    assign base_ram_ce_n = ~(base_read_active || base_write_active);
    assign base_ram_oe_n = ~base_read_active;
    assign base_ram_we_n = ~base_write_active;
    assign base_ram_data = base_write_active ? wdata_r : 32'bz;

    assign ext_ram_addr = ext_read_launch ? s_araddr[21:2] :
                          (ext_read_active ? read_addr[21:2] :
                                             write_addr[21:2]);
    assign ext_ram_be_n = ext_write_active ? ~wstrb_r : 4'b0000;
    assign ext_ram_ce_n = ~(ext_read_active || ext_write_active);
    assign ext_ram_oe_n = ~ext_read_active;
    assign ext_ram_we_n = ~ext_write_active;
    assign ext_ram_data = ext_write_active ? wdata_r : 32'bz;

    // Minimal 16550 register behavior used by supervisor:
    // +0 data/DLL, +1 DLH, +2 FCR, +3 LCR, +4 MCR, +5 LSR.
    reg [7:0] lcr;
    reg [7:0] dll;
    reg [7:0] dlh;
    reg       tx_start;
    reg [7:0] tx_byte;
    wire      tx_busy;
    wire      rx_ready_raw;
    wire [7:0] rx_data_raw;
    reg       rx_avail;
    reg [7:0] rx_byte;
    wire      rx_clear = rx_ready_raw;

    async_transmitter #(.ClkFrequency(CLK_FREQ_HZ), .Baud(115200)) u_uart_tx (
        .clk(clk), .TxD_start(tx_start), .TxD_data(tx_byte), .TxD(txd), .TxD_busy(tx_busy)
    );
    async_receiver #(.ClkFrequency(CLK_FREQ_HZ), .Baud(115200)) u_uart_rx (
        .clk(clk), .RxD(rxd), .RxD_data_ready(rx_ready_raw),
        .RxD_clear(rx_clear), .RxD_data(rx_data_raw)
    );

    function [7:0] selected_write_byte;
        input [31:0] value;
        input [1:0] lane;
        begin
            case (lane)
                2'd0: selected_write_byte = value[7:0];
                2'd1: selected_write_byte = value[15:8];
                2'd2: selected_write_byte = value[23:16];
                default: selected_write_byte = value[31:24];
            endcase
        end
    endfunction

    wire [7:0] uart_status = {2'b00, ~tx_busy, 4'b0000, rx_avail};
    always @(posedge clk) begin
        if (reset) begin
            read_state      <= R_IDLE;
            read_device     <= DEV_ERR;
            read_id         <= 4'd0;
            read_addr       <= 32'd0;
            read_len        <= 8'd0;
            read_beat       <= 8'd0;
            read_wait_count <= 8'd0;
            rdata_r         <= 32'd0;
            rresp_r         <= 2'b00;
            write_state      <= W_IDLE;
            write_device     <= DEV_ERR;
            write_id         <= 4'd0;
            write_addr       <= 32'd0;
            write_len        <= 8'd0;
            write_beat       <= 8'd0;
            write_wait_count <= 8'd0;
            wdata_r          <= 32'd0;
            wstrb_r          <= 4'd0;
            bresp_r          <= 2'b00;
            lcr        <= 8'h03;
            dll        <= 8'd0;
            dlh        <= 8'd0;
            tx_start   <= 1'b0;
            tx_byte    <= 8'd0;
            rx_avail   <= 1'b0;
            rx_byte    <= 8'd0;
        end else begin
            tx_start <= 1'b0;
            if (rx_ready_raw) begin
                rx_avail <= 1'b1;
                rx_byte  <= rx_data_raw;
            end

            case (read_state)
                R_IDLE: begin
                    read_wait_count <= 8'd0;
                    read_beat <= 8'd0;
                    rresp_r <= 2'b00;
                    if (ar_fire) begin
                        read_id     <= s_arid;
                        read_addr   <= s_araddr;
                        read_len    <= s_arlen;
                        read_device <= incoming_read_device;
                        if (incoming_read_device == DEV_UART) begin
                            // Values are shifted to the addressed byte lane.
                            case (s_araddr[2:0])
                                3'd0: rdata_r <= {24'd0, rx_byte};
                                3'd1: rdata_r <= {16'd0, dlh, 8'd0};
                                3'd3: rdata_r <= {lcr, 24'd0};
                                3'd5: rdata_r <= {16'd0, uart_status, 8'd0};
                                default: rdata_r <= 32'd0;
                            endcase
                            if (s_araddr[2:0] == 3'd0) rx_avail <= 1'b0;
                            read_state <= R_RESP;
                        end else if (incoming_read_device == DEV_ERR) begin
                            rdata_r <= 32'd0;
                            rresp_r <= 2'b10;
                            read_state <= R_RESP;
                        end else begin
                            // The address was already presented during this
                            // handshake cycle, so count that elapsed cycle.
                            read_wait_count <=
                                (SRAM_READ_ACCESS_CYCLES > 1) ? 8'd1 : 8'd0;
                            read_state <= R_WAIT;
                        end
                    end
                end

                R_WAIT: begin
                    if (read_wait_count == SRAM_READ_ACCESS_CYCLES - 1) begin
                        rdata_r <= (read_device == DEV_BASE) ? base_ram_data : ext_ram_data;
                        if (read_beat < read_len)
                            read_addr <= read_addr + 32'd4;
                        read_state <= R_RESP;
                    end else begin
                        read_wait_count <= read_wait_count + 8'd1;
                    end
                end

                R_RESP: if (r_fire) begin
                    if (read_beat < read_len) begin
                        read_beat <= read_beat + 8'd1;
                        // One SRAM access cycle elapsed while the current
                        // response was visible.  Seed the remaining wait so
                        // the next beat still observes the configured total.
                        read_wait_count <= (SRAM_READ_ACCESS_CYCLES > 1) ? 8'd1 : 8'd0;
                        read_state <= R_WAIT;
                    end else begin
                        read_state <= R_IDLE;
                    end
                end
                default: read_state <= R_IDLE;
            endcase

            case (write_state)
                W_IDLE: begin
                    write_wait_count <= 8'd0;
                    write_beat <= 8'd0;
                    bresp_r <= 2'b00;
                    if (aw_fire) begin
                        write_id     <= s_awid;
                        write_addr   <= s_awaddr;
                        write_len    <= s_awlen;
                        write_device <= incoming_write_device;
                        if (w_fire) begin
                            wdata_r <= s_wdata;
                            wstrb_r <= s_wstrb;
                            write_state <= W_ACCESS;
                        end else begin
                            write_state <= W_WAIT;
                        end
                    end
                end

                W_WAIT: if (w_fire) begin
                    wdata_r <= s_wdata;
                    wstrb_r <= s_wstrb;
                    write_wait_count <= 8'd0;
                    write_state <= W_ACCESS;
                end

                W_ACCESS: begin
                    if (write_device == DEV_UART) begin
                        case (write_addr[2:0])
                            3'd0: begin
                                if (lcr[7]) dll <= selected_write_byte(wdata_r, write_addr[1:0]);
                                else if (!tx_busy) begin
                                    tx_byte  <= selected_write_byte(wdata_r, write_addr[1:0]);
                                    tx_start <= 1'b1;
                                end
                            end
                            3'd1: if (lcr[7]) dlh <= selected_write_byte(wdata_r, write_addr[1:0]);
                            3'd3: lcr <= selected_write_byte(wdata_r, write_addr[1:0]);
                            default: begin end
                        endcase
                        write_state <= W_RESP;
                    end else if (write_device == DEV_ERR) begin
                        bresp_r <= 2'b10;
                        write_state <= W_RESP;
                    end else if (write_wait_count == SRAM_WRITE_ACCESS_CYCLES - 1) begin
                        if (write_beat < write_len) begin
                            write_beat <= write_beat + 8'd1;
                            write_addr <= write_addr + 32'd4;
                            write_wait_count <= 8'd0;
                            write_state <= W_WAIT;
                        end else begin
                            write_state <= W_RESP;
                        end
                    end else begin
                        write_wait_count <= write_wait_count + 8'd1;
                    end
                end

                W_RESP: if (b_fire) write_state <= W_IDLE;
                default: write_state <= W_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
