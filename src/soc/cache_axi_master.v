`default_nettype none

// Performance-oriented cache hierarchy with a single AXI4 master.
// I-cache: 4 KiB direct mapped plus a 128-byte, eight-line L0 loop buffer.
//          Hot sequential/loop code is served at one instruction/cycle;
//          the backing array uses synchronous/block-RAM-friendly reads.
// D-cache: 64 KiB, 2-way set associative, 16-byte lines and pseudo-LRU.
//          Cache hits are write-back; store misses remain no-write-allocate.
//          Tags and data use synchronous block RAM lookup paths.
module cache_axi_master (
    input  wire        clk,
    input  wire        reset,

    input  wire        inst_req,
    input  wire [31:0] inst_addr,
    output wire        inst_addr_ok,
    output wire        inst_data_ok,
    output wire [31:0] inst_rdata,
    output wire [31:0] inst_rdata1,
    output wire        inst_rdata1_valid,
    input  wire        inst_resp_ready,

    input  wire        data_req,
    input  wire        data_prefetch_hint,
    input  wire [ 3:0] data_we,
    input  wire [31:0] data_addr,
    input  wire [31:0] data_pc,
    input  wire [ 2:0] data_size,
    input  wire [31:0] data_wdata,
    output wire        data_addr_ok,
    output wire        data_data_ok,
    output wire [31:0] data_rdata,
    output wire        data_id_forward_ok,
    output wire [31:0] data_id_forward_data,

    input  wire        cacheop_valid,
    input  wire [ 4:0] cacheop_code,
    input  wire [31:0] cacheop_addr,
    output wire        cacheop_ready,

    // CRMD.PG: bypass caches in direct-address mode.
    input  wire        cache_enable,
    output wire [ 3:0] m_arid,
    output wire [31:0] m_araddr,
    output wire [ 7:0] m_arlen,
    output wire [ 2:0] m_arsize,
    output wire [ 1:0] m_arburst,
    output wire        m_arvalid,
    input  wire        m_arready,

    input  wire [ 3:0] m_rid,
    input  wire [31:0] m_rdata,
    input  wire [ 1:0] m_rresp,
    input  wire        m_rlast,
    input  wire        m_rvalid,
    output wire        m_rready,

    output wire [ 3:0] m_awid,
    output wire [31:0] m_awaddr,
    output wire [ 7:0] m_awlen,
    output wire [ 2:0] m_awsize,
    output wire [ 1:0] m_awburst,
    output wire        m_awvalid,
    input  wire        m_awready,

    output wire [31:0] m_wdata,
    output wire [ 3:0] m_wstrb,
    output wire        m_wlast,
    output wire        m_wvalid,
    input  wire        m_wready,

    input  wire [ 3:0] m_bid,
    input  wire [ 1:0] m_bresp,
    input  wire        m_bvalid,
    output wire        m_bready
);

    localparam S_IDLE   = 4'd0;
    localparam S_RADDR  = 4'd1;
    localparam S_RDATA  = 4'd2;
    localparam S_IRESP  = 4'd3;
    localparam S_DRESP  = 4'd4;
    localparam S_WSEND  = 4'd5;
    localparam S_WRESP  = 4'd6;
    localparam S_DLOOKUP = 4'd7;
    localparam S_ILOOKUP = 4'd8;
    localparam S_WB_PREP = 4'd9;
    localparam S_WB_ADDR = 4'd10;
    localparam S_WB_DATA = 4'd11;
    localparam S_WB_RESP = 4'd12;
    localparam S_DTAG    = 4'd13;
    localparam S_ICINV   = 4'd14;
    localparam S_DCSTART = 4'd15;

    reg [3:0] state;
    reg       read_owner_data;
    reg       read_refill;
    reg [31:0] req_vaddr;
    reg [31:0] req_paddr;
    reg [31:0] req_pc;
    reg [ 1:0] req_word;
    reg [10:0] req_index;
    reg [19:0] req_tag;
    reg        req_replace_way;
    reg        req_hit_way;
    reg [ 2:0] refill_beat;
    reg [127:0] refill_line;
    reg        refill_data_responded;
    reg        refill_response_pending;
    reg        early_word_active;
    reg        early_word_ar_accepted;
    reg        early_word_data_valid;
    reg        early_word_eligible;
    reg        early_word_retire_pending;
    reg [31:0] early_word_addr;
    reg [31:0] early_word_data;
    reg        refill_load_probe_pending;
    reg        refill_load_probe_same_line;
    reg [ 1:0] refill_load_probe_word;
    reg [31:0] refill_load_probe_forward_data;
    reg [ 3:0] refill_load_probe_forward_mask;
    reg        overlap_store_pending;
    reg        overlap_store_addr_acked;
    reg [31:0] overlap_store_paddr;
    reg [10:0] overlap_store_index;
    reg [16:0] overlap_store_tag;
    reg [ 1:0] overlap_store_word;
    reg [ 3:0] overlap_store_we;
    reg [31:0] overlap_store_wdata;
    reg        overlap_store_ic_conflict;
    reg [31:0] read_addr_r;
    reg [ 7:0] read_len_r;
    reg [ 3:0] ar_id_hold;
    reg [31:0] ar_addr_hold;
    reg [ 7:0] ar_len_hold;
    reg [31:0] response_data;
    reg [31:0] req_forward_data;
    reg [ 3:0] req_forward_mask;
    reg [ 3:0] req_we;
    reg [ 2:0] req_size;
    reg [31:0] req_wdata;
    reg        req_store;
    reg        req_ic_store_conflict;
    reg        req_cacheop;
    reg [ 4:0] req_cacheop_code;
    reg        req_cacheop_way;
    reg [ 7:0] req_icache_index;
    reg        inst_resp_valid;
    reg [31:0] inst_response_data;
    reg [31:0] inst_response_data1;
    reg        inst_response_data1_valid;
    reg        ic_sync_pending;

    reg [31:0] wb_addr;
    reg [127:0] wb_line;
    reg [1:0] wb_beat;
    reg wb_for_refill;
    reg wb_way;

    reg [31:0] write_addr_r;
    reg [31:0] write_data_r;
    reg [ 3:0] write_strb_r;
    reg        aw_done;
    reg        w_done;

    // Four-entry write-through store buffer.  Stores retire when enqueued;
    // AXI completion proceeds in the background.  Loads and cache maintenance
    // wait for the buffer to drain, preserving simple in-order memory semantics.
    reg [31:0] sb_addr [0:3];
    reg [31:0] sb_data [0:3];
    reg [ 3:0] sb_strb [0:3];
    reg [ 1:0] sb_wr_ptr;
    reg [ 1:0] sb_rd_ptr;
    reg [ 2:0] sb_count;

    // Per-load-PC locality predictor.  Low-confidence word loads bypass
    // line allocation so random accesses do not fetch three unused words.
    reg [63:0] lp_valid;
    (* ram_style = "distributed" *) reg [44:0] lp_table [0:63];

    reg        ic_valid [0:255];
    reg        ic_seen  [0:255];
    reg [19:0] ic_tag   [0:255];
    reg        ic_buffer_valid [0:7];
    reg [27:0] ic_buffer_line_addr [0:7];
    reg [127:0] ic_buffer_data [0:7];

    // D-cache metadata is kept in one synchronous block RAM.  Keeping tag,
    // valid, dirty and replacement state together avoids five independent
    // 2048:1 asynchronous mux/decode networks.
    reg        dc_init_busy;
    reg [10:0] dc_init_index;

    wire [127:0] ic_ram_rline;
    wire [31:0]  dc_ram0_rdata;
    wire [31:0]  dc_ram1_rdata;
    wire [127:0] dc_ram0_rline;
    wire [127:0] dc_ram1_rline;
    wire [38:0] dc_meta_q;

    integer i;

    function [31:0] translate_addr;
        input [31:0] va;
        begin
            // Supervisor DMW1 maps 0xa0000000-0xbfffffff to low 512 MiB.
            translate_addr = (va[31:29] == 3'b101) ? {3'b000, va[28:0]} : va;
        end
    endfunction

    function is_cacheable;
        input [31:0] pa;
        begin
            is_cacheable = cache_enable &&
                           (pa >= 32'h1c00_0000) && (pa < 32'h1c80_0000);
        end
    endfunction

    function [31:0] merge_bytes;
        input [31:0] old_word;
        input [31:0] new_word;
        input [ 3:0] strb;
        begin
            merge_bytes = old_word;
            if (strb[0]) merge_bytes[ 7: 0] = new_word[ 7: 0];
            if (strb[1]) merge_bytes[15: 8] = new_word[15: 8];
            if (strb[2]) merge_bytes[23:16] = new_word[23:16];
            if (strb[3]) merge_bytes[31:24] = new_word[31:24];
        end
    endfunction

    function [31:0] line_word;
        input [127:0] line;
        input [1:0] word;
        begin
            case (word)
                2'd0: line_word = line[31:0];
                2'd1: line_word = line[63:32];
                2'd2: line_word = line[95:64];
                default: line_word = line[127:96];
            endcase
        end
    endfunction

    function [31:0] apply_forward;
        input [31:0] base_word;
        input [31:0] forward_word;
        input [ 3:0] forward_mask;
        begin
            apply_forward = base_word;
            if (forward_mask[0]) apply_forward[7:0]   = forward_word[7:0];
            if (forward_mask[1]) apply_forward[15:8]  = forward_word[15:8];
            if (forward_mask[2]) apply_forward[23:16] = forward_word[23:16];
            if (forward_mask[3]) apply_forward[31:24] = forward_word[31:24];
        end
    endfunction

    // Fold low tag bits into three positions of the set number.  This is a
    // bijective permutation for each tag and therefore preserves capacity and
    // coherence, while dispersing power-of-two-strided arrays that otherwise
    // collide in the conventional 64 KiB, two-way organization.
    function [10:0] dc_hash_fold;
        input [7:0] tag_low;
        reg [10:0] extended_tag;
        begin
            extended_tag = {3'b000, tag_low};
            dc_hash_fold = (extended_tag << 1) ^
                           (extended_tag << 4) ^
                           (extended_tag << 8);
        end
    endfunction

    function [10:0] dc_hash_index;
        input [31:0] pa;
        begin
            dc_hash_index = pa[14:4] ^ dc_hash_fold(pa[22:15]);
        end
    endfunction

    function [10:0] dc_unhash_index;
        input [10:0] hashed_index;
        input [16:0] tag;
        begin
            dc_unhash_index = hashed_index ^ dc_hash_fold(tag[7:0]);
        end
    endfunction

    wire [31:0] inst_pa = translate_addr(inst_addr);
    wire [31:0] data_pa = translate_addr(data_addr);
    wire [ 7:0] inst_idx = inst_pa[11:4];
    wire [10:0] data_idx = dc_hash_index(data_pa);
    wire [19:0] inst_tag_now = inst_pa[31:12];
    wire [16:0] data_tag_now = data_pa[31:15];
    wire [10:0] cacheop_idx = cacheop_addr[14:4];
    wire inst_hit = is_cacheable(inst_pa) && ic_valid[inst_idx] &&
                    (ic_tag[inst_idx] == inst_tag_now);
    wire lookup_cacheable = is_cacheable(req_paddr);
    wire [16:0] dc_tag0_q   = dc_meta_q[16:0];
    wire        dc_dirty0_q = dc_meta_q[17];
    wire        dc_valid0_q = dc_meta_q[18];
    wire [16:0] dc_tag1_q   = dc_meta_q[35:19];
    wire        dc_dirty1_q = dc_meta_q[36];
    wire        dc_valid1_q = dc_meta_q[37];
    wire        dc_lru_q    = dc_meta_q[38];
    // The cacheable data window is 0x1c000000..0x1c7fffff, so address bits
    // [31:23] are constant whenever lookup_cacheable is true.  Comparing only
    // tag bits [22:15] is therefore equivalent to the original 17-bit compare,
    // while removing a carry-comparator level from the BRAM-to-hit path.
    wire data_hit0 = lookup_cacheable && dc_valid0_q &&
                     (dc_tag0_q[7:0] == req_tag[7:0]);
    wire data_hit1 = lookup_cacheable && dc_valid1_q &&
                     (dc_tag1_q[7:0] == req_tag[7:0]);
    wire data_hit = data_hit0 || data_hit1;
    wire overlap_store_raw_hit0 = dc_valid0_q &&
                                  (dc_tag0_q[7:0] == overlap_store_tag[7:0]);
    wire overlap_store_raw_hit1 = dc_valid1_q &&
                                  (dc_tag1_q[7:0] == overlap_store_tag[7:0]);
    // Until RLAST, metadata still describes the line selected as the refill
    // victim.  A store matching that old line must be treated as a miss or it
    // would be overwritten when the new line is installed.
    wire overlap_store_victim0 = (overlap_store_index == req_index) &&
                                 !req_replace_way;
    wire overlap_store_victim1 = (overlap_store_index == req_index) &&
                                  req_replace_way;
    wire overlap_store_hit0 = overlap_store_raw_hit0 &&
                              !overlap_store_victim0;
    wire overlap_store_hit1 = overlap_store_raw_hit1 &&
                              !overlap_store_victim1;
    wire overlap_store_hit = overlap_store_hit0 || overlap_store_hit1;
    wire victim_way_now = !dc_valid0_q ? 1'b0 :
                          !dc_valid1_q ? 1'b1 : dc_lru_q;
    wire victim_dirty_now = victim_way_now ?
                            (dc_valid1_q && dc_dirty1_q) :
                            (dc_valid0_q && dc_dirty0_q);
    wire [2:0] inst_buffer_index = inst_pa[6:4];
    wire inst_buffer_hit = is_cacheable(inst_pa) &&
                           ic_buffer_valid[inst_buffer_index] &&
                           (ic_buffer_line_addr[inst_buffer_index] == inst_pa[31:4]);
    wire [31:0] inst_buffer_word =
        line_word(ic_buffer_data[inst_buffer_index], inst_pa[3:2]);
    // The line buffer already holds 128 bits.  Export the adjacent word at no
    // additional memory-port cost when PC+4 remains in the same cache line.
    wire inst_buffer_word1_valid = inst_buffer_hit & (inst_pa[3:2] != 2'd3);
    wire [31:0] inst_buffer_word1 =
        line_word(ic_buffer_data[inst_buffer_index], inst_pa[3:2] + 2'd1);

    // Assemble an AXI refill in a register first, then commit the complete
    // 128-bit line to the backing RAM on RLAST.  A single full-width write is
    // substantially easier for Vivado to map to BRAM than four independent
    // asynchronous word arrays.
    reg [127:0] refill_line_next;
    always @(*) begin
        refill_line_next = refill_line;
        case (refill_beat[1:0])
            2'd0: refill_line_next[31:0]   = m_rdata;
            2'd1: refill_line_next[63:32]  = m_rdata;
            2'd2: refill_line_next[95:64]  = m_rdata;
            2'd3: refill_line_next[127:96] = m_rdata;
        endcase
    end

    // The refill accumulator is written only by registered AXI refill beats.
    // Every cache-line transaction returns all four words, so clearing this
    // register when a new request is decoded is unnecessary: a word is never
    // consumed before its corresponding beat has overwritten the old value.
    // Keeping this register in a dedicated process prevents the EXE request
    // and cache-control priority tree from being folded into the 128-bit
    // register-enable network, which is important for a future faster CPU
    // clock without changing refill latency or behavior.
    always @(posedge clk) begin
        if (reset)
            refill_line <= 128'd0;
        else if ((state == S_RDATA) && m_rvalid && m_rready &&
                 (m_rid != 4'd2) && read_refill)
            refill_line <= refill_line_next;
    end

    // Cache hits are completed directly from the lookup path.  Keeping hits
    // out of the miss FSM removes the former IDLE->RESP->IDLE bubble and lets
    // the I-cache deliver one instruction on every cycle while the pipeline
    // can accept it.
    wire store_req = data_req && (data_we != 4'b0000);
    wire load_req  = data_req && (data_we == 4'b0000);
    wire ic_store_conflict = is_cacheable(data_pa) &&
        ((ic_seen[data_pa[11:4]] &&
          (ic_tag[data_pa[11:4]] == data_pa[31:12])) ||
         (ic_buffer_valid[data_pa[6:4]] &&
          (ic_buffer_line_addr[data_pa[6:4]] == data_pa[31:4])));

    // Search the ordered store queue from oldest to youngest.  Later matches
    // overwrite earlier bytes, so the snapshot represents the architecturally
    // newest value for every byte of the requested word.
    reg [31:0] sb_forward_data;
    reg [ 3:0] sb_forward_mask;
    reg [ 1:0] sb_scan_index;
    integer sb_scan;
    always @(*) begin
        sb_forward_data = 32'd0;
        sb_forward_mask = 4'd0;
        sb_scan_index = 2'd0;
        for (sb_scan = 0; sb_scan < 4; sb_scan = sb_scan + 1) begin
            sb_scan_index = sb_rd_ptr + sb_scan[1:0];
            if ((sb_scan < sb_count) &&
                (sb_addr[sb_scan_index][31:2] == data_pa[31:2])) begin
                if (sb_strb[sb_scan_index][0]) begin
                    sb_forward_data[7:0] = sb_data[sb_scan_index][7:0];
                    sb_forward_mask[0] = 1'b1;
                end
                if (sb_strb[sb_scan_index][1]) begin
                    sb_forward_data[15:8] = sb_data[sb_scan_index][15:8];
                    sb_forward_mask[1] = 1'b1;
                end
                if (sb_strb[sb_scan_index][2]) begin
                    sb_forward_data[23:16] = sb_data[sb_scan_index][23:16];
                    sb_forward_mask[2] = 1'b1;
                end
                if (sb_strb[sb_scan_index][3]) begin
                    sb_forward_data[31:24] = sb_data[sb_scan_index][31:24];
                    sb_forward_mask[3] = 1'b1;
                end
            end
        end
    end
    // The store queue is independent of the read-miss FSM.  Accepting an
    // older store while an instruction response waits for ID prevents a
    // pipeline/cache circular wait.
    // Remember lines that have been fetched as instructions.  A program
    // upload commonly modifies several words after the first word has already
    // invalidated the I-cache; every later D-cache hit to that remembered line
    // must still write through so instruction refill cannot observe stale
    // external SRAM contents.
    wire store_force_through = req_ic_store_conflict;
    wire store_needs_buffer = req_store &&
                              (!data_hit || store_force_through);
    wire store_accept = (state == S_DTAG) && !req_cacheop && req_store &&
                        ((data_hit && !store_force_through) ||
                         (sb_count < 3'd4));
    wire store_enqueue = store_accept && store_needs_buffer;
    // Once a data refill has returned its critical word, permit a following
    // store to look up the D-cache while the remaining beats arrive, but only
    // when it targets the other physical SRAM chip.  The store has its own
    // request registers so the refill context remains untouched.
    // refill_data_responded is set only for a data-owned line refill and both
    // qualifiers remain stable throughout S_RDATA.  Avoid rechecking those
    // high-fanout state bits in the overlap launch timing cone.
    // Preselecting the live Store operands is side-effect free.  Every real
    // overlap launch implies this condition, while a false preselect only
    // changes otherwise-unused holding registers and read-only RAM addresses.
    // This keeps hit/allow feedback and Store-buffer availability out of the
    // metadata-to-data-RAM address path without adding a handshake cycle.
    wire overlap_store_preselect = (state == S_RDATA) &&
        refill_data_responded && !overlap_store_pending &&
        (data_we != 4'b0000);
    wire overlap_store_launch = (state == S_RDATA) &&
        refill_data_responded &&
        !overlap_store_pending && data_req && store_req &&
        is_cacheable(data_pa) && (data_pa[22] != read_addr_r[22]) &&
        (sb_count < 3'd4);
    wire overlap_store_needs_buffer =
        !overlap_store_hit || overlap_store_ic_conflict;
    wire dc_tag_write = (state == S_RDATA) && m_rvalid &&
                        (m_rid != 4'd2) && m_rlast && read_refill &&
                        read_owner_data;
    wire overlap_store_cache_port_free =
        !((state == S_RDATA) && m_rvalid && read_refill && read_owner_data) &&
        !dc_tag_write;
    // Register the request first, acknowledge its EXE address phase one cycle
    // later, then complete it only after the store has entered MEM.  This
    // preserves the two-phase CPU memory handshake without feeding the live
    // EXE request back through data_addr_ok.
    wire overlap_store_addr_accept = overlap_store_pending &&
                                     !overlap_store_addr_acked;
    wire overlap_store_accept = overlap_store_pending &&
        overlap_store_addr_acked &&
        (!overlap_store_hit || overlap_store_cache_port_free) &&
        (!overlap_store_needs_buffer || (sb_count < 3'd4));
    wire overlap_store_enqueue = overlap_store_accept &&
                                 overlap_store_needs_buffer;
    wire any_store_enqueue = store_enqueue || overlap_store_enqueue;
    // Probe a younger load without accepting it.  Registering the line
    // comparison keeps the EXE address out of the data_addr_ok/allow chain;
    // the core holds the request stable until probe_ready acknowledges it.
    wire refill_load_probe_launch =
        (state == S_RDATA) && read_refill && read_owner_data &&
        refill_data_responded && !refill_load_probe_pending &&
        data_req && load_req && is_cacheable(data_pa);
    wire refill_load_probe_ready =
        refill_load_probe_pending && refill_load_probe_same_line &&
        (refill_load_probe_word < refill_beat[1:0]);
    wire [31:0] refill_load_probe_data =
        line_word(refill_line, refill_load_probe_word);
    // A dirty replacement needs exclusive use of the write channel.  Hits,
    // clean misses and fully-forwarded reads may pass pending store traffic.
    wire [5:0] lp_index_now = req_pc[7:2];
    wire [44:0] lp_entry_now = lp_table[lp_index_now];
    wire [23:0] lp_tag_now = lp_entry_now[44:21];
    wire [18:0] lp_last_line_now = lp_entry_now[20:2];
    wire [ 1:0] lp_conf_now = lp_entry_now[1:0];
    wire lp_hit_now = lp_valid[lp_index_now] &&
                      (lp_tag_now == req_pc[31:8]);
    wire lp_word_mode_now = lp_hit_now && (lp_conf_now < 2'd2) &&
                            (req_size == 3'd2);
    wire lp_line_refill_now = lookup_cacheable && !lp_word_mode_now;
    wire lp_local_now = (lp_last_line_now == req_paddr[22:4]) ||
                        (lp_last_line_now + 19'd1 == req_paddr[22:4]);
    wire load_tag_active = (state == S_DTAG) && !req_cacheop && !req_store;
    // A hit never depends on replacement or store-buffer availability.  Keep
    // it as a dedicated term so the BRAM tag compare reaches data_data_ok
    // directly instead of traversing the generic miss-accept priority cone.
    wire load_hit_accept = load_tag_active && data_hit;
    wire load_miss_accept = load_tag_active && !data_hit &&
                            (!lookup_cacheable || lp_word_mode_now ||
                             !victim_dirty_now || (sb_count == 3'd0));
    wire load_accept = load_hit_accept || load_miss_accept;
    wire lp_update = load_accept && !data_hit && lookup_cacheable;
    wire [1:0] lp_next_conf = !lp_hit_now ? 2'd2 :
        (lp_local_now ? ((lp_conf_now == 2'd3) ? 2'd3 : lp_conf_now + 2'd1) :
                        ((lp_conf_now == 2'd0) ? 2'd0 : lp_conf_now - 2'd1));

    // Predictor-selected random word reads may start beside the synchronous
    // tag lookup.  Eligibility belongs to exactly one CPU lookup and is
    // revoked by any later lookup, so a delayed response cannot become valid
    // again through a wrapping sequence number.
    wire [5:0] lp_live_index = data_pc[7:2];
    wire [44:0] lp_live_entry = lp_table[lp_live_index];
    wire lp_live_word_mode = lp_valid[lp_live_index] &&
        (lp_live_entry[44:21] == data_pc[31:8]) &&
        (lp_live_entry[1:0] < 2'd2) && (data_size == 3'd2);
    wire early_word_launch = (state == S_IDLE) && !dc_init_busy &&
        data_prefetch_hint && is_cacheable(data_pa) && lp_live_word_mode &&
        !early_word_active;

    always @(posedge clk) begin
        if (reset) begin
            lp_valid <= 64'd0;
        end else if (lp_update) begin
            lp_valid[lp_index_now] <= 1'b1;
            lp_table[lp_index_now] <= {req_pc[31:8], req_paddr[22:4],
                                       lp_next_conf};
        end
    end

    // After a registered load, expose the next synchronous lookup slot without
    // feeding the current tag comparison back into addr_ok.  The core only
    // asserts data_req when MEM can advance, so a miss naturally suppresses
    // this path while a hit chains the next request at full throughput.
    wire data_lookup_ready = !dc_init_busy && !overlap_store_pending &&
                             ((state == S_IDLE) ||
                              ((state == S_DTAG) && !req_cacheop &&
                               !req_store));
    wire data_lookup_launch = data_req && data_lookup_ready;
    wire [10:0] dc_lookup_set = overlap_store_pending ? overlap_store_index :
                                (overlap_store_preselect ? data_idx :
                                 (data_lookup_launch ? data_idx : req_index));
    wire [10:0] dc_ram_rd_set = dc_lookup_set;
    wire [1:0] dc_ram_rd_word = overlap_store_pending ? overlap_store_word :
                                ((overlap_store_preselect ||
                                  data_lookup_launch) ?
                                 data_pa[3:2] : req_word);

    // The data arrays are explicit synchronous byte-write RAMs.  A refill
    // writes one 32-bit bank per AXI beat; a store hit uses the same port with
    // byte enables.  These cases are mutually exclusive by store_accept.
    wire dc_refill_write = (state == S_RDATA) && m_rvalid &&
                           (m_rid != 4'd2) && read_refill && read_owner_data;
    wire overlap_store_cache_write = overlap_store_accept && overlap_store_hit;
    wire dc_store_write0 = (store_accept && data_hit0) ||
                           (overlap_store_cache_write && overlap_store_hit0);
    wire dc_store_write1 = (store_accept && data_hit1) ||
                           (overlap_store_cache_write && overlap_store_hit1);
    wire dc_ram0_we = dc_store_write0 || (dc_refill_write && !req_replace_way);
    wire dc_ram1_we = dc_store_write1 || (dc_refill_write &&  req_replace_way);
    wire [10:0] dc_ram_wr_set = overlap_store_cache_write ?
                                overlap_store_index : req_index;
    wire [1:0] dc_ram_wr_word = dc_refill_write ? refill_beat[1:0] :
                                (overlap_store_cache_write ?
                                 overlap_store_word : req_word);
    wire [31:0] dc_ram_wr_data = dc_refill_write ? m_rdata :
                                 (overlap_store_cache_write ?
                                  overlap_store_wdata : req_wdata);
    wire [3:0] dc_ram_wr_strb = dc_refill_write ? 4'b1111 :
                               (overlap_store_cache_write ?
                                overlap_store_we : req_we);

    // Tags and the five frequently updated status bits use independent BRAM
    // write enables.  The old packed 39-bit read/modify/write path fed tag
    // comparisons through the complete metadata priority mux and back into a
    // BRAM input in one cycle.  Keeping tags unchanged unless a refill installs
    // a line removes that loop without changing lookup or hit latency.
    // Status layout: {lru, valid1, dirty1, valid0, dirty0}.
    reg        dc_meta_tag0_we;
    reg        dc_meta_tag1_we;
    reg        dc_meta_status_we;
    reg [10:0] dc_meta_wr_set;
    reg [16:0] dc_meta_wr_tag0;
    reg [16:0] dc_meta_wr_tag1;
    reg [ 4:0] dc_meta_wr_status;
    always @(*) begin
        dc_meta_tag0_we   = 1'b0;
        dc_meta_tag1_we   = 1'b0;
        dc_meta_status_we = 1'b0;
        dc_meta_wr_set    = req_index;
        // Tag data is don't-care unless the matching refill write enable is
        // asserted; drive it from the registered refill tag unconditionally
        // so no tag-RAM output feeds back to a tag-RAM input.
        dc_meta_wr_tag0   = req_tag[16:0];
        dc_meta_wr_tag1   = req_tag[16:0];
        dc_meta_wr_status = {dc_lru_q, dc_valid1_q, dc_dirty1_q,
                             dc_valid0_q, dc_dirty0_q};

        if (dc_init_busy) begin
            // Invalid status makes stale power-up tags unobservable, so reset
            // only the compact status RAM rather than rewriting both tags.
            dc_meta_status_we = 1'b1;
            dc_meta_wr_set    = dc_init_index;
            dc_meta_wr_status = 5'd0;
        end else if (store_accept && data_hit) begin
            dc_meta_status_we = 1'b1;
            if (data_hit0) begin
                dc_meta_wr_status[0] = 1'b1;
                dc_meta_wr_status[4] = 1'b1;
            end else begin
                dc_meta_wr_status[2] = 1'b1;
                dc_meta_wr_status[4] = 1'b0;
            end
        end else if (overlap_store_cache_write) begin
            dc_meta_status_we = 1'b1;
            dc_meta_wr_set    = overlap_store_index;
            if (overlap_store_hit0) begin
                dc_meta_wr_status[0] = 1'b1;
                dc_meta_wr_status[4] = 1'b1;
            end else begin
                dc_meta_wr_status[2] = 1'b1;
                dc_meta_wr_status[4] = 1'b0;
            end
        end else if (load_hit_accept) begin
            dc_meta_status_we = 1'b1;
            dc_meta_wr_status[4] = data_hit0 ? 1'b1 : 1'b0;
        end else if ((state == S_DTAG) && req_cacheop &&
                     (req_cacheop_code == 5'h01)) begin
            dc_meta_status_we = 1'b1;
            if (!req_cacheop_way) begin
                dc_meta_wr_status[1:0] = 2'b00;
            end else begin
                dc_meta_wr_status[3:2] = 2'b00;
            end
        end else if ((state == S_DTAG) && req_cacheop &&
                     (req_cacheop_code == 5'h09) &&
                     !(req_cacheop_way ? (dc_valid1_q && dc_dirty1_q) :
                                         (dc_valid0_q && dc_dirty0_q))) begin
            dc_meta_status_we = 1'b1;
            if (!req_cacheop_way) begin
                dc_meta_wr_status[1:0] = 2'b00;
            end else begin
                dc_meta_wr_status[3:2] = 2'b00;
            end
        end else if (dc_tag_write) begin
            dc_meta_status_we = 1'b1;
            if (!req_replace_way) begin
                dc_meta_tag0_we       = 1'b1;
                dc_meta_wr_tag0       = req_tag[16:0];
                dc_meta_wr_status[1:0] = 2'b10;
                dc_meta_wr_status[4]   = 1'b1;
            end else begin
                dc_meta_tag1_we       = 1'b1;
                dc_meta_wr_tag1       = req_tag[16:0];
                dc_meta_wr_status[3:2] = 2'b10;
                dc_meta_wr_status[4]   = 1'b0;
            end
        end else if ((state == S_WB_RESP) && m_bvalid && m_bready) begin
            dc_meta_status_we = 1'b1;
            if (!wb_way) begin
                dc_meta_wr_status[0] = 1'b0;
                if (!wb_for_refill)
                    dc_meta_wr_status[1] = 1'b0;
            end else begin
                dc_meta_wr_status[2] = 1'b0;
                if (!wb_for_refill)
                    dc_meta_wr_status[3] = 1'b0;
            end
        end
    end

    wire ic_ram_we = (state == S_RDATA) && m_rvalid &&
                     (m_rid != 4'd2) && m_rlast && read_refill &&
                     !read_owner_data;

    cache_line_ram_256x128 ic_data_ram (
        .clk(clk),
        .rd_set(inst_idx),
        .rd_line(ic_ram_rline),
        .wr_en(ic_ram_we),
        .wr_set(req_index[7:0]),
        .wr_line(refill_line_next)
    );

    cache_meta_ram_2048x39 dc_meta_ram (
        .clk(clk),
        .rd_set(dc_lookup_set),
        .rd_meta(dc_meta_q),
        .wr_set(dc_meta_wr_set),
        .wr_tag0_en(dc_meta_tag0_we),
        .wr_tag0(dc_meta_wr_tag0),
        .wr_tag1_en(dc_meta_tag1_we),
        .wr_tag1(dc_meta_wr_tag1),
        .wr_status_en(dc_meta_status_we),
        .wr_status(dc_meta_wr_status)
    );

    cache_word_ram_2048x32 dc_way0_ram (
        .clk(clk),
        .rd_set(dc_ram_rd_set),
        .rd_word(dc_ram_rd_word),
        .rd_data(dc_ram0_rdata),
        .rd_line(dc_ram0_rline),
        .wr_en(dc_ram0_we),
        .wr_set(dc_ram_wr_set),
        .wr_word(dc_ram_wr_word),
        .wr_data(dc_ram_wr_data),
        .wr_strb(dc_ram_wr_strb)
    );

    cache_word_ram_2048x32 dc_way1_ram (
        .clk(clk),
        .rd_set(dc_ram_rd_set),
        .rd_word(dc_ram_rd_word),
        .rd_data(dc_ram1_rdata),
        .rd_line(dc_ram1_rline),
        .wr_en(dc_ram1_we),
        .wr_set(dc_ram_wr_set),
        .wr_word(dc_ram_wr_word),
        .wr_data(dc_ram_wr_data),
        .wr_strb(dc_ram_wr_strb)
    );

    // The L0 instruction buffer is a register array independent of the D-cache
    // BRAMs and AXI write channel.  Serve it while data lookup/refill proceeds,
    // except when an in-flight store may modify that exact instruction line.
    wire inst_path_busy = (((state == S_RADDR) || (state == S_RDATA)) &&
                           !read_owner_data) || (state == S_ILOOKUP);
    // Once the request is registered, suppress any younger fetch from a line
    // that the store may modify.  Avoid feeding the EXE address comparison
    // back into IF in the launch cycle; that path spans ALU, cache decode and
    // the complete front-end allow chain and cannot close at 100 MHz.
    wire current_store_ic_conflict =
        (state == S_DTAG) && req_store && req_ic_store_conflict;
    wire inst_hit_fast = !dc_init_busy && !inst_resp_valid && inst_req &&
                         !cacheop_valid && !ic_sync_pending &&
                         !inst_path_busy && !current_store_ic_conflict &&
                         inst_buffer_hit;

    assign cacheop_ready = (state == S_IDLE) && !dc_init_busy &&
                           (sb_count == 3'd0) &&
                           !aw_done && !w_done && !data_req &&
                           !overlap_store_pending;
    // Accept the request when its synchronous tag/data lookup is launched.
    // Miss handling may continue internally, but the CPU no longer pays an
    // unnecessary extra address-handshake cycle on every cache hit.
    assign data_addr_ok   = data_lookup_ready || overlap_store_addr_accept ||
                             refill_load_probe_ready;
    assign inst_addr_ok   = inst_hit_fast ||
                            ((state == S_IDLE) && !dc_init_busy &&
                             !inst_resp_valid && inst_req && !data_req &&
                             !cacheop_valid && !ic_sync_pending);
    assign inst_data_ok   = inst_hit_fast || inst_resp_valid;
    // A synchronous D-cache lookup is launched in S_IDLE and completes in
    // S_DTAG.  Hits acknowledge in that cycle; S_DRESP is reserved for AXI
    // responses.  This avoids adding a global cycle to every Load/Store hit.
    // early_word_eligible is the registered token for exactly one D-cache
    // lookup.  Both early_word_addr and req_paddr are captured from data_pa on
    // that lookup edge, and any later lookup clears/replaces the token before
    // it can enter S_RADDR.  Re-comparing the two registered 32-bit addresses
    // here was therefore redundant and put three CARRY4 levels on the live
    // data-response -> MEM_allow path.
    wire early_request_match = early_word_eligible;
    wire early_wait_match = (state == S_RADDR) && read_owner_data &&
                            !read_refill && early_request_match &&
                            (early_word_active || early_word_data_valid);
    wire early_live_response = early_wait_match && early_word_active &&
                               early_word_ar_accepted && m_rvalid &&
                               (m_rid == 4'd2) && m_rlast;
    wire early_buffer_response = early_wait_match && early_word_data_valid;
    wire early_response_now = early_live_response || early_buffer_response;
`ifndef SYNTHESIS
    // Guard the token invariant in every simulation that exercises the cache.
    always @(posedge clk) begin
        if (!reset && early_wait_match && (early_word_addr != read_addr_r)) begin
            $display("FAIL early-word token address mismatch early=%h read=%h",
                     early_word_addr, read_addr_r);
            $fatal(1);
        end
    end
