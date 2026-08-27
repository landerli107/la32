/**
 * @file RegFile.v
 * @author ykykzq (5-stage version)
 * @brief 寄存器堆：32个32位寄存器
 * @version 0.1
 * @date 2024-08-12
 */
module RegFile(
    input  wire        clk,
    input  wire [ 4:0] r_addr1,
    input  wire [ 4:0] r_addr2,
    output wire [31:0] r_data1,
    output wire [31:0] r_data2,
    input  wire [ 4:0] r_addr3,
    input  wire [ 4:0] r_addr4,
    output wire [31:0] r_data3,
    output wire [31:0] r_data4,

    input  wire [31:0] w_data,
    input  wire [ 4:0] w_addr,
    input  wire        w_en,
    input  wire [31:0] w_data2,
    input  wire [ 4:0] w_addr2,
    input  wire        w_en2
);

    // Replication supplies four asynchronous read ports without creating a
    // large 4R memory.  Both write ports update both copies; on an accidental
    // same-address write, slot1 is younger and therefore wins.
    reg [31:0] Reg_File0 [0:31];
    reg [31:0] Reg_File1 [0:31];

    always@(posedge clk) begin
        if(w_en && w_addr!=5'b0) begin
            Reg_File0[w_addr] <= w_data;
            Reg_File1[w_addr] <= w_data;
        end
        if(w_en2 && w_addr2!=5'b0) begin
            Reg_File0[w_addr2] <= w_data2;
            Reg_File1[w_addr2] <= w_data2;
        end
    end

    assign r_data1 = (r_addr1==5'b0) ? 32'b0 : Reg_File0[r_addr1];
    assign r_data2 = (r_addr2==5'b0) ? 32'b0 : Reg_File0[r_addr2];
    assign r_data3 = (r_addr3==5'b0) ? 32'b0 : Reg_File1[r_addr3];
    assign r_data4 = (r_addr4==5'b0) ? 32'b0 : Reg_File1[r_addr4];

endmodule
