/**
 * @file ALU.v
 * @author refactored (5-stage version)
 * @brief 算术逻辑单元
 */
`include "./include/myCPU.h"

module alu(
    input  wire [18:0] alu_op,     // 19位独热码操作码
    input  wire [31:0] alu_src1,
    input  wire [31:0] alu_src2,
    output wire [31:0] alu_result,
    output wire [31:0] alu_fast_result
);

    // Avoid the multi-DSP cascade used by the default implementation.  The
    // low 32-bit mul.w result is implemented in LUT/carry logic in one cycle.
    (* use_dsp = "no" *) wire [31:0] mul_result = alu_src1 * alu_src2;

    assign alu_fast_result =
        (alu_op[ 0]) ? (alu_src1 +          alu_src2) :
        (alu_op[ 1]) ? (alu_src1 -          alu_src2) :
        (alu_op[ 2]) ? ($signed(alu_src1) < $signed(alu_src2) ? 32'b1 : 32'b0) :
        (alu_op[ 3]) ? (alu_src1 <          alu_src2  ? 32'b1 : 32'b0) :
        (alu_op[ 4]) ? (alu_src1 &          alu_src2) :
        (alu_op[ 5]) ? (~(alu_src1 |         alu_src2)) :
        (alu_op[ 6]) ? (alu_src1 |          alu_src2) :
        (alu_op[ 7]) ? (alu_src1 ^          alu_src2) :
        (alu_op[ 8]) ? (alu_src1 <<         alu_src2[4:0]) :
        (alu_op[ 9]) ? (alu_src1 >>         alu_src2[4:0]) :
        (alu_op[10]) ? ($signed(alu_src1) >>> alu_src2[4:0]) :
        (alu_op[11]) ? (alu_src2) :          // lu12i.w: result = imm20 << 12
        (alu_op[12]) ? 32'b0 :               // mod.wu (未实现)
        (alu_op[13]) ? 32'b0 :               // mod.w  (未实现)
        (alu_op[14]) ? 32'b0 :               // div.wu (未实现)
        (alu_op[15]) ? 32'b0 :               // div.w  (未实现)
        (alu_op[16]) ? 32'b0 :               // mulh.wu(未实现)
        (alu_op[17]) ? 32'b0 : 32'b0;         // mulh.w (未实现)

    assign alu_result = alu_op[18] ? mul_result : alu_fast_result;

endmodule
