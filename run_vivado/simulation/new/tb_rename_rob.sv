`timescale 1ns/1ps

module tb_rename_rob;
    reg clk = 1'b0;
    reg reset;

    wire can_alloc1, can_alloc2;
    reg alloc0_valid, alloc1_valid;
    wire [4:0] alloc0_tag, alloc1_tag;
    reg [31:0] alloc0_pc, alloc1_pc;
    reg [3:0] alloc0_class, alloc1_class;
    reg [4:0] alloc0_rd, alloc1_rd;
    reg alloc0_writes_rd, alloc1_writes_rd;
    reg alloc0_checkpoint_valid, alloc1_checkpoint_valid;
    reg [1:0] alloc0_checkpoint_id, alloc1_checkpoint_id;
    reg alloc0_store_valid, alloc1_store_valid;
    reg [1:0] alloc0_store_index, alloc1_store_index;
    reg [13:0] alloc0_serial_index, alloc1_serial_index;
    reg [31:0] alloc0_serial_operand0, alloc1_serial_operand0;
    reg [31:0] alloc0_serial_operand1, alloc1_serial_operand1;

    reg complete0_valid, complete1_valid;
    reg [4:0] complete0_tag, complete1_tag;
    reg [31:0] complete0_result, complete1_result;
    reg rollback_valid;
    reg [4:0] rollback_keep_tag;
    wire rollback_busy;

    reg src00_used, src01_used, src10_used, src11_used;
    reg [4:0] src00_addr, src01_addr, src10_addr, src11_addr;
    wire src00_mapped, src01_mapped, src10_mapped, src11_mapped;
    wire src00_ready, src01_ready, src10_ready, src11_ready;
    wire [4:0] src00_tag, src01_tag, src10_tag, src11_tag;
    wire [31:0] src00_value, src01_value, src10_value, src11_value;

    wire commit0_valid, commit1_valid;
    wire [4:0] commit0_tag, commit1_tag;
    wire [31:0] commit0_pc, commit1_pc;
    wire [3:0] commit0_class, commit1_class;
    wire commit0_writes_rd, commit1_writes_rd;
    wire [4:0] commit0_rd, commit1_rd;
    wire [31:0] commit0_result, commit1_result;
    wire [4:0] occupancy;

    integer failures;
    integer n;
    reg [4:0] tag0, tag1, new_tag;

    rename_rob dut (
        .clk(clk), .reset(reset),
        .can_alloc1(can_alloc1), .can_alloc2(can_alloc2),
        .alloc0_valid(alloc0_valid), .alloc1_valid(alloc1_valid),
        .alloc0_tag(alloc0_tag), .alloc1_tag(alloc1_tag),
        .alloc0_pc(alloc0_pc), .alloc1_pc(alloc1_pc),
        .alloc0_class(alloc0_class), .alloc1_class(alloc1_class),
        .alloc0_rd(alloc0_rd), .alloc1_rd(alloc1_rd),
        .alloc0_writes_rd(alloc0_writes_rd),
        .alloc1_writes_rd(alloc1_writes_rd),
        .alloc0_checkpoint_valid(alloc0_checkpoint_valid),
        .alloc1_checkpoint_valid(alloc1_checkpoint_valid),
        .alloc0_checkpoint_id(alloc0_checkpoint_id),
        .alloc1_checkpoint_id(alloc1_checkpoint_id),
        .alloc0_store_valid(alloc0_store_valid),
        .alloc1_store_valid(alloc1_store_valid),
        .alloc0_store_index(alloc0_store_index),
        .alloc1_store_index(alloc1_store_index),
        .alloc0_serial_index(alloc0_serial_index),
        .alloc1_serial_index(alloc1_serial_index),
        .alloc0_serial_operand0(alloc0_serial_operand0),
        .alloc1_serial_operand0(alloc1_serial_operand0),
        .alloc0_serial_operand1(alloc0_serial_operand1),
        .alloc1_serial_operand1(alloc1_serial_operand1),
        .complete0_valid(complete0_valid), .complete0_tag(complete0_tag),
        .complete0_result(complete0_result),
        .complete1_valid(complete1_valid), .complete1_tag(complete1_tag),
        .complete1_result(complete1_result),
        .rollback_valid(rollback_valid),
        .rollback_keep_tag(rollback_keep_tag),
        .rollback_busy(rollback_busy),
        .src00_used(src00_used), .src00_addr(src00_addr),
        .src00_mapped(src00_mapped), .src00_ready(src00_ready),
        .src00_tag(src00_tag), .src00_value(src00_value),
        .src01_used(src01_used), .src01_addr(src01_addr),
        .src01_mapped(src01_mapped), .src01_ready(src01_ready),
        .src01_tag(src01_tag), .src01_value(src01_value),
        .src10_used(src10_used), .src10_addr(src10_addr),
        .src10_mapped(src10_mapped), .src10_ready(src10_ready),
        .src10_tag(src10_tag), .src10_value(src10_value),
        .src11_used(src11_used), .src11_addr(src11_addr),
        .src11_mapped(src11_mapped), .src11_ready(src11_ready),
        .src11_tag(src11_tag), .src11_value(src11_value),
        .commit0_valid(commit0_valid), .commit0_tag(commit0_tag),
        .commit0_pc(commit0_pc), .commit0_class(commit0_class),
        .commit0_writes_rd(commit0_writes_rd), .commit0_rd(commit0_rd),
        .commit0_result(commit0_result),
        .commit1_valid(commit1_valid), .commit1_tag(commit1_tag),
        .commit1_pc(commit1_pc), .commit1_class(commit1_class),
        .commit1_writes_rd(commit1_writes_rd), .commit1_rd(commit1_rd),
        .commit1_result(commit1_result), .occupancy(occupancy)
    );

    always #5 clk = ~clk;

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task check;
        input condition;
        input [8*96-1:0] message;
        begin
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task clear_inputs;
        begin
            alloc0_valid = 0; alloc1_valid = 0;
            alloc0_pc = 0; alloc1_pc = 0;
            alloc0_class = 0; alloc1_class = 0;
            alloc0_rd = 0; alloc1_rd = 0;
            alloc0_writes_rd = 0; alloc1_writes_rd = 0;
            alloc0_checkpoint_valid = 0; alloc1_checkpoint_valid = 0;
            alloc0_checkpoint_id = 0; alloc1_checkpoint_id = 0;
            alloc0_store_valid = 0; alloc1_store_valid = 0;
            alloc0_store_index = 0; alloc1_store_index = 0;
            alloc0_serial_index = 0; alloc1_serial_index = 0;
            alloc0_serial_operand0 = 0; alloc1_serial_operand0 = 0;
            alloc0_serial_operand1 = 0; alloc1_serial_operand1 = 0;
            complete0_valid = 0; complete1_valid = 0;
            complete0_tag = 0; complete1_tag = 0;
            complete0_result = 0; complete1_result = 0;
            rollback_valid = 0; rollback_keep_tag = 0;
            src00_used = 0; src01_used = 0;
            src10_used = 0; src11_used = 0;
            src00_addr = 0; src01_addr = 0;
            src10_addr = 0; src11_addr = 0;
        end
    endtask

    task do_reset;
        begin
            clear_inputs();
            reset = 1;
            tick();
            tick();
            reset = 0;
            #1;
            check(occupancy == 0, "reset occupancy");
            check(can_alloc1 && can_alloc2, "reset allocation readiness");
        end
    endtask

    task alloc_pair;
        input [4:0] rd0;
        input [4:0] rd1;
        input [3:0] class0;
        output [4:0] out_tag0;
        output [4:0] out_tag1;
        begin
            alloc0_valid = 1;
            alloc1_valid = 1;
            alloc0_rd = rd0;
            alloc1_rd = rd1;
            alloc0_writes_rd = (rd0 != 0);
            alloc1_writes_rd = (rd1 != 0);
            alloc0_class = class0;
            alloc1_class = 0;
            alloc0_pc = 32'h1000 + (occupancy << 2);
            alloc1_pc = alloc0_pc + 4;
            #1;
            out_tag0 = alloc0_tag;
            out_tag1 = alloc1_tag;
            tick();
            alloc0_valid = 0;
            alloc1_valid = 0;
            alloc0_writes_rd = 0;
            alloc1_writes_rd = 0;
            alloc0_class = 0;
            #1;
            // Reservation is followed by a registered metadata population
            // edge; the real core naturally supplies this EXE cycle.
            tick();
        end
    endtask

    task alloc_single;
        input [4:0] rd;
        input [3:0] class0;
        output [4:0] out_tag;
        begin
            alloc0_valid = 1;
            alloc0_rd = rd;
            alloc0_writes_rd = (rd != 0);
            alloc0_class = class0;
            #1;
            out_tag = alloc0_tag;
            tick();
            alloc0_valid = 0;
            alloc0_writes_rd = 0;
            alloc0_class = 0;
            #1;
            tick();
        end
    endtask

    task complete_single;
        input [4:0] tag;
        input [31:0] value;
        begin
            complete0_valid = 1;
            complete0_tag = tag;
            complete0_result = value;
            #1;
            tick();
            complete0_valid = 0;
            #1;
        end
    endtask

    initial begin
        failures = 0;
        reset = 0;
        clear_inputs();

        // Out-of-order completion must still retire in order, with no extra
        // completion-to-commit cycle for the head entry.
        do_reset();
        alloc_pair(5'd1, 5'd2, 4'd0, tag0, tag1);
        check(occupancy == 2, "dual allocation occupancy");
        src00_used = 1; src00_addr = 1;
        #1;
        check(src00_mapped && !src00_ready && src00_tag == tag0,
              "RAT maps first destination to incomplete ROB entry");
        src00_used = 0;
        complete_single(tag1, 32'h2222_2222);
        check(!commit0_valid && occupancy == 2,
              "younger completion cannot pass incomplete head");
        complete0_valid = 1;
        complete0_tag = tag0;
        complete0_result = 32'h1111_1111;
        #1;
        check(commit0_valid && commit1_valid, "two-wide ordered commit");
        check(commit0_result == 32'h1111_1111 &&
              commit1_result == 32'h2222_2222,
              "commit result bypass and stored result");
        tick();
        complete0_valid = 0;
        check(occupancy == 0, "dual commit drains ROB");

        // Slot1 must see slot0's newly allocated mapping in the same cycle.
        do_reset();
        alloc0_valid = 1; alloc1_valid = 1;
        alloc0_rd = 5'd5; alloc1_rd = 5'd6;
        alloc0_writes_rd = 1; alloc1_writes_rd = 1;
        src10_used = 1; src10_addr = 5'd5;
        #1;
        tag0 = alloc0_tag;
        check(src10_mapped && !src10_ready && src10_tag == tag0,
              "same-cycle slot0 to slot1 RAW rename");
        tick();
        clear_inputs();

        // On WAW, retirement of the older entry must not clear the younger RAT.
        do_reset();
        alloc_pair(5'd3, 5'd3, 4'd0, tag0, tag1);
        complete0_valid = 1;
        complete0_tag = tag0;
        complete0_result = 32'haaaa_0001;
        #1;
        check(commit0_valid && !commit1_valid, "older WAW commits alone");
        tick();
        complete0_valid = 0;
        src00_used = 1; src00_addr = 5'd3;
        #1;
        check(src00_mapped && !src00_ready && src00_tag == tag1,
              "older WAW commit preserves younger RAT mapping");
        src00_used = 0;
        complete_single(tag1, 32'hbbbb_0002);
        src00_used = 1; src00_addr = 5'd3;
        #1;
        check(!src00_mapped, "youngest WAW commit clears RAT mapping");
        src00_used = 0;

        // Generation bit must reject a stale completion after pointer wrap.
        do_reset();
        for (n = 0; n < 16; n = n + 1) begin
            alloc_single(5'd7, 4'd0, new_tag);
            check(new_tag == n[4:0], "pre-wrap allocation tag sequence");
            complete_single(new_tag, 32'h7000_0000 + n);
        end
        alloc_single(5'd7, 4'd0, new_tag);
        check(new_tag == 5'h10, "allocation generation toggles after wrap");
        complete0_valid = 1;
        complete0_tag = 5'h00;
        complete0_result = 32'hdead_beef;
        #1;
        check(!commit0_valid, "stale completion cannot commit new generation");
        tick();
        complete0_valid = 0;
        check(!commit0_valid && occupancy == 1,
              "stale completion not stored in reused entry");
        complete_single(new_tag, 32'h7000_0010);
        check(occupancy == 0, "correct-generation completion commits");

        // Rollback removes all younger state and restores a WAW RAT chain.
        do_reset();
        alloc_single(5'd0, 4'd1, tag0);
        alloc_pair(5'd4, 5'd4, 4'd0, tag1, new_tag);
        check(occupancy == 3, "rollback setup occupancy");
        rollback_valid = 1;
        rollback_keep_tag = tag0;
        tick();
        rollback_valid = 0;
        while (rollback_busy)
            tick();
        check(occupancy == 1, "rollback keeps branch and removes younger entries");
        src00_used = 1; src00_addr = 5'd4;
        #1;
        check(!src00_mapped, "rollback restores RAT before younger WAW chain");
        src00_used = 0;
        complete_single(tag0, 32'h0);
        check(occupancy == 0, "kept branch commits after rollback");

        // Capacity and dual drain validate the 16-entry count boundaries.
        do_reset();
        for (n = 0; n < 8; n = n + 1)
            alloc_pair(5'd0, 5'd0, 4'd0, tag0, tag1);
        check(occupancy == 16 && !can_alloc1 && !can_alloc2,
              "ROB full boundary");
        for (n = 0; n < 8; n = n + 1) begin
            complete0_valid = 1;
            complete1_valid = 1;
            complete0_tag = (n * 2);
            complete1_tag = (n * 2) + 1;
            complete0_result = n;
            complete1_result = n + 1;
            #1;
            check(commit0_valid && commit1_valid,
                  "full ROB drains two entries per cycle");
            tick();
            complete0_valid = 0;
            complete1_valid = 0;
        end
        check(occupancy == 0 && can_alloc1 && can_alloc2,
              "capacity recovers after drain");

        if (failures == 0)
            $display("PASS tb_rename_rob");
        else
            $display("FAIL tb_rename_rob failures=%0d", failures);
        $finish;
    end
endmodule
