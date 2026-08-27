`include "./include/myCPU.h"

// EXE-stage branch resolver. All inputs arrive through the ID/EXE register,
// so a producer's forwarding path ends at that register instead of continuing
// through the branch compare and into the IF PC register in the same cycle.
module BranchResolveEXE(
    input  wire [`BR_OP_WD-1:0] br_op,
    input  wire [31:0]          pred_PC,
    input  wire [31:0]          branch_target,
    input  wire [31:0]          fallthrough_PC,
    input  wire [31:0]          branch_src1,
    input  wire [31:0]          branch_src2,
    input  wire [31:0]          jirl_offset,
    output reg  [31:0]          resolved_PC,
    output wire                 redirect
);
    wire is_branch = (br_op != `BR_NONE);
    wire eq = (branch_src1 == branch_src2);
    wire signed_lt = ($signed(branch_src1) < $signed(branch_src2));
    wire unsigned_lt = (branch_src1 < branch_src2);
    wire pred_target_match = (pred_PC == branch_target);
    wire pred_fallthrough_match = (pred_PC == fallthrough_PC);
    reg redirect_next;

    always @(*) begin
        case (br_op)
            `BR_JIRL: resolved_PC = branch_src1 + jirl_offset;
            `BR_B,
            `BR_BL:   resolved_PC = branch_target;
            `BR_EQ:   resolved_PC = eq           ? branch_target : fallthrough_PC;
            `BR_NE:   resolved_PC = !eq          ? branch_target : fallthrough_PC;
            `BR_GE:   resolved_PC = !signed_lt   ? branch_target : fallthrough_PC;
            `BR_GEU:  resolved_PC = !unsigned_lt ? branch_target : fallthrough_PC;
            `BR_LT:   resolved_PC = signed_lt    ? branch_target : fallthrough_PC;
            `BR_LTU:  resolved_PC = unsigned_lt  ? branch_target : fallthrough_PC;
            default:  resolved_PC = fallthrough_PC;
        endcase
    end

    // Compare both conditional-branch destinations in parallel with the
    // branch condition.  Selecting a one-bit match result avoids placing the
    // pred_PC/resolved_PC comparator after the resolved_PC data mux.
    always @(*) begin
        case (br_op)
            `BR_JIRL: redirect_next = (pred_PC != (branch_src1 + jirl_offset));
            `BR_B,
            `BR_BL:   redirect_next = !pred_target_match;
            `BR_EQ:   redirect_next = eq
                                    ? !pred_target_match
                                    : !pred_fallthrough_match;
            `BR_NE:   redirect_next = !eq
                                    ? !pred_target_match
                                    : !pred_fallthrough_match;
            `BR_GE:   redirect_next = !signed_lt
                                    ? !pred_target_match
                                    : !pred_fallthrough_match;
            `BR_GEU:  redirect_next = !unsigned_lt
                                    ? !pred_target_match
                                    : !pred_fallthrough_match;
            `BR_LT:   redirect_next = signed_lt
                                    ? !pred_target_match
                                    : !pred_fallthrough_match;
            `BR_LTU:  redirect_next = unsigned_lt
                                    ? !pred_target_match
                                    : !pred_fallthrough_match;
            default:  redirect_next = is_branch && !pred_fallthrough_match;
        endcase
    end

    assign redirect = redirect_next;
endmodule
