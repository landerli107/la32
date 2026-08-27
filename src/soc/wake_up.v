/**
 * @file wake_up.v
 * @author ykykzq (5-stage version)
 * @brief WakeUP检测源操作数是否准备好，控制是否唤醒当前指令。
 *        5级流水线版本：检查3级 (EXE/MEM/WB)
 */
`include "myCPU.h"
module WakeUP(
    // 源操作数的控制信号与读取的寄存器号
    input  wire[ 1: 0]					sel_alu_src1,
    input  wire[ 2: 0]					sel_alu_src2,
    input  wire							sel_bu_src1,
    input  wire							sel_bu_src2,
    input  wire[ 4: 0]					RegFile_r_addr1,
    input  wire[ 4: 0]					RegFile_r_addr2,
    input  wire							sel_data_ram_we,

    // 流水线数据交互
    input  wire[`BY_TO_WK_BUS_WD-1:0]	BY_to_WK_bus,

    // 输出源操作数可以获得信号
    output reg 							alu_src_1_ready,
    output reg							alu_src_2_ready,
    output reg 							bu_src_1_ready,
    output reg							bu_src_2_ready,
    output reg 							mem_w_data_ready
    );
    // EXE
    wire [ 4: 0]	EXE_RegFile_w_addr	;
    wire 	EXE_sel_RF_w_data_valid		;
    wire	EXE_valid					;
    wire 	EXE_sel_rf_w_en				;

    // MEM (合并原PMEM+MEM)
    wire [ 4: 0]MEM_RegFile_w_addr		;
    wire MEM_sel_RF_w_data_valid		;
    wire MEM_valid						;
    wire MEM_sel_rf_w_en				;

    // WB
    wire [ 4: 0]	WB_RegFile_w_addr	;
    wire WB_sel_RF_w_data_valid			;
    wire WB_valid						;
    wire WB_sel_rf_w_en				 	;

    /////////////////////////////////////////////////////////////////
    /// 检测是否已经准备好

    // bu_src1
    always@(*)
    begin
        if(sel_bu_src1)
            if(RegFile_r_addr1==EXE_RegFile_w_addr && EXE_RegFile_w_addr!=5'b0 && EXE_sel_rf_w_en && EXE_valid)
                if(EXE_sel_RF_w_data_valid)
                    bu_src_1_ready<=1'b1;
                else
                    bu_src_1_ready<=1'b0;
            else if(RegFile_r_addr1==MEM_RegFile_w_addr && MEM_RegFile_w_addr!=5'b0 && MEM_sel_rf_w_en && MEM_valid)
                if(MEM_sel_RF_w_data_valid)
                    bu_src_1_ready<=1'b1;
                else
                    bu_src_1_ready<=1'b0;
            else if(RegFile_r_addr1==WB_RegFile_w_addr && WB_RegFile_w_addr!=5'b0 && WB_sel_rf_w_en && WB_valid)
                if(WB_sel_RF_w_data_valid)
                    bu_src_1_ready<=1'b1;
                else
                    bu_src_1_ready<=1'b0;
            else
                bu_src_1_ready<=1'b1;
        else
            bu_src_1_ready<=1'b1;
    end
    // bu_src2
    always@(*)
    begin
        if(sel_bu_src2)
            if(RegFile_r_addr2==EXE_RegFile_w_addr && EXE_RegFile_w_addr!=5'b0 && EXE_sel_rf_w_en && EXE_valid)
                if(EXE_sel_RF_w_data_valid)
                    bu_src_2_ready<=1'b1;
                else
                    bu_src_2_ready<=1'b0;
            else if(RegFile_r_addr2==MEM_RegFile_w_addr && MEM_RegFile_w_addr!=5'b0 && MEM_sel_rf_w_en && MEM_valid)
                if(MEM_sel_RF_w_data_valid)
                    bu_src_2_ready<=1'b1;
                else
                    bu_src_2_ready<=1'b0;
            else if(RegFile_r_addr2==WB_RegFile_w_addr && WB_RegFile_w_addr!=5'b0 && WB_sel_rf_w_en && WB_valid)
                if(WB_sel_RF_w_data_valid)
                    bu_src_2_ready<=1'b1;
                else
                    bu_src_2_ready<=1'b0;
            else
                bu_src_2_ready<=1'b1;
        else
            bu_src_2_ready<=1'b1;
    end

    // alu_src_1
    always@(*)
    begin
        if(sel_alu_src1[1])
            if(RegFile_r_addr1==EXE_RegFile_w_addr && EXE_RegFile_w_addr!=5'b0 && EXE_sel_rf_w_en && EXE_valid)
                if(EXE_sel_RF_w_data_valid)
                    alu_src_1_ready<=1'b1;
                else
                    alu_src_1_ready<=1'b0;
            else if(RegFile_r_addr1==MEM_RegFile_w_addr && MEM_RegFile_w_addr!=5'b0 && MEM_sel_rf_w_en && MEM_valid)
                if(MEM_sel_RF_w_data_valid)
                    alu_src_1_ready<=1'b1;
                else
                    alu_src_1_ready<=1'b0;
            else if(RegFile_r_addr1==WB_RegFile_w_addr && WB_RegFile_w_addr!=5'b0 && WB_sel_rf_w_en && WB_valid)
                if(WB_sel_rf_w_en)
                    alu_src_1_ready<=1'b1;
                else
                    alu_src_1_ready<=1'b0;
            else
                alu_src_1_ready<=1'b1;
        else
            alu_src_1_ready<=1'b1;
    end

    // alu_src_2
    always@(*)
    begin
        if(sel_alu_src2[1])
            if(RegFile_r_addr2==EXE_RegFile_w_addr && EXE_RegFile_w_addr!=5'b0 && EXE_sel_rf_w_en && EXE_valid)
                if(EXE_sel_RF_w_data_valid)
                    alu_src_2_ready<=1'b1;
                else
                    alu_src_2_ready<=1'b0;
            else if(RegFile_r_addr2==MEM_RegFile_w_addr && MEM_RegFile_w_addr!=5'b0 && MEM_sel_rf_w_en && MEM_valid)
                if(MEM_sel_RF_w_data_valid)
                    alu_src_2_ready<=1'b1;
                else
                    alu_src_2_ready<=1'b0;
            else if(RegFile_r_addr2==WB_RegFile_w_addr && WB_RegFile_w_addr!=5'b0 && WB_sel_rf_w_en && WB_valid)
                if(WB_sel_rf_w_en)
                    alu_src_2_ready<=1'b1;
                else
                    alu_src_2_ready<=1'b0;
            else
                alu_src_2_ready<=1'b1;
        else
            alu_src_2_ready<=1'b1;
    end

    // mem_w_data_ready
    always@(*)
    begin
        if(sel_data_ram_we)
            if(RegFile_r_addr2==EXE_RegFile_w_addr && EXE_RegFile_w_addr!=5'b0 && EXE_sel_rf_w_en && EXE_valid)
                // Store data is not needed for its address calculation.  Let
                // the store enter EXE and take a late forward from MEM when
                // the immediately preceding load completes.
                mem_w_data_ready<=1'b1;
            else if(RegFile_r_addr2==MEM_RegFile_w_addr && MEM_RegFile_w_addr!=5'b0 && MEM_sel_rf_w_en && MEM_valid)
                if(MEM_sel_RF_w_data_valid)
                    mem_w_data_ready<=1'b1;
                else
                    mem_w_data_ready<=1'b0;
            else if(RegFile_r_addr2==WB_RegFile_w_addr && WB_RegFile_w_addr!=5'b0 && WB_sel_rf_w_en && WB_valid)
                if(WB_sel_RF_w_data_valid)
                    mem_w_data_ready<=1'b1;
                else
                    mem_w_data_ready<=1'b0;
            else
                mem_w_data_ready<=1'b1;
        else
            mem_w_data_ready<=1'b1;
    end

    /////////////////////////////////////////////////////////////////
    /// 流水线数据交互

    // BY_to_WK_bus中应该包括从ID阶段之后 所有阶段 的寄存器写入信息
    // 5级流水线：EXE(8) + MEM(8) + WB(8) = 24b
    assign {
        // EXE阶段信号
        EXE_RegFile_w_addr			,//5
        EXE_sel_RF_w_data_valid		,//1
        EXE_valid					,//1
        EXE_sel_rf_w_en				,//1
        // MEM阶段信号
        MEM_RegFile_w_addr			,//5
        MEM_sel_RF_w_data_valid		,//1
        MEM_valid					,//1
        MEM_sel_rf_w_en				,//1
        // WB阶段信号
        WB_RegFile_w_addr			,//5
        WB_sel_RF_w_data_valid		,//1
        WB_valid					,//1
        WB_sel_rf_w_en				 //1
    }=BY_to_WK_bus;

endmodule
