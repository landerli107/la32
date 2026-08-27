`timescale 1ns/1ps

module tb_core_mixed_fallback;
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
    localparam integer EXPECTED_COMMITS = 7;

    reg [31:0] instruction_mem [0:PROGRAM_WORDS-1];
    reg [31:0] expected_pc [0:EXPECTED_COMMITS-1];
    reg [3:0]  expected_we [0:EXPECTED_COMMITS-1];
    reg [4:0]  expected_rd [0:EXPECTED_COMMITS-1];
    reg [31:0] expected_data [0:EXPECTED_COMMITS-1];
    integer commit_index;
    integer timeout_cycles;
    integer slot1_non_simple_commits;

    wire [31:0] word_index0 = (inst_addr - BASE) >> 2;
    wire [31:0] word_index1 = word_index0 + 32'd1;
    assign inst_rdata1_valid = inst_en && (inst_addr[3:2] != 2'd3) &&
                               (word_index1 < PROGRAM_WORDS);

    always @(*) begin
        inst_rdata = 32'h0280_0000;
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
        .data_sram_rdata(32'd41), .data_sram_addr_ok(1'b1),
        .data_sram_data_ok(1'b1), .data_sram_id_forward_ok(1'b0),
        .data_sram_id_forward_data(32'b0),
        .cacheop_valid(cacheop_valid), .cacheop_code(cacheop_code),
        .cacheop_addr(cacheop_addr), .cacheop_ready(1'b1),
        .sel_strcture_hazard(1'b0)
    );

    always #5 clk = ~clk;

    task check_commit;
        input [31:0] pc;
        input [3:0] rf_we;
        input [4:0] rd;
        input [31:0] data;
        input integer lane;
        begin
            if (pc == BASE + 32'd20)
                $fatal(1, "wrong-path instruction committed on lane%0d", lane);
            if (commit_index >= EXPECTED_COMMITS)
                $fatal(1, "unexpected extra commit lane%0d pc=%h", lane, pc);
            if (pc !== expected_pc[commit_index] ||
                rf_we !== expected_we[commit_index] ||
                (|rf_we && (rd !== expected_rd[commit_index] ||
                            data !== expected_data[commit_index])))
                $fatal(1, "commit mismatch index=%0d lane=%0d pc=%h we=%h rd=%0d data=%h",
                       commit_index, lane, pc, rf_we, rd, data);
            if (lane == 1 && (pc == BASE + 32'd4 || pc == BASE + 32'd16))
                slot1_non_simple_commits = slot1_non_simple_commits + 1;
            commit_index = commit_index + 1;
        end
    endtask

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
        instruction_mem[0] = 32'h0280_0001; // addi.w r1,r0,0
        instruction_mem[1] = 32'h2880_0022; // ld.w   r2,r1,0; must leave slot1
        instruction_mem[2] = 32'h0280_0443; // addi.w r3,r2,1 -> 42 (load-use)
        instruction_mem[3] = 32'h0280_1004; // addi.w r4,r0,4
        instruction_mem[4] = 32'h5000_0800; // b +8; flush instruction at PC+4
        instruction_mem[5] = 32'h0281_8c05; // wrong path: addi.w r5,r0,99
        instruction_mem[6] = 32'h0280_1806; // target: addi.w r6,r0,6
        instruction_mem[7] = 32'h0280_1c07; // addi.w r7,r0,7

        expected_pc[0] = BASE + 32'd0;  expected_we[0] = 4'hf; expected_rd[0] = 5'd1; expected_data[0] = 32'd0;
        expected_pc[1] = BASE + 32'd4;  expected_we[1] = 4'hf; expected_rd[1] = 5'd2; expected_data[1] = 32'd41;
        expected_pc[2] = BASE + 32'd8;  expected_we[2] = 4'hf; expected_rd[2] = 5'd3; expected_data[2] = 32'd42;
        expected_pc[3] = BASE + 32'd12; expected_we[3] = 4'hf; expected_rd[3] = 5'd4; expected_data[3] = 32'd4;
        expected_pc[4] = BASE + 32'd16; expected_we[4] = 4'h0; expected_rd[4] = 5'd0; expected_data[4] = 32'd0;
        expected_pc[5] = BASE + 32'd24; expected_we[5] = 4'hf; expected_rd[5] = 5'd6; expected_data[5] = 32'd6;
        expected_pc[6] = BASE + 32'd28; expected_we[6] = 4'hf; expected_rd[6] = 5'd7; expected_data[6] = 32'd7;

        clk = 1'b0;
        reset = 1'b1;
        commit_index = 0;
        timeout_cycles = 0;
        slot1_non_simple_commits = 0;
        repeat (3) @(posedge clk);
        reset = 1'b0;

        while ((commit_index < EXPECTED_COMMITS) && (timeout_cycles < 120)) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        @(negedge clk);

        if (commit_index != EXPECTED_COMMITS)
            $fatal(1, "mixed program timed out with %0d/%0d commits",
                   commit_index, EXPECTED_COMMITS);
        if (slot1_non_simple_commits != 0)
            $fatal(1, "load or branch incorrectly committed through lane1");
        // r5 is intentionally never written.  The register file has no reset
        // initialization, so its untouched simulation value is unspecified;
        // wrong-path suppression is proven by the commit-PC assertion above.
        if (dut.id_run.RF.Reg_File0[3] !== 32'd42 ||
            dut.id_run.RF.Reg_File0[7] !== 32'd7)
            $fatal(1, "mixed program architectural state mismatch");

        $display("PASS: mixed load/branch fallback, load-use and wrong-path flush tests");
        $display("STATS: cycles=%0d issue0=%0d issue1=%0d attempts=%0d blocked=%0d",
                 dut.stat_cycle_count, dut.stat_slot0_issue_count,
                 dut.stat_slot1_issue_count, dut.stat_pair_attempt_count,
                 dut.stat_pair_blocked_count);
        $finish;
    end
endmodule
