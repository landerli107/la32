// Simulation-visible performance accounting.  The instance is guarded by
// SYNTHESIS in YK_Core so these counters never affect FPGA resources or timing.
module dual_issue_stats (
    input  wire       clk,
    input  wire       reset,
    input  wire       slot0_issue,
    input  wire       slot1_issue,
    input  wire       slot1_present,
    input  wire       slot0_commit,
    input  wire       slot1_commit,
    input  wire       pair_raw_block,
    input  wire       pair_waw_block,
    input  wire       lane1_unsupported_block,
    input  wire       lsu_structural_block,
    input  wire       frontend_no_instruction,
    input  wire       fetch_response_full,
    input  wire       queue_full,
    input  wire       queue_empty,
    input  wire       load_use_stall,
    input  wire       dcache_wait,
    input  wire       mul_div_wait,
    input  wire       branch_redirect,
    input  wire [2:0] branch_flushed_younger,
    output reg  [63:0] cycle_count,
    output reg  [63:0] retired_instruction_count,
    output reg  [63:0] slot0_issue_count,
    output reg  [63:0] slot1_issue_count,
    output reg  [63:0] pair_candidate_count,
    output reg  [63:0] pair_success_count,
    output reg  [63:0] pair_blocked_count,
    output reg  [63:0] raw_block_count,
    output reg  [63:0] waw_block_count,
    output reg  [63:0] lane1_unsupported_count,
    output reg  [63:0] lsu_structural_conflict_count,
    output reg  [63:0] frontend_no_instruction_count,
    output reg  [63:0] fetch_response_full_cycle_count,
    output reg  [63:0] queue_full_cycle_count,
    output reg  [63:0] queue_empty_cycle_count,
    output reg  [63:0] load_use_stall_count,
    output reg  [63:0] dcache_wait_cycle_count,
    output reg  [63:0] mul_div_wait_cycle_count,
    output reg  [63:0] branch_redirect_count,
    output reg  [63:0] branch_flushed_younger_count,
    output reg  [63:0] slot0_commit_count,
    output reg  [63:0] slot1_commit_count
);
    wire pair_candidate;
    assign pair_candidate = slot0_issue && slot1_present;

    always @(posedge clk) begin
        if (reset) begin
            cycle_count                        <= 64'd0;
            retired_instruction_count          <= 64'd0;
            slot0_issue_count                  <= 64'd0;
            slot1_issue_count                  <= 64'd0;
            pair_candidate_count               <= 64'd0;
            pair_success_count                 <= 64'd0;
            pair_blocked_count                 <= 64'd0;
            raw_block_count                    <= 64'd0;
            waw_block_count                    <= 64'd0;
            lane1_unsupported_count            <= 64'd0;
            lsu_structural_conflict_count       <= 64'd0;
            frontend_no_instruction_count      <= 64'd0;
            fetch_response_full_cycle_count     <= 64'd0;
            queue_full_cycle_count              <= 64'd0;
            queue_empty_cycle_count             <= 64'd0;
            load_use_stall_count                <= 64'd0;
            dcache_wait_cycle_count             <= 64'd0;
            mul_div_wait_cycle_count            <= 64'd0;
            branch_redirect_count               <= 64'd0;
            branch_flushed_younger_count        <= 64'd0;
            slot0_commit_count                  <= 64'd0;
            slot1_commit_count                  <= 64'd0;
        end else begin
            cycle_count <= cycle_count + 64'd1;
            retired_instruction_count <= retired_instruction_count
                                               + {63'd0, slot0_commit}
                                               + {63'd0, slot1_commit};
            if (slot0_issue)
                slot0_issue_count <= slot0_issue_count + 64'd1;
            if (slot1_issue)
                slot1_issue_count <= slot1_issue_count + 64'd1;
            if (pair_candidate)
                pair_candidate_count <= pair_candidate_count + 64'd1;
            if (slot1_issue)
                pair_success_count <= pair_success_count + 64'd1;
            if (pair_candidate && !slot1_issue)
                pair_blocked_count <= pair_blocked_count + 64'd1;
            if (pair_candidate && pair_raw_block)
                raw_block_count <= raw_block_count + 64'd1;
            if (pair_candidate && pair_waw_block)
                waw_block_count <= waw_block_count + 64'd1;
            if (pair_candidate && lane1_unsupported_block)
                lane1_unsupported_count <= lane1_unsupported_count + 64'd1;
            if (pair_candidate && lsu_structural_block)
                lsu_structural_conflict_count <= lsu_structural_conflict_count + 64'd1;
            if (frontend_no_instruction)
                frontend_no_instruction_count <= frontend_no_instruction_count + 64'd1;
            if (fetch_response_full)
                fetch_response_full_cycle_count <=
                    fetch_response_full_cycle_count + 64'd1;
            if (queue_full)
                queue_full_cycle_count <= queue_full_cycle_count + 64'd1;
            if (queue_empty)
                queue_empty_cycle_count <= queue_empty_cycle_count + 64'd1;
            if (load_use_stall)
                load_use_stall_count <= load_use_stall_count + 64'd1;
            if (dcache_wait)
                dcache_wait_cycle_count <= dcache_wait_cycle_count + 64'd1;
            if (mul_div_wait)
                mul_div_wait_cycle_count <= mul_div_wait_cycle_count + 64'd1;
            if (branch_redirect) begin
                branch_redirect_count <= branch_redirect_count + 64'd1;
                branch_flushed_younger_count <= branch_flushed_younger_count
                                               + {61'd0, branch_flushed_younger};
            end
            if (slot0_commit)
                slot0_commit_count <= slot0_commit_count + 64'd1;
            if (slot1_commit)
                slot1_commit_count <= slot1_commit_count + 64'd1;
        end
    end
endmodule
