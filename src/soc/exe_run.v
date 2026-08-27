/**
 * @file exe_run.v
 * @author refactored (5-stage version)
 * @brief EXE阶段组合逻辑：ALU计算、旁路信号生成
 */
`include "myCPU.h"
module exe_run(
    // 来自EXE_reg
    input  wire [`ID_TO_EXE_BUS_WD-1:0]  ID_to_EXE_reg_data,
    input  wire                          EXE_valid,

    // 流水线数据传送
    output wire [`EXE_TO_MEM_BUS_WD-1:0] EXE_to_MEM_bus,
    output wire [`EXE_TO_BY_BUS_WD-1:0]  EXE_to_BY_bus,
    output wire                          branch_redirect_valid,
    output wire [31:0]                   branch_redirect_pc,

    // Launch D-cache requests from EXE.  The synchronous cache lookup then
    // completes while the instruction advances into MEM, removing the fixed
    // MEM-stage bubble from every cache hit.
    output wire                          data_ram_en,
    output wire                          data_ram_prefetch_hint,
    output wire [31:0]                   data_ram_addr,
    output wire [31:0]                   data_ram_pc,
    output wire [ 2:0]                   data_ram_size,
    output wire [3:0]                    data_ram_w_en,
    output reg  [31:0]                   data_ram_w_data,
    input  wire                          data_ram_addr_ok,

    input  wire [4:0]                    mem_forward_addr,
    input  wire [31:0]                   mem_forward_data,
    input  wire                          mem_forward_valid,

    // 流水线控制
    input  wire                          MEM_allow_in,
    output wire                          EXE_to_MEM_valid,
    output wire                          EXE_allow_in
);

    // ID_to_EXE_reg 分解 (与ID_to_EXE_bus格式一致：162位)
    wire [`BR_OP_WD-1:0] br_op;
    wire [31:0] pred_PC;
    wire [31:0] branch_target;
    wire [31:0] fallthrough_PC;
    wire [31:0] branch_offset;
    wire [31:0] branch_src1;
    wire [31:0] branch_src2;

    wire [2:0]  sel_rf_w_data_valid_stage;
    wire        sel_rf_w_en;
    wire        sel_rf_w_data;
    wire [1:0]  sel_data_ram_wd;
    wire        sel_data_ram_extend;
    wire        sel_data_ram_we;
    wire        sel_data_ram_en;
    wire [4:0]  store_src_addr;
    wire [31:0] data_ram_wdata;
    wire [31:0] effective_store_wdata;
    wire        store_forward_hit;
    wire [31:0] direct_store_payload;
    wire [31:0] forward_store_payload;
    wire [4:0]  RegFile_w_addr;
    wire [18:0] alu_op;
    wire [31:0] alu_bu_src1;
    wire [31:0] alu_bu_src2;
    wire [31:0] inst_PC;

    // ALU结果
    wire [31:0] alu_result;
    wire [31:0] alu_fast_result;
    wire [31:0] data_addr_sum;
    wire        branch_redirect_raw;
    reg  [3:0]  data_ram_b_en;

    // 旁路信号
    wire EXE_sel_rf_w_data_valid;
    wire EXE_ready_go;

    ////////////////////////////////////////////////////////
    /// 流水线控制
    assign EXE_ready_go       = (~sel_data_ram_en) | data_ram_addr_ok;
    assign EXE_allow_in       = (~EXE_valid) | (EXE_ready_go & MEM_allow_in);
    assign EXE_to_MEM_valid   = EXE_ready_go & EXE_valid;

    ///////////////////////////////////////////////////////
    /// ID_to_EXE_reg 分解 (与ID_to_EXE_bus格式一致)
    // {sel_rf_w_data_valid_stage(3), sel_rf_w_en(1), sel_rf_w_data(1),
    //  sel_data_ram_wd(2), sel_data_ram_extend(1), sel_data_ram_we(1),
    //  sel_data_ram_en(1), store_src_addr(5), data_ram_wdata(32),
    //  RegFile_w_addr(5),
    //  alu_op(19), alu_bu_src2(32), alu_bu_src1(32), inst_PC(32)}
    assign {
        br_op,                     // 4
        pred_PC,                   // 32
        branch_target,             // 32
        fallthrough_PC,            // 32
        branch_offset,             // 32
        branch_src2,               // 32
        branch_src1,               // 32
        sel_rf_w_data_valid_stage, // 3
        sel_rf_w_en,              // 1
        sel_rf_w_data,            // 1
        sel_data_ram_wd,          // 2
        sel_data_ram_extend,      // 1
        sel_data_ram_we,          // 1
        sel_data_ram_en,          // 1
        store_src_addr,           // 5
        data_ram_wdata,           // 32
        RegFile_w_addr,           // 5
        alu_op,                   // 19
        alu_bu_src2,              // 32
        alu_bu_src1,              // 32
        inst_PC                    // 32
    } = ID_to_EXE_reg_data;

    ///////////////////////////////////////////////////////
    /// ALU
    alu ALU(
        .alu_op     (alu_op     ),
        .alu_src1   (alu_bu_src1),
        .alu_src2   (alu_bu_src2),
        .alu_result (alu_result ),
        .alu_fast_result(alu_fast_result)
    );

    BranchResolveEXE branch_resolve(
        .br_op           (br_op),
        .pred_PC         (pred_PC),
        .branch_target   (branch_target),
        .fallthrough_PC  (fallthrough_PC),
        .branch_src1     (branch_src1),
        .branch_src2     (branch_src2),
        .jirl_offset     (branch_offset),
        .resolved_PC     (branch_redirect_pc),
        .redirect        (branch_redirect_raw)
    );

    assign branch_redirect_valid = EXE_valid & branch_redirect_raw;

    // Start the memory request one pipeline stage earlier than its response.
    // Do not let the cache consume an EXE request unless the older MEM-stage
    // instruction can advance on this edge.  This makes speculative address
    // slot availability safe even while a previous load is being resolved.
    assign data_ram_en   = EXE_valid & sel_data_ram_en & MEM_allow_in;
    // Registered EXE load hint; never acknowledges an architectural request.
    assign data_ram_prefetch_hint = EXE_valid & sel_data_ram_en &
                                    !sel_data_ram_we;
    // Every load/store uses the ordinary address adder (alu_op[0]).  Bypass
    // the final mul-vs-fast-result mux here so the multiplier can never enter
    // the EXE -> D-cache address timing path.
    assign data_addr_sum = alu_bu_src1 + alu_bu_src2;
    assign data_ram_addr = data_addr_sum;
    assign data_ram_pc   = inst_PC;
    assign data_ram_size = sel_data_ram_wd[1] ? 3'd0 :
                           (sel_data_ram_wd[0] ? 3'd1 : 3'd2);

    always @(*) begin
        if (sel_data_ram_wd[1]) begin
            case (data_addr_sum[1:0])
                2'b00: data_ram_b_en = 4'b0001;
                2'b01: data_ram_b_en = 4'b0010;
                2'b10: data_ram_b_en = 4'b0100;
                default: data_ram_b_en = 4'b1000;
            endcase
        end else if (sel_data_ram_wd[0]) begin
            data_ram_b_en = (data_addr_sum[1:0] == 2'b00) ?
                            4'b0011 : 4'b1100;
        end else begin
            data_ram_b_en = 4'b1111;
        end
    end

    assign data_ram_w_en = (EXE_valid & sel_data_ram_we) ?
                           data_ram_b_en : 4'b0000;

    assign store_forward_hit = sel_data_ram_we &&
        (store_src_addr != 5'b0) && mem_forward_valid &&
        (mem_forward_addr == store_src_addr);
    assign effective_store_wdata = store_forward_hit ?
                                   mem_forward_data : data_ram_wdata;

    // Format the registered source and the live MEM-forward source in
    // parallel, then select once at the output.  The former ordering selected
    // a 32-bit source first and placed the byte/halfword replication mux after
    // the complete load-response forwarding cone.
    assign direct_store_payload = sel_data_ram_wd[1] ?
        {4{data_ram_wdata[7:0]}} :
        sel_data_ram_wd[0] ? {2{data_ram_wdata[15:0]}} : data_ram_wdata;
    assign forward_store_payload = sel_data_ram_wd[1] ?
        {4{mem_forward_data[7:0]}} :
        sel_data_ram_wd[0] ? {2{mem_forward_data[15:0]}} : mem_forward_data;

    always @(*) begin
        data_ram_w_data = store_forward_hit ?
                          forward_store_payload : direct_store_payload;
    end

    ///////////////////////////////////////////////////////
    /// 旁路信号生成
    assign EXE_sel_rf_w_data_valid = EXE_ready_go & EXE_valid & sel_rf_w_data_valid_stage[0];

    ///////////////////////////////////////////////////////
    /// 发送数据
    assign EXE_to_MEM_bus = {
        sel_rf_w_data_valid_stage, // 3
        sel_rf_w_en,              // 1
        sel_rf_w_data,            // 1
        sel_data_ram_wd,          // 2
        sel_data_ram_extend,      // 1
        sel_data_ram_we,          // 1
        sel_data_ram_en,          // 1
        effective_store_wdata,   // 32
        RegFile_w_addr,           // 5
        alu_result,               // 32
        inst_PC                    // 32
    };

    assign EXE_to_BY_bus = {
        RegFile_w_addr            , // 5
        alu_fast_result           , // 32
        EXE_sel_rf_w_data_valid   , // 1
        EXE_valid                 , // 1
        sel_rf_w_en                 // 1
    };

endmodule
