
`include"./include/myCPU.h"
module YK_Core(
    input  wire        clk,
    input  wire        reset,
    // inst sram interface
    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,
    input  wire [31:0] inst_sram_rdata1,
    input  wire        inst_sram_rdata1_valid,
    input  wire        inst_sram_addr_ok,
    input  wire        inst_sram_data_ok,
    output wire        inst_sram_resp_ready,
    // data sram interface
    output wire        data_sram_en,
    output wire        data_sram_prefetch_hint,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_pc,
    output wire [ 2:0] data_sram_size,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    input  wire        data_sram_addr_ok,
    input  wire        data_sram_data_ok,
    input  wire        data_sram_id_forward_ok,
    input  wire [31:0] data_sram_id_forward_data,
    // Cache maintenance interface (cacop from the decode stage)
    output wire        cacheop_valid,
    output wire [ 4:0] cacheop_code,
    output wire [31:0] cacheop_addr,
    input  wire        cacheop_ready,
    output wire        cache_enable,
    // 发生结构冒险控制信号
    input wire sel_strcture_hazard
);

    // 流水级控制
    wire IF_allow_in      ;
    wire ID_allow_in      ;
    wire ID_fetch_allow_in;
    wire ID_issue_slot0   ;
    wire ID_issue_slot1   ;
    wire IF_to_ID_valid   ;
    wire EXE_allow_in     ;
    wire ID_to_EXE_valid  ;
    wire ID1_to_EXE_valid ;
    wire MEM_allow_in     ;
    wire EXE_to_MEM_valid ;
    wire WB_allow_in      ;
    wire MEM_to_WB_valid  ;

    // 流水级数据交互
    wire [`IF_TO_ID_BUS_WD-1:0]     IF_to_ID_bus    ;
    wire [`IF_TO_ID_BUS_WD-1:0]     IF_to_ID_bus1   ;
    wire                             IF_to_ID_valid1 ;
    wire [`IF_TO_ID_BUS_WD-1:0]     IF_to_resp_bus  ;
    wire [`IF_TO_ID_BUS_WD-1:0]     IF_to_resp_bus1 ;
    wire                             IF_to_resp_valid;
    wire                             IF_to_resp_valid1;
    wire                             fetch_resp_allow_in;
    wire [`ID_TO_EXE_BUS_WD-1:0]    ID_to_EXE_bus   ;
    wire [`ID1_TO_EXE_BUS_WD-1:0]   ID1_to_EXE_bus  ;
    wire [`EXE1_TO_MEM_BUS_WD-1:0]  EXE1_to_MEM_bus ;
    wire [`MEM1_TO_WB_BUS_WD-1:0]   MEM1_to_WB_bus  ;
    wire [`EXE_TO_MEM_BUS_WD-1:0]   EXE_to_MEM_bus  ;
    wire [`MEM_TO_WB_BUS_WD-1:0]    MEM_to_WB_bus   ;
    wire [`WB_to_ID_bus_WD-1:0]     WB_to_ID_bus    ;
    wire [`WB_to_ID_bus_WD-1:0]     completion_WB_to_ID_bus;

    wire [`ID_TO_IF_BUS_WD-1:0]     ID_to_IF_bus    ;

    wire [`EXE_TO_BY_BUS_WD-1:0]    EXE_to_BY_bus   ;
    wire [`MEM_TO_BY_BUS_WD-1:0]    MEM_to_BY_bus   ;
    wire [`WB_TO_BY_BUS_WD-1:0]     WB_to_BY_bus    ;
    wire [`BY_TO_ID_BUS_WD-1:0]     BY_to_ID_bus    ;
    wire [`EXE_TO_BY_BUS_WD-1:0]    EXE1_to_ID_bus  ;
    wire [`EXE_TO_BY_BUS_WD-1:0]    MEM1_to_ID_bus  ;
    wire [`EXE_TO_BY_BUS_WD-1:0]    WB1_to_ID_bus   ;
    wire [37:0]                      WB1_to_RF_bus   ;

    // debug 接口
    wire [31:0] debug_wb_pc      ;
    wire [3:0]  debug_wb_rf_we   ;
    wire [4:0]  debug_wb_rf_wnum ;
    wire [31:0] debug_wb_rf_wdata;

    // ======== IF_reg与if_run之间的内部连线 ========
    wire [31:0] IF_PC           ;
    wire        IF_valid        ;
    wire [31:0] next_PC         ;
    wire        Pre_to_IF_valid ;
    wire        br_taken_cancel_from_IF;  // if_run输出的br_taken_cancel

    // ======== ID_reg与id_run之间的内部连线 ========
    wire [`IF_TO_ID_BUS_WD-1:0] IF_to_ID_reg_data;
    wire [`IF_TO_ID_BUS_WD-1:0] IF_to_ID_reg_data1;
    wire        ID_valid         ;
    wire        ID_valid1        ;
    wire        branch_redirect_valid;
    wire [31:0] branch_redirect_pc;
    wire        branch_redirect_fire;
    reg         redirect_pending;
    reg  [31:0] redirect_pc_pending;

    // ======== EXE_reg与exe_run之间的内部连线 ========
    wire [`ID_TO_EXE_BUS_WD-1:0] ID_to_EXE_reg_data;
    wire [`ID1_TO_EXE_BUS_WD-1:0] ID1_to_EXE_reg_data;
    wire        EXE_valid        ;
    wire        EXE1_valid       ;
    wire        EXE1_to_MEM_valid;

    // Commit an EXE redirect exactly once, then hold it in a register until
    // IF can consume/discard any outstanding wrong-path cache response.
    assign branch_redirect_fire = branch_redirect_valid & MEM_allow_in;
    assign ID_to_IF_bus = {redirect_pending, redirect_pc_pending};

    always @(posedge clk) begin
        if (reset) begin
            redirect_pending    <= 1'b0;
            redirect_pc_pending <= 32'b0;
        end else if (branch_redirect_fire) begin
            redirect_pending    <= 1'b1;
            redirect_pc_pending <= branch_redirect_pc;
        end else if (redirect_pending && IF_allow_in) begin
            redirect_pending    <= 1'b0;
        end
    end

    // ======== MEM_reg与mem_run之间的内部连线 ========
    wire [`EXE_TO_MEM_BUS_WD-1:0] EXE_to_MEM_reg_data;
    wire [`EXE1_TO_MEM_BUS_WD-1:0] EXE1_to_MEM_reg_data;
    wire        MEM_valid        ;
    wire        MEM1_valid       ;
    wire        MEM1_to_WB_valid ;

    // ======== WB_reg与wb_run之间的内部连线 ========
    wire [`MEM_TO_WB_BUS_WD-1:0] MEM_to_WB_reg_data;
    wire [`MEM1_TO_WB_BUS_WD-1:0] MEM1_to_WB_reg_data;
    wire        WB_valid         ;
    wire        WB1_valid        ;

    // Phase-2 rename/ROB sideband.  Tags follow the existing elastic stage
    // enables, so no normal pipeline stage or mandatory cycle is added.
    wire        rob_can_alloc1;
    wire        rob_can_alloc2;
    wire        rob_rollback_busy;
    wire [4:0]  rob_alloc0_tag;
    wire [4:0]  rob_alloc1_tag;
    wire [4:0]  rob_occupancy;
    wire        rob_commit0_valid;
    wire        rob_commit1_valid;
    wire [4:0]  rob_commit0_tag;
    wire [4:0]  rob_commit1_tag;
    wire [31:0] rob_commit0_pc;
    wire [31:0] rob_commit1_pc;
    wire [3:0]  rob_commit0_class;
    wire [3:0]  rob_commit1_class;
    wire        rob_commit0_writes_rd;
    wire        rob_commit1_writes_rd;
    wire [4:0]  rob_commit0_rd;
    wire [4:0]  rob_commit1_rd;
    wire [31:0] rob_commit0_result;
    wire [31:0] rob_commit1_result;

    wire [31:0] rename_pc0;
    wire [31:0] rename_pc1;
    wire [3:0]  rename_class0;
    wire [3:0]  rename_class1;
    wire [4:0]  rename_rd0;
    wire [4:0]  rename_rd1;
    wire        rename_writes_rd0;
    wire        rename_writes_rd1;
    wire        rename_src00_used;
    wire        rename_src01_used;
    wire        rename_src10_used;
    wire        rename_src11_used;
    wire [4:0]  rename_src00_addr;
    wire [4:0]  rename_src01_addr;
    wire [4:0]  rename_src10_addr;
    wire [4:0]  rename_src11_addr;
    wire [13:0] rename_serial_index0;
    wire [31:0] rename_serial_operand0;
    wire [31:0] rename_serial_operand1;

    wire rename_src00_mapped, rename_src01_mapped;
    wire rename_src10_mapped, rename_src11_mapped;
    wire rename_src00_ready, rename_src01_ready;
    wire rename_src10_ready, rename_src11_ready;
    wire [4:0] rename_src00_tag, rename_src01_tag;
    wire [4:0] rename_src10_tag, rename_src11_tag;
    wire [31:0] rename_src00_value, rename_src01_value;
    wire [31:0] rename_src10_value, rename_src11_value;

    reg [4:0] EXE_rob_tag0, EXE_rob_tag1;
    reg [4:0] MEM_rob_tag0, MEM_rob_tag1;
    reg [4:0] WB_rob_tag0, WB_rob_tag1;
    always @(posedge clk) begin
        if (reset) begin
            EXE_rob_tag0 <= 5'd0;
            EXE_rob_tag1 <= 5'd0;
            MEM_rob_tag0 <= 5'd0;
            MEM_rob_tag1 <= 5'd0;
            WB_rob_tag0  <= 5'd0;
            WB_rob_tag1  <= 5'd0;
        end else begin
            if (EXE_allow_in && ID_to_EXE_valid)
                EXE_rob_tag0 <= rob_alloc0_tag;
            if (EXE_allow_in && ID1_to_EXE_valid)
                EXE_rob_tag1 <= rob_alloc1_tag;
            if (MEM_allow_in && EXE_to_MEM_valid)
                MEM_rob_tag0 <= EXE_rob_tag0;
            if (MEM_allow_in && EXE1_to_MEM_valid)
                MEM_rob_tag1 <= EXE_rob_tag1;
            if (WB_allow_in && MEM_to_WB_valid)
                WB_rob_tag0 <= MEM_rob_tag0;
            if (WB_allow_in && MEM1_to_WB_valid)
                WB_rob_tag1 <= MEM_rob_tag1;
        end
    end

    rename_rob rename_rob (
        .clk                        (clk),
        .reset                      (reset),
        .can_alloc1                 (rob_can_alloc1),
        .can_alloc2                 (rob_can_alloc2),
        .alloc0_valid               (ID_issue_slot0),
        .alloc1_valid               (ID_issue_slot1),
        .alloc0_tag                 (rob_alloc0_tag),
        .alloc1_tag                 (rob_alloc1_tag),
        .alloc0_pc                  (rename_pc0),
        .alloc1_pc                  (rename_pc1),
        .alloc0_class               (rename_class0),
        .alloc1_class               (rename_class1),
        .alloc0_rd                  (rename_rd0),
        .alloc1_rd                  (rename_rd1),
        .alloc0_writes_rd           (rename_writes_rd0),
        .alloc1_writes_rd           (rename_writes_rd1),
        .alloc0_checkpoint_valid    (rename_class0 == 4'd1),
        .alloc1_checkpoint_valid    (1'b0),
        .alloc0_checkpoint_id       (2'd0),
        .alloc1_checkpoint_id       (2'd0),
        .alloc0_store_valid         (rename_class0 == 4'd3),
        .alloc1_store_valid         (1'b0),
        .alloc0_store_index         (2'd0),
        .alloc1_store_index         (2'd0),
        .alloc0_serial_index        (rename_serial_index0),
        .alloc1_serial_index        (14'd0),
        .alloc0_serial_operand0     (rename_serial_operand0),
        .alloc1_serial_operand0     (32'd0),
        .alloc0_serial_operand1     (rename_serial_operand1),
        .alloc1_serial_operand1     (32'd0),
        .complete0_valid            (WB_valid),
        .complete0_tag              (WB_rob_tag0),
        .complete0_result           (completion_WB_to_ID_bus[36:5]),
        .complete1_valid            (WB1_valid),
        .complete1_tag              (WB_rob_tag1),
        .complete1_result           (WB1_to_RF_bus[36:5]),
        // Ordered issue cannot allocate past a branch held in EXE, and the
        // redirect suppresses ID issue on its resolve edge.  Phase 2 therefore
        // has no younger allocated entries to roll back.
        .rollback_valid             (1'b0),
        .rollback_keep_tag          (5'd0),
        .rollback_busy              (rob_rollback_busy),
        .src00_used                 (rename_src00_used),
        .src00_addr                 (rename_src00_addr),
        .src00_mapped               (rename_src00_mapped),
        .src00_ready                (rename_src00_ready),
        .src00_tag                  (rename_src00_tag),
        .src00_value                (rename_src00_value),
        .src01_used                 (rename_src01_used),
        .src01_addr                 (rename_src01_addr),
        .src01_mapped               (rename_src01_mapped),
        .src01_ready                (rename_src01_ready),
        .src01_tag                  (rename_src01_tag),
        .src01_value                (rename_src01_value),
        .src10_used                 (rename_src10_used),
        .src10_addr                 (rename_src10_addr),
        .src10_mapped               (rename_src10_mapped),
        .src10_ready                (rename_src10_ready),
        .src10_tag                  (rename_src10_tag),
        .src10_value                (rename_src10_value),
        .src11_used                 (rename_src11_used),
        .src11_addr                 (rename_src11_addr),
        .src11_mapped               (rename_src11_mapped),
        .src11_ready                (rename_src11_ready),
        .src11_tag                  (rename_src11_tag),
        .src11_value                (rename_src11_value),
        .commit0_valid              (rob_commit0_valid),
        .commit0_tag                (rob_commit0_tag),
        .commit0_pc                 (rob_commit0_pc),
        .commit0_class              (rob_commit0_class),
        .commit0_writes_rd          (rob_commit0_writes_rd),
        .commit0_rd                 (rob_commit0_rd),
        .commit0_result             (rob_commit0_result),
        .commit1_valid              (rob_commit1_valid),
        .commit1_tag                (rob_commit1_tag),
        .commit1_pc                 (rob_commit1_pc),
        .commit1_class              (rob_commit1_class),
        .commit1_writes_rd          (rob_commit1_writes_rd),
        .commit1_rd                 (rob_commit1_rd),
        .commit1_result             (rob_commit1_result),
        .occupancy                  (rob_occupancy)
    );

    assign WB_to_ID_bus = {
        rob_commit1_valid & rob_commit1_writes_rd,
        rob_commit1_result,
        rob_commit1_rd,
        rob_commit0_valid & rob_commit0_writes_rd,
        rob_commit0_result,
        rob_commit0_rd
    };

`ifndef SYNTHESIS
    // Ordered architectural commit observation for local reference-model
    // checking.  slot0 is always older than slot1 in the same cycle.  These
    // signals deliberately remain hierarchical simulation nets so the FPGA
    // top-level pinout and synthesized datapath are unchanged.
    wire        sim_commit0_valid  = rob_commit0_valid;
    wire [31:0] sim_commit0_pc     = rob_commit0_pc;
    wire [3:0]  sim_commit0_rf_we  =
        {4{rob_commit0_valid & rob_commit0_writes_rd}};
    wire [4:0]  sim_commit0_rf_wnum = rob_commit0_rd;
    wire [31:0] sim_commit0_rf_wdata = rob_commit0_result;
    wire        sim_commit1_valid  = rob_commit1_valid;
    wire [31:0] sim_commit1_pc     = rob_commit1_pc;
    wire [3:0]  sim_commit1_rf_we  =
        {4{rob_commit1_valid & rob_commit1_writes_rd}};
    wire [4:0]  sim_commit1_rf_wnum = rob_commit1_rd;
    wire [31:0] sim_commit1_rf_wdata = rob_commit1_result;

    wire [31:0] stat_slot1_inst = IF_to_ID_reg_data1[31:0];
    wire        stat_slot1_is_lsu =
        stat_slot1_inst[31:22] == 10'b00_1010_0000 ||
        stat_slot1_inst[31:22] == 10'b00_1010_0001 ||
        stat_slot1_inst[31:22] == 10'b00_1010_0010 ||
        stat_slot1_inst[31:22] == 10'b00_1010_0100 ||
        stat_slot1_inst[31:22] == 10'b00_1010_0101 ||
        stat_slot1_inst[31:22] == 10'b00_1010_0110 ||
        stat_slot1_inst[31:22] == 10'b00_1010_1000 ||
        stat_slot1_inst[31:22] == 10'b00_1010_1001;
    wire        stat_pair_raw_block =
        id_run.sel_rf_w_en &&
        id_run.simple0_rd != 5'b0 &&
        ((id_run.simple1_rs1_used &&
          id_run.simple0_rd == id_run.simple1_rs1) ||
         (id_run.simple1_rs2_used &&
          id_run.simple0_rd == id_run.simple1_rs2));
    wire        stat_pair_waw_block =
        id_run.sel_rf_w_en &&
        id_run.simple0_rd != 5'b0 &&
        id_run.simple1_rd != 5'b0 &&
        id_run.simple0_rd == id_run.simple1_rd;
    wire        stat_lane1_unsupported_block = !id_run.simple1;
    wire        stat_lsu_structural_block =
        id_run.sel_data_ram_en && stat_slot1_is_lsu;
    wire        stat_frontend_no_instruction =
        IF_valid && !inst_sram_data_ok && !branch_redirect_fire;
    wire        stat_queue_full =
        ID_valid && ID_valid1 && !ID_issue_slot0;
    wire        stat_queue_empty = !ID_valid && !ID_valid1;
    wire        stat_load_use_stall =
        ID_valid && !id_run.operands_ready &&
        ((EXE_valid && exe_run.sel_rf_w_data_valid_stage[1]) ||
         (MEM_valid && mem_run.sel_rf_w_data_valid_stage[1]));
    wire        stat_dcache_wait =
        MEM_valid && mem_run.sel_data_ram_en && !data_sram_data_ok;
    wire        stat_mul_div_wait =
        ID_valid && !id_run.operands_ready &&
        ((EXE_valid && exe_run.sel_rf_w_data_valid_stage[2]) ||
         (MEM_valid && mem_run.sel_rf_w_data_valid_stage[2]));
    wire [2:0]  stat_branch_flushed_younger =
        {2'b0, IF_valid} + {2'b0, ID_valid} + {2'b0, ID_valid1};

    wire [63:0] stat_cycle_count;
    wire [63:0] stat_retired_instruction_count;
    wire [63:0] stat_slot0_issue_count;
    wire [63:0] stat_slot1_issue_count;
    wire [63:0] stat_pair_candidate_count;
    wire [63:0] stat_pair_attempt_count = stat_pair_candidate_count;
    wire [63:0] stat_pair_success_count;
    wire [63:0] stat_pair_blocked_count;
    wire [63:0] stat_raw_block_count;
    wire [63:0] stat_waw_block_count;
    wire [63:0] stat_lane1_unsupported_count;
    wire [63:0] stat_lsu_structural_conflict_count;
    wire [63:0] stat_frontend_no_instruction_count;
    wire [63:0] stat_fetch_response_full_cycle_count;
    wire [63:0] stat_queue_full_cycle_count;
    wire [63:0] stat_queue_empty_cycle_count;
    wire [63:0] stat_load_use_stall_count;
    wire [63:0] stat_dcache_wait_cycle_count;
    wire [63:0] stat_mul_div_wait_cycle_count;
    wire [63:0] stat_branch_redirect_count;
    wire [63:0] stat_branch_flushed_younger_count;
    wire [63:0] stat_slot0_commit_count;
    wire [63:0] stat_slot1_commit_count;

    always @(posedge clk) begin
        if (!reset) begin
            if (rob_commit0_valid !== WB_valid) begin
                $display("FAIL ROB/WB lane0 valid mismatch rob=%b wb=%b",
                         rob_commit0_valid, WB_valid);
                $fatal(1);
            end
            if (WB_valid && ((rob_commit0_tag != WB_rob_tag0) ||
                (rob_commit0_pc != debug_wb_pc) ||
                (rob_commit0_result != debug_wb_rf_wdata) ||
                (rob_commit0_rd != debug_wb_rf_wnum))) begin
                $display("FAIL ROB/WB lane0 payload mismatch");
                $fatal(1);
            end
            if (rob_commit1_valid !== WB1_valid) begin
                $display("FAIL ROB/WB lane1 valid mismatch rob=%b wb=%b",
                         rob_commit1_valid, WB1_valid);
                $fatal(1);
            end
            if (WB1_valid && ((rob_commit1_tag != WB_rob_tag1) ||
                (rob_commit1_pc != MEM1_to_WB_reg_data[31:0]) ||
                (rob_commit1_result != WB1_to_RF_bus[36:5]) ||
                (rob_commit1_rd != WB1_to_RF_bus[4:0]))) begin
                $display("FAIL ROB/WB lane1 payload mismatch");
                $fatal(1);
            end
        end
    end
`endif

    // ======== Data RAM内部连线（mem_run输出） ========
    wire        mem_data_ram_en   ;
    wire [31:0] mem_data_ram_addr ;
    wire [3:0]  mem_data_ram_w_en ;
    wire [31:0] mem_data_ram_w_data;
    wire        exe_data_ram_en   ;
    wire        exe_data_ram_prefetch_hint;
    wire [31:0] exe_data_ram_addr ;
    wire [31:0] exe_data_ram_pc   ;
    wire [ 2:0] exe_data_ram_size ;
    wire [3:0]  exe_data_ram_w_en ;
    wire [31:0] exe_data_ram_w_data;
    wire [4:0]  mem_forward_addr;
    wire [31:0] mem_forward_data;
    wire        mem_forward_valid;
    wire [4:0]  mem_store_forward_addr;
    wire [31:0] mem_store_forward_data;
    wire        mem_store_forward_valid;

    //////////////////////////////////////////////////////////////////////
    /// 5级流水线 (每级 = _run组合逻辑 + _reg流水线寄存器)
    //////////////////////////////////////////////////////////////////////

    // ============ 第1级: IF ============
    if_run if_run(
        .reset              (reset),
        .PC                 (IF_PC),
        .IF_valid           (IF_valid),
        .ID_to_IF_bus       (ID_to_IF_bus),
        .IF_to_ID_bus       (IF_to_resp_bus),
        .IF_to_ID_bus1      (IF_to_resp_bus1),
        .inst_ram_en        (inst_sram_en),
        .inst_ram_addr      (inst_sram_addr),
        .inst_ram_w_en      (inst_sram_we),
        .inst_ram_r_data    (inst_sram_rdata),
        .inst_ram_r_data1   (inst_sram_rdata1),
        .inst_ram_r_data1_valid(inst_sram_rdata1_valid),
        .inst_ram_data_ok   (inst_sram_data_ok),
        .inst_ram_resp_ready(inst_sram_resp_ready),
        .inst_ram_w_data    (inst_sram_wdata),
        .ID_allow_in        (fetch_resp_allow_in),
        .IF_to_ID_valid     (IF_to_resp_valid),
        .IF_to_ID_valid1    (IF_to_resp_valid1),
        .IF_allow_in        (IF_allow_in),
        .sel_strcture_hazard(sel_strcture_hazard),
        .next_PC            (next_PC),
        .Pre_to_IF_valid    (Pre_to_IF_valid),
        .br_taken_cancel    (br_taken_cancel_from_IF)
    );

    IF_reg IF_reg(
        .clk                (clk),
        .reset              (reset),
        .IF_allow_in        (IF_allow_in),
        .Pre_to_IF_valid    (Pre_to_IF_valid),
        .next_PC            (next_PC),
        .br_taken_cancel    (br_taken_cancel_from_IF),
        .PC                 (IF_PC),
        .IF_valid           (IF_valid)
    );

    // Normal responses bypass this register, preserving the existing cycle
    // count. A downstream stall captures the complete packet locally.
    fetch_response_slice fetch_response_slice(
        .clk                (clk),
        .reset              (reset),
        .flush              (branch_redirect_fire),
        .in_valid0          (IF_to_resp_valid),
        .in_valid1          (IF_to_resp_valid1),
        .in_data0           (IF_to_resp_bus),
        .in_data1           (IF_to_resp_bus1),
        .in_allow           (fetch_resp_allow_in),
        .out_valid0         (IF_to_ID_valid),
        .out_valid1         (IF_to_ID_valid1),
        .out_data0          (IF_to_ID_bus),
        .out_data1          (IF_to_ID_bus1),
        .out_allow          (ID_fetch_allow_in)
    );

    // ============ 第2级: ID (合并原 IPD + ID) ============
    id_run id_run(
        .clk                (clk),
        .reset              (reset),
        .IF_to_ID_reg_data  (IF_to_ID_reg_data),
        .IF_to_ID_reg_data1 (IF_to_ID_reg_data1),
        .ID_valid           (ID_valid),
        .ID_valid1          (ID_valid1),
        .ID_to_EXE_bus      (ID_to_EXE_bus),
        .ID1_to_EXE_bus     (ID1_to_EXE_bus),
        .WB_to_ID_bus       (WB_to_ID_bus),
        .BY_to_ID_bus       (BY_to_ID_bus),
        .EXE1_to_ID_bus     (EXE1_to_ID_bus),
        .MEM1_to_ID_bus     (MEM1_to_ID_bus),
        .WB1_to_ID_bus      (WB1_to_ID_bus),
        .EXE_allow_in       (EXE_allow_in),
        .rob_can_alloc1     (rob_can_alloc1),
        .rob_can_alloc2     (rob_can_alloc2),
        .rob_rollback_busy  (rob_rollback_busy),
        .ID_allow_in        (ID_allow_in),
        .ID_to_EXE_valid    (ID_to_EXE_valid),
        .ID1_to_EXE_valid   (ID1_to_EXE_valid),
        .ID_ready_go        (),
        .pipeline_flush     (branch_redirect_fire)
        ,.issue_slot0       (ID_issue_slot0)
        ,.issue_slot1       (ID_issue_slot1)
        ,.cacheop_valid     (cacheop_valid)
        ,.cacheop_code      (cacheop_code)
        ,.cacheop_addr      (cacheop_addr)
        ,.cacheop_ready     (cacheop_ready)
        ,.cache_enable      (cache_enable)
        ,.rename_pc0        (rename_pc0)
        ,.rename_pc1        (rename_pc1)
        ,.rename_class0     (rename_class0)
        ,.rename_class1     (rename_class1)
        ,.rename_rd0        (rename_rd0)
        ,.rename_rd1        (rename_rd1)
        ,.rename_writes_rd0 (rename_writes_rd0)
        ,.rename_writes_rd1 (rename_writes_rd1)
        ,.rename_src00_used (rename_src00_used)
        ,.rename_src00_addr (rename_src00_addr)
        ,.rename_src01_used (rename_src01_used)
        ,.rename_src01_addr (rename_src01_addr)
        ,.rename_src10_used (rename_src10_used)
        ,.rename_src10_addr (rename_src10_addr)
        ,.rename_src11_used (rename_src11_used)
        ,.rename_src11_addr (rename_src11_addr)
        ,.rename_serial_index0(rename_serial_index0)
        ,.rename_serial_operand0(rename_serial_operand0)
        ,.rename_serial_operand1(rename_serial_operand1)
    );

    ID_reg ID_reg(
        .clk                (clk),
        .reset              (reset),
        .IF_to_ID_valid     (IF_to_ID_valid),
        .IF_to_ID_valid1    (IF_to_ID_valid1),
        .issue_slot0        (ID_issue_slot0),
        .issue_slot1        (ID_issue_slot1),
        .br_taken_cancel    (branch_redirect_fire),
        .IF_to_ID_bus       (IF_to_ID_bus),
        .IF_to_ID_bus1      (IF_to_ID_bus1),
        .IF_to_ID_reg_data  (IF_to_ID_reg_data),
        .IF_to_ID_reg_data1 (IF_to_ID_reg_data1),
        .ID_valid           (ID_valid),
        .ID_valid1          (ID_valid1),
        .IF_allow_in        (ID_fetch_allow_in)
    );

    // ============ 第3级: EXE ============
    exe_run exe_run(
        .ID_to_EXE_reg_data (ID_to_EXE_reg_data),
        .EXE_valid          (EXE_valid),
        .EXE_to_MEM_bus     (EXE_to_MEM_bus),
        .EXE_to_BY_bus      (EXE_to_BY_bus),
        .branch_redirect_valid(branch_redirect_valid),
        .branch_redirect_pc (branch_redirect_pc),
        .data_ram_en        (exe_data_ram_en),
        .data_ram_prefetch_hint(exe_data_ram_prefetch_hint),
        .data_ram_addr      (exe_data_ram_addr),
        .data_ram_pc        (exe_data_ram_pc),
        .data_ram_size      (exe_data_ram_size),
        .data_ram_w_en      (exe_data_ram_w_en),
        .data_ram_w_data    (exe_data_ram_w_data),
        .data_ram_addr_ok   (data_sram_addr_ok),
        .mem_forward_addr   (mem_store_forward_addr),
        .mem_forward_data   (mem_store_forward_data),
        .mem_forward_valid  (mem_store_forward_valid),
        .MEM_allow_in       (MEM_allow_in),
        .EXE_to_MEM_valid   (EXE_to_MEM_valid),
        .EXE_allow_in       (EXE_allow_in)
    );

    EXE1_reg EXE1_reg(
        .clk                (clk),
        .reset              (reset),
        .ID1_to_EXE_valid   (ID1_to_EXE_valid),
        .EXE_allow_in       (EXE_allow_in),
        .ID1_to_EXE_bus     (ID1_to_EXE_bus),
        .ID1_to_EXE_reg_data(ID1_to_EXE_reg_data),
        .EXE1_valid         (EXE1_valid)
    );

    exe1_run exe1_run(
        .ID1_to_EXE_reg_data(ID1_to_EXE_reg_data),
        .EXE1_valid         (EXE1_valid),
        .EXE1_to_MEM_bus    (EXE1_to_MEM_bus),
        .EXE1_to_MEM_valid  (EXE1_to_MEM_valid),
        .EXE1_to_ID_bus     (EXE1_to_ID_bus)
    );

    EXE_reg EXE_reg(
        .clk                (clk),
        .reset              (reset),
        .ID_to_EXE_valid    (ID_to_EXE_valid),
        .EXE_allow_in       (EXE_allow_in),
        .ID_to_EXE_bus      (ID_to_EXE_bus),
        .ID_to_EXE_reg_data (ID_to_EXE_reg_data),
        .EXE_valid          (EXE_valid)
    );

    // ============ 第4级: MEM (合并原 PreMEM + MEM) ============
    mem_run mem_run(
        .EXE_to_MEM_reg_data(EXE_to_MEM_reg_data),
        .MEM_valid          (MEM_valid),
        .MEM_to_WB_bus      (MEM_to_WB_bus),
        .MEM_to_BY_bus      (MEM_to_BY_bus),
        .mem_store_forward_addr(mem_store_forward_addr),
        .mem_store_forward_data(mem_store_forward_data),
        .mem_store_forward_valid(mem_store_forward_valid),
        .WB_allow_in        (WB_allow_in),
        .MEM_allow_in       (MEM_allow_in),
        .MEM_to_WB_valid    (MEM_to_WB_valid),
        .data_ram_en        (mem_data_ram_en),
        .data_ram_addr      (mem_data_ram_addr),
        .data_ram_w_en      (mem_data_ram_w_en),
        .data_ram_r_data    (data_sram_rdata),
        .data_ram_data_ok   (data_sram_data_ok),
        .data_ram_id_forward_ok(data_sram_id_forward_ok),
        .data_ram_id_forward_data(data_sram_id_forward_data),
        .data_ram_w_data    (mem_data_ram_w_data)
    );

    MEM1_reg MEM1_reg(
        .clk                (clk),
        .reset              (reset),
        .EXE1_to_MEM_valid  (EXE1_to_MEM_valid),
        .MEM_allow_in       (MEM_allow_in),
        .EXE1_to_MEM_bus    (EXE1_to_MEM_bus),
        .EXE1_to_MEM_reg_data(EXE1_to_MEM_reg_data),
        .MEM1_valid         (MEM1_valid)
    );

    mem1_run mem1_run(
        .EXE1_to_MEM_reg_data(EXE1_to_MEM_reg_data),
        .MEM1_valid         (MEM1_valid),
        .MEM1_to_WB_bus     (MEM1_to_WB_bus),
        .MEM1_to_WB_valid   (MEM1_to_WB_valid),
        .MEM1_to_ID_bus     (MEM1_to_ID_bus)
    );

    MEM_reg MEM_reg(
        .clk                (clk),
        .reset              (reset),
        .EXE_to_MEM_valid   (EXE_to_MEM_valid),
        .MEM_allow_in       (MEM_allow_in),
        .EXE_to_MEM_bus     (EXE_to_MEM_bus),
        .EXE_to_MEM_reg_data(EXE_to_MEM_reg_data),
        .MEM_valid          (MEM_valid)
    );

    // ============ 第5级: WB ============
    wb_run wb_run(
        .MEM_to_WB_reg_data (MEM_to_WB_reg_data),
        .WB_valid           (WB_valid),
        .WB1_to_RF_bus      (WB1_to_RF_bus),
        .WB_to_ID_bus       (completion_WB_to_ID_bus),
        .WB_to_BY_bus       (WB_to_BY_bus),
        .debug_wb_pc        (debug_wb_pc),
        .debug_wb_rf_we    (debug_wb_rf_we),
        .debug_wb_rf_wnum   (debug_wb_rf_wnum),
        .debug_wb_rf_wdata  (debug_wb_rf_wdata),
        .WB_allow_in        (WB_allow_in)
    );

    WB1_reg WB1_reg(
        .clk                (clk),
        .reset              (reset),
        .MEM1_to_WB_valid   (MEM1_to_WB_valid),
        .WB_allow_in        (WB_allow_in),
        .MEM1_to_WB_bus     (MEM1_to_WB_bus),
        .MEM1_to_WB_reg_data(MEM1_to_WB_reg_data),
        .WB1_valid          (WB1_valid)
    );

    wb1_run wb1_run(
        .MEM1_to_WB_reg_data(MEM1_to_WB_reg_data),
        .WB1_valid          (WB1_valid),
        .WB1_to_RF_bus      (WB1_to_RF_bus),
        .WB1_to_ID_bus      (WB1_to_ID_bus)
    );

    WB_reg WB_reg(
        .clk                (clk),
        .reset              (reset),
        .MEM_to_WB_valid    (MEM_to_WB_valid),
        .WB_allow_in        (WB_allow_in),
        .MEM_to_WB_bus      (MEM_to_WB_bus),
        .MEM_to_WB_reg_data (MEM_to_WB_reg_data),
        .WB_valid           (WB_valid)
    );

    // Launch the request in EXE; MEM consumes the synchronous cache response.
    assign data_sram_en    = exe_data_ram_en;
    assign data_sram_prefetch_hint = exe_data_ram_prefetch_hint;
    assign data_sram_addr  = exe_data_ram_addr;
    assign data_sram_pc    = exe_data_ram_pc;
    assign data_sram_size  = exe_data_ram_size;
    assign data_sram_we    = exe_data_ram_w_en;
    assign data_sram_wdata = exe_data_ram_w_data;

    ////////////////////////////////////////////////////////////////////
    /// 5级流水之外的模块（3级旁路：EXE -> MEM -> WB）
    Bypassing Bypassing(
        .EXE_to_BY_bus      (EXE_to_BY_bus),
        .MEM_to_BY_bus      (MEM_to_BY_bus),
        .WB_to_BY_bus       (WB_to_BY_bus),
        .BY_to_ID_bus       (BY_to_ID_bus),
        .mem_forward_addr   (mem_forward_addr),
        .mem_forward_data   (mem_forward_data),
        .mem_forward_valid  (mem_forward_valid)
    );

`ifndef SYNTHESIS
    // Hierarchical simulation counters used by local performance benches.
    // They are excluded from synthesis so timing and resource measurements
    // remain representative of the architectural datapath only.
    dual_issue_stats dual_issue_stats (
        .clk                            (clk),
        .reset                          (reset),
        .slot0_issue                    (ID_issue_slot0),
        .slot1_issue                    (ID_issue_slot1),
        .slot1_present                  (ID_valid1),
        .slot0_commit                   (rob_commit0_valid),
        .slot1_commit                   (rob_commit1_valid),
        .pair_raw_block                 (stat_pair_raw_block),
        .pair_waw_block                 (stat_pair_waw_block),
        .lane1_unsupported_block        (stat_lane1_unsupported_block),
        .lsu_structural_block           (stat_lsu_structural_block),
        .frontend_no_instruction        (stat_frontend_no_instruction),
        .fetch_response_full            (IF_to_ID_valid && !ID_fetch_allow_in),
        .queue_full                     (stat_queue_full),
        .queue_empty                    (stat_queue_empty),
        .load_use_stall                 (stat_load_use_stall),
        .dcache_wait                    (stat_dcache_wait),
        .mul_div_wait                   (stat_mul_div_wait),
        .branch_redirect                (branch_redirect_fire),
        .branch_flushed_younger         (stat_branch_flushed_younger),
        .cycle_count                    (stat_cycle_count),
        .retired_instruction_count      (stat_retired_instruction_count),
        .slot0_issue_count              (stat_slot0_issue_count),
        .slot1_issue_count              (stat_slot1_issue_count),
        .pair_candidate_count           (stat_pair_candidate_count),
        .pair_success_count             (stat_pair_success_count),
        .pair_blocked_count             (stat_pair_blocked_count),
        .raw_block_count                (stat_raw_block_count),
        .waw_block_count                (stat_waw_block_count),
        .lane1_unsupported_count        (stat_lane1_unsupported_count),
        .lsu_structural_conflict_count  (stat_lsu_structural_conflict_count),
        .frontend_no_instruction_count  (stat_frontend_no_instruction_count),
        .fetch_response_full_cycle_count(stat_fetch_response_full_cycle_count),
        .queue_full_cycle_count         (stat_queue_full_cycle_count),
        .queue_empty_cycle_count        (stat_queue_empty_cycle_count),
        .load_use_stall_count           (stat_load_use_stall_count),
        .dcache_wait_cycle_count        (stat_dcache_wait_cycle_count),
        .mul_div_wait_cycle_count       (stat_mul_div_wait_cycle_count),
        .branch_redirect_count          (stat_branch_redirect_count),
        .branch_flushed_younger_count   (stat_branch_flushed_younger_count),
        .slot0_commit_count             (stat_slot0_commit_count),
        .slot1_commit_count             (stat_slot1_commit_count)
    );
`endif

endmodule
