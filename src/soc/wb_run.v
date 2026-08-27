/**
 * @file wb_run.v
 * @author refactored (5-stage version)
 * @brief WB阶段组合逻辑：写回数据选择与扩展
 */
`include "myCPU.h"
module wb_run(
    // 来自WB_reg
    input  wire [`MEM_TO_WB_BUS_WD-1:0]  MEM_to_WB_reg_data,
    input  wire                          WB_valid,
    input  wire [37:0]                   WB1_to_RF_bus,

    // 流水级数据交互
    output wire [`WB_to_ID_bus_WD-1:0]   WB_to_ID_bus,
    output wire [`WB_TO_BY_BUS_WD-1:0]   WB_to_BY_bus,

    // debug接口
    output wire [31:0] debug_wb_pc,
    output wire [3:0]  debug_wb_rf_we,
    output wire [4:0]  debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata,

    // 流水线控制
    output wire                           WB_allow_in
);

    // MEM_to_WB_reg 分解
    wire [2:0]  sel_rf_w_data_valid_stage;
    wire        sel_rf_w_en;
    wire        sel_rf_w_data;
    wire [1:0]  sel_data_ram_wd;
    wire        sel_data_ram_extend;
    wire [3:0]  data_ram_b_en;
    wire [31:0] data_ram_r_data;
    wire [4:0]  RegFile_w_addr;
    wire [31:0] alu_result;
    wire [31:0] inst_PC;

    // 写回数据
    wire [31:0] RF_w_data_from_ALU;
    reg  [31:0] RF_w_data_from_RAM;
    wire [31:0] RegFile_w_data;

    // 控制
    wire WB_ready_go;
    wire WB_to_RF_valid;
    wire RegFile_w_en;

    // 旁路信号
    wire WB_sel_rf_w_data_valid;

    //////////////////////////////////////////////
    /// 流水线控制
    assign WB_ready_go     = 1'b1;
    assign WB_allow_in     = (~WB_valid) | (WB_ready_go);
    assign WB_to_RF_valid  = WB_valid & WB_ready_go;

    ///////////////////////////////////////////////
    /// MEM_to_WB_reg 分解
    assign {
        sel_rf_w_data_valid_stage, // 3
        sel_rf_w_en,              // 1
        sel_rf_w_data,            // 1
        sel_data_ram_wd,          // 2
        sel_data_ram_extend,      // 1
        data_ram_b_en,            // 4
        data_ram_r_data,          // 32
        RegFile_w_addr,           // 5
        alu_result,               // 32
        inst_PC                    // 32
    } = MEM_to_WB_reg_data;

    ///////////////////////////////////////////////
    /// 写回数据选择
    assign RegFile_w_en       = WB_to_RF_valid & sel_rf_w_en;
    assign RF_w_data_from_ALU = alu_result;

    always@(*) begin
        if(sel_data_ram_wd[1]) begin
            // byte
            case(data_ram_b_en)
                4'b0001: RF_w_data_from_RAM <= sel_data_ram_extend ? {24'b0, data_ram_r_data[ 7:0]} : {{24{data_ram_r_data[7]}}, data_ram_r_data[ 7:0]};
                4'b0010: RF_w_data_from_RAM <= sel_data_ram_extend ? {24'b0, data_ram_r_data[15:8]} : {{24{data_ram_r_data[15]}}, data_ram_r_data[15:8]};
                4'b0100: RF_w_data_from_RAM <= sel_data_ram_extend ? {24'b0, data_ram_r_data[23:16]} : {{24{data_ram_r_data[23]}}, data_ram_r_data[23:16]};
                4'b1000: RF_w_data_from_RAM <= sel_data_ram_extend ? {24'b0, data_ram_r_data[31:24]} : {{24{data_ram_r_data[31]}}, data_ram_r_data[31:24]};
                default: RF_w_data_from_RAM <= 32'b0;
            endcase
        end else if(sel_data_ram_wd[0]) begin
            // half-word
            if(data_ram_b_en==4'b0011)
                RF_w_data_from_RAM <= sel_data_ram_extend ? {16'b0, data_ram_r_data[15:0]} : {{16{data_ram_r_data[15]}}, data_ram_r_data[15:0]};
            else
                RF_w_data_from_RAM <= sel_data_ram_extend ? {16'b0, data_ram_r_data[31:16]} : {{16{data_ram_r_data[31]}}, data_ram_r_data[31:16]};
        end else
            RF_w_data_from_RAM <= data_ram_r_data;
    end

    assign RegFile_w_data = (RegFile_w_addr==5'b0_0000) ? 32'b0 :
                            sel_rf_w_data ? RF_w_data_from_RAM : RF_w_data_from_ALU;

    ///////////////////////////////////////////////
    /// 旁路信号
    assign WB_sel_rf_w_data_valid = WB_valid & WB_ready_go
        & (sel_rf_w_data_valid_stage[0] | sel_rf_w_data_valid_stage[1] | sel_rf_w_data_valid_stage[2]);

    ///////////////////////////////////////////////
    /// 发送数据
    assign WB_to_ID_bus = {
        WB1_to_RF_bus,
        RegFile_w_en,
        RegFile_w_data,
        RegFile_w_addr
    };

    assign WB_to_BY_bus = {
        RegFile_w_addr        , // 5
        RegFile_w_data        , // 32
        WB_sel_rf_w_data_valid, // 1
        WB_valid              , // 1
        sel_rf_w_en             // 1
    };

    ///////////////////////////////////////////////
    /// Debug接口
    assign debug_wb_pc       = inst_PC;
    assign debug_wb_rf_we    = {4{RegFile_w_en}};
    assign debug_wb_rf_wnum  = RegFile_w_addr;
    assign debug_wb_rf_wdata = RegFile_w_data;

endmodule
