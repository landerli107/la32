/**
 * @file ID_reg.v
 * @brief Ordered two-entry IF/ID queue.
 *
 * The fetch response may contain one or two consecutive instructions.  The
 * issue side may consume slot0 only or both slots.  When only slot0 issues,
 * slot1 is retained and shifted into slot0 before any newly accepted fetch
 * response is appended.  The queue therefore never exposes a younger
 * instruction ahead of an older retained instruction.
 */
`include "myCPU.h"
module ID_reg(
    input  wire          clk,
    input  wire          reset,

    input  wire          IF_to_ID_valid,
    input  wire          IF_to_ID_valid1,
    input  wire          issue_slot0,
    input  wire          issue_slot1,
    input  wire          br_taken_cancel,
    input  wire [`IF_TO_ID_BUS_WD-1:0] IF_to_ID_bus,
    input  wire [`IF_TO_ID_BUS_WD-1:0] IF_to_ID_bus1,

    (* extract_enable = "yes" *) output reg [`IF_TO_ID_BUS_WD-1:0] IF_to_ID_reg_data,
    (* extract_enable = "yes" *) output wire [`IF_TO_ID_BUS_WD-1:0] IF_to_ID_reg_data1,
    (* extract_enable = "yes" *) output reg ID_valid,
    (* extract_enable = "yes" *) output reg ID_valid1,
    output wire IF_allow_in
);

    // issue_slot0/1 are already fully qualified consume pulses from id_run:
    // slot0 implies ID_valid, and slot1 implies both slot0 and ID_valid1.
    // Rechecking those state bits here only deepens the IF/ID queue update path.
    wire pop0 = issue_slot0;
    wire pop1 = issue_slot1;

    wire remain_valid0 = pop0 ? (pop1 ? 1'b0 : ID_valid1) : ID_valid;
    wire remain_valid1 = pop0 ? 1'b0 : ID_valid1;
    wire [1:0] remain_count = remain_valid1 ? 2'd2 :
                              remain_valid0 ? 2'd1 : 2'd0;
    wire fetch_fits = IF_to_ID_valid1 ? ~remain_valid0 : ~remain_valid1;

    // IF_to_ID_valid is low while no response is present and also while a
    // redirect discards a wrong-path response.  Neither case needs queue
    // capacity.  Otherwise reserve enough room for the complete fetch group;
    // accepting only its older half would lose the younger instruction.
    assign IF_allow_in = br_taken_cancel | ~IF_to_ID_valid | fetch_fits;

    // This enable reaches the two wide slot-1 candidate banks.  Bound its
    // physical fanout so synthesis replicates the small capacity predicate
    // close to those registers instead of routing one 280+ sink control net
    // across the complete decode/forwarding region.
    (* max_fanout = 32 *) wire accept_fetch =
        IF_to_ID_valid & fetch_fits & ~br_taken_cancel;

    reg next_valid0;
    reg next_valid1;

    always @(*) begin
        next_valid0 = remain_valid0;
        next_valid1 = remain_valid1;

        if (accept_fetch) begin
            case (remain_count)
                2'd0: begin
                    next_valid0 = 1'b1;
                    next_valid1 = IF_to_ID_valid1;
                end
                2'd1: begin
                    next_valid1 = 1'b1;
                end
                default: begin
                    // IF_allow_in prevents an append to a full queue.
                end
            endcase
        end
    end

    // Encode slot0's two real updates directly.  A new packet replaces slot0
    // when the queue was empty or both old slots issue; a single-slot issue
    // shifts old slot1 forward.  This is equivalent to the remain_valid mux,
    // but removes that generic capacity cone from the 160 payload D inputs.
    wire pop_empties_queue = pop0 & (~ID_valid1 | pop1);
    wire load_input0 = IF_to_ID_valid & ~br_taken_cancel &
                       (~ID_valid | pop_empties_queue);
    // The payload changes on every slot-0 pop, regardless of whether the
    // replacement comes from slot1 or the incoming fetch packet.  Expressing
    // that common enable separately keeps the slot1 issue decision off the
    // 160-bit register CE path; it remains only on the data-select path.
    wire write_data0 = pop0 |
                       (IF_to_ID_valid & ~br_taken_cancel & ~ID_valid);

    // When a fetch packet is appended, slot1 receives input slot0 if one old
    // instruction remains, otherwise it receives input slot1.  Duplicating
    // the two candidates moves the late issue/forwarding decision from 160
    // payload D pins to one registered select bit.  This preserves the exact
    // queue semantics while cutting the routed D-cache-response critical path.
    (* extract_enable = "yes" *) reg [`IF_TO_ID_BUS_WD-1:0]
        slot1_input0_data;
    (* extract_enable = "yes" *) reg [`IF_TO_ID_BUS_WD-1:0]
        slot1_input1_data;
    reg slot1_select_input0;
    assign IF_to_ID_reg_data1 = slot1_select_input0 ?
                                slot1_input0_data : slot1_input1_data;

    always @(posedge clk) begin
        if (reset || br_taken_cancel) begin
            ID_valid <= 1'b0;
            ID_valid1 <= 1'b0;
            IF_to_ID_reg_data <= {`IF_TO_ID_BUS_WD{1'b0}};
            slot1_input0_data <= {`IF_TO_ID_BUS_WD{1'b0}};
            slot1_input1_data <= {`IF_TO_ID_BUS_WD{1'b0}};
            slot1_select_input0 <= 1'b0;
        end else begin
            ID_valid <= next_valid0;
            ID_valid1 <= next_valid1;
            if (write_data0) begin
                if (load_input0)
                    IF_to_ID_reg_data <= IF_to_ID_bus;
                else
                    IF_to_ID_reg_data <= IF_to_ID_reg_data1;
            end
            if (accept_fetch) begin
                slot1_input0_data <= IF_to_ID_bus;
                slot1_input1_data <= IF_to_ID_bus1;
                slot1_select_input0 <= remain_valid0;
            end
        end
    end

endmodule
