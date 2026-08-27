`timescale 1ns/1ps

module tb_core_dual_program;
    reg clk;
    reg reset;

    wire        inst_en;
    wire [3:0]  inst_we;
    wire [31:0] inst_addr;
    wire [31:0] inst_wdata;
    reg  [31:0] inst_rdata;
    reg  [31:0] inst_rdata1;
    wire        inst_rdata1_valid;
    wire        inst_resp_ready;

    wire        data_en;
    wire [3:0]  data_we;
    wire [31:0] data_addr;
    wire [31:0] data_pc;
    wire [2:0]  data_size;
    wire [31:0] data_wdata;
    wire        cacheop_valid;
    wire [4:0]  cacheop_code;
    wire [31:0] cacheop_addr;

    localparam [31:0] BASE = 32'h1c00_0000;
    localparam integer PROGRAM_WORDS = 8;

    reg [31:0] instruction_mem [0:PROGRAM_WORDS-1];
    reg [31:0] expected_pc [0:PROGRAM_WORDS-1];
    reg [4:0]  expected_rd [0:PROGRAM_WORDS-1];
    reg [31:0] expected_data [0:PROGRAM_WORDS-1];
    integer commit_index;
    integer timeout_cycles;

    wire [31:0] word_index0 = (inst_addr - BASE) >> 2;
    wire [31:0] word_index1 = word_index0 + 32'd1;

    assign inst_rdata1_valid = inst_en && (inst_addr[3:2] != 2'd3) &&
                               (word_index1 < PROGRAM_WORDS);

    always @(*) begin
        inst_rdata = 32'h0280_0000;  // addi.w r0,r0,0 outside the instruction_mem
        inst_rdata1 = 32'h0280_0000;
        if ((inst_addr >= BASE) && (word_index0 < PROGRAM_WORDS))
            inst_rdata = instruction_mem[word_index0];
        if ((inst_addr >= BASE) && (word_index1 < PROGRAM_WORDS))
            inst_rdata1 = instruction_mem[word_index1];
    end

    YK_Core dut(
        .clk(clk), .reset(reset),
        .inst_sram_en(inst_en), .inst_sram_we(inst_we),
        .inst_sram_addr(inst_addr), .inst_sram_wdata(inst_wdata),
        .inst_sram_rdata(inst_rdata), .inst_sram_rdata1(inst_rdata1),
        .inst_sram_rdata1_valid(inst_rdata1_valid),
        .inst_sram_addr_ok(1'b1), .inst_sram_data_ok(inst_en),
        .inst_sram_resp_ready(inst_resp_ready),
        .data_sram_en(data_en), .data_sram_we(data_we),
        .data_sram_addr(data_addr), .data_sram_pc(data_pc),
        .data_sram_size(data_size), .data_sram_wdata(data_wdata),
        .data_sram_rdata(32'b0), .data_sram_addr_ok(1'b1),
        .data_sram_data_ok(1'b1), .data_sram_id_forward_ok(1'b0),
        .data_sram_id_forward_data(32'b0),
        .cacheop_valid(cacheop_valid), .cacheop_code(cacheop_code),
        .cacheop_addr(cacheop_addr), .cacheop_ready(1'b1),
        .sel_strcture_hazard(1'b0)
    );

    always #5 clk = ~clk;

`ifdef FORCE_SINGLE_ISSUE
    // A/B control: keep the identical front end and pipeline, but make every
    // candidate pair serialize by disabling the pairing decision only.
    initial force dut.id_run.pair_valid = 1'b0;
