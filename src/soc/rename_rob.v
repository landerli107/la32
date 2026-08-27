/**
 * 16-entry, two-wide rename table and in-order reorder buffer.
 *
 * Tags are {generation,index[3:0]}.  Allocation and completion are independent;
 * commit is always ordered from head.  A completion matching the head may
 * commit in the same cycle, avoiding an extra architectural writeback stage.
 */
module rename_rob(
    input  wire        clk,
    input  wire        reset,

    output wire        can_alloc1,
    output wire        can_alloc2,
    input  wire        alloc0_valid,
    input  wire        alloc1_valid,
    output wire [ 4:0] alloc0_tag,
    output wire [ 4:0] alloc1_tag,
    input  wire [31:0] alloc0_pc,
    input  wire [31:0] alloc1_pc,
    input  wire [ 3:0] alloc0_class,
    input  wire [ 3:0] alloc1_class,
    input  wire [ 4:0] alloc0_rd,
    input  wire [ 4:0] alloc1_rd,
    input  wire        alloc0_writes_rd,
    input  wire        alloc1_writes_rd,
    input  wire        alloc0_checkpoint_valid,
    input  wire        alloc1_checkpoint_valid,
    input  wire [ 1:0] alloc0_checkpoint_id,
    input  wire [ 1:0] alloc1_checkpoint_id,
    input  wire        alloc0_store_valid,
    input  wire        alloc1_store_valid,
    input  wire [ 1:0] alloc0_store_index,
    input  wire [ 1:0] alloc1_store_index,
    input  wire [13:0] alloc0_serial_index,
    input  wire [13:0] alloc1_serial_index,
    input  wire [31:0] alloc0_serial_operand0,
    input  wire [31:0] alloc1_serial_operand0,
    input  wire [31:0] alloc0_serial_operand1,
    input  wire [31:0] alloc1_serial_operand1,

    input  wire        complete0_valid,
    input  wire [ 4:0] complete0_tag,
    input  wire [31:0] complete0_result,
    input  wire        complete1_valid,
    input  wire [ 4:0] complete1_tag,
    input  wire [31:0] complete1_result,

    input  wire        rollback_valid,
    input  wire [ 4:0] rollback_keep_tag,
    output reg         rollback_busy,

    input  wire        src00_used,
    input  wire [ 4:0] src00_addr,
    output wire        src00_mapped,
    output wire        src00_ready,
    output wire [ 4:0] src00_tag,
    output wire [31:0] src00_value,
    input  wire        src01_used,
    input  wire [ 4:0] src01_addr,
    output wire        src01_mapped,
    output wire        src01_ready,
    output wire [ 4:0] src01_tag,
    output wire [31:0] src01_value,
    input  wire        src10_used,
    input  wire [ 4:0] src10_addr,
    output wire        src10_mapped,
    output wire        src10_ready,
    output wire [ 4:0] src10_tag,
    output wire [31:0] src10_value,
    input  wire        src11_used,
    input  wire [ 4:0] src11_addr,
    output wire        src11_mapped,
    output wire        src11_ready,
    output wire [ 4:0] src11_tag,
    output wire [31:0] src11_value,

    output wire        commit0_valid,
    output wire [ 4:0] commit0_tag,
    output wire [31:0] commit0_pc,
    output wire [ 3:0] commit0_class,
    output wire        commit0_writes_rd,
    output wire [ 4:0] commit0_rd,
    output wire [31:0] commit0_result,
    output wire        commit1_valid,
    output wire [ 4:0] commit1_tag,
    output wire [31:0] commit1_pc,
    output wire [ 3:0] commit1_class,
    output wire        commit1_writes_rd,
    output wire [ 4:0] commit1_rd,
    output wire [31:0] commit1_result,
    output wire [ 4:0] occupancy
);
    localparam [3:0] CLASS_BRANCH = 4'd1;
    localparam [3:0] CLASS_SERIAL = 4'd5;

    reg [4:0] head_ptr;
    reg [4:0] tail_ptr;
    reg [4:0] count;
    reg [4:0] rollback_target_tail;

    reg        rob_valid [0:15];
    reg        rob_complete [0:15];
    reg        rob_generation [0:15];
    reg [31:0] rob_pc [0:15];
    reg [ 3:0] rob_class [0:15];
    reg [ 4:0] rob_rd [0:15];
    reg        rob_writes_rd [0:15];
    reg [31:0] rob_result [0:15];
    reg        rob_checkpoint_valid [0:15];
    reg [ 1:0] rob_checkpoint_id [0:15];
    reg        rob_store_valid [0:15];
    reg [ 1:0] rob_store_index [0:15];
    reg [13:0] rob_serial_index [0:15];
    reg [31:0] rob_serial_operand0 [0:15];
    reg [31:0] rob_serial_operand1 [0:15];
    reg        rob_old_rat_mapped [0:15];
    reg [ 4:0] rob_old_rat_tag [0:15];

    (* keep = "true" *) reg        rat_mapped [0:31];
    (* keep = "true" *) reg [ 4:0] rat_tag [0:31];

    // Reservation happens on the existing ID consume edge.  The wide entry
    // write is performed one cycle later from this registered two-slot packet,
    // preventing cache backpressure from driving every ROB entry clock-enable.
    reg        pending0_valid, pending1_valid;
    reg [ 4:0] pending0_tag, pending1_tag;
    reg [31:0] pending0_pc, pending1_pc;
    reg [ 3:0] pending0_class, pending1_class;
    reg [ 4:0] pending0_rd, pending1_rd;
    reg        pending0_writes_rd, pending1_writes_rd;
    reg        pending0_checkpoint_valid, pending1_checkpoint_valid;
    reg [ 1:0] pending0_checkpoint_id, pending1_checkpoint_id;
    reg        pending0_store_valid, pending1_store_valid;
    reg [ 1:0] pending0_store_index, pending1_store_index;
    reg [13:0] pending0_serial_index, pending1_serial_index;
    reg [31:0] pending0_serial_operand0, pending1_serial_operand0;
    reg [31:0] pending0_serial_operand1, pending1_serial_operand1;
    reg        pending0_old_rat_mapped, pending1_old_rat_mapped;
    reg [ 4:0] pending0_old_rat_tag, pending1_old_rat_tag;

    assign occupancy = count;
    assign can_alloc1 = !rollback_busy && !rollback_valid && (count < 5'd16);
    assign can_alloc2 = !rollback_busy && !rollback_valid && (count < 5'd15);
    assign alloc0_tag = tail_ptr;
    assign alloc1_tag = tail_ptr + 5'd1;

    wire alloc_group_ready = alloc1_valid ? can_alloc2 : can_alloc1;
    wire alloc0_fire = alloc0_valid && alloc_group_ready;
    wire alloc1_fire = alloc0_fire && alloc1_valid;
    wire [1:0] alloc_count = alloc1_fire ? 2'd2 :
                             alloc0_fire ? 2'd1 : 2'd0;

    wire [4:0] head1_ptr = head_ptr + 5'd1;
    wire head0_live = (count != 5'd0) && rob_valid[head_ptr[3:0]] &&
                      (rob_generation[head_ptr[3:0]] == head_ptr[4]);
    wire head1_live = (count > 5'd1) && rob_valid[head1_ptr[3:0]] &&
                      (rob_generation[head1_ptr[3:0]] == head1_ptr[4]);

    wire complete0_hits_head0 = complete0_valid &&
                                (complete0_tag == head_ptr);
    wire complete1_hits_head0 = complete1_valid &&
                                (complete1_tag == head_ptr);
    wire complete0_hits_head1 = complete0_valid &&
                                (complete0_tag == head1_ptr);
    wire complete1_hits_head1 = complete1_valid &&
                                (complete1_tag == head1_ptr);
    wire head0_complete_now = rob_complete[head_ptr[3:0]] ||
                              complete0_hits_head0 || complete1_hits_head0;
    wire head1_complete_now = rob_complete[head1_ptr[3:0]] ||
                              complete0_hits_head1 || complete1_hits_head1;
    wire head0_blocks_pair = (rob_class[head_ptr[3:0]] == CLASS_BRANCH) ||
                             (rob_class[head_ptr[3:0]] == CLASS_SERIAL);

    assign commit0_valid = !rollback_busy && !rollback_valid &&
                           head0_live && head0_complete_now;
    assign commit1_valid = commit0_valid && !head0_blocks_pair &&
                           head1_live && head1_complete_now;
    wire [1:0] commit_count = commit1_valid ? 2'd2 :
                              commit0_valid ? 2'd1 : 2'd0;

    // Allocation observes the architectural mapping after same-cycle commit.
    // This matters when a committing destination is immediately renamed again:
    // rollback of the new entry must not resurrect the already retired tag.
    wire alloc0_rat_cleared_by_commit =
        (commit0_valid && commit0_writes_rd &&
         (commit0_rd == alloc0_rd) && (rat_tag[alloc0_rd] == commit0_tag)) ||
        (commit1_valid && commit1_writes_rd &&
         (commit1_rd == alloc0_rd) && (rat_tag[alloc0_rd] == commit1_tag));
    wire alloc1_rat_cleared_by_commit =
        (commit0_valid && commit0_writes_rd &&
         (commit0_rd == alloc1_rd) && (rat_tag[alloc1_rd] == commit0_tag)) ||
        (commit1_valid && commit1_writes_rd &&
         (commit1_rd == alloc1_rd) && (rat_tag[alloc1_rd] == commit1_tag));
    wire alloc0_old_rat_mapped = (alloc0_rd != 5'd0) &&
                                 rat_mapped[alloc0_rd] &&
                                 !alloc0_rat_cleared_by_commit;
    wire alloc1_old_rat_mapped = (alloc1_rd != 5'd0) &&
                                 rat_mapped[alloc1_rd] &&
                                 !alloc1_rat_cleared_by_commit;

    assign commit0_tag = head_ptr;
    assign commit1_tag = head1_ptr;
    assign commit0_pc = rob_pc[head_ptr[3:0]];
    assign commit1_pc = rob_pc[head1_ptr[3:0]];
    assign commit0_class = rob_class[head_ptr[3:0]];
    assign commit1_class = rob_class[head1_ptr[3:0]];
    assign commit0_writes_rd = rob_writes_rd[head_ptr[3:0]];
    assign commit1_writes_rd = rob_writes_rd[head1_ptr[3:0]];
    assign commit0_rd = rob_rd[head_ptr[3:0]];
    assign commit1_rd = rob_rd[head1_ptr[3:0]];
    assign commit0_result = complete0_hits_head0 ? complete0_result :
                            complete1_hits_head0 ? complete1_result :
                            rob_result[head_ptr[3:0]];
    assign commit1_result = complete0_hits_head1 ? complete0_result :
                            complete1_hits_head1 ? complete1_result :
                            rob_result[head1_ptr[3:0]];

    function [38:0] resolve_mapping;
        input       mapped_in;
        input [4:0] tag_in;
        reg         ready_v;
        reg [31:0]  value_v;
        begin
            ready_v = 1'b0;
            value_v = 32'd0;
            if (!mapped_in) begin
                ready_v = 1'b1;
            end else if (complete0_valid && (complete0_tag == tag_in)) begin
                ready_v = 1'b1;
                value_v = complete0_result;
            end else if (complete1_valid && (complete1_tag == tag_in)) begin
                ready_v = 1'b1;
                value_v = complete1_result;
            end else if (rob_valid[tag_in[3:0]] &&
                         (rob_generation[tag_in[3:0]] == tag_in[4]) &&
                         rob_complete[tag_in[3:0]]) begin
                ready_v = 1'b1;
                value_v = rob_result[tag_in[3:0]];
            end
            resolve_mapping = {mapped_in, ready_v, tag_in, value_v};
        end
    endfunction

    wire src00_map = src00_used && (src00_addr != 5'd0) &&
                     rat_mapped[src00_addr];
    wire src01_map = src01_used && (src01_addr != 5'd0) &&
                     rat_mapped[src01_addr];
    wire src10_from_alloc0 = alloc0_fire && alloc0_writes_rd &&
                             (alloc0_rd != 5'd0) && src10_used &&
                             (src10_addr == alloc0_rd);
    wire src11_from_alloc0 = alloc0_fire && alloc0_writes_rd &&
                             (alloc0_rd != 5'd0) && src11_used &&
                             (src11_addr == alloc0_rd);
    wire src10_map = src10_used && (src10_addr != 5'd0) &&
                     (src10_from_alloc0 || rat_mapped[src10_addr]);
    wire src11_map = src11_used && (src11_addr != 5'd0) &&
                     (src11_from_alloc0 || rat_mapped[src11_addr]);
    wire [4:0] src10_map_tag = src10_from_alloc0 ?
                               alloc0_tag : rat_tag[src10_addr];
    wire [4:0] src11_map_tag = src11_from_alloc0 ?
                               alloc0_tag : rat_tag[src11_addr];

    wire [38:0] src00_resolved = resolve_mapping(
        src00_map, rat_tag[src00_addr]);
    wire [38:0] src01_resolved = resolve_mapping(
        src01_map, rat_tag[src01_addr]);
    wire [38:0] src10_resolved = resolve_mapping(
        src10_map, src10_map_tag);
    wire [38:0] src11_resolved = resolve_mapping(
        src11_map, src11_map_tag);

    assign {src00_mapped, src00_ready, src00_tag, src00_value} =
        src00_resolved;
    assign {src01_mapped, src01_ready, src01_tag, src01_value} =
        src01_resolved;
    assign {src10_mapped, src10_ready, src10_tag, src10_value} =
        src10_resolved;
    assign {src11_mapped, src11_ready, src11_tag, src11_value} =
        src11_resolved;

    wire [4:0] rollback_remove_tag = tail_ptr - 5'd1;
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            head_ptr <= 5'd0;
            tail_ptr <= 5'd0;
            count <= 5'd0;
            rollback_busy <= 1'b0;
            rollback_target_tail <= 5'd0;
            pending0_valid <= 1'b0;
            pending1_valid <= 1'b0;
            pending0_tag <= 5'd0;
            pending1_tag <= 5'd0;
            pending0_pc <= 32'd0;
            pending1_pc <= 32'd0;
            pending0_class <= 4'd0;
            pending1_class <= 4'd0;
            pending0_rd <= 5'd0;
            pending1_rd <= 5'd0;
            pending0_writes_rd <= 1'b0;
            pending1_writes_rd <= 1'b0;
            pending0_checkpoint_valid <= 1'b0;
            pending1_checkpoint_valid <= 1'b0;
            pending0_checkpoint_id <= 2'd0;
            pending1_checkpoint_id <= 2'd0;
            pending0_store_valid <= 1'b0;
            pending1_store_valid <= 1'b0;
            pending0_store_index <= 2'd0;
            pending1_store_index <= 2'd0;
            pending0_serial_index <= 14'd0;
            pending1_serial_index <= 14'd0;
            pending0_serial_operand0 <= 32'd0;
            pending1_serial_operand0 <= 32'd0;
            pending0_serial_operand1 <= 32'd0;
            pending1_serial_operand1 <= 32'd0;
            pending0_old_rat_mapped <= 1'b0;
            pending1_old_rat_mapped <= 1'b0;
            pending0_old_rat_tag <= 5'd0;
            pending1_old_rat_tag <= 5'd0;
            for (i = 0; i < 16; i = i + 1) begin
                rob_valid[i] <= 1'b0;
                rob_complete[i] <= 1'b0;
                rob_generation[i] <= 1'b0;
                rob_pc[i] <= 32'd0;
                rob_class[i] <= 4'd0;
                rob_rd[i] <= 5'd0;
                rob_writes_rd[i] <= 1'b0;
                rob_result[i] <= 32'd0;
                rob_checkpoint_valid[i] <= 1'b0;
                rob_checkpoint_id[i] <= 2'd0;
                rob_store_valid[i] <= 1'b0;
                rob_store_index[i] <= 2'd0;
                rob_serial_index[i] <= 14'd0;
                rob_serial_operand0[i] <= 32'd0;
                rob_serial_operand1[i] <= 32'd0;
                rob_old_rat_mapped[i] <= 1'b0;
                rob_old_rat_tag[i] <= 5'd0;
            end
            for (i = 0; i < 32; i = i + 1) begin
                rat_mapped[i] <= 1'b0;
                rat_tag[i] <= 5'd0;
            end
        end else if (rollback_valid) begin
            rollback_target_tail <= rollback_keep_tag + 5'd1;
            rollback_busy <= (tail_ptr != (rollback_keep_tag + 5'd1));
            pending0_valid <= 1'b0;
            pending1_valid <= 1'b0;
            if (pending0_valid) begin
                rob_valid[pending0_tag[3:0]] <= 1'b1;
                rob_complete[pending0_tag[3:0]] <= 1'b0;
                rob_generation[pending0_tag[3:0]] <= pending0_tag[4];
                rob_pc[pending0_tag[3:0]] <= pending0_pc;
                rob_class[pending0_tag[3:0]] <= pending0_class;
                rob_rd[pending0_tag[3:0]] <= pending0_rd;
                rob_writes_rd[pending0_tag[3:0]] <= pending0_writes_rd;
                rob_result[pending0_tag[3:0]] <= 32'd0;
                rob_checkpoint_valid[pending0_tag[3:0]] <= pending0_checkpoint_valid;
                rob_checkpoint_id[pending0_tag[3:0]] <= pending0_checkpoint_id;
                rob_store_valid[pending0_tag[3:0]] <= pending0_store_valid;
                rob_store_index[pending0_tag[3:0]] <= pending0_store_index;
                rob_serial_index[pending0_tag[3:0]] <= pending0_serial_index;
                rob_serial_operand0[pending0_tag[3:0]] <= pending0_serial_operand0;
                rob_serial_operand1[pending0_tag[3:0]] <= pending0_serial_operand1;
                rob_old_rat_mapped[pending0_tag[3:0]] <= pending0_old_rat_mapped;
                rob_old_rat_tag[pending0_tag[3:0]] <= pending0_old_rat_tag;
            end
            if (pending1_valid) begin
                rob_valid[pending1_tag[3:0]] <= 1'b1;
                rob_complete[pending1_tag[3:0]] <= 1'b0;
                rob_generation[pending1_tag[3:0]] <= pending1_tag[4];
                rob_pc[pending1_tag[3:0]] <= pending1_pc;
                rob_class[pending1_tag[3:0]] <= pending1_class;
                rob_rd[pending1_tag[3:0]] <= pending1_rd;
                rob_writes_rd[pending1_tag[3:0]] <= pending1_writes_rd;
                rob_result[pending1_tag[3:0]] <= 32'd0;
                rob_checkpoint_valid[pending1_tag[3:0]] <= pending1_checkpoint_valid;
                rob_checkpoint_id[pending1_tag[3:0]] <= pending1_checkpoint_id;
                rob_store_valid[pending1_tag[3:0]] <= pending1_store_valid;
                rob_store_index[pending1_tag[3:0]] <= pending1_store_index;
                rob_serial_index[pending1_tag[3:0]] <= pending1_serial_index;
                rob_serial_operand0[pending1_tag[3:0]] <= pending1_serial_operand0;
                rob_serial_operand1[pending1_tag[3:0]] <= pending1_serial_operand1;
                rob_old_rat_mapped[pending1_tag[3:0]] <= pending1_old_rat_mapped;
                rob_old_rat_tag[pending1_tag[3:0]] <= pending1_old_rat_tag;
            end
            // A redirect may coincide with an older WB completion.  Commit is
            // intentionally suppressed during rollback, so retain that pulse
            // in the ROB instead of losing it while younger entries unwind.
            if (complete0_valid &&
                ((rob_valid[complete0_tag[3:0]] &&
                  (rob_generation[complete0_tag[3:0]] == complete0_tag[4])) ||
                 (pending0_valid && (pending0_tag == complete0_tag)) ||
                 (pending1_valid && (pending1_tag == complete0_tag)))) begin
                rob_complete[complete0_tag[3:0]] <= 1'b1;
                rob_result[complete0_tag[3:0]] <= complete0_result;
            end
            if (complete1_valid &&
                ((rob_valid[complete1_tag[3:0]] &&
                  (rob_generation[complete1_tag[3:0]] == complete1_tag[4])) ||
                 (pending0_valid && (pending0_tag == complete1_tag)) ||
                 (pending1_valid && (pending1_tag == complete1_tag)))) begin
                rob_complete[complete1_tag[3:0]] <= 1'b1;
                rob_result[complete1_tag[3:0]] <= complete1_result;
            end
        end else if (rollback_busy) begin
            // Backend stages are allowed to drain while rollback removes only
            // buffered, never-executed younger instructions.  Preserve any
            // completion from the kept branch or an older instruction.
            if (complete0_valid && rob_valid[complete0_tag[3:0]] &&
                (rob_generation[complete0_tag[3:0]] == complete0_tag[4])) begin
                rob_complete[complete0_tag[3:0]] <= 1'b1;
                rob_result[complete0_tag[3:0]] <= complete0_result;
            end
            if (complete1_valid && rob_valid[complete1_tag[3:0]] &&
                (rob_generation[complete1_tag[3:0]] == complete1_tag[4])) begin
                rob_complete[complete1_tag[3:0]] <= 1'b1;
                rob_result[complete1_tag[3:0]] <= complete1_result;
            end
            rob_valid[rollback_remove_tag[3:0]] <= 1'b0;
            rob_complete[rollback_remove_tag[3:0]] <= 1'b0;
            tail_ptr <= rollback_remove_tag;
            count <= count - 5'd1;
            if (rob_writes_rd[rollback_remove_tag[3:0]] &&
                (rob_rd[rollback_remove_tag[3:0]] != 5'd0)) begin
                rat_mapped[rob_rd[rollback_remove_tag[3:0]]] <=
                    rob_old_rat_mapped[rollback_remove_tag[3:0]];
                rat_tag[rob_rd[rollback_remove_tag[3:0]]] <=
                    rob_old_rat_tag[rollback_remove_tag[3:0]];
            end
            if (rollback_remove_tag == rollback_target_tail)
                rollback_busy <= 1'b0;
        end else begin
            head_ptr <= head_ptr + commit_count;
            tail_ptr <= tail_ptr + alloc_count;
            count <= count + alloc_count - commit_count;

            pending0_valid <= alloc0_fire;
            pending1_valid <= alloc1_fire;
            pending0_tag <= alloc0_tag;
            pending1_tag <= alloc1_tag;
            pending0_pc <= alloc0_pc;
            pending1_pc <= alloc1_pc;
            pending0_class <= alloc0_class;
            pending1_class <= alloc1_class;
            pending0_rd <= alloc0_rd;
            pending1_rd <= alloc1_rd;
            pending0_writes_rd <= alloc0_writes_rd && (alloc0_rd != 5'd0);
            pending1_writes_rd <= alloc1_writes_rd && (alloc1_rd != 5'd0);
            pending0_checkpoint_valid <= alloc0_checkpoint_valid;
            pending1_checkpoint_valid <= alloc1_checkpoint_valid;
            pending0_checkpoint_id <= alloc0_checkpoint_id;
            pending1_checkpoint_id <= alloc1_checkpoint_id;
            pending0_store_valid <= alloc0_store_valid;
            pending1_store_valid <= alloc1_store_valid;
            pending0_store_index <= alloc0_store_index;
            pending1_store_index <= alloc1_store_index;
            pending0_serial_index <= alloc0_serial_index;
            pending1_serial_index <= alloc1_serial_index;
            pending0_serial_operand0 <= alloc0_serial_operand0;
            pending1_serial_operand0 <= alloc1_serial_operand0;
            pending0_serial_operand1 <= alloc0_serial_operand1;
            pending1_serial_operand1 <= alloc1_serial_operand1;
            pending0_old_rat_mapped <= alloc0_old_rat_mapped;
            pending0_old_rat_tag <= rat_tag[alloc0_rd];
            pending1_old_rat_mapped <= (alloc1_rd != 5'd0) &&
                ((alloc0_writes_rd && (alloc0_rd == alloc1_rd) &&
                  (alloc0_rd != 5'd0)) || alloc1_old_rat_mapped);
            pending1_old_rat_tag <=
                (alloc0_writes_rd && (alloc0_rd == alloc1_rd) &&
                 (alloc0_rd != 5'd0)) ? alloc0_tag : rat_tag[alloc1_rd];

            if (pending0_valid) begin
                rob_valid[pending0_tag[3:0]] <= 1'b1;
                rob_complete[pending0_tag[3:0]] <= 1'b0;
                rob_generation[pending0_tag[3:0]] <= pending0_tag[4];
                rob_pc[pending0_tag[3:0]] <= pending0_pc;
                rob_class[pending0_tag[3:0]] <= pending0_class;
                rob_rd[pending0_tag[3:0]] <= pending0_rd;
                rob_writes_rd[pending0_tag[3:0]] <= pending0_writes_rd;
                rob_result[pending0_tag[3:0]] <= 32'd0;
                rob_checkpoint_valid[pending0_tag[3:0]] <= pending0_checkpoint_valid;
                rob_checkpoint_id[pending0_tag[3:0]] <= pending0_checkpoint_id;
                rob_store_valid[pending0_tag[3:0]] <= pending0_store_valid;
                rob_store_index[pending0_tag[3:0]] <= pending0_store_index;
                rob_serial_index[pending0_tag[3:0]] <= pending0_serial_index;
                rob_serial_operand0[pending0_tag[3:0]] <= pending0_serial_operand0;
                rob_serial_operand1[pending0_tag[3:0]] <= pending0_serial_operand1;
                rob_old_rat_mapped[pending0_tag[3:0]] <= pending0_old_rat_mapped;
                rob_old_rat_tag[pending0_tag[3:0]] <= pending0_old_rat_tag;
            end
            if (pending1_valid) begin
                rob_valid[pending1_tag[3:0]] <= 1'b1;
                rob_complete[pending1_tag[3:0]] <= 1'b0;
                rob_generation[pending1_tag[3:0]] <= pending1_tag[4];
                rob_pc[pending1_tag[3:0]] <= pending1_pc;
                rob_class[pending1_tag[3:0]] <= pending1_class;
                rob_rd[pending1_tag[3:0]] <= pending1_rd;
                rob_writes_rd[pending1_tag[3:0]] <= pending1_writes_rd;
                rob_result[pending1_tag[3:0]] <= 32'd0;
                rob_checkpoint_valid[pending1_tag[3:0]] <= pending1_checkpoint_valid;
                rob_checkpoint_id[pending1_tag[3:0]] <= pending1_checkpoint_id;
                rob_store_valid[pending1_tag[3:0]] <= pending1_store_valid;
                rob_store_index[pending1_tag[3:0]] <= pending1_store_index;
                rob_serial_index[pending1_tag[3:0]] <= pending1_serial_index;
                rob_serial_operand0[pending1_tag[3:0]] <= pending1_serial_operand0;
                rob_serial_operand1[pending1_tag[3:0]] <= pending1_serial_operand1;
                rob_old_rat_mapped[pending1_tag[3:0]] <= pending1_old_rat_mapped;
                rob_old_rat_tag[pending1_tag[3:0]] <= pending1_old_rat_tag;
            end

            if (complete0_valid &&
                ((rob_valid[complete0_tag[3:0]] &&
                  (rob_generation[complete0_tag[3:0]] == complete0_tag[4])) ||
                 (pending0_valid && (pending0_tag == complete0_tag)) ||
                 (pending1_valid && (pending1_tag == complete0_tag)))) begin
                rob_complete[complete0_tag[3:0]] <= 1'b1;
                rob_result[complete0_tag[3:0]] <= complete0_result;
            end
            if (complete1_valid &&
                ((rob_valid[complete1_tag[3:0]] &&
                  (rob_generation[complete1_tag[3:0]] == complete1_tag[4])) ||
                 (pending0_valid && (pending0_tag == complete1_tag)) ||
                 (pending1_valid && (pending1_tag == complete1_tag)))) begin
                rob_complete[complete1_tag[3:0]] <= 1'b1;
                rob_result[complete1_tag[3:0]] <= complete1_result;
            end

            if (commit0_valid) begin
                rob_valid[commit0_tag[3:0]] <= 1'b0;
                rob_complete[commit0_tag[3:0]] <= 1'b0;
                if (commit0_writes_rd && (commit0_rd != 5'd0) &&
                    rat_mapped[commit0_rd] &&
                    (rat_tag[commit0_rd] == commit0_tag))
                    rat_mapped[commit0_rd] <= 1'b0;
            end
            if (commit1_valid) begin
                rob_valid[commit1_tag[3:0]] <= 1'b0;
                rob_complete[commit1_tag[3:0]] <= 1'b0;
                if (commit1_writes_rd && (commit1_rd != 5'd0) &&
                    rat_mapped[commit1_rd] &&
                    (rat_tag[commit1_rd] == commit1_tag))
                    rat_mapped[commit1_rd] <= 1'b0;
            end

            if (alloc0_fire) begin
                if (alloc0_writes_rd && (alloc0_rd != 5'd0)) begin
                    rat_mapped[alloc0_rd] <= 1'b1;
                    rat_tag[alloc0_rd] <= alloc0_tag;
                end
            end
            if (alloc1_fire) begin
                if (alloc1_writes_rd && (alloc1_rd != 5'd0)) begin
                    rat_mapped[alloc1_rd] <= 1'b1;
                    rat_tag[alloc1_rd] <= alloc1_tag;
                end
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (!reset && alloc1_valid && !alloc0_valid) begin
            $display("FAIL ROB slot1 allocated without slot0");
            $fatal(1);
        end
        if (!reset && alloc0_valid && !alloc_group_ready) begin
            $display("FAIL ROB allocation attempted while full/rollback");
            $fatal(1);
        end
        if (!reset && (count > 5'd16)) begin
            $display("FAIL ROB occupancy overflow count=%0d", count);
            $fatal(1);
        end
    end
`endif
endmodule
