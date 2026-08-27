`include "myCPU.h"

// Timing-local decoder used only by the conservative dual-issue policy.
// It recognizes single-cycle integer ALU operations and exposes explicit
// source-use bits so pair hazards never depend on unused instruction fields.
module simple_alu_decode(
    input  wire [31:0] inst,
    input  wire [31:0] pc,
    output wire        valid,
    output wire        rs1_used,
    output wire        rs2_used,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  rd,
    output wire [18:0] alu_op,
    output wire [31:0] src1,
    output wire [31:0] src2
);
    wire [21:0] op22 = inst[31:10];
    wire [16:0] op17 = inst[31:15];
    wire [ 9:0] op10 = inst[31:22];
    wire [ 6:0] op07 = inst[31:25];
    wire [4:0] rk = inst[14:10];
    wire [4:0] rj = inst[9:5];

    wire addi   = op10 == 10'b00_0000_1010;
    wire add    = op17 == 17'b0_0000_0000_0010_0000;
    wire sub_op = op17 == 17'b0_0000_0000_0010_0010;
    wire or_op  = op17 == 17'b0_0000_0000_0010_1010;
    wire ori    = op10 == 10'b00_0000_1110;
    wire nor_op = op17 == 17'b0_0000_0000_0010_1000;
    wire andi   = op10 == 10'b00_0000_1101;
    wire and_op = op17 == 17'b0_0000_0000_0010_1001;
    wire xor_op = op17 == 17'b0_0000_0000_0010_1011;
    wire xori   = op10 == 10'b00_0000_1111;
    wire srl_op = op17 == 17'b0_0000_0000_0010_1111;
    wire srli   = op17 == 17'b0_0000_0000_1000_1001;
    wire sll_op = op17 == 17'b0_0000_0000_0010_1110;
    wire slli   = op17 == 17'b0_0000_0000_1000_0001;
    wire sra_op = op17 == 17'b0_0000_0000_0011_0000;
    wire srai   = op17 == 17'b0_0000_0000_1001_0001;
    wire lu12i  = op07 == 7'b000_1010;
    wire pcaddu = op07 == 7'b000_1110;
    wire slt_op = op17 == 17'b0_0000_0000_0010_0100;
    wire slti   = op10 == 10'b00_0000_1000;
    wire sltu_op= op17 == 17'b0_0000_0000_0010_0101;
    wire sltui  = op10 == 10'b00_0000_1001;

    wire reg_reg = add | sub_op | or_op | nor_op | and_op | xor_op |
                   srl_op | sll_op | sra_op | slt_op | sltu_op;
    wire imm12_signed = addi | slti | sltui;
    wire imm12_unsigned = ori | andi | xori;
    wire shift_imm = srli | slli | srai;

    assign valid = reg_reg | imm12_signed | imm12_unsigned | shift_imm |
                   lu12i | pcaddu;
    assign rs1_used = reg_reg | imm12_signed | imm12_unsigned | shift_imm;
    assign rs2_used = reg_reg;
    assign rs1 = rj;
    assign rs2 = rk;
    assign rd = inst[4:0];

    wire [31:0] imm = imm12_signed ? {{20{inst[21]}}, inst[21:10]} :
                      imm12_unsigned ? {20'b0, inst[21:10]} :
                      shift_imm ? {27'b0, inst[14:10]} :
                      (lu12i | pcaddu) ? {inst[24:5], 12'b0} : 32'b0;

    assign src1 = pcaddu ? pc : 32'b0;
    assign src2 = reg_reg ? 32'b0 : imm;
    assign alu_op = {
        1'b0,                 // mul
        6'b0,                 // mulh/div/mod
        lu12i,
        (sra_op | srai),
        (srl_op | srli),
        (sll_op | slli),
        (xor_op | xori),
        (or_op | ori),
        nor_op,
        (and_op | andi),
        (sltu_op | sltui),
        (slt_op | slti),
        sub_op,
        (add | addi | pcaddu)
    };
endmodule
