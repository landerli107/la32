`timescale 1ns/1ps

module tb_core_asymmetric_pair;
    reg clk;
    reg reset;

    wire inst_en;
    wire [3:0] inst_we;
    wire [31:0] inst_addr, inst_wdata;
    reg [31:0] inst_rdata, inst_rdata1;
    wire inst_rdata1_valid, inst_resp_ready;
    wire data_en;
    wire [3:0] data_we;
    wire [31:0] data_addr, data_pc, data_wdata;
    wire [2:0] data_size;
    wire cacheop_valid;
    wire [4:0] cacheop_code;
    wire [31:0] cacheop_addr;

    localparam [31:0] BASE = 32'h1c00_0000;
    localparam integer PROGRAM_WORDS = 8;

    reg [31:0] instruction_mem [0:PROGRAM_WORDS-1];
    reg [3:0] expected_we [0:PROGRAM_WORDS-1];
    reg [4:0] expected_rd [0:PROGRAM_WORDS-1];
    reg [31:0] expected_data [0:PROGRAM_WORDS-1];
    integer commit_index;
    integer timeout_cycles;
    integer store_count;

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
            if (commit_index >= PROGRAM_WORDS)
                $fatal(1, "unexpected commit lane=%0d pc=%h", lane, pc);
            if (pc !== BASE + commit_index*4 || rf_we !== expected_we[commit_index] ||
                (|rf_we && (rd !== expected_rd[commit_index] ||
                            data !== expected_data[commit_index])))
                $fatal(1, "commit mismatch index=%0d lane=%0d pc=%h we=%h rd=%0d data=%h",
                       commit_index, lane, pc, rf_we, rd, data);
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
            if (data_en && (|data_we)) begin
                if (data_addr !== 32'd4 || data_we !== 4'hf || data_wdata !== 32'd7)
                    $fatal(1, "store mismatch addr=%h we=%h data=%h",
                           data_addr, data_we, data_wdata);
                store_count = store_count + 1;
            end
        end
    end

    initial begin
        // Pair 0: load in lane0 while an independent ALU uses lane1.
        instruction_mem[0] = 32'h2880_0002; // ld.w   r2,r0,0 -> 41
        instruction_mem[1] = 32'h0280_1c03; // addi.w r3,r0,7
        // Pair 1: store in lane0 while an independent ALU uses lane1.
        instruction_mem[2] = 32'h2980_1003; // st.w   r3,r0,4
        instruction_mem[3] = 32'h0280_2404; // addi.w r4,r0,9
        // Produce operands for the multiply as a normal ALU pair.
        instruction_mem[4] = 32'h0280_1805; // addi.w r5,r0,6
        instruction_mem[5] = 32'h0280_1c06; // addi.w r6,r0,7
        // Pair 3: mul.w in lane0 while an independent ALU uses lane1.
        instruction_mem[6] = 32'h001c_18a7; // mul.w  r7,r5,r6 -> 42
        instruction_mem[7] = 32'h0280_2c08; // addi.w r8,r0,11

        expected_we[0]=4'hf; expected_rd[0]=5'd2; expected_data[0]=32'd41;
        expected_we[1]=4'hf; expected_rd[1]=5'd3; expected_data[1]=32'd7;
        expected_we[2]=4'h0; expected_rd[2]=5'd0; expected_data[2]=32'd0;
        expected_we[3]=4'hf; expected_rd[3]=5'd4; expected_data[3]=32'd9;
        expected_we[4]=4'hf; expected_rd[4]=5'd5; expected_data[4]=32'd6;
        expected_we[5]=4'hf; expected_rd[5]=5'd6; expected_data[5]=32'd7;
        expected_we[6]=4'hf; expected_rd[6]=5'd7; expected_data[6]=32'd42;
        expected_we[7]=4'hf; expected_rd[7]=5'd8; expected_data[7]=32'd11;

        clk = 1'b0;
        reset = 1'b1;
        commit_index = 0;
        timeout_cycles = 0;
        store_count = 0;
        repeat (3) @(posedge clk);
        reset = 1'b0;

        while ((commit_index < PROGRAM_WORDS) && (timeout_cycles < 100)) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        @(negedge clk);

        if (commit_index != PROGRAM_WORDS)
            $fatal(1, "asymmetric pair test timed out at %0d commits", commit_index);
        if (dut.stat_slot1_issue_count < 64'd4)
            $fatal(1, "expected four slot1 issues, got %0d", dut.stat_slot1_issue_count);
        if (store_count != 1)
            $fatal(1, "expected one store, got %0d", store_count);
        if (dut.id_run.RF.Reg_File0[7] !== 32'd42 ||
            dut.id_run.RF.Reg_File0[8] !== 32'd11)
            $fatal(1, "architectural state mismatch");

        $display("PASS: load/store/mul lane0 plus independent lane1 ALU pairs");
        $display("STATS: cycles=%0d issue0=%0d issue1=%0d attempts=%0d blocked=%0d",
                 dut.stat_cycle_count, dut.stat_slot0_issue_count,
                 dut.stat_slot1_issue_count, dut.stat_pair_attempt_count,
                 dut.stat_pair_blocked_count);
        $finish;
    end
endmodule