`endif
    // The bridge permits only one read transaction.  A non-refill data-owned
    // response with a non-speculative RID can therefore only belong to the
    // normal request already advanced from S_RADDR into S_RDATA.  Rechecking
    // the FSM state here was redundant and put state decode on the complete
    // response -> MEM wakeup -> ID/EXE forwarding path.
    wire normal_word_response_now = read_owner_data && !read_refill &&
                                    m_rvalid && (m_rid != 4'd2) && m_rlast;
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (!reset && normal_word_response_now && (state != S_RDATA)) begin
            $display("FAIL normal word response outside S_RDATA state=%0d",
                     state);
            $fatal(1);
        end
    end
`endif
    wire word_response_now = normal_word_response_now || early_response_now;
    wire [31:0] word_response_data = early_buffer_response ?
                                     early_word_data : m_rdata;
    // Registered/AXI responses may bypass to ID. A synchronous D-cache hit
    // waits for WB, keeping the metadata BRAM out of the ID operand path.
    assign data_id_forward_ok = refill_response_pending ||
                                refill_load_probe_ready ||
                                word_response_now || (state == S_DRESP);
    // This bus is used only when data_id_forward_ok is asserted.  List every
    // valid case explicitly so the synchronous D-tag/data hit path cannot
    // reach the ID operand mux.  A refill probe is a same-cycle value from the
    // partially assembled line; response_data is updated only at the edge.
    assign data_id_forward_data = word_response_now ?
                                  apply_forward(word_response_data,
                                                req_forward_data,
                                                req_forward_mask) :
                                  refill_load_probe_ready ?
                                  apply_forward(refill_load_probe_data,
                                                refill_load_probe_forward_data,
                                                refill_load_probe_forward_mask) :
                                  response_data;
    assign data_data_ok   = store_accept ||
                            overlap_store_accept ||
                             load_hit_accept ||
                            refill_response_pending ||
                            word_response_now ||
                            (state == S_DRESP);
    // When a refill response is valid it owns the return bus; otherwise the
    // only cycle in which inst_data_ok can assert is the buffered hit path.
    // Selecting with inst_resp_valid is equivalent on every valid transfer,
    // and keeps cacheop_valid out of the instruction-data/next-PC path.
    assign inst_rdata     = inst_resp_valid ? inst_response_data : inst_buffer_word;
    assign inst_rdata1    = inst_resp_valid ? inst_response_data1 : inst_buffer_word1;
    assign inst_rdata1_valid = inst_resp_valid ? inst_response_data1_valid :
                               (inst_hit_fast & inst_buffer_word1_valid);
    assign data_rdata     = word_response_now ?
                            apply_forward(word_response_data,
                                          req_forward_data,
                                          req_forward_mask) :
                            (state == S_DTAG) ?
                            apply_forward(data_hit1 ? dc_ram1_rdata : dc_ram0_rdata,
                                          req_forward_data, req_forward_mask) :
                            response_data;

    // The hint comes only from registered EXE state and is independent of
    // MEM_allow_in/data_addr_ok.  It can therefore launch beside the D-tag
    // lookup without recreating the metadata -> core allow -> AR feedback
    // path that made the former live data_req launch fail timing.
    // Register the speculative word address before driving AXI.  Driving the
    // launch-cycle EXE address directly reached the asynchronous SRAM pins as
    // a 14-16 ns unconstrained combinational path and corrupted board reads.
    wire early_ar_select = early_word_active;
    wire early_ar_drive = early_ar_select && !early_word_ar_accepted;
    // Keep the private bridge at one read outstanding.  A stale ID2 drains
    // before any normal instruction/data address can be accepted.
    wire normal_ar_block = early_word_active || early_word_data_valid ||
                           early_word_retire_pending;
    // Keep the accepted transaction's address fields selected until its
    // response retires.  Only ARVALID is withdrawn after the handshake.  The
    // old don't-care switch back to the normal fields let
    // early_word_ar_accepted traverse the bridge device decoder and SRAM
    // address mux even though no second address could be accepted.
    // Capture the complete AR payload when a transaction is formed.  Driving
    // ARID/address/length from one register bank removes early_word_active
    // from the bridge device-decode and asynchronous SRAM address paths.
    assign m_arid    = ar_id_hold;
    assign m_araddr  = ar_addr_hold;
    assign m_arlen   = ar_len_hold;
    assign m_arsize  = 3'd2;
    assign m_arburst = 2'b01;
    assign m_arvalid = early_ar_drive ||
                       ((state == S_RADDR) && !normal_ar_block);
    assign m_rready  = (state == S_RDATA) || early_word_active;

    wire wb_mode = (state == S_WB_PREP) || (state == S_WB_ADDR) ||
                   (state == S_WB_DATA) || (state == S_WB_RESP);
    assign m_awid    = 4'd1;
    assign m_awaddr  = wb_mode ? wb_addr : sb_addr[sb_rd_ptr];
    assign m_awlen   = wb_mode ? 8'd3 : 8'd0;
    assign m_awsize  = wb_mode ? 3'd2 :
                       ((sb_strb[sb_rd_ptr] == 4'b1111) ? 3'd2 : 3'd0);
    assign m_awburst = 2'b01;
    assign m_awvalid = (state == S_WB_ADDR) ? 1'b1 :
                       (!wb_mode && (sb_count != 3'd0) && !aw_done);
    assign m_wdata   = wb_mode ? line_word(wb_line, wb_beat) : sb_data[sb_rd_ptr];
    assign m_wstrb   = wb_mode ? 4'b1111 : sb_strb[sb_rd_ptr];
    assign m_wlast   = wb_mode ? (wb_beat == 2'd3) : 1'b1;
    assign m_wvalid  = (state == S_WB_DATA) ? 1'b1 :
                       (!wb_mode && (sb_count != 3'd0) && !w_done);
    assign m_bready  = (state == S_WB_RESP) ? 1'b1 :
                       (!wb_mode && (sb_count != 3'd0) && aw_done && w_done);

    wire ar_fire = m_arvalid && m_arready;
    wire r_fire  = m_rvalid && m_rready;
    wire early_ar_fire = early_ar_drive && m_arready;
    wire early_r_fire = r_fire && (m_rid == 4'd2) && m_rlast;
    wire normal_ar_fire = (state == S_RADDR) && !normal_ar_block && m_arready;
    wire normal_r_fire = r_fire && (m_rid != 4'd2);
    wire aw_fire = m_awvalid && m_awready;
    wire w_fire  = m_wvalid && m_wready;
    wire b_fire  = m_bvalid && m_bready;
    wire sb_aw_fire = aw_fire && !wb_mode;
    wire sb_w_fire  = w_fire && !wb_mode;
    wire sb_b_fire  = b_fire && !wb_mode;

    wire normal_inst_read_capture = (state == S_IDLE) && !dc_init_busy &&
        !inst_resp_valid && inst_req && !data_req && !cacheop_valid &&
        !ic_sync_pending && !inst_buffer_hit && !inst_hit;
    wire normal_data_read_capture = (state == S_DTAG) && load_accept &&
                                    !data_hit;

    // An early request may temporarily block a younger normal read.  In that
    // case read_addr_r/read_len_r already retain the normal payload; transfer
    // it into the unified AR bank as the early response retires.
    always @(posedge clk) begin
        if (reset) begin
            ar_id_hold   <= 4'd0;
            ar_addr_hold <= 32'd0;
            ar_len_hold  <= 8'd0;
        end else if (early_word_launch) begin
            ar_id_hold   <= 4'd2;
            ar_addr_hold <= data_pa;
            ar_len_hold  <= 8'd0;
        end else if (early_r_fire && (state == S_RADDR)) begin
            ar_id_hold   <= read_owner_data ? 4'd1 : 4'd0;
            ar_addr_hold <= read_addr_r;
            ar_len_hold  <= read_len_r;
        end else if (normal_inst_read_capture && !early_word_active) begin
            ar_id_hold   <= 4'd0;
            ar_addr_hold <= is_cacheable(inst_pa) ?
                            {inst_pa[31:4], 4'b0} : inst_pa;
            ar_len_hold  <= is_cacheable(inst_pa) ? 8'd3 : 8'd0;
        end else if (normal_data_read_capture && !early_word_active) begin
            ar_id_hold   <= 4'd1;
            ar_addr_hold <= lp_line_refill_now ?
                            {req_paddr[31:4], 4'b0} : req_paddr;
            ar_len_hold  <= lp_line_refill_now ? 8'd3 : 8'd0;
        end
    end

`ifndef SYNTHESIS
    // Hierarchical performance observation only.  These counters disappear
    // from the synthesized design and cannot alter FPGA timing or resources.
    reg [63:0] sim_ic_fast_hit_count;
    reg [63:0] sim_ic_backing_hit_count;
    reg [63:0] sim_ic_miss_count;
    reg [63:0] sim_ic_registered_response_count;
    reg [63:0] sim_dc_load_hit_count;
    reg [63:0] sim_dc_load_miss_count;
    reg [63:0] sim_dc_store_accept_count;
    reg [63:0] sim_axi_read_request_count;
    reg [63:0] sim_axi_read_wait_cycle_count;

    wire sim_ic_fast_hit = inst_hit_fast && inst_resp_ready;
    wire sim_ic_registered_response = inst_resp_valid && inst_resp_ready;
    wire sim_ic_lookup_launch = (state == S_IDLE) && !dc_init_busy &&
        !inst_resp_valid && inst_req && !data_req && !cacheop_valid &&
        !ic_sync_pending && !inst_buffer_hit;
    wire sim_ic_backing_hit = sim_ic_lookup_launch && inst_hit;
    wire sim_ic_miss = sim_ic_lookup_launch && !inst_hit;
    wire sim_dc_load_hit = load_hit_accept && lookup_cacheable;
    wire sim_dc_load_miss = load_accept && lookup_cacheable && !data_hit;
    wire sim_dc_store_accept = store_accept || overlap_store_accept;

    always @(posedge clk) begin
        if (reset) begin
            sim_ic_fast_hit_count             <= 64'd0;
            sim_ic_backing_hit_count          <= 64'd0;
            sim_ic_miss_count                 <= 64'd0;
            sim_ic_registered_response_count <= 64'd0;
            sim_dc_load_hit_count             <= 64'd0;
            sim_dc_load_miss_count            <= 64'd0;
            sim_dc_store_accept_count         <= 64'd0;
            sim_axi_read_request_count        <= 64'd0;
            sim_axi_read_wait_cycle_count     <= 64'd0;
        end else begin
            if (sim_ic_fast_hit)
                sim_ic_fast_hit_count <= sim_ic_fast_hit_count + 64'd1;
            if (sim_ic_backing_hit)
                sim_ic_backing_hit_count <= sim_ic_backing_hit_count + 64'd1;
            if (sim_ic_miss)
                sim_ic_miss_count <= sim_ic_miss_count + 64'd1;
            if (sim_ic_registered_response)
                sim_ic_registered_response_count <=
                    sim_ic_registered_response_count + 64'd1;
            if (sim_dc_load_hit)
                sim_dc_load_hit_count <= sim_dc_load_hit_count + 64'd1;
            if (sim_dc_load_miss)
                sim_dc_load_miss_count <= sim_dc_load_miss_count + 64'd1;
            if (sim_dc_store_accept)
                sim_dc_store_accept_count <= sim_dc_store_accept_count + 64'd1;
            if (ar_fire)
                sim_axi_read_request_count <=
                    sim_axi_read_request_count + 64'd1;
            if (m_arvalid && !m_arready)
                sim_axi_read_wait_cycle_count <=
                    sim_axi_read_wait_cycle_count + 64'd1;
        end
    end
`endif

    // The response may unblock MEM in S_RADDR, but the main FSM retires it
    // from a registered flag on the following edge.  The live AXI/address
    // compare therefore cannot enter state_reg/CE.
    always @(posedge clk) begin
        if (reset) begin
            early_word_active         <= 1'b0;
            early_word_ar_accepted    <= 1'b0;
            early_word_data_valid     <= 1'b0;
            early_word_eligible       <= 1'b0;
            early_word_retire_pending <= 1'b0;
            early_word_addr           <= 32'd0;
            early_word_data           <= 32'd0;
        end else begin
            if (data_lookup_launch)
                early_word_eligible <= early_word_launch;

            // Reaching IDLE after the tagged lookup means the speculative
            // word was not selected by a miss.  Revoke it before an
            // instruction or unrelated data miss can enter S_RADDR.  This
            // cleanup depends only on registered state, never on dc_meta_q.
            if ((state == S_IDLE) && !early_word_launch) begin
                early_word_data_valid <= 1'b0;
                early_word_eligible   <= 1'b0;
            end

            if (early_word_launch) begin
                early_word_active      <= 1'b1;
                early_word_ar_accepted <= 1'b0;
                early_word_data_valid  <= 1'b0;
                early_word_addr        <= data_pa;
            end else if (early_ar_fire) begin
                early_word_ar_accepted <= 1'b1;
            end

            if (early_r_fire) begin
                early_word_active      <= 1'b0;
                early_word_ar_accepted <= 1'b0;
                early_word_data        <= m_rdata;
                early_word_data_valid  <= early_word_eligible &&
                                          !data_lookup_launch &&
                                          (state != S_IDLE);
            end

            if (early_response_now) begin
                early_word_active         <= 1'b0;
                early_word_ar_accepted    <= 1'b0;
                early_word_data_valid     <= 1'b0;
                early_word_eligible       <= 1'b0;
                early_word_retire_pending <= 1'b1;
            end else if ((state == S_RADDR) &&
                         early_word_retire_pending) begin
                early_word_retire_pending <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state           <= S_IDLE;
            read_owner_data <= 1'b0;
            read_refill     <= 1'b0;
            req_vaddr       <= 32'd0;
            req_paddr       <= 32'd0;
            req_pc          <= 32'd0;
            req_word        <= 2'd0;
            req_index       <= 11'd0;
            req_tag         <= 20'd0;
            req_replace_way <= 1'b0;
            req_hit_way     <= 1'b0;
            refill_beat     <= 3'd0;
            refill_data_responded <= 1'b0;
            refill_response_pending <= 1'b0;
            refill_load_probe_pending <= 1'b0;
            refill_load_probe_same_line <= 1'b0;
            refill_load_probe_word <= 2'd0;
            refill_load_probe_forward_data <= 32'd0;
            refill_load_probe_forward_mask <= 4'd0;
            overlap_store_pending <= 1'b0;
            overlap_store_addr_acked <= 1'b0;
            overlap_store_paddr <= 32'd0;
            overlap_store_index <= 11'd0;
            overlap_store_tag <= 17'd0;
            overlap_store_word <= 2'd0;
            overlap_store_we <= 4'd0;
            overlap_store_wdata <= 32'd0;
            overlap_store_ic_conflict <= 1'b0;
            read_addr_r     <= 32'd0;
            read_len_r      <= 8'd0;
            response_data   <= 32'd0;
            req_forward_data <= 32'd0;
            req_forward_mask <= 4'd0;
            req_we           <= 4'd0;
            req_size         <= 3'd2;
            req_wdata        <= 32'd0;
            req_store        <= 1'b0;
            req_ic_store_conflict <= 1'b0;
            req_cacheop      <= 1'b0;
            req_cacheop_code <= 5'd0;
            req_cacheop_way  <= 1'b0;
            req_icache_index <= 8'd0;
            inst_resp_valid <= 1'b0;
            inst_response_data <= 32'd0;
            inst_response_data1 <= 32'd0;
            inst_response_data1_valid <= 1'b0;
            ic_sync_pending <= 1'b0;
            wb_addr          <= 32'd0;
            wb_line          <= 128'd0;
            wb_beat          <= 2'd0;
            wb_for_refill    <= 1'b0;
            wb_way           <= 1'b0;
            write_addr_r    <= 32'd0;
            write_data_r    <= 32'd0;
            write_strb_r    <= 4'd0;
            aw_done         <= 1'b0;
            w_done          <= 1'b0;
            sb_wr_ptr       <= 2'd0;
            sb_rd_ptr       <= 2'd0;
            sb_count        <= 3'd0;
            dc_init_busy    <= 1'b1;
            dc_init_index   <= 11'd0;
            for (i = 0; i < 8; i = i + 1) begin
                ic_buffer_valid[i] <= 1'b0;
                ic_buffer_line_addr[i] <= 28'd0;
                ic_buffer_data[i] <= 128'd0;
            end
            for (i = 0; i < 256; i = i + 1) begin
`ifdef VERILATOR
                // Old lint releases reject delayed array assignments in loops.
                ic_valid[i] = 1'b0;
                ic_seen[i] = 1'b0;
`else
                ic_valid[i] <= 1'b0;
                ic_seen[i] <= 1'b0;
`endif
            end
        end else begin
            // A critical refill word is returned for exactly one cycle.  The
            // full line may continue arriving after the CPU has restarted.
            refill_response_pending <= 1'b0;
            if (dc_init_busy) begin
                if (dc_init_index == 11'd2047) begin
                    dc_init_busy <= 1'b0;
                end else begin
                    dc_init_index <= dc_init_index + 11'd1;
                end
            end
            if (inst_resp_valid && inst_resp_ready)
                inst_resp_valid <= 1'b0;
            if (ic_sync_pending && (sb_count == 3'd0) && !any_store_enqueue)
                ic_sync_pending <= 1'b0;
            if (state != S_RDATA)
                refill_load_probe_pending <= 1'b0;
            if (refill_load_probe_launch) begin
                refill_load_probe_pending <= 1'b1;
                refill_load_probe_same_line <=
                    (data_pa[31:4] == read_addr_r[31:4]);
                refill_load_probe_word <= data_pa[3:2];
                refill_load_probe_forward_data <= sb_forward_data;
                refill_load_probe_forward_mask <= sb_forward_mask;
            end
            if (refill_load_probe_ready) begin
                response_data <= apply_forward(refill_load_probe_data,
                    refill_load_probe_forward_data,
                    refill_load_probe_forward_mask);
                refill_response_pending <= 1'b1;
                refill_load_probe_pending <= 1'b0;
            end else if ((state == S_RDATA) && r_fire && m_rlast) begin
                refill_load_probe_pending <= 1'b0;
            end

            if (overlap_store_preselect) begin
                overlap_store_paddr <= data_pa;
                overlap_store_index <= data_idx;
                overlap_store_tag <= data_tag_now;
                overlap_store_word <= data_pa[3:2];
                overlap_store_we <= data_we;
                overlap_store_wdata <= data_wdata;
                overlap_store_ic_conflict <= ic_store_conflict;
            end

            if (overlap_store_launch) begin
                overlap_store_pending <= 1'b1;
                overlap_store_addr_acked <= 1'b0;
            end else if (overlap_store_addr_accept) begin
                overlap_store_addr_acked <= 1'b1;
            end else if (overlap_store_accept) begin
                overlap_store_pending <= 1'b0;
                overlap_store_addr_acked <= 1'b0;
            end

            // Store-buffer queue accounting.  Enqueue and completion may
            // happen in the same cycle, in which case occupancy is unchanged.
            case ({any_store_enqueue, sb_b_fire})
                2'b10: sb_count <= sb_count + 3'd1;
                2'b01: sb_count <= sb_count - 3'd1;
                default: sb_count <= sb_count;
            endcase
            if (any_store_enqueue) begin
                sb_addr[sb_wr_ptr] <= overlap_store_enqueue ?
                                      overlap_store_paddr : req_paddr;
                sb_data[sb_wr_ptr] <= overlap_store_enqueue ?
                                      overlap_store_wdata : req_wdata;
                sb_strb[sb_wr_ptr] <= overlap_store_enqueue ?
                                      overlap_store_we : req_we;
                sb_wr_ptr <= sb_wr_ptr + 2'd1;
            end

            if (store_accept) begin
                // Cache hits are write-back: update BRAM and mark the resident
                // way dirty.  Misses remain no-write-allocate and use the
                // ordered store queue, which is ideal for streaming stores.
                if (ic_valid[req_paddr[11:4]] &&
                    (ic_tag[req_paddr[11:4]] == req_paddr[31:12]))
                    ic_valid[req_paddr[11:4]] <= 1'b0;
                if (ic_buffer_valid[req_paddr[6:4]] &&
                    (ic_buffer_line_addr[req_paddr[6:4]] == req_paddr[31:4]))
                    ic_buffer_valid[req_paddr[6:4]] <= 1'b0;
                if (req_ic_store_conflict)
                    ic_sync_pending <= 1'b1;
            end
            if (overlap_store_accept) begin
                if (ic_valid[overlap_store_paddr[11:4]] &&
                    (ic_tag[overlap_store_paddr[11:4]] ==
                     overlap_store_paddr[31:12]))
                    ic_valid[overlap_store_paddr[11:4]] <= 1'b0;
                if (ic_buffer_valid[overlap_store_paddr[6:4]] &&
                    (ic_buffer_line_addr[overlap_store_paddr[6:4]] ==
                     overlap_store_paddr[31:4]))
                    ic_buffer_valid[overlap_store_paddr[6:4]] <= 1'b0;
                if (overlap_store_ic_conflict)
                    ic_sync_pending <= 1'b1;
            end
            if (sb_b_fire) begin
                sb_rd_ptr <= sb_rd_ptr + 2'd1;
                aw_done <= 1'b0;
                w_done  <= 1'b0;
            end else begin
                if (sb_aw_fire) aw_done <= 1'b1;
                if (sb_w_fire)  w_done  <= 1'b1;
                if (sb_count == 3'd0) begin
                    aw_done <= 1'b0;
                    w_done  <= 1'b0;
                end
            end

            case (state)
                S_IDLE: begin
                    refill_beat <= 3'd0;
                    refill_data_responded <= 1'b0;
                    // MEM contains an older instruction than ID, so an active
                    // data request must win over cache maintenance from ID.
                    if (dc_init_busy) begin
                        state <= S_IDLE;
                    end else if (data_req) begin
                        req_vaddr <= data_addr;
                        req_paddr <= data_pa;
                        req_pc    <= data_pc;
                        req_word  <= data_pa[3:2];
                        req_index <= data_idx;
                        req_tag   <= {3'b0, data_tag_now};
                        req_forward_data <= sb_forward_data;
                        req_forward_mask <= sb_forward_mask;
                        req_we <= data_we;
                        req_size <= data_size;
                        req_wdata <= data_wdata;
                        req_store <= store_req;
                        req_ic_store_conflict <= ic_store_conflict;
                        req_cacheop <= 1'b0;
                        read_owner_data <= 1'b1;
                        // Tags and data sample the requested set on this edge.
                        state <= S_DTAG;
                    end else if (cacheop_valid && cacheop_ready) begin
                        // Register the I-cache maintenance index before
                        // decoding the 256-entry valid array.  This splits
                        // the former D-cache/bypass/address-add/ic_valid path
                        // across two cycles.  Normal fetch/load/store timing
                        // is unchanged; only this rare CACOP gains one cycle.
                        if (cacheop_code == 5'h00) begin
                            req_icache_index <= cacheop_addr[11:4];
                            req_cacheop <= 1'b0;
                            state <= S_ICINV;
                        end else if ((cacheop_code == 5'h01) ||
                            (cacheop_code == 5'h09)) begin
                            req_index <= cacheop_idx;
                            req_cacheop <= 1'b1;
                            req_cacheop_code <= cacheop_code;
                            req_cacheop_way <= cacheop_addr[0];
                            state <= S_DCSTART;
                        end
                    // A line-buffer hit is already completed by the
                    // combinational fast path in this cycle.  Do not also
                    // create a registered response for the same request.
                    end else if (inst_req && !inst_resp_valid && !inst_buffer_hit &&
                                 !ic_sync_pending) begin
                        req_vaddr <= inst_addr;
                        req_paddr <= inst_pa;
                        req_word  <= inst_pa[3:2];
                        req_index <= {3'b0, inst_idx};
                        req_tag   <= inst_tag_now;
                        read_owner_data <= 1'b0;
                        if (inst_hit) begin
                            // The backing BRAM samples inst_idx on this edge.
                            state <= S_ILOOKUP;
                        end else begin
                            read_refill <= is_cacheable(inst_pa);
                            read_addr_r <= is_cacheable(inst_pa) ? {inst_pa[31:4], 4'b0} : inst_pa;
                            read_len_r  <= is_cacheable(inst_pa) ? 8'd3 : 8'd0;
                            state <= S_RADDR;
                        end
                    end
                end

                S_DTAG: begin
                    if (req_cacheop) begin
                        if (req_cacheop_code == 5'h09) begin
                            wb_way <= req_cacheop_way;
                            wb_for_refill <= 1'b0;
                            if (!req_cacheop_way && dc_valid0_q &&
                                dc_dirty0_q) begin
                                wb_addr <= {dc_tag0_q,
                                    dc_unhash_index(req_index, dc_tag0_q), 4'b0};
                                state <= S_WB_PREP;
                            end else if (req_cacheop_way && dc_valid1_q &&
                                         dc_dirty1_q) begin
                                wb_addr <= {dc_tag1_q,
                                    dc_unhash_index(req_index, dc_tag1_q), 4'b0};
                                state <= S_WB_PREP;
                            end else begin
                                state <= S_IDLE;
                            end
                        end else begin
                            state <= S_IDLE;
                        end
                    end else if (store_accept) begin
                        // Queue/cache write and I-cache invalidation are
                        // performed by the common logic above.
                        state <= S_IDLE;
                    end else if (load_accept) begin
                        if (data_hit) begin
                            req_hit_way <= data_hit1;
                            if (data_req) begin
                                req_vaddr <= data_addr;
                                req_paddr <= data_pa;
                                req_pc    <= data_pc;
                                req_word  <= data_pa[3:2];
                                req_index <= data_idx;
                                req_tag   <= {3'b0, data_tag_now};
                                req_forward_data <= sb_forward_data;
                                req_forward_mask <= sb_forward_mask;
                                req_we <= data_we;
                                req_size <= data_size;
                                req_wdata <= data_wdata;
                                req_store <= store_req;
                                req_ic_store_conflict <= ic_store_conflict;
                                req_cacheop <= 1'b0;
                                read_owner_data <= 1'b1;
                                state <= S_DTAG;
                            end else begin
                                state <= S_IDLE;
                            end
                        end else begin
                            req_replace_way <= victim_way_now;
                            read_refill <= lp_line_refill_now;
                            read_addr_r <= lp_line_refill_now ?
                                           {req_paddr[31:4], 4'b0} : req_paddr;
                            read_len_r  <= lp_line_refill_now ? 8'd3 : 8'd0;
                            if (lp_line_refill_now) begin
                                refill_beat <= 3'd0;
                                refill_data_responded <= 1'b0;
                            end
                            if (lp_line_refill_now && victim_dirty_now) begin
                                wb_addr <= victim_way_now ?
                                    {dc_tag1_q,
                                     dc_unhash_index(req_index, dc_tag1_q), 4'b0} :
                                    {dc_tag0_q,
                                     dc_unhash_index(req_index, dc_tag0_q), 4'b0};
                                wb_way <= victim_way_now;
                                wb_for_refill <= 1'b1;
                                state <= S_WB_PREP;
                            end else begin
                                state <= S_RADDR;
                            end
                        end
                    end
                end

                S_ICINV: begin
                    ic_valid[req_icache_index] <= 1'b0;
                    if (ic_buffer_valid[req_icache_index[2:0]] &&
                        (ic_buffer_line_addr[req_icache_index[2:0]][7:0] ==
                         req_icache_index))
                        ic_buffer_valid[req_icache_index[2:0]] <= 1'b0;
                    state <= S_IDLE;
                end

                // The registered CACOP index is presented to the synchronous
                // D-cache metadata/data RAMs for one full cycle.  Their
                // outputs are consumed in S_DTAG on the following cycle.
                S_DCSTART: state <= S_DTAG;

                S_RADDR: begin
                    if (early_word_retire_pending)
                        state <= S_IDLE;
                    else if (normal_ar_fire)
                        state <= S_RDATA;
                end

                S_RDATA: if (normal_r_fire) begin
                    if (read_refill && read_owner_data &&
                        (refill_beat[1:0] == req_word)) begin
                        response_data <= apply_forward(m_rdata,
                                                       req_forward_data,
                                                       req_forward_mask);
                        refill_data_responded <= 1'b1;
                        refill_response_pending <= 1'b1;
                    end
                    if (m_rlast) begin
                        if (read_refill) begin
                            if (read_owner_data) begin
                                // The metadata RAM commits tag/valid/dirty/LRU
                                // together with the final refill beat.
                            end else begin
                                ic_valid[req_index[7:0]] <= 1'b1;
                                ic_seen[req_index[7:0]]  <= 1'b1;
                                ic_tag[req_index[7:0]]   <= req_tag;
                                ic_buffer_data[req_paddr[6:4]]      <= refill_line_next;
                                ic_buffer_line_addr[req_paddr[6:4]] <= req_paddr[31:4];
                                ic_buffer_valid[req_paddr[6:4]]     <= 1'b1;
                                inst_response_data <= line_word(refill_line_next, req_word);
                            end
                        end else begin
                            if (read_owner_data)
                                response_data <= apply_forward(m_rdata,
                                                               req_forward_data,
                                                               req_forward_mask);
                            else
                                inst_response_data <= m_rdata;
                        end
                        if (read_owner_data) begin
                            // A cacheable load was already acknowledged when
                            // its critical word arrived.  Finish installing
                            // the line silently so refill completion cannot
                            // generate a second data_data_ok pulse.
                            if (read_refill &&
                                (refill_data_responded ||
                                 (refill_beat[1:0] == req_word)))
                                state <= S_IDLE;
                            else if (!read_refill)
                                state <= S_IDLE;
                            else
                                state <= S_DRESP;
                        end else begin
                            // Hold the completed instruction independently so
                            // D-cache traffic can proceed while ID is stalled.
                            inst_resp_valid <= 1'b1;
                            inst_response_data1 <= line_word(refill_line_next,
                                                            req_word + 2'd1);
                            inst_response_data1_valid <=
                                is_cacheable(req_paddr) && (req_word != 2'd3);
                            state <= S_IDLE;
                        end
                    end else begin
                        refill_beat <= refill_beat + 3'd1;
                    end
                end

                S_DLOOKUP: state <= S_IDLE;

                S_ILOOKUP: begin
                    // Registered BRAM output is now valid.  Hold one response
                    // independently so a stalled ID stage cannot lose it.
                    ic_buffer_data[req_paddr[6:4]]      <= ic_ram_rline;
                    ic_buffer_line_addr[req_paddr[6:4]] <= req_paddr[31:4];
                    ic_buffer_valid[req_paddr[6:4]]     <= 1'b1;
                    inst_response_data  <= line_word(ic_ram_rline, req_word);
                    inst_response_data1 <= line_word(ic_ram_rline, req_word + 2'd1);
                    inst_response_data1_valid <= (req_word != 2'd3);
                    inst_resp_valid     <= 1'b1;
                    state               <= S_IDLE;
                end

                S_WB_PREP: begin
                    wb_line <= wb_way ? dc_ram1_rline : dc_ram0_rline;
                    wb_beat <= 2'd0;
                    state <= S_WB_ADDR;
                end

                S_WB_ADDR: if (aw_fire) begin
                    wb_beat <= 2'd0;
                    state <= S_WB_DATA;
                end

                S_WB_DATA: if (w_fire) begin
                    if (wb_beat == 2'd3)
                        state <= S_WB_RESP;
                    else
                        wb_beat <= wb_beat + 2'd1;
                end

                S_WB_RESP: if (b_fire) begin
                    if (wb_for_refill) begin
                        refill_beat <= 3'd0;
                        state <= S_RADDR;
                    end else begin
                        state <= S_IDLE;
                    end
                end

                S_DRESP: state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

// Synchronous metadata storage removes deep asynchronous 2048:1 mux trees.
// Tags change only on refill, while status changes on hits and maintenance;
// independent RAM write enables avoid a packed 39-bit read/modify/write loop.
module cache_meta_ram_2048x39 (
    input  wire        clk,
    input  wire [10:0] rd_set,
    output wire [38:0] rd_meta,
    input  wire [10:0] wr_set,
    input  wire        wr_tag0_en,
    input  wire [16:0] wr_tag0,
    input  wire        wr_tag1_en,
    input  wire [16:0] wr_tag1,
    input  wire        wr_status_en,
    input  wire [ 4:0] wr_status
);
    (* ram_style = "block" *) reg [16:0] tag0 [0:2047];
    (* ram_style = "block" *) reg [16:0] tag1 [0:2047];
    (* ram_style = "block" *) reg [ 4:0] status [0:2047];
    reg [16:0] tag0_q;
    reg [16:0] tag1_q;
    reg [ 4:0] status_q;

    always @(posedge clk) begin
        tag0_q <= tag0[rd_set];
        if (wr_tag0_en)
            tag0[wr_set] <= wr_tag0;
    end

    always @(posedge clk) begin
        tag1_q <= tag1[rd_set];
        if (wr_tag1_en)
            tag1[wr_set] <= wr_tag1;
    end

    always @(posedge clk) begin
        status_q <= status[rd_set];
        if (wr_status_en)
            status[wr_set] <= wr_status;
    end

    assign rd_meta = {status_q[4], status_q[3], status_q[2], tag1_q,
                      status_q[1], status_q[0], tag0_q};
endmodule

// Four independently banked 256x32 memories provide a complete 128-bit
// I-cache line after one clock.  Keeping storage in a leaf module with only a
// synchronous read and one full-word write makes block-RAM inference explicit.
module cache_line_ram_256x128 (
    input  wire         clk,
    input  wire [7:0]   rd_set,
    output wire [127:0] rd_line,
    input  wire         wr_en,
    input  wire [7:0]   wr_set,
    input  wire [127:0] wr_line
);
    (* ram_style = "block" *) reg [31:0] bank0 [0:255];
    (* ram_style = "block" *) reg [31:0] bank1 [0:255];
    (* ram_style = "block" *) reg [31:0] bank2 [0:255];
    (* ram_style = "block" *) reg [31:0] bank3 [0:255];
    reg [31:0] q0, q1, q2, q3;

    always @(posedge clk) begin
        q0 <= bank0[rd_set];
        if (wr_en) bank0[wr_set] <= wr_line[31:0];
    end
    always @(posedge clk) begin
        q1 <= bank1[rd_set];
        if (wr_en) bank1[wr_set] <= wr_line[63:32];
    end
    always @(posedge clk) begin
        q2 <= bank2[rd_set];
        if (wr_en) bank2[wr_set] <= wr_line[95:64];
    end
    always @(posedge clk) begin
        q3 <= bank3[rd_set];
        if (wr_en) bank3[wr_set] <= wr_line[127:96];
    end
    assign rd_line = {q3, q2, q1, q0};
endmodule

// One D-cache way, organized as four word banks.  Each bank is a synchronous
// simple-dual-port RAM with native byte enables, supporting both word refills
// and st.b/st.h/st.w hit updates without turning the array into flip-flops.
module cache_word_ram_2048x32 (
    input  wire        clk,
    input  wire [10:0] rd_set,
    input  wire [1:0]  rd_word,
    output reg  [31:0] rd_data,
    output wire [127:0] rd_line,
    input  wire        wr_en,
    input  wire [10:0] wr_set,
    input  wire [1:0]  wr_word,
    input  wire [31:0] wr_data,
    input  wire [3:0]  wr_strb
);
    (* ram_style = "block" *) reg [31:0] bank0 [0:2047];
    (* ram_style = "block" *) reg [31:0] bank1 [0:2047];
    (* ram_style = "block" *) reg [31:0] bank2 [0:2047];
    (* ram_style = "block" *) reg [31:0] bank3 [0:2047];
    reg [31:0] q0, q1, q2, q3;
    reg [1:0] rd_word_q;

    always @(posedge clk) begin
        rd_word_q <= rd_word;
        q0 <= bank0[rd_set];
        if (wr_en && (wr_word == 2'd0)) begin
            if (wr_strb[0]) bank0[wr_set][7:0]   <= wr_data[7:0];
            if (wr_strb[1]) bank0[wr_set][15:8]  <= wr_data[15:8];
            if (wr_strb[2]) bank0[wr_set][23:16] <= wr_data[23:16];
            if (wr_strb[3]) bank0[wr_set][31:24] <= wr_data[31:24];
        end
    end
    always @(posedge clk) begin
        q1 <= bank1[rd_set];
        if (wr_en && (wr_word == 2'd1)) begin
            if (wr_strb[0]) bank1[wr_set][7:0]   <= wr_data[7:0];
            if (wr_strb[1]) bank1[wr_set][15:8]  <= wr_data[15:8];
            if (wr_strb[2]) bank1[wr_set][23:16] <= wr_data[23:16];
            if (wr_strb[3]) bank1[wr_set][31:24] <= wr_data[31:24];
        end
    end
    always @(posedge clk) begin
        q2 <= bank2[rd_set];
        if (wr_en && (wr_word == 2'd2)) begin
            if (wr_strb[0]) bank2[wr_set][7:0]   <= wr_data[7:0];
            if (wr_strb[1]) bank2[wr_set][15:8]  <= wr_data[15:8];
            if (wr_strb[2]) bank2[wr_set][23:16] <= wr_data[23:16];
            if (wr_strb[3]) bank2[wr_set][31:24] <= wr_data[31:24];
        end
    end
    always @(posedge clk) begin
        q3 <= bank3[rd_set];
        if (wr_en && (wr_word == 2'd3)) begin
            if (wr_strb[0]) bank3[wr_set][7:0]   <= wr_data[7:0];
            if (wr_strb[1]) bank3[wr_set][15:8]  <= wr_data[15:8];
            if (wr_strb[2]) bank3[wr_set][23:16] <= wr_data[23:16];
            if (wr_strb[3]) bank3[wr_set][31:24] <= wr_data[31:24];
        end
    end

    always @(*) begin
        case (rd_word_q)
            2'd0: rd_data = q0;
            2'd1: rd_data = q1;
            2'd2: rd_data = q2;
            default: rd_data = q3;
        endcase
    end
    assign rd_line = {q3, q2, q1, q0};
endmodule

`default_nettype wire
