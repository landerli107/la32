/**
 * @file if_run.v
 * @author refactored (5-stage version)
 * @brief IF阶段组合逻辑单元：PC计算、分支预测、取指控制
 */
`include "myCPU.h"
module if_run(
    input  wire          reset,
    // 来自IF_reg
    input  wire [31:0]   PC,
    input  wire          IF_valid,

    // 流水线数据传输
    input  wire [`ID_TO_IF_BUS_WD-1:0]  ID_to_IF_bus,
    output wire [`IF_TO_ID_BUS_WD-1:0]  IF_to_ID_bus,
    output wire [`IF_TO_ID_BUS_WD-1:0]  IF_to_ID_bus1,

    // 连接指令RAM
    output wire          inst_ram_en,
    output wire [31:0]   inst_ram_addr,
    output wire [3:0]    inst_ram_w_en,
    input  wire [31:0]   inst_ram_r_data,
    input  wire [31:0]   inst_ram_r_data1,
    input  wire          inst_ram_r_data1_valid,
    input  wire          inst_ram_data_ok,
    output wire          inst_ram_resp_ready,
    output wire [31:0]   inst_ram_w_data,

    // 流水线控制
    input  wire          ID_allow_in,
    output wire          IF_to_ID_valid,
    output wire          IF_to_ID_valid1,
    output wire          IF_allow_in,
    input  wire          sel_strcture_hazard,

    // 输出到IF_reg
    output wire [31:0]   next_PC,
    output wire          Pre_to_IF_valid,
    output wire          br_taken_cancel
);

    wire [31:0] PC_plus_4;
    wire [31:0] PC_fromID;
    wire [31:0] pred_PC;
    wire [31:0] branch_target;
    wire [31:0] cond_offset;
    wire [31:0] uncond_offset;
    wire [ 5:0] opcode_6;
    wire        is_b;
    wire        is_bl;
    wire        is_cond_branch;
    wire        predict_taken;
    wire        IF_ready_go;
    wire [31:0] PC1;
    wire [31:0] PC1_plus_4;
    wire [31:0] pred_PC1;
    wire [31:0] branch_target1;
    wire [31:0] cond_offset1;
    wire [31:0] uncond_offset1;
    wire [5:0]  opcode_6_1;
    wire        is_b1;
    wire        is_bl1;
    wire        is_cond_branch1;
    wire        predict_taken1;

    assign PC_plus_4 = PC + 3'b100;
    assign PC1 = PC_plus_4;
    assign PC1_plus_4 = PC + 4'd8;

    // Static BTFNT predictor.  Unconditional PC-relative branches are always
    // taken; backward conditional branches are predicted taken.  JIRL remains
    // predicted not-taken because its target depends on a register value.
    assign opcode_6       = inst_ram_r_data[31:26];
    assign is_b           = opcode_6 == 6'b01_0100;
    assign is_bl          = opcode_6 == 6'b01_0101;
    assign is_cond_branch = (opcode_6 == 6'b01_0110) || // beq
                            (opcode_6 == 6'b01_0111) || // bne
                            (opcode_6 == 6'b01_1000) || // blt
                            (opcode_6 == 6'b01_1001) || // bge
                            (opcode_6 == 6'b01_1010) || // bltu
                            (opcode_6 == 6'b01_1011);   // bgeu
    assign cond_offset    = {{14{inst_ram_r_data[25]}}, inst_ram_r_data[25:10], 2'b0};
    assign uncond_offset  = {{4{inst_ram_r_data[9]}}, inst_ram_r_data[9:0],
                             inst_ram_r_data[25:10], 2'b0};
    assign predict_taken  = is_b || is_bl || (is_cond_branch && inst_ram_r_data[25]);
    assign branch_target  = PC + ((is_b || is_bl) ? uncond_offset : cond_offset);
    assign pred_PC        = predict_taken ? branch_target : PC_plus_4;

    assign opcode_6_1       = inst_ram_r_data1[31:26];
    assign is_b1            = opcode_6_1 == 6'b01_0100;
    assign is_bl1           = opcode_6_1 == 6'b01_0101;
    assign is_cond_branch1  = (opcode_6_1 >= 6'b01_0110) &&
                              (opcode_6_1 <= 6'b01_1011);
    assign cond_offset1     = {{14{inst_ram_r_data1[25]}},
                               inst_ram_r_data1[25:10], 2'b0};
    assign uncond_offset1   = {{4{inst_ram_r_data1[9]}},
                               inst_ram_r_data1[9:0],
                               inst_ram_r_data1[25:10], 2'b0};
    assign predict_taken1   = is_b1 || is_bl1 ||
                              (is_cond_branch1 && inst_ram_r_data1[25]);
    assign branch_target1   = PC1 + ((is_b1 || is_bl1) ?
                                      uncond_offset1 : cond_offset1);
    assign pred_PC1         = predict_taken1 ? branch_target1 : PC1_plus_4;

    // 分支预测纠正
    assign br_taken_cancel = ID_to_IF_bus[32];
    assign PC_fromID       = ID_to_IF_bus[31:0];
    // A predicted-taken slot0 ends the fetch group.  Otherwise slot1, when
    // available, owns the next fetch PC and advances the front end by 8 bytes.
    assign next_PC         = br_taken_cancel ? PC_fromID :
                             (inst_ram_r_data1_valid && !predict_taken ?
                              pred_PC1 : pred_PC);

    // 流水线控制
    // A cache hit or an AXI refill may take multiple cycles.  Hold PC and the
    // IF valid bit until the instruction response is actually available.
    assign IF_ready_go     = inst_ram_data_ok & ~sel_strcture_hazard;
    assign IF_allow_in     = (~IF_valid) | (IF_ready_go & ID_allow_in);
    assign Pre_to_IF_valid = ~reset;
    // The response present in IF when an older branch redirects is a
    // wrong-path instruction.  Consume it from the cache but never mark it
    // valid for ID.
    assign IF_to_ID_valid  = IF_valid & IF_ready_go & ~br_taken_cancel;
    assign IF_to_ID_valid1 = IF_to_ID_valid & inst_ram_r_data1_valid &
                             ~predict_taken;
    // A response is consumed only when the same transfer is allowed to
    // advance (or be discarded by a redirect).  In particular, a structural
    // hazard must not acknowledge the cache while PC and IF/ID stay frozen.
    assign inst_ram_resp_ready = IF_valid & IF_ready_go & ID_allow_in;

    // 取指令RAM
    assign inst_ram_en     = IF_valid;
    assign inst_ram_addr   = PC;
    assign inst_ram_w_data = 32'b0;
    assign inst_ram_w_en   = 4'b0;

    // 流水线数据交互
    assign IF_to_ID_bus = {
        pred_PC          , // 32: prediction used for later verification
        branch_target    , // 32: precomputed PC-relative branch target
        PC_plus_4        , // 32: precomputed fall-through PC
        PC               , // 32
        inst_ram_r_data    // 32
    };

    assign IF_to_ID_bus1 = {
        pred_PC1,
        branch_target1,
        PC1_plus_4,
        PC1,
        inst_ram_r_data1
    };

endmodule
