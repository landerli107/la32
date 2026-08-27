/**
 * @file Bypassing.v
 * @author ykykzq (5-stage version)
 * @brief 获得来自ID阶段之后的各阶段的写寄存器相关信息，并传送到ID阶段
 *        5级流水线版本：3级旁路 (EXE/MEM/WB)
 */
`include "myCPU.h"
module Bypassing(
    // 流水线数据交互，需要包括ID阶段之后所有阶段的信息
    input  wire[`EXE_TO_BY_BUS_WD-1:0]	EXE_to_BY_bus,
    input wire[`MEM_TO_BY_BUS_WD-1:0]	MEM_to_BY_bus,
    input  wire[`WB_TO_BY_BUS_WD-1:0]	WB_to_BY_bus,

    // 将旁路数据传输到ID阶段
    output wire[`BY_TO_ID_BUS_WD-1:0]	BY_to_ID_bus,
    output wire [4:0]                    mem_forward_addr,
    output wire [31:0]                   mem_forward_data,
    output wire                          mem_forward_valid
    );

    // EXE
    wire [ 4: 0]	EXE_RegFile_w_addr	;
    wire [31: 0]	EXE_alu_result		;
    wire 	EXE_sel_RF_w_data_valid		;
    wire    EXE_valid                  ;
    wire 	EXE_sel_rf_w_en				;

    wire [31: 0]	EXE_RegFile_w_data	;

    // MEM (合并原PMEM+MEM)
    wire [ 2: 0]	MEM_sel_RF_w_data_valid_stage;
    wire [ 3: 0]	MEM_data_ram_b_en	;
    wire [ 4: 0]	MEM_RegFile_w_addr	;
    wire [31: 0]	MEM_data_ram_r_data	;
    wire [31: 0]	MEM_alu_result		;
    wire 	MEM_sel_RF_w_data_valid		;
    wire [ 1: 0]	MEM_sel_data_ram_wd			;
    wire 			MEM_sel_data_ram_extend	;
    wire 			MEM_valid			;
    wire 	MEM_sel_rf_w_en				;

    reg  [31: 0]	MEM_RegFile_w_data	;
    wire [31:0] MEM_ID_RegFile_w_data;

    // WB
    wire [ 4: 0]	WB_RegFile_w_addr	;
    wire [31: 0]	WB_RegFile_w_data	;
    wire WB_sel_RF_w_data_valid			;
    wire WB_valid                         ;
    wire WB_sel_rf_w_en				 	;

    /////////////////////////////////////////////////////////
    /// 筛选

    // 通过筛选信号，提前把写入数据筛选出来

    // EXE
    assign EXE_RegFile_w_data=(EXE_RegFile_w_addr==5'b0)?32'b0:EXE_alu_result;

    // MEM，需要处理半字读与字节读
    always@(*)
    begin
        if(MEM_RegFile_w_addr==5'b0_0000)
            MEM_RegFile_w_data<=32'b0;
        else if(MEM_sel_RF_w_data_valid_stage[0] |
                MEM_sel_RF_w_data_valid_stage[2])
            MEM_RegFile_w_data<=MEM_alu_result;
        else if(MEM_sel_data_ram_wd[1]==1)
            // byte
            if(MEM_data_ram_b_en==4'b0001)
                if(MEM_sel_data_ram_extend)
                    MEM_RegFile_w_data<={24'b0,MEM_data_ram_r_data[7:0]};
                else
                    MEM_RegFile_w_data<={{24{MEM_data_ram_r_data[7]}},MEM_data_ram_r_data[7:0]};
            else if(MEM_data_ram_b_en==4'b0010)
                if(MEM_sel_data_ram_extend)
                    MEM_RegFile_w_data<={24'b0,MEM_data_ram_r_data[15:8]};
                else
                    MEM_RegFile_w_data<={{24{MEM_data_ram_r_data[15]}},MEM_data_ram_r_data[15:8]};
            else if(MEM_data_ram_b_en==4'b0100)
                if(MEM_sel_data_ram_extend)
                    MEM_RegFile_w_data<={24'b0,MEM_data_ram_r_data[23:16]};
                else
                    MEM_RegFile_w_data<={{24{MEM_data_ram_r_data[23]}},MEM_data_ram_r_data[23:16]};
            else if(MEM_data_ram_b_en==4'b1000)
                if(MEM_sel_data_ram_extend)
                    MEM_RegFile_w_data<={24'b0,MEM_data_ram_r_data[31:24]};
                else
                    MEM_RegFile_w_data<={{24{MEM_data_ram_r_data[31]}},MEM_data_ram_r_data[31:24]};
            else
                MEM_RegFile_w_data<=32'b0;
        else if(MEM_sel_data_ram_wd[0]==1)
            // half-word
            if(MEM_data_ram_b_en==4'b0011)
                if(MEM_sel_data_ram_extend)
                    MEM_RegFile_w_data<={16'b0,MEM_data_ram_r_data[15: 0]};
                else
                    MEM_RegFile_w_data<={{16{MEM_data_ram_r_data[15]}},MEM_data_ram_r_data[15: 0]};
            else if(MEM_data_ram_b_en==4'b1100)
                if(MEM_sel_data_ram_extend)
                    MEM_RegFile_w_data<={16'b0,MEM_data_ram_r_data[31:16]};
                else
                    MEM_RegFile_w_data<={{16{MEM_data_ram_r_data[31]}},MEM_data_ram_r_data[31:16]};
            else
                MEM_RegFile_w_data<=32'b0;
        else
            MEM_RegFile_w_data<=MEM_data_ram_r_data;
    end

    // MEM-to-ID is enabled only for ALU/multiply or aligned full-word loads.
    // Narrow loads complete through WB, so their extraction mux must not sit
    // on the cache-to-ID timing path.
    assign MEM_ID_RegFile_w_data =
        (MEM_RegFile_w_addr == 5'b0) ? 32'b0 :
        ((MEM_sel_RF_w_data_valid_stage[0] |
          MEM_sel_RF_w_data_valid_stage[2]) ?
         MEM_alu_result : MEM_data_ram_r_data);

    /////////////////////////////////////////////////////////////
    /// 流水线数据交互

    // 接收
    assign {
        // EXE阶段信号
        EXE_RegFile_w_addr			,//5
        EXE_alu_result				,//32
        EXE_sel_RF_w_data_valid		,//1
        EXE_valid					,//1
        EXE_sel_rf_w_en				 //1
    }=EXE_to_BY_bus;

    assign {
        // MEM阶段信号
        MEM_sel_RF_w_data_valid_stage	,//3
        MEM_data_ram_b_en				,//4
        MEM_RegFile_w_addr				,//5
        MEM_data_ram_r_data				,//32
        MEM_alu_result					,//32
        MEM_sel_RF_w_data_valid			,//1
        MEM_sel_data_ram_wd				,//2
        MEM_sel_data_ram_extend			,//1
        MEM_valid						,//1
        MEM_sel_rf_w_en					 //1
    }=MEM_to_BY_bus;

    assign {
        // WB阶段信号
        WB_RegFile_w_addr			,//5
        WB_RegFile_w_data			,//32
        WB_sel_RF_w_data_valid		,//1
        WB_valid					,//1
        WB_sel_rf_w_en				 //1
    }=WB_to_BY_bus;

    // A store already in EXE can consume a just-completed MEM result.
    assign mem_forward_addr  = MEM_RegFile_w_addr;
    assign mem_forward_data  = MEM_ID_RegFile_w_data;
    assign mem_forward_valid = MEM_valid & MEM_sel_rf_w_en &
                               MEM_sel_RF_w_data_valid;

    // 发送
    assign BY_to_ID_bus={
        // EXE阶段信号
        EXE_RegFile_w_addr			,//5
        EXE_alu_result				,//32
        EXE_sel_RF_w_data_valid		,//1
        EXE_valid					,//1
        EXE_sel_rf_w_en				,//1
        // MEM阶段信号
        MEM_RegFile_w_addr			,//5
        MEM_ID_RegFile_w_data		,//32
        MEM_sel_RF_w_data_valid		,//1
        MEM_valid					,//1
        MEM_sel_rf_w_en				,//1
        // WB阶段信号
        WB_RegFile_w_addr			,//5
        WB_RegFile_w_data			,//32
        WB_sel_RF_w_data_valid		,//1
        WB_valid					,//1
        WB_sel_rf_w_en				 //1
    };

endmodule
