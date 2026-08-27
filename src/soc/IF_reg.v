/**
 * @file IF_reg.v
 * @author refactored (5-stage version)
 * @brief IF阶段流水线寄存器：PC寄存器和IF_valid寄存器
 */
`include "myCPU.h"
module IF_reg(
    input  wire          clk,
    input  wire          reset,

    // 控制信号
    input  wire          IF_allow_in,
    input  wire          Pre_to_IF_valid,
    input  wire [31:0]   next_PC,
    input  wire          br_taken_cancel,

    // 输出
    // Keep the pipeline write enable on the FPGA register CE pin.  Otherwise
    // Vivado may absorb IF_allow_in into the PC data mux/adder and create a
    // long D-cache-hit -> pipeline-ready -> next-PC combinational path.
    (* extract_enable = "yes" *) output wire [31:0]   PC,
    (* extract_enable = "yes" *) output reg           IF_valid
);

    // IF_valid
    always@(posedge clk) begin
        if(reset)
            IF_valid <= 1'b0;
        else if(IF_allow_in)
            IF_valid <= Pre_to_IF_valid;
        // While a redirect waits for an outstanding cache response, retain
        // IF_valid.  The response is consumed/discarded when IF_allow_in goes
        // high, and PC is changed to the branch target in the same cycle.
    end

    // PC.  Instantiate the native CE explicitly for synthesis so back-pressure
    // terminates at the CE pin instead of being folded into the next-PC data
    // mux.  RTL simulation keeps the equivalent clocked model because UNISIM
    // primitives include delays that are inappropriate for this zero-delay TB.
    localparam [31:0] RESET_PC = 32'h1c00_0000 - 32'd4;
    wire pc_ce = IF_allow_in & Pre_to_IF_valid;
`ifdef SYNTHESIS
    genvar pc_bit;
    generate
        for (pc_bit = 0; pc_bit < 32; pc_bit = pc_bit + 1) begin : gen_pc
            if (RESET_PC[pc_bit]) begin : gen_set
                FDSE #(.INIT(1'b0)) pc_ff (
                    .Q(PC[pc_bit]), .C(clk), .CE(pc_ce),
                    .D(next_PC[pc_bit]), .S(reset)
                );
            end else begin : gen_reset
                FDRE #(.INIT(1'b0)) pc_ff (
                    .Q(PC[pc_bit]), .C(clk), .CE(pc_ce),
                    .D(next_PC[pc_bit]), .R(reset)
                );
            end
        end
    endgenerate
`else
    reg [31:0] pc_sim;
    assign PC = pc_sim;
    always @(posedge clk) begin
        if (reset)
            pc_sim <= RESET_PC;
        else if (pc_ce)
            pc_sim <= next_PC;
    end
`endif

endmodule