`endif

    task check_commit;
        input [31:0] pc;
        input [3:0] rf_we;
        input [4:0] rd;
        input [31:0] data;
        input integer lane;
        begin
            if (commit_index >= PROGRAM_WORDS)
                $fatal(1, "unexpected extra instruction_mem commit lane%0d pc=%h", lane, pc);
            if (pc !== expected_pc[commit_index])
                $fatal(1, "commit order mismatch index=%0d lane=%0d got_pc=%h expected_pc=%h",
                       commit_index, lane, pc, expected_pc[commit_index]);
            if (rf_we !== 4'hf || rd !== expected_rd[commit_index] ||
                data !== expected_data[commit_index])
                $fatal(1, "commit payload mismatch index=%0d lane=%0d we=%h rd=%0d data=%h",
                       commit_index, lane, rf_we, rd, data);
            commit_index = commit_index + 1;
        end
    endtask

    // A reference model consumes the older slot0 event first and then slot1.
    // Sampling on the falling edge avoids races with WB pipeline registers.
    always @(negedge clk) begin
        if (!reset) begin
            if (dut.sim_commit0_valid && dut.sim_commit0_pc < BASE + PROGRAM_WORDS*4)
                check_commit(dut.sim_commit0_pc, dut.sim_commit0_rf_we,
                             dut.sim_commit0_rf_wnum, dut.sim_commit0_rf_wdata, 0);
            if (dut.sim_commit1_valid && dut.sim_commit1_pc < BASE + PROGRAM_WORDS*4)
                check_commit(dut.sim_commit1_pc, dut.sim_commit1_rf_we,
                             dut.sim_commit1_rf_wnum, dut.sim_commit1_rf_wdata, 1);
        end
    end

    initial begin
        // Pair 0: independent writes.
        instruction_mem[0] = 32'h0280_1401; // addi.w r1,r0,5
        instruction_mem[1] = 32'h0280_1c02; // addi.w r2,r0,7
        // Pair 1: consume prior lane0 and lane1 results through forwarding.
        instruction_mem[2] = 32'h0280_0423; // addi.w r3,r1,1 -> 6
        instruction_mem[3] = 32'h0280_0844; // addi.w r4,r2,2 -> 9
        // RAW within the fetch group: slot1 must be retained and serialized.
        instruction_mem[4] = 32'h0280_0c65; // addi.w r5,r3,3 -> 9
        instruction_mem[5] = 32'h0280_04a6; // addi.w r6,r5,1 -> 10
        // Pair 3: independent writes after the serialized group.
        instruction_mem[6] = 32'h0280_2407; // addi.w r7,r0,9
        instruction_mem[7] = 32'h0280_2808; // addi.w r8,r0,10

        expected_pc[0] = BASE + 32'd0;  expected_rd[0] = 5'd1; expected_data[0] = 32'd5;
        expected_pc[1] = BASE + 32'd4;  expected_rd[1] = 5'd2; expected_data[1] = 32'd7;
        expected_pc[2] = BASE + 32'd8;  expected_rd[2] = 5'd3; expected_data[2] = 32'd6;
        expected_pc[3] = BASE + 32'd12; expected_rd[3] = 5'd4; expected_data[3] = 32'd9;
        expected_pc[4] = BASE + 32'd16; expected_rd[4] = 5'd5; expected_data[4] = 32'd9;
        expected_pc[5] = BASE + 32'd20; expected_rd[5] = 5'd6; expected_data[5] = 32'd10;
        expected_pc[6] = BASE + 32'd24; expected_rd[6] = 5'd7; expected_data[6] = 32'd9;
        expected_pc[7] = BASE + 32'd28; expected_rd[7] = 5'd8; expected_data[7] = 32'd10;

        clk = 1'b0;
        reset = 1'b1;
        commit_index = 0;
        timeout_cycles = 0;
        repeat (3) @(posedge clk);
        reset = 1'b0;

        while ((commit_index < PROGRAM_WORDS) && (timeout_cycles < 80)) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        @(negedge clk);

        if (commit_index != PROGRAM_WORDS)
            $fatal(1, "instruction_mem timed out after %0d cycles with %0d/%0d commits",
                   timeout_cycles, commit_index, PROGRAM_WORDS);
`ifdef FORCE_SINGLE_ISSUE
        if (dut.stat_slot1_issue_count != 64'd0)
            $fatal(1, "single-issue control unexpectedly used slot1");
`else
        if (dut.stat_slot1_issue_count < 64'd3)
            $fatal(1, "expected at least three slot1 issues, got %0d",
                   dut.stat_slot1_issue_count);
        if (dut.stat_pair_blocked_count < 64'd1)
            $fatal(1, "same-group RAW was not counted as a blocked pair");
`endif
        if (dut.id_run.RF.Reg_File0[6] !== 32'd10 ||
            dut.id_run.RF.Reg_File0[8] !== 32'd10)
            $fatal(1, "architectural register state mismatch");

`ifdef FORCE_SINGLE_ISSUE
        $display("PASS: forced single-issue control program completed in order");
`else
        $display("PASS: core dual-fetch program, ordered dual commit and forwarding tests");
`endif
        $display("STATS: cycles=%0d issue0=%0d issue1=%0d attempts=%0d blocked=%0d commit0=%0d commit1=%0d",
                 dut.stat_cycle_count, dut.stat_slot0_issue_count,
                 dut.stat_slot1_issue_count, dut.stat_pair_attempt_count,
                 dut.stat_pair_blocked_count, dut.stat_slot0_commit_count,
                 dut.stat_slot1_commit_count);
        $finish;
    end
endmodule
