// Asymmetric ordered pairing policy.  Lane0 may be an ALU, LSU, or mul.w
// instruction while lane1 remains a side-effect-free simple ALU operation.
// Both lanes still advance and stall together, so architectural completion
// remains in order.  Same-cycle RAW and WAW pairs serialize; WAR is safe because
// all four register operands are read before either instruction reaches WB.
module dual_issue_pair(
    input  wire       valid0,
    input  wire       valid1,
    input  wire       lane0_pairable,
    input  wire       lane0_writes_rd,
    input  wire       simple1,
    input  wire       rs1_used1,
    input  wire       rs2_used1,
    input  wire [4:0] rs1_1,
    input  wire [4:0] rs2_1,
    input  wire [4:0] rd0,
    input  wire [4:0] rd1,
    output wire       pair_valid
);
    wire raw = lane0_writes_rd && (rd0 != 5'b0) &&
               ((rs1_used1 && (rd0 == rs1_1)) ||
                (rs2_used1 && (rd0 == rs2_1)));
    wire waw = lane0_writes_rd && (rd0 != 5'b0) &&
               (rd1 != 5'b0) && (rd0 == rd1);

    assign pair_valid = valid0 && valid1 && lane0_pairable && simple1 &&
                        !raw && !waw;
endmodule
