/**
 * @file id_run.v
 * @author refactored (5-stage version - merged IPD+ID)
 * @brief ID阶段组合逻辑单元：指令译码 + 寄存器堆、唤醒模块、分支单元、旁路选择
 *
 * 合并了原7级流水线中IPD(译码)和ID(寄存器堆/唤醒/分支)两级的功能。
 * 输入: IF_to_ID_reg_data = {inst_PC(32), inst(32)}
 *
 * ID_to_EXE_bus保持与原7级版本相同的162位格式：
 * NOTE: The current buses are IF_to_ID=160 bits and ID_to_EXE=358 bits.
 *   IF_to_ID_reg_data = {pred_PC, branch_target, fallthrough_PC, inst_PC, inst}
 *   {sel_rf_w_data_valid_stage(3), sel_rf_w_en(1), sel_rf_w_data(1),
 *    sel_data_ram_wd(2), sel_data_ram_extend(1), sel_data_ram_we(1),
 *    sel_data_ram_en(1), data_ram_wdata(32), RegFile_w_addr(5),
 *    alu_op(19), alu_src2(32), alu_src1(32), inst_PC(32)}
 */
`include "myCPU.h"
module id_run(
    input  wire                          clk,
    input  wire                          reset,
    // 来自ID_reg
    input  wire [`IF_TO_ID_BUS_WD-1:0]   IF_to_ID_reg_data,
    input  wire [`IF_TO_ID_BUS_WD-1:0]   IF_to_ID_reg_data1,
    input  wire                          ID_valid,
    input  wire                          ID_valid1,

    // 流水线数据传输
    output wire [`ID_TO_EXE_BUS_WD-1:0]  ID_to_EXE_bus,
    output wire [`ID1_TO_EXE_BUS_WD-1:0] ID1_to_EXE_bus,

    input  wire [`WB_to_ID_bus_WD-1:0]   WB_to_ID_bus,
    input  wire [`BY_TO_ID_BUS_WD-1:0]   BY_to_ID_bus,
    input  wire [`EXE_TO_BY_BUS_WD-1:0]  EXE1_to_ID_bus,
    input  wire [`EXE_TO_BY_BUS_WD-1:0]  MEM1_to_ID_bus,
    input  wire [`EXE_TO_BY_BUS_WD-1:0]  WB1_to_ID_bus,

    // 流水线控制
    input  wire                          EXE_allow_in,
    input  wire                          rob_can_alloc1,
    input  wire                          rob_can_alloc2,
    input  wire                          rob_rollback_busy,
    output wire                          ID_allow_in,
    output wire                          ID_to_EXE_valid,
    output wire                          ID1_to_EXE_valid,
    output wire                          ID_ready_go,

    // 反馈到ID_reg：当前阶段真正消费的槽位数
    input  wire                          pipeline_flush
    ,output wire                         issue_slot0
    ,output wire                         issue_slot1
    ,output wire                         cacheop_valid
    ,output wire [4:0]                   cacheop_code
    ,output wire [31:0]                  cacheop_addr
    ,input  wire                         cacheop_ready
    ,output wire                         cache_enable
    ,output wire [31:0]                  rename_pc0
    ,output wire [31:0]                  rename_pc1
    ,output wire [3:0]                   rename_class0
    ,output wire [3:0]                   rename_class1
    ,output wire [4:0]                   rename_rd0
    ,output wire [4:0]                   rename_rd1
    ,output wire                         rename_writes_rd0
    ,output wire                         rename_writes_rd1
    ,output wire                         rename_src00_used
    ,output wire [4:0]                   rename_src00_addr
    ,output wire                         rename_src01_used
    ,output wire [4:0]                   rename_src01_addr
    ,output wire                         rename_src10_used
    ,output wire [4:0]                   rename_src10_addr
    ,output wire                         rename_src11_used
    ,output wire [4:0]                   rename_src11_addr
    ,output wire [13:0]                  rename_serial_index0
    ,output wire [31:0]                  rename_serial_operand0
    ,output wire [31:0]                  rename_serial_operand1
);

    // 当前指令及PC
    wire [31:0] inst_ram_r_data;
    wire [31:0] inst_PC;
    wire [31:0] inst1;
    wire [31:0] inst_PC1;

    // 指令译码信号
    wire [`INST_TYPE_WD-1:0] inst_type;
    wire inst_addi_w, inst_add_w, inst_sub_w, inst_or, inst_ori;
    wire inst_nor, inst_andi, inst_and, inst_xor, inst_xori;
    wire inst_srl_w, inst_srli_w, inst_sll_w, inst_slli_w;
    wire inst_sra_w, inst_srai_w, inst_lu12i_w, inst_pcaddu12i;
    wire inst_slt, inst_slti, inst_sltu, inst_sltui;
    wire inst_mul_w, inst_mulh_w, inst_mulh_wu;
    wire inst_div_w, inst_mod_w, inst_div_wu, inst_mod_wu;
    wire inst_jirl, inst_b, inst_beq, inst_bne, inst_bge, inst_bgeu;
    wire inst_bl, inst_blt, inst_bltu;
    wire inst_st_w, inst_ld_w, inst_st_h, inst_ld_h;
    wire inst_st_b, inst_ld_b, inst_ld_bu, inst_ld_hu;
    wire inst_cpucfg, inst_csr, inst_cacop;
    wire inst_csrwr, inst_csrxchg;

    wire [4:0] RegFile_r_addr1, RegFile_r_addr2, RegFile_w_addr;
    wire [31:0] immediate;

    wire [4:0] rk, rj, rd;
    wire [21:0] opcode_22b;
    wire [16:0] opcode_17b;
    wire [9:0]  opcode_10b;
    wire [7:0]  opcode_08b;
    wire [6:0]  opcode_07b;
    wire [5:0]  opcode_06b;
    wire [31:0] inst;

    // 控制信号
    wire [1:0] sel_alu_src1;
    wire [2:0] sel_alu_src2;
    wire       sel_bu_src1, sel_bu_src2;
    wire [1:0] sel_rf_r_addr_1, sel_rf_r_addr_2, sel_rf_w_addr;
    wire [18:0] alu_op;
    wire op_mul_s_l, op_mul_s_h, op_mul_u_h;
    wire op_div_s, op_div_u, op_mod_s, op_mod_u;
    wire op_lui, op_sra, op_srl, op_sll, op_xor, op_or, op_nor, op_and;
    wire op_sltu, op_slt, op_sub, op_add;
    wire sel_data_ram_we, sel_data_ram_en, sel_data_ram_extend;
    wire [1:0] sel_data_ram_wd;
    wire sel_rf_w_en, sel_rf_w_data;
    wire [2:0] sel_rf_w_data_valid_stage;

    // 寄存器堆
    wire [31:0] RegFile_r_data1;
    wire [31:0] RegFile_r_data2;
    wire [31:0] RegFile_r_data3;
    wire [31:0] RegFile_r_data4;
    wire        w_en;
    wire [31:0] w_data;
    wire [4:0]  w_addr;
    wire        w_en2;
    wire [31:0] w_data2;
    wire [4:0]  w_addr2;

    // ALU源操作数
    reg  [31:0] alu_src1;
    reg  [31:0] alu_src2;

    // BU源操作数
    reg  [31:0] bu_src1;
    reg  [31:0] bu_src2;

    // 数据RAM写数据
    reg  [31:0] data_ram_wdata;

    // 分支处理
    wire [31:0] pred_PC;
    wire [31:0] branch_target;
    wire [31:0] fallthrough_PC;
    wire [`BR_OP_WD-1:0] br_op;

    // 唤醒模块信号——来自旁路模块Bypassing (3级: EXE/MEM/WB)
    wire [4:0]  EXE_RegFile_w_addr;
    wire [31:0] EXE_RegFile_w_data;
    wire        EXE_sel_RF_w_data_valid;
    wire        EXE_valid;
    wire        EXE_sel_rf_w_en;
    wire [4:0]  MEM_RegFile_w_addr;
    wire [31:0] MEM_RegFile_w_data;
    wire        MEM_sel_RF_w_data_valid;
    wire        MEM_valid;
    wire        MEM_sel_rf_w_en;
    wire [4:0]  WB_RegFile_w_addr;
    wire [31:0] WB_RegFile_w_data;
    wire        WB_sel_RF_w_data_valid;
    wire        WB_valid;
    wire        WB_sel_rf_w_en;

    // 唤醒模块
    wire        alu_src_1_ready;
    wire        alu_src_2_ready;
    wire        bu_src_1_ready;
    wire        bu_src_2_ready;
    wire        mem_w_data_ready;
    wire        operands_ready;
    wire        source1_used;
    wire        source2_used;
    wire        source1_ready_full;
    wire        source2_ready_full;
    wire        id_fire;
    wire        cacheop_capture;
    wire        cacheop_handshake;
    reg         cacheop_pending;
    reg         cacheop_complete;
    reg  [ 4:0] cacheop_code_r;
    reg  [31:0] cacheop_addr_r;

    reg  [31:0] csr_crmd;
    reg  [31:0] csr_dmw0;
    reg  [31:0] csr_dmw1;
    reg  [31:0] csr_old_value;

    // Direct-address mode must bypass both caches until software enables PG.
    assign cache_enable = csr_crmd[4];
    reg  [31:0] cpucfg_value;
    wire [13:0] csr_num = inst[23:10];
    wire [31:0] rf1_forwarded;
    wire [31:0] rf2_forwarded;
    wire [31:0] csr_write_mask;
    wire [31:0] csr_new_value;

    wire [`BY_TO_WK_BUS_WD-1:0] BY_to_WK_bus;

    // Conservative lane1 decode and operand state.
    wire simple0;
    wire simple1;
    wire lane0_pairable;
    wire lane0_writes_rd;
    wire simple0_rs1_used;
    wire simple0_rs2_used;
    wire simple1_rs1_used;
    wire simple1_rs2_used;
    wire [4:0] simple0_rs1;
    wire [4:0] simple0_rs2;
    wire [4:0] simple0_rd;
    wire [4:0] simple1_rs1;
    wire [4:0] simple1_rs2;
    wire [4:0] simple1_rd;
    wire [18:0] simple0_alu_op;
    wire [18:0] simple1_alu_op;
    wire [31:0] simple0_src1_base;
    wire [31:0] simple0_src2_base;
    wire [31:0] simple1_src1_base;
    wire [31:0] simple1_src2_base;
    wire pair_valid;
    wire lane0_lane1_producers_ready;
    wire lane1_operands_ready;
    wire [31:0] lane1_rf1_forwarded;
    wire [31:0] lane1_rf2_forwarded;
    wire [31:0] lane1_src1;
    wire [31:0] lane1_src2;

    wire [4:0] EXE1_w_addr, MEM1_w_addr, WB1_w_addr;
    wire [31:0] EXE1_w_data, MEM1_w_data, WB1_w_data;
    wire EXE1_data_valid, EXE1_valid, EXE1_w_en;
    wire MEM1_data_valid, MEM1_valid, MEM1_w_en;
    wire WB1_data_valid, WB1_valid, WB1_w_en;

    ///////////////////////////////////////////////////////////
    /// 流水线控制
    assign source1_used = sel_alu_src1[1] | sel_bu_src1;
    assign source2_used = sel_alu_src2[1] | sel_bu_src2 | sel_data_ram_we;
    assign source1_ready_full = !source1_used || RegFile_r_addr1==5'b0 ? 1'b1 :
        (RegFile_r_addr1==EXE1_w_addr && EXE1_w_en && EXE1_valid) ? EXE1_data_valid :
        (RegFile_r_addr1==EXE_RegFile_w_addr && EXE_sel_rf_w_en && EXE_valid) ? EXE_sel_RF_w_data_valid :
        (RegFile_r_addr1==MEM1_w_addr && MEM1_w_en && MEM1_valid) ? MEM1_data_valid :
        (RegFile_r_addr1==MEM_RegFile_w_addr && MEM_sel_rf_w_en && MEM_valid) ? MEM_sel_RF_w_data_valid :
        (RegFile_r_addr1==WB1_w_addr && WB1_w_en && WB1_valid) ? WB1_data_valid :
        (RegFile_r_addr1==WB_RegFile_w_addr && WB_sel_rf_w_en && WB_valid) ? WB_sel_RF_w_data_valid : 1'b1;
    assign source2_ready_full = !source2_used || RegFile_r_addr2==5'b0 ? 1'b1 :
        (RegFile_r_addr2==EXE1_w_addr && EXE1_w_en && EXE1_valid) ? EXE1_data_valid :
        (RegFile_r_addr2==EXE_RegFile_w_addr && EXE_sel_rf_w_en && EXE_valid) ? EXE_sel_RF_w_data_valid :
        (RegFile_r_addr2==MEM1_w_addr && MEM1_w_en && MEM1_valid) ? MEM1_data_valid :
        (RegFile_r_addr2==MEM_RegFile_w_addr && MEM_sel_rf_w_en && MEM_valid) ? MEM_sel_RF_w_data_valid :
        (RegFile_r_addr2==WB1_w_addr && WB1_w_en && WB1_valid) ? WB1_data_valid :
        (RegFile_r_addr2==WB_RegFile_w_addr && WB_sel_rf_w_en && WB_valid) ? WB_sel_RF_w_data_valid : 1'b1;
    assign operands_ready = source1_ready_full & source2_ready_full;
    // A ready cache operation may issue on its handshake edge with no added
    // cycle.  If EXE is blocked on that edge, the completion token remembers
    // that the cache already consumed the request and prevents a duplicate.
    wire decode_operands_ready = inst_cacop ?
                                     (cacheop_handshake | cacheop_complete) :
                                     operands_ready;
    // Ordered phase-2 has at most the three downstream dual slots in flight,
    // so a 16-entry ROB cannot fill.  Do not put its capacity comparator back
    // on the front-end consume path; phase-3 reconnects it after the registered
    // dispatch boundary.  rename_rob still asserts on any illegal allocation.
    assign ID_ready_go        = decode_operands_ready;
    assign ID_allow_in        = (~ID_valid) | (ID_ready_go & EXE_allow_in);
    assign ID_to_EXE_valid    = ID_ready_go & ID_valid & ~pipeline_flush;
    assign ID1_to_EXE_valid   = ID_to_EXE_valid & pair_valid &
                                lane1_operands_ready;
    // A branch/jirl must not redirect or flush IF while one of its source
    // operands is still waiting for a load result.  In that cycle the
    // bypass mux intentionally supplies zero, which is not a valid target.
    // Keep a resolved redirect asserted for one extra cycle if the single
    // SRAM port is busy; ID_reg deliberately retains the branch fields until
    // IF can accept the target PC.
    assign id_fire            = ID_to_EXE_valid & EXE_allow_in;
    assign issue_slot0        = id_fire;
    assign issue_slot1        = id_fire & pair_valid & lane1_operands_ready;

    // Phase-2 rename metadata is generated on the existing ID -> EXE edge.
    // It is sideband-only: no additional normal pipeline stage is inserted.
    assign rename_pc0 = inst_PC;
    assign rename_pc1 = inst_PC1;
    assign rename_class0 = (br_op != `BR_NONE) ? 4'd1 :
                           (inst_ld_w | inst_ld_h | inst_ld_b |
                            inst_ld_bu | inst_ld_hu) ? 4'd2 :
                           (inst_st_w | inst_st_h | inst_st_b) ? 4'd3 :
                           (inst_mul_w | inst_mulh_w | inst_mulh_wu |
                            inst_div_w | inst_div_wu |
                            inst_mod_w | inst_mod_wu) ? 4'd4 :
                           (inst_csr | inst_cpucfg | inst_cacop) ? 4'd5 : 4'd0;
    assign rename_class1 = 4'd0;
    assign rename_rd0 = RegFile_w_addr;
    assign rename_rd1 = simple1_rd;
    assign rename_writes_rd0 = sel_rf_w_en & (RegFile_w_addr != 5'd0);
    assign rename_writes_rd1 = simple1 & (simple1_rd != 5'd0);
    assign rename_src00_used = source1_used;
    assign rename_src00_addr = RegFile_r_addr1;
    assign rename_src01_used = source2_used;
    assign rename_src01_addr = RegFile_r_addr2;
    assign rename_src10_used = simple1_rs1_used;
    assign rename_src10_addr = simple1_rs1;
    assign rename_src11_used = simple1_rs2_used;
    assign rename_src11_addr = simple1_rs2;
    assign rename_serial_index0 = inst_cacop ? {9'd0, rd} :
                                  inst_csr ? csr_num : 14'd0;
    assign rename_serial_operand0 = rf1_forwarded;
    assign rename_serial_operand1 = rf2_forwarded;

    /////////////////////////////////////////////////////////////
    /// IF_to_ID_reg 分解
    assign {pred_PC, branch_target, fallthrough_PC,
            inst_PC, inst_ram_r_data} = IF_to_ID_reg_data;
    assign inst1 = IF_to_ID_reg_data1[31:0];
    assign inst_PC1 = IF_to_ID_reg_data1[63:32];

    // 指令字段
    assign inst = inst_ram_r_data;
    assign rk = inst[14:10];
    assign rj = inst[ 9: 5];
    assign rd = inst[ 4: 0];
    assign opcode_22b = inst[31:10];
    assign opcode_17b = inst[31:15];
    assign opcode_10b = inst[31:22];
    assign opcode_08b = inst[31:24];
    assign opcode_07b = inst[31:25];
    assign opcode_06b = inst[31:26];

    /////////////////////////////////////////////////////////////
    /// 指令译码
    assign inst_addi_w   = opcode_10b==10'b00_0000_1010;
    assign inst_add_w    = opcode_17b==17'b0_0000_0000_0010_0000;
    assign inst_sub_w    = opcode_17b==17'b0_0000_0000_0010_0010;
    assign inst_or       = opcode_17b==17'b0_0000_0000_0010_1010;
    assign inst_ori      = opcode_10b==10'b00_0000_1110;
    assign inst_nor      = opcode_17b==17'b0_0000_0000_0010_1000;
    assign inst_andi     = opcode_10b==10'b00_0000_1101;
    assign inst_and      = opcode_17b==17'b0_0000_0000_0010_1001;
    assign inst_xor      = opcode_17b==17'b0_0000_0000_0010_1011;
    assign inst_xori     = opcode_10b==10'b00_0000_1111;
    assign inst_srl_w    = opcode_17b==17'b0_0000_0000_0010_1111;
    assign inst_srli_w   = opcode_17b==17'b0_0000_0000_1000_1001;
    assign inst_sll_w    = opcode_17b==17'b0_0000_0000_0010_1110;
    assign inst_slli_w   = opcode_17b==17'b0_0000_0000_1000_0001;
    assign inst_sra_w    = opcode_17b==17'b0_0000_0000_0011_0000;
    assign inst_srai_w   = opcode_17b==17'b0_0000_0000_1001_0001;
    assign inst_lu12i_w  = opcode_07b==7'b000_1010;
    assign inst_pcaddu12i= opcode_07b==7'b000_1110;
    assign inst_slt      = opcode_17b==17'b0_0000_0000_0010_0100;
    assign inst_slti     = opcode_10b==10'b00_0000_1000;
    assign inst_sltu     = opcode_17b==17'b0_0000_0000_0010_0101;
    assign inst_sltui    = opcode_10b==10'b00_0000_1001;
    assign inst_mul_w    = opcode_17b==17'b0_0000_0000_0011_1000;
    assign inst_mulh_w   = opcode_17b==17'b0_0000_0000_0011_1001;
    assign inst_mulh_wu  = opcode_17b==17'b0_0000_0000_0011_1010;
    assign inst_div_w    = opcode_17b==17'b0_0000_0000_0100_0000;
    assign inst_mod_w    = opcode_17b==17'b0_0000_0000_0100_0001;
    assign inst_div_wu   = opcode_17b==17'b0_0000_0000_0100_0010;
    assign inst_mod_wu   = opcode_17b==17'b0_0000_0000_0100_0011;
    assign inst_jirl     = opcode_06b==6'b01_0011;
    assign inst_b        = opcode_06b==6'b01_0100;
    assign inst_beq      = opcode_06b==6'b01_0110;
    assign inst_bne      = opcode_06b==6'b01_0111;
    assign inst_bge      = opcode_06b==6'b01_1001;
    assign inst_bgeu     = opcode_06b==6'b01_1011;
    assign inst_bl       = opcode_06b==6'b01_0101;
    assign inst_blt      = opcode_06b==6'b01_1000;
    assign inst_bltu     = opcode_06b==6'b01_1010;

    // Only a compact branch operation crosses the ID/EXE boundary.  The
    // actual compare and redirect decision are made from registered values
    // in EXE, not on the forwarding-to-IF combinational path.
    assign br_op = inst_jirl ? `BR_JIRL :
                   inst_b    ? `BR_B    :
                   inst_bl   ? `BR_BL   :
                   inst_beq  ? `BR_EQ   :
                   inst_bne  ? `BR_NE   :
                   inst_bge  ? `BR_GE   :
                   inst_bgeu ? `BR_GEU  :
                   inst_blt  ? `BR_LT   :
                   inst_bltu ? `BR_LTU  : `BR_NONE;
    assign inst_st_w     = opcode_10b==10'b00_1010_0110;
    assign inst_ld_w     = opcode_10b==10'b00_1010_0010;
    assign inst_st_h     = opcode_10b==10'b00_1010_0101;
    assign inst_ld_h     = opcode_10b==10'b00_1010_0001;
    assign inst_st_b     = opcode_10b==10'b00_1010_0100;
    assign inst_ld_b     = opcode_10b==10'b00_1010_0000;
    assign inst_ld_bu    = opcode_10b==10'b00_1010_1000;
    assign inst_ld_hu    = opcode_10b==10'b00_1010_1001;
    assign inst_cpucfg   = opcode_22b==22'h00001b;
    assign inst_csr      = opcode_08b==8'h04;
    assign inst_csrwr    = inst_csr && (rj == 5'd1);
    assign inst_csrxchg  = inst_csr && (rj != 5'd0) && (rj != 5'd1);
    assign inst_cacop    = opcode_10b==10'b00_0001_1000;

    assign inst_type = {
        inst_addi_w, inst_add_w, inst_sub_w, inst_or, inst_ori,
        inst_nor, inst_andi, inst_and, inst_xor, inst_xori,
        inst_srl_w, inst_srli_w, inst_sll_w, inst_slli_w,
        inst_sra_w, inst_srai_w, inst_lu12i_w, inst_pcaddu12i,
        inst_slt, inst_slti, inst_sltu, inst_sltui,
        inst_mul_w, inst_mulh_w, inst_mulh_wu,
        inst_div_w, inst_mod_w, inst_div_wu, inst_mod_wu,
        inst_jirl, inst_b, inst_beq, inst_bne, inst_bge, inst_bgeu,
        inst_bl, inst_blt, inst_bltu,
        inst_st_w, inst_ld_w, inst_st_h, inst_ld_h,
        inst_st_b, inst_ld_b, inst_ld_bu, inst_ld_hu
    };

    /////////////////////////////////////////////////////////////
    /// 寄存器号选择
    assign sel_rf_r_addr_1[1] = 1'b0;
    assign sel_rf_r_addr_1[0] = inst_add_w | inst_addi_w | inst_sub_w
        | inst_mul_w | inst_mulh_w | inst_mulh_wu
        | inst_div_w | inst_div_wu | inst_mod_w | inst_mod_wu
        | inst_or | inst_ori | inst_nor | inst_and | inst_andi | inst_xor | inst_xori
        | inst_srl_w | inst_sll_w | inst_sra_w
        | inst_srli_w | inst_slli_w | inst_srai_w
        | inst_slt | inst_sltu | inst_slti | inst_sltui
        | inst_jirl | inst_beq | inst_bne | inst_bge | inst_bgeu | inst_blt | inst_bltu
        | inst_st_w | inst_st_h | inst_st_b | inst_ld_w | inst_ld_h | inst_ld_b
        | inst_ld_bu | inst_ld_hu | inst_cpucfg | inst_cacop;
    // When source 1 is unused its address is a don't-care because every
    // consumer is gated by the decoded source-enable.  Default directly to
    // rj and keep only the CSR rd exception, avoiding the wide instruction-
    // class OR before the asynchronous register-file read address.
    assign RegFile_r_addr1 = inst_csr ? rd : rj;

    assign sel_rf_r_addr_2[1] = inst_add_w | inst_sub_w
        | inst_mul_w | inst_mulh_w | inst_mulh_wu
        | inst_div_w | inst_div_wu | inst_mod_w | inst_mod_wu
        | inst_or | inst_nor | inst_and | inst_xor
        | inst_srl_w | inst_sll_w | inst_sra_w
        | inst_slt | inst_sltu;
    assign sel_rf_r_addr_2[0] = inst_beq | inst_bne | inst_bge | inst_bgeu | inst_blt | inst_bltu
        | inst_st_w | inst_st_h | inst_st_b;
    // Register-register operations use rk, branches/stores use rd, and
    // CSRXCHG uses rj.  The address is likewise irrelevant when source 2 is
    // disabled, so the large register-register class decode is unnecessary.
    assign RegFile_r_addr2 = sel_rf_r_addr_2[0] ? rd :
                             inst_csrxchg ? rj : rk;

    assign sel_rf_w_addr[1] = inst_addi_w | inst_add_w | inst_sub_w
        | inst_mul_w | inst_mulh_w | inst_mulh_wu
        | inst_div_w | inst_div_wu | inst_mod_w | inst_mod_wu
        | inst_or | inst_ori | inst_nor | inst_andi | inst_and | inst_xor | inst_xori
        | inst_srl_w | inst_srli_w | inst_sll_w | inst_slli_w | inst_sra_w | inst_srai_w
        | inst_lu12i_w | inst_pcaddu12i
        | inst_slt | inst_slti | inst_sltu | inst_sltui | inst_jirl
        | inst_ld_w | inst_ld_h | inst_ld_b | inst_ld_bu | inst_ld_hu;
    assign sel_rf_w_addr[0] = inst_bl;
    // All writing instructions target rd except BL, which writes r1.  The
    // address is a don't-care when sel_rf_w_en is low.
    assign RegFile_w_addr = inst_bl ? 5'b0_0001 : rd;

    /////////////////////////////////////////////////////////////
    /// 立即数
    assign immediate = (inst_addi_w | inst_st_w | inst_ld_w | inst_st_h | inst_ld_h | inst_st_b | inst_ld_b | inst_ld_bu | inst_ld_hu | inst_slti | inst_sltui) ? {{20{inst[21]}}, inst[21:10]} :
                       (inst_ori | inst_andi | inst_xori) ? {20'b0, inst[21:10]} :
                       (inst_srli_w | inst_slli_w | inst_srai_w) ? {27'b0, inst[14:10]} :
                       (inst_lu12i_w | inst_pcaddu12i) ? {inst[24:5], 12'b0} :
                       (inst_jirl | inst_beq | inst_bne | inst_bge | inst_bgeu | inst_blt | inst_bltu) ? {{14{inst[25]}}, inst[25:10], 2'b0} :
                       (inst_b | inst_bl) ? {{4{inst[9]}}, inst[9:0], inst[25:10], 2'b0} :
                       inst_cacop ? {{20{inst[21]}}, inst[21:10]} : 32'b0;

    /////////////////////////////////////////////////////////////
    /// BranchUnit源操作数选择
    assign sel_bu_src1 = inst_jirl | inst_beq | inst_bne | inst_bge | inst_bgeu | inst_blt | inst_bltu;
    assign sel_bu_src2 = inst_beq | inst_bne | inst_bge | inst_bgeu | inst_blt | inst_bltu;

    /////////////////////////////////////////////////////////////
    /// ALU控制信号
    assign op_mul_s_l = inst_mul_w;
    assign op_mul_s_h = inst_mulh_w;
    assign op_mul_u_h = inst_mulh_wu;
    assign op_div_s   = inst_div_w;
    assign op_div_u   = inst_div_wu;
    assign op_mod_s   = inst_mod_w;
    assign op_mod_u   = inst_mod_wu;
    assign op_lui     = inst_lu12i_w;
    assign op_sra     = inst_srai_w | inst_sra_w;
    assign op_srl     = inst_srli_w | inst_srl_w;
    assign op_sll     = inst_slli_w | inst_sll_w;
    assign op_xor     = inst_xor | inst_xori;
    assign op_or      = inst_or | inst_ori;
    assign op_nor     = inst_nor;
    assign op_and     = inst_and | inst_andi;
    assign op_sltu    = inst_sltu | inst_sltui;
    assign op_slt     = inst_slt | inst_slti;
    assign op_sub     = inst_sub_w;
    assign op_add     = inst_addi_w | inst_add_w | inst_jirl | inst_bl | inst_cpucfg | inst_csr
                      | inst_st_w | inst_ld_w | inst_st_h | inst_ld_h | inst_st_b | inst_ld_b
                      | inst_ld_bu | inst_ld_hu | inst_pcaddu12i;

    assign alu_op = {
        op_mul_s_l, op_mul_s_h, op_mul_u_h,
        op_div_s, op_div_u, op_mod_s, op_mod_u,
        op_lui, op_sra, op_srl, op_sll, op_xor, op_or, op_nor, op_and,
        op_sltu, op_slt, op_sub, op_add
    };

    /////////////////////////////////////////////////////////////
    /// ALU源操作数选择
    assign sel_alu_src1[1] = inst_addi_w | inst_add_w | inst_sub_w
        | inst_mul_w | inst_mulh_w | inst_mulh_wu
        | inst_div_w | inst_div_wu | inst_mod_w | inst_mod_wu
        | inst_or | inst_nor | inst_and | inst_xor
        | inst_ori | inst_andi | inst_xori
        | inst_srli_w | inst_slli_w | inst_srai_w
        | inst_srl_w | inst_sll_w | inst_sra_w
        | inst_slt | inst_sltu | inst_slti | inst_sltui
        | inst_st_w | inst_st_h | inst_st_b
        | inst_ld_w | inst_ld_h | inst_ld_b
        | inst_ld_bu | inst_ld_hu | inst_cpucfg | inst_csr | inst_cacop;
    assign sel_alu_src1[0] = inst_pcaddu12i | inst_bl | inst_jirl;

    assign sel_alu_src2[2] = inst_bl | inst_jirl;
    assign sel_alu_src2[1] = inst_add_w | inst_sub_w
        | inst_mul_w | inst_mulh_w | inst_mulh_wu
        | inst_div_w | inst_div_wu | inst_mod_w | inst_mod_wu
        | inst_or | inst_nor | inst_and | inst_xor
        | inst_srl_w | inst_sll_w | inst_sra_w
        | inst_slt | inst_sltu | inst_csrxchg;
    assign sel_alu_src2[0] = inst_addi_w | inst_ori | inst_andi | inst_xori
        | inst_srli_w | inst_slli_w | inst_srai_w
        | inst_slti | inst_sltui
        | inst_lu12i_w | inst_pcaddu12i
        | inst_st_w | inst_st_h | inst_st_b
        | inst_ld_w | inst_ld_h | inst_ld_b
        | inst_ld_bu | inst_ld_hu;

    /////////////////////////////////////////////////////////////
    /// 数据RAM控制信号
    assign sel_data_ram_we     = inst_st_b | inst_st_w | inst_st_h;
    assign sel_data_ram_en     = inst_st_b | inst_st_w | inst_st_h
                               | inst_ld_b | inst_ld_w | inst_ld_h
                               | inst_ld_bu | inst_ld_hu;
    assign sel_data_ram_extend = inst_ld_bu | inst_ld_hu;
    assign sel_data_ram_wd[1]  = inst_st_b | inst_ld_b | inst_ld_bu;
    assign sel_data_ram_wd[0]  = inst_st_h | inst_ld_h | inst_ld_hu;

    /////////////////////////////////////////////////////////////
    /// WB控制信号
    assign sel_rf_w_en = inst_addi_w | inst_add_w | inst_sub_w
        | inst_mul_w | inst_mulh_w | inst_mulh_wu
        | inst_div_w | inst_div_wu | inst_mod_w | inst_mod_wu
        | inst_or | inst_and | inst_xor | inst_nor
        | inst_ori | inst_andi | inst_xori
        | inst_srli_w | inst_slli_w | inst_srai_w
        | inst_srl_w | inst_sll_w | inst_sra_w
        | inst_lu12i_w | inst_pcaddu12i
        | inst_slt | inst_sltu
        | inst_slti | inst_sltui
        | inst_jirl | inst_bl | inst_cpucfg | inst_csr
        | inst_ld_w | inst_ld_b | inst_ld_h | inst_ld_hu | inst_ld_bu;

    assign sel_rf_w_data = inst_ld_w | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu;

    /////////////////////////////////////////////////////////////
    /// 旁路/唤醒信号
    // mul.w is forwarded from MEM instead of directly from EXE.  An
    // immediately dependent instruction waits one cycle, removing the
    // multiplier -> ID bypass -> EXE-register feedback path.
    assign sel_rf_w_data_valid_stage[2] = inst_mul_w;
    assign sel_rf_w_data_valid_stage[1] = inst_ld_w | inst_ld_b | inst_ld_h | inst_ld_hu | inst_ld_bu;
    assign sel_rf_w_data_valid_stage[0] = inst_addi_w | inst_add_w | inst_sub_w
        | inst_mulh_w | inst_mulh_wu
        | inst_div_w | inst_div_wu | inst_mod_w | inst_mod_wu
        | inst_or | inst_and | inst_xor | inst_nor
        | inst_ori | inst_andi | inst_xori
        | inst_srli_w | inst_slli_w | inst_srai_w
        | inst_srl_w | inst_sll_w | inst_sra_w
        | inst_lu12i_w | inst_pcaddu12i
        | inst_slt | inst_sltu
        | inst_slti | inst_sltui
        | inst_jirl | inst_bl | inst_cpucfg | inst_csr;

    /////////////////////////////////////////////////////////////
    /// 寄存器堆
    RegFile RF(
        .clk      (clk),
        .r_addr1  (RegFile_r_addr1),
        .r_addr2  (RegFile_r_addr2),
        .r_data1  (RegFile_r_data1),
        .r_data2  (RegFile_r_data2),
        .r_addr3  (simple1_rs1),
        .r_addr4  (simple1_rs2),
        .r_data3  (RegFile_r_data3),
        .r_data4  (RegFile_r_data4),
        .w_data   (w_data),
        .w_addr   (w_addr),
        .w_en     (w_en),
        .w_data2  (w_data2),
        .w_addr2  (w_addr2),
        .w_en2    (w_en2)
    );

    simple_alu_decode decode_simple0(
        .inst(inst), .pc(inst_PC), .valid(simple0),
        .rs1_used(simple0_rs1_used), .rs2_used(simple0_rs2_used),
        .rs1(simple0_rs1), .rs2(simple0_rs2), .rd(simple0_rd),
        .alu_op(simple0_alu_op), .src1(simple0_src1_base),
        .src2(simple0_src2_base)
    );

    simple_alu_decode decode_simple1(
        .inst(inst1), .pc(inst_PC1), .valid(simple1),
        .rs1_used(simple1_rs1_used), .rs2_used(simple1_rs2_used),
        .rs1(simple1_rs1), .rs2(simple1_rs2), .rd(simple1_rd),
        .alu_op(simple1_alu_op), .src1(simple1_src1_base),
        .src2(simple1_src2_base)
    );

    // Lane1 has no LSU or control-flow side effects.  Allow it to use otherwise
    // idle execution bandwidth beside a lane0 load/store or low-half multiply.
    // Div/mod, mulh, branches, CSR and cache operations remain serialized.
    assign lane0_pairable = simple0 | sel_data_ram_en | inst_mul_w;
    assign lane0_writes_rd = sel_rf_w_en;

    dual_issue_pair pair_check(
        .valid0(ID_valid), .valid1(ID_valid1),
        .lane0_pairable(lane0_pairable),
        .lane0_writes_rd(lane0_writes_rd), .simple1(simple1),
        .rs1_used1(simple1_rs1_used), .rs2_used1(simple1_rs2_used),
        .rs1_1(simple1_rs1), .rs2_1(simple1_rs2),
        .rd0(simple0_rd), .rd1(simple1_rd), .pair_valid(pair_valid)
    );

    ///////////////////////////////////////////////////////////
    /// BY_to_ID_bus 分解 (3级: EXE/MEM/WB, 每级40b)
    assign {
        EXE_RegFile_w_addr        , // 5
        EXE_RegFile_w_data        , // 32
        EXE_sel_RF_w_data_valid   , // 1
        EXE_valid                 , // 1
        EXE_sel_rf_w_en           , // 1
        MEM_RegFile_w_addr        , // 5
        MEM_RegFile_w_data        , // 32
        MEM_sel_RF_w_data_valid   , // 1
        MEM_valid                 , // 1
        MEM_sel_rf_w_en           , // 1
        WB_RegFile_w_addr         , // 5
        WB_RegFile_w_data         , // 32
        WB_sel_RF_w_data_valid    , // 1
        WB_valid                  , // 1
        WB_sel_rf_w_en              // 1
    } = BY_to_ID_bus;

    ///////////////////////////////////////////////////////////
    /// WB_to_ID_bus 分解
    assign {w_en2, w_data2, w_addr2, w_en, w_data, w_addr} = WB_to_ID_bus;

    assign {EXE1_w_addr, EXE1_w_data, EXE1_data_valid,
            EXE1_valid, EXE1_w_en} = EXE1_to_ID_bus;
    assign {MEM1_w_addr, MEM1_w_data, MEM1_data_valid,
            MEM1_valid, MEM1_w_en} = MEM1_to_ID_bus;
    assign {WB1_w_addr, WB1_w_data, WB1_data_valid,
            WB1_valid, WB1_w_en} = WB1_to_ID_bus;

    // Forwarded architectural operands used by CPUCFG, CSR and CACOP.
    assign rf1_forwarded =
        (RegFile_r_addr1==EXE1_w_addr && EXE1_w_addr!=5'b0 && EXE1_w_en && EXE1_valid) ? EXE1_w_data :
        (RegFile_r_addr1==EXE_RegFile_w_addr && EXE_RegFile_w_addr!=5'b0 && EXE_sel_rf_w_en && EXE_valid) ?
            (EXE_sel_RF_w_data_valid ? EXE_RegFile_w_data : 32'd0) :
        (RegFile_r_addr1==MEM1_w_addr && MEM1_w_addr!=5'b0 && MEM1_w_en && MEM1_valid) ? MEM1_w_data :
        (RegFile_r_addr1==MEM_RegFile_w_addr && MEM_RegFile_w_addr!=5'b0 && MEM_sel_rf_w_en && MEM_valid) ?
            (MEM_sel_RF_w_data_valid ? MEM_RegFile_w_data : 32'd0) :
        (RegFile_r_addr1==WB1_w_addr && WB1_w_addr!=5'b0 && WB1_w_en && WB1_valid) ? WB1_w_data :
        (RegFile_r_addr1==WB_RegFile_w_addr && WB_RegFile_w_addr!=5'b0 && WB_sel_rf_w_en && WB_valid) ?
            (WB_sel_RF_w_data_valid ? WB_RegFile_w_data : 32'd0) : RegFile_r_data1;

    assign rf2_forwarded =
        (RegFile_r_addr2==EXE1_w_addr && EXE1_w_addr!=5'b0 && EXE1_w_en && EXE1_valid) ? EXE1_w_data :
        (RegFile_r_addr2==EXE_RegFile_w_addr && EXE_RegFile_w_addr!=5'b0 && EXE_sel_rf_w_en && EXE_valid) ?
            (EXE_sel_RF_w_data_valid ? EXE_RegFile_w_data : 32'd0) :
        (RegFile_r_addr2==MEM1_w_addr && MEM1_w_addr!=5'b0 && MEM1_w_en && MEM1_valid) ? MEM1_w_data :
        (RegFile_r_addr2==MEM_RegFile_w_addr && MEM_RegFile_w_addr!=5'b0 && MEM_sel_rf_w_en && MEM_valid) ?
            (MEM_sel_RF_w_data_valid ? MEM_RegFile_w_data : 32'd0) :
        (RegFile_r_addr2==WB1_w_addr && WB1_w_addr!=5'b0 && WB1_w_en && WB1_valid) ? WB1_w_data :
        (RegFile_r_addr2==WB_RegFile_w_addr && WB_RegFile_w_addr!=5'b0 && WB_sel_rf_w_en && WB_valid) ?
            (WB_sel_RF_w_data_valid ? WB_RegFile_w_data : 32'd0) : RegFile_r_data2;

    // lane1 producers are always one-cycle simple ALU operations.  Program
    // order requires their value to take priority over the older lane0 value
    // from the same pipeline stage.
    assign lane1_rf1_forwarded =
        (simple1_rs1!=5'b0 && simple1_rs1==EXE1_w_addr && EXE1_w_en && EXE1_valid) ?
            EXE1_w_data :
        (simple1_rs1!=5'b0 && simple1_rs1==EXE_RegFile_w_addr && EXE_sel_rf_w_en && EXE_valid) ?
            EXE_RegFile_w_data :
        (simple1_rs1!=5'b0 && simple1_rs1==MEM1_w_addr && MEM1_w_en && MEM1_valid) ?
            MEM1_w_data :
        (simple1_rs1!=5'b0 && simple1_rs1==MEM_RegFile_w_addr && MEM_sel_rf_w_en && MEM_valid) ?
            MEM_RegFile_w_data :
        (simple1_rs1!=5'b0 && simple1_rs1==WB1_w_addr && WB1_w_en && WB1_valid) ?
            WB1_w_data :
        (simple1_rs1!=5'b0 && simple1_rs1==WB_RegFile_w_addr && WB_sel_rf_w_en && WB_valid) ?
            WB_RegFile_w_data : RegFile_r_data3;

    assign lane1_rf2_forwarded =
        (simple1_rs2!=5'b0 && simple1_rs2==EXE1_w_addr && EXE1_w_en && EXE1_valid) ?
            EXE1_w_data :
        (simple1_rs2!=5'b0 && simple1_rs2==EXE_RegFile_w_addr && EXE_sel_rf_w_en && EXE_valid) ?
            EXE_RegFile_w_data :
        (simple1_rs2!=5'b0 && simple1_rs2==MEM1_w_addr && MEM1_w_en && MEM1_valid) ?
            MEM1_w_data :
        (simple1_rs2!=5'b0 && simple1_rs2==MEM_RegFile_w_addr && MEM_sel_rf_w_en && MEM_valid) ?
            MEM_RegFile_w_data :
        (simple1_rs2!=5'b0 && simple1_rs2==WB1_w_addr && WB1_w_en && WB1_valid) ?
            WB1_w_data :
        (simple1_rs2!=5'b0 && simple1_rs2==WB_RegFile_w_addr && WB_sel_rf_w_en && WB_valid) ?
            WB_RegFile_w_data : RegFile_r_data4;

    assign lane0_lane1_producers_ready =
        (!simple1_rs1_used || simple1_rs1==5'b0 ? 1'b1 :
         (simple1_rs1==EXE1_w_addr && EXE1_w_en && EXE1_valid) ? EXE1_data_valid :
         (simple1_rs1==EXE_RegFile_w_addr && EXE_sel_rf_w_en && EXE_valid) ? EXE_sel_RF_w_data_valid :
         (simple1_rs1==MEM1_w_addr && MEM1_w_en && MEM1_valid) ? MEM1_data_valid :
         (simple1_rs1==MEM_RegFile_w_addr && MEM_sel_rf_w_en && MEM_valid) ? MEM_sel_RF_w_data_valid :
         (simple1_rs1==WB1_w_addr && WB1_w_en && WB1_valid) ? WB1_data_valid :
         (simple1_rs1==WB_RegFile_w_addr && WB_sel_rf_w_en && WB_valid) ? WB_sel_RF_w_data_valid : 1'b1) &&
        (!simple1_rs2_used || simple1_rs2==5'b0 ? 1'b1 :
         (simple1_rs2==EXE1_w_addr && EXE1_w_en && EXE1_valid) ? EXE1_data_valid :
         (simple1_rs2==EXE_RegFile_w_addr && EXE_sel_rf_w_en && EXE_valid) ? EXE_sel_RF_w_data_valid :
         (simple1_rs2==MEM1_w_addr && MEM1_w_en && MEM1_valid) ? MEM1_data_valid :
         (simple1_rs2==MEM_RegFile_w_addr && MEM_sel_rf_w_en && MEM_valid) ? MEM_sel_RF_w_data_valid :
         (simple1_rs2==WB1_w_addr && WB1_w_en && WB1_valid) ? WB1_data_valid :
         (simple1_rs2==WB_RegFile_w_addr && WB_sel_rf_w_en && WB_valid) ? WB_sel_RF_w_data_valid : 1'b1);
    assign lane1_operands_ready = lane0_lane1_producers_ready;
    assign lane1_src1 = simple1_rs1_used ? lane1_rf1_forwarded : simple1_src1_base;
    assign lane1_src2 = simple1_rs2_used ? lane1_rf2_forwarded : simple1_src2_base;

    always @(*) begin
        case (rf1_forwarded)
            32'h0000_0010: cpucfg_value = 32'h0000_0005; // L1 I$ + D$
            32'h0000_0011: cpucfg_value = 32'h0408_0000; // 16B, 256 sets, 1 way
            32'h0000_0012: cpucfg_value = 32'h040b_0001; // 16B, 2048 sets, 2 ways
            default:       cpucfg_value = 32'd0;
        endcase
    end

    always @(*) begin
        case (csr_num)
            14'h0000: csr_old_value = csr_crmd;
            14'h0180: csr_old_value = csr_dmw0;
            14'h0181: csr_old_value = csr_dmw1;
            default:  csr_old_value = 32'd0;
        endcase
    end

    assign csr_write_mask = inst_csrwr ? 32'hffff_ffff :
                            inst_csrxchg ? rf2_forwarded : 32'd0;
    assign csr_new_value  = (csr_old_value & ~csr_write_mask) |
                            (rf1_forwarded & csr_write_mask);

    always @(posedge clk) begin
        if (reset) begin
            csr_crmd <= 32'h0000_0008; // DA=1, PG=0 after reset
            csr_dmw0 <= 32'd0;
            csr_dmw1 <= 32'd0;
        end else if (id_fire && inst_csr) begin
            case (csr_num)
                14'h0000: csr_crmd <= csr_new_value;
                14'h0180: csr_dmw0 <= csr_new_value;
                14'h0181: csr_dmw1 <= csr_new_value;
                default: begin end
            endcase
        end
    end

    assign cacheop_capture = ID_valid & inst_cacop & operands_ready &
                             ~cacheop_pending & ~cacheop_complete &
                             ~pipeline_flush;
    assign cacheop_handshake = cacheop_pending & cacheop_ready;

    always @(posedge clk) begin
        if (reset || pipeline_flush) begin
            cacheop_pending <= 1'b0;
            cacheop_complete <= 1'b0;
            cacheop_code_r  <= 5'b0;
            cacheop_addr_r  <= 32'b0;
        end else if (cacheop_handshake) begin
            cacheop_pending <= 1'b0;
            cacheop_complete <= ~id_fire;
        end else if (cacheop_complete && id_fire) begin
            cacheop_complete <= 1'b0;
        end else if (cacheop_capture) begin
            cacheop_pending <= 1'b1;
            cacheop_code_r  <= rd;
            cacheop_addr_r  <= rf1_forwarded + immediate;
        end
    end

    assign cacheop_valid = cacheop_pending;
    assign cacheop_code  = cacheop_code_r;
    assign cacheop_addr  = cacheop_addr_r;

    ///////////////////////////////////////////////////////////
    /// WakeUP模块 (3级: EXE/MEM/WB)
    assign BY_to_WK_bus = {
        EXE_RegFile_w_addr        , // 5
        EXE_sel_RF_w_data_valid   , // 1
        EXE_valid                 , // 1
        EXE_sel_rf_w_en           , // 1
        MEM_RegFile_w_addr        , // 5
        MEM_sel_RF_w_data_valid   , // 1
        MEM_valid                 , // 1
        MEM_sel_rf_w_en           , // 1
        WB_RegFile_w_addr         , // 5
        WB_sel_RF_w_data_valid    , // 1
        WB_valid                  , // 1
        WB_sel_rf_w_en              // 1
    };

    WakeUP Wake_UP(
        .sel_alu_src1      (sel_alu_src1),
        .sel_alu_src2      (sel_alu_src2),
        .sel_bu_src1       (sel_bu_src1),
        .sel_bu_src2       (sel_bu_src2),
        .RegFile_r_addr1   (RegFile_r_addr1),
        .RegFile_r_addr2   (RegFile_r_addr2),
        .sel_data_ram_we   (sel_data_ram_we),
        .BY_to_WK_bus      (BY_to_WK_bus),
        .alu_src_1_ready   (alu_src_1_ready),
        .alu_src_2_ready   (alu_src_2_ready),
        .bu_src_1_ready    (bu_src_1_ready),
        .bu_src_2_ready    (bu_src_2_ready),
        .mem_w_data_ready  (mem_w_data_ready)
    );

    ///////////////////////////////////////////////////////////
    /// 分支预测检查
    ///////////////////////////////////////////////////////////
    /// BU源操作数旁路选择 (3级: EXE/MEM/WB)
    always@(*) begin
        if(sel_bu_src1)
            bu_src1 <= rf1_forwarded;
        else
            bu_src1 <= 32'b0;
    end

    always@(*) begin
        if(sel_bu_src2)
            bu_src2 <= rf2_forwarded;
        else
            bu_src2 <= 32'b0;
    end

    ///////////////////////////////////////////////////////////
    /// ALU源操作数旁路选择 (3级: EXE/MEM/WB)
    always@(*) begin
        if(inst_cpucfg)
            alu_src1 <= cpucfg_value;
        else if(inst_csr)
            alu_src1 <= csr_old_value;
        else if(sel_alu_src1[1])
            alu_src1 <= rf1_forwarded;
        else if(sel_alu_src1[0])
            alu_src1 <= inst_PC;
        else
            alu_src1 <= 32'b0;
    end

    always@(*) begin
        if(inst_cpucfg | inst_csr)
            alu_src2 <= 32'd0;
        else if(sel_alu_src2[1])
            alu_src2 <= rf2_forwarded;
        else if(sel_alu_src2[2])
            alu_src2 <= 32'h0000_0004;
        else if(sel_alu_src2[0])
            alu_src2 <= immediate;
        else
            alu_src2 <= 32'b0;
    end

    ///////////////////////////////////////////////////////////
    /// 数据RAM写数据旁路选择 (3级: EXE/MEM/WB)
    always@(*) begin
        if(sel_data_ram_we)
            data_ram_wdata <= rf2_forwarded;
        else
            data_ram_wdata <= 32'b0;
    end

    ///////////////////////////////////////////////////////////
    /// 发送数据
    // ID_to_EXE_bus格式保持与原7级版本一致 (162b):
    // The fields below are the original 162-bit payload, preceded by the
    // 196-bit EXE branch-resolution payload in the assignment.
    // {sel_rf_w_data_valid_stage(3), sel_rf_w_en(1), sel_rf_w_data(1),
    //  sel_data_ram_wd(2), sel_data_ram_extend(1), sel_data_ram_we(1),
    //  sel_data_ram_en(1), store_src_addr(5), data_ram_wdata(32), RegFile_w_addr(5),
    //  alu_op(19), alu_src2(32), alu_src1(32), inst_PC(32)}
    assign ID1_to_EXE_bus = {
        simple1_alu_op,           // 19
        lane1_src2,               // 32
        lane1_src1,               // 32
        simple1_rd,               // 5
        inst_PC1                  // 32
    };

    assign ID_to_EXE_bus = {
        br_op,                    // 4
        pred_PC,                  // 32
        branch_target,            // 32
        fallthrough_PC,           // 32
        immediate,                // 32: JIRL target offset
        bu_src2,                  // 32
        bu_src1,                  // 32
        sel_rf_w_data_valid_stage, // 3
        sel_rf_w_en,              // 1
        sel_rf_w_data,            // 1
        sel_data_ram_wd,          // 2
        sel_data_ram_extend,      // 1
        sel_data_ram_we,          // 1
        sel_data_ram_en,          // 1
        RegFile_r_addr2,           // 5: late MEM-to-store forwarding match
        data_ram_wdata,           // 32
        RegFile_w_addr,           // 5
        alu_op,                   // 19
        alu_src2,                 // 32
        alu_src1,                 // 32
        inst_PC                    // 32
    };

endmodule
