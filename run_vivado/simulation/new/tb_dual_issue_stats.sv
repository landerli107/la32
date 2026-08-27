`timescale 1ns/1ps

module tb_dual_issue_stats;
    reg clk;
    reg reset;
    reg issue0;
    reg issue1;
    reg present1;
    reg commit0;
    reg commit1;
    reg raw_block;
    reg waw_block;
    reg unsupported_block;
    reg lsu_block;
    reg frontend_empty;
    reg fetch_full;
    reg queue_full;
    reg queue_empty;
    reg load_use;
    reg dcache_wait;
    reg mul_div_wait;
    reg redirect;
    reg [2:0] flushed;

    wire [63:0] cycles, retired, issues0, issues1;
    wire [63:0] candidates, success, blocked;
    wire [63:0] raw_count, waw_count, unsupported_count, lsu_count;
    wire [63:0] frontend_count, fetch_full_count, full_count, empty_count;
    wire [63:0] load_use_count, dcache_count, mul_div_count;
    wire [63:0] redirect_count, flushed_count, commits0, commits1;

    dual_issue_stats dut (
        .clk(clk), .reset(reset),
        .slot0_issue(issue0), .slot1_issue(issue1),
        .slot1_present(present1),
        .slot0_commit(commit0), .slot1_commit(commit1),
        .pair_raw_block(raw_block), .pair_waw_block(waw_block),
        .lane1_unsupported_block(unsupported_block),
        .lsu_structural_block(lsu_block),
        .frontend_no_instruction(frontend_empty),
        .fetch_response_full(fetch_full),
        .queue_full(queue_full), .queue_empty(queue_empty),
        .load_use_stall(load_use), .dcache_wait(dcache_wait),
        .mul_div_wait(mul_div_wait), .branch_redirect(redirect),
        .branch_flushed_younger(flushed),
        .cycle_count(cycles), .retired_instruction_count(retired),
        .slot0_issue_count(issues0), .slot1_issue_count(issues1),
        .pair_candidate_count(candidates), .pair_success_count(success),
        .pair_blocked_count(blocked),
        .raw_block_count(raw_count), .waw_block_count(waw_count),
        .lane1_unsupported_count(unsupported_count),
        .lsu_structural_conflict_count(lsu_count),
        .frontend_no_instruction_count(frontend_count),
        .fetch_response_full_cycle_count(fetch_full_count),
        .queue_full_cycle_count(full_count),
        .queue_empty_cycle_count(empty_count),
        .load_use_stall_count(load_use_count),
        .dcache_wait_cycle_count(dcache_count),
        .mul_div_wait_cycle_count(mul_div_count),
        .branch_redirect_count(redirect_count),
        .branch_flushed_younger_count(flushed_count),
        .slot0_commit_count(commits0), .slot1_commit_count(commits1)
    );

    always #5 clk = ~clk;

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task clear_events;
        begin
            issue0 = 0; issue1 = 0; present1 = 0;
            commit0 = 0; commit1 = 0;
            raw_block = 0; waw_block = 0;
            unsupported_block = 0; lsu_block = 0;
            frontend_empty = 0; fetch_full = 0;
            queue_full = 0; queue_empty = 0;
            load_use = 0; dcache_wait = 0; mul_div_wait = 0;
            redirect = 0; flushed = 0;
        end
    endtask

    initial begin
        clk = 0;
        reset = 1;
        clear_events();
        tick();
        reset = 0;

        // Successful pair, both instructions eventually commit.
        issue0 = 1; issue1 = 1; present1 = 1;
        commit0 = 1; commit1 = 1; fetch_full = 1; queue_full = 1;
        tick();
        clear_events();

        // Pair rejected for overlapping RAW and unsupported-lane reasons.
        issue0 = 1; present1 = 1;
        raw_block = 1; unsupported_block = 1;
        frontend_empty = 1; load_use = 1; mul_div_wait = 1;
        tick();
        clear_events();

        // Pair rejected for WAW plus an LSU structural conflict.
        issue0 = 1; present1 = 1;
        waw_block = 1; lsu_block = 1; dcache_wait = 1;
        redirect = 1; flushed = 3'd2; commit0 = 1;
        tick();
        clear_events();

        // Ordinary single issue with an empty queue indication.
        issue0 = 1; queue_empty = 1;
        tick();

        if (cycles !== 4 || retired !== 3 ||
            issues0 !== 4 || issues1 !== 1 ||
            candidates !== 3 || success !== 1 || blocked !== 2 ||
            raw_count !== 1 || waw_count !== 1 ||
            unsupported_count !== 1 || lsu_count !== 1 ||
            frontend_count !== 1 || fetch_full_count !== 1 ||
            full_count !== 1 || empty_count !== 1 ||
            load_use_count !== 1 || dcache_count !== 1 || mul_div_count !== 1 ||
            redirect_count !== 1 || flushed_count !== 2 ||
            commits0 !== 2 || commits1 !== 1)
            $fatal(1, "detailed dual-issue statistics mismatch");

        $display("PASS: detailed dual-issue accounting tests");
        $finish;
    end
endmodule
