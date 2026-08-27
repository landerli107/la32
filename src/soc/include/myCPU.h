`ifndef MYCPU_H
    `define MYCPU_H

    // 指令类型，用独热码区分不同指令
    `define INST_TYPE_WD    46

    // 流水线间数据通信（5级流水线：IF->ID->EXE->MEM->WB）
    `define IF_TO_ID_BUS_WD     160 // {pred_PC, branch_target, PC+4, PC, inst}
    `define ID_TO_EXE_BUS_WD    363 // payload + store source register + branch metadata
    `define ID1_TO_EXE_BUS_WD   120 // {alu_op, src2, src1, rd, pc}
    `define EXE_TO_MEM_BUS_WD   111
    `define EXE1_TO_MEM_BUS_WD  69  // {result, rd, pc}
    `define MEM_TO_WB_BUS_WD    113
    `define MEM1_TO_WB_BUS_WD   69  // {result, rd, pc}
    `define WB_to_ID_bus_WD     76  // two ordered {we,data,addr} write ports

    `define ID_TO_IF_BUS_WD     33  // {br_taken_cancel(1), PC_fromID(32)}

    // Compact branch operation passed from ID to EXE.
    `define BR_OP_WD       4
    `define BR_NONE        4'd0
    `define BR_JIRL        4'd1
    `define BR_B           4'd2
    `define BR_BL          4'd3
    `define BR_EQ          4'd4
    `define BR_NE          4'd5
    `define BR_GE          4'd6
    `define BR_GEU         4'd7
    `define BR_LT          4'd8
    `define BR_LTU         4'd9

    // 旁路与流水级通信（3级旁路：EXE->MEM->WB）
    `define EXE_TO_BY_BUS_WD    40
    `define MEM_TO_BY_BUS_WD    82
    `define WB_TO_BY_BUS_WD     40

    `define BY_TO_ID_BUS_WD     120 // 3级 × 40b = 120b

    // Wake UP模块与流水级通信
    `define BY_TO_WK_BUS_WD     24  // 3级 × 8b = 24b

`endif
