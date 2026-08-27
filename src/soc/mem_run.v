/**
 * @file mem_run.v
 * @author refactored (5-stage version)
 * @brief MEM stage combinational logic
 */
`include "myCPU.h"
module mem_run(
    // From MEM_reg
    input  wire [`EXE_TO_MEM_BUS_WD-1:0]  EXE_to_MEM_reg_data,
    input  wire                            MEM_valid,

    // Pipeline data
    output wire [`MEM_TO_WB_BUS_WD-1:0]   MEM_to_WB_bus,
    output wire [`MEM_TO_BY_BUS_WD-1:0]   MEM_to_BY_bus,
    output wire [4:0]                     mem_store_forward_addr,
    output wire [31:0]                    mem_store_forward_data,
    output wire                           mem_store_forward_valid,

    // Pipeline control
    input  wire                           WB_allow_in,
    output wire                           MEM_allow_in,
    output wire                           MEM_to_WB_valid,

    // Data RAM
    output wire                           data_ram_en,
    output wire [31:0]                    data_ram_addr,
    output wire [3:0]                     data_ram_w_en,
    input  wire [31:0]                    data_ram_r_data,
    input  wire                           data_ram_data_ok,
    input  wire                           data_ram_id_forward_ok,
    input  wire [31:0]                    data_ram_id_forward_data,
    output reg  [31:0]                    data_ram_w_data
);

    // EXE_to_MEM_reg decode
    wire [2:0]  sel_rf_w_data_valid_stage;
    wire        sel_rf_w_en;
    wire        sel_rf_w_data;
    wire [1:0]  sel_data_ram_wd;
    wire        sel_data_ram_extend;
    wire        sel_data_ram_we;
    wire        sel_data_ram_en;
    wire [31:0] data_ram_wdata_from_exe;
    wire [4:0]  RegFile_w_addr;
    wire [31:0] alu_result;
    wire [31:0] inst_PC;

    // Data RAM
    wire [31:0] data_ram_addr_from_alu;
    reg  [3:0]  data_ram_b_en;

    // Forwarding
    wire        MEM_sel_rf_w_data_valid;
    wire        MEM_forward_to_id_valid;
    wire        MEM_ready_go;
    wire        mem_store_forward_is_word;
    reg  [31:0] mem_store_forward_subword;

    /////////////////////////////////////////////////////////
    // Pipeline control
    assign MEM_ready_go       = (~sel_data_ram_en) | data_ram_data_ok;
    assign MEM_allow_in       = (~MEM_valid) | (MEM_ready_go & WB_allow_in);
    assign MEM_to_WB_valid    = MEM_valid & MEM_ready_go;

    /////////////////////////////////////////////////////////
    // EXE_to_MEM_reg decode
    assign {
        sel_rf_w_data_valid_stage, // 3
        sel_rf_w_en,               // 1
        sel_rf_w_data,             // 1
        sel_data_ram_wd,           // 2
        sel_data_ram_extend,       // 1
        sel_data_ram_we,           // 1
        sel_data_ram_en,           // 1
        data_ram_wdata_from_exe,   // 32
        RegFile_w_addr,            // 5
        alu_result,                // 32
        inst_PC                    // 32
    } = EXE_to_MEM_reg_data;

    /////////////////////////////////////////////////////////
    // Forwarding valid
    assign MEM_sel_rf_w_data_valid = MEM_valid & MEM_ready_go
        & (sel_rf_w_data_valid_stage[0] | sel_rf_w_data_valid_stage[1]
           | sel_rf_w_data_valid_stage[2]);
    assign MEM_forward_to_id_valid = MEM_valid &
        (sel_rf_w_data_valid_stage[0] | sel_rf_w_data_valid_stage[2] |
         (sel_rf_w_data_valid_stage[1] & data_ram_id_forward_ok &
          ~(sel_data_ram_wd[1] | sel_data_ram_wd[0])));

    /////////////////////////////////////////////////////////
    // Data RAM signals
    assign data_ram_en            = MEM_valid & sel_data_ram_en;
    assign data_ram_addr_from_alu = alu_result;
    assign data_ram_addr          = data_ram_addr_from_alu;
    assign mem_store_forward_is_word = ~(sel_data_ram_wd[1] | sel_data_ram_wd[0]);

    always @(*) begin
        if (sel_data_ram_wd[1]) begin
            case (data_ram_addr_from_alu[1:0])
                2'b00:   data_ram_b_en <= 4'b0001;
                2'b01:   data_ram_b_en <= 4'b0010;
                2'b10:   data_ram_b_en <= 4'b0100;
                2'b11:   data_ram_b_en <= 4'b1000;
                default: data_ram_b_en <= 4'b0000;
            endcase
        end else if (sel_data_ram_wd[0]) begin
            if (data_ram_addr_from_alu[1:0] == 2'b00)
                data_ram_b_en <= 4'b0011;
            else
                data_ram_b_en <= 4'b1100;
        end else begin
            data_ram_b_en <= 4'b1111;
        end
    end

    assign data_ram_w_en = (MEM_valid & sel_data_ram_we) ? data_ram_b_en : 4'b0000;

    always @(*) begin
        if (sel_data_ram_wd[1]) begin
            case (data_ram_addr_from_alu[1:0])
                2'b00:   data_ram_w_data <= {24'b0, data_ram_wdata_from_exe[7:0]};
                2'b01:   data_ram_w_data <= {16'b0, data_ram_wdata_from_exe[7:0], 8'b0};
                2'b10:   data_ram_w_data <= {8'b0, data_ram_wdata_from_exe[7:0], 16'b0};
                2'b11:   data_ram_w_data <= {data_ram_wdata_from_exe[7:0], 24'b0};
                default: data_ram_w_data <= 32'b0;
            endcase
        end else if (sel_data_ram_wd[0]) begin
            if (data_ram_addr_from_alu[1:0] == 2'b00)
                data_ram_w_data <= {16'b0, data_ram_wdata_from_exe[15:0]};
            else
                data_ram_w_data <= {data_ram_wdata_from_exe[15:0], 16'b0};
        end else begin
            data_ram_w_data <= data_ram_wdata_from_exe;
        end
    end

    always @(*) begin
        if (sel_rf_w_data_valid_stage[0] | sel_rf_w_data_valid_stage[2])
            mem_store_forward_subword <= alu_result;
        else if (sel_data_ram_wd[1] == 1'b1)
            if (data_ram_b_en == 4'b0001)
                if (sel_data_ram_extend)
                    mem_store_forward_subword <= {24'b0, data_ram_r_data[7:0]};
                else
                    mem_store_forward_subword <= {{24{data_ram_r_data[7]}}, data_ram_r_data[7:0]};
            else if (data_ram_b_en == 4'b0010)
                if (sel_data_ram_extend)
                    mem_store_forward_subword <= {24'b0, data_ram_r_data[15:8]};
                else
                    mem_store_forward_subword <= {{24{data_ram_r_data[15]}}, data_ram_r_data[15:8]};
            else if (data_ram_b_en == 4'b0100)
                if (sel_data_ram_extend)
                    mem_store_forward_subword <= {24'b0, data_ram_r_data[23:16]};
                else
                    mem_store_forward_subword <= {{24{data_ram_r_data[23]}}, data_ram_r_data[23:16]};
            else if (data_ram_b_en == 4'b1000)
                if (sel_data_ram_extend)
                    mem_store_forward_subword <= {24'b0, data_ram_r_data[31:24]};
                else
                    mem_store_forward_subword <= {{24{data_ram_r_data[31]}}, data_ram_r_data[31:24]};
            else
                mem_store_forward_subword <= 32'b0;
        else if (sel_data_ram_wd[0] == 1'b1)
            if (data_ram_b_en == 4'b0011)
                if (sel_data_ram_extend)
                    mem_store_forward_subword <= {16'b0, data_ram_r_data[15:0]};
                else
                    mem_store_forward_subword <= {{16{data_ram_r_data[15]}}, data_ram_r_data[15:0]};
            else if (data_ram_b_en == 4'b1100)
                if (sel_data_ram_extend)
                    mem_store_forward_subword <= {16'b0, data_ram_r_data[31:16]};
                else
                    mem_store_forward_subword <= {{16{data_ram_r_data[31]}}, data_ram_r_data[31:16]};
            else
                mem_store_forward_subword <= 32'b0;
        else
            mem_store_forward_subword <= data_ram_r_data;
    end

    assign mem_store_forward_addr  = RegFile_w_addr;
    // The three result-stage bits are one-hot for every decoded writer.
    // A valid MEM store-forward is therefore load data exactly when stage 1
    // is set; all other observable forward results come from the ALU path.
    assign mem_store_forward_data  =
        sel_rf_w_data_valid_stage[1] ?
        (mem_store_forward_is_word ? data_ram_r_data :
         mem_store_forward_subword) :
        alu_result;
    assign mem_store_forward_valid = MEM_valid & sel_rf_w_en & MEM_sel_rf_w_data_valid;

    /////////////////////////////////////////////////////////
    // Output buses
    assign MEM_to_WB_bus = {
        sel_rf_w_data_valid_stage, // 3
        sel_rf_w_en,               // 1
        sel_rf_w_data,             // 1
        sel_data_ram_wd,           // 2
        sel_data_ram_extend,       // 1
        data_ram_b_en,             // 4
        data_ram_r_data,           // 32: raw response retained for WB
        RegFile_w_addr,            // 5
        alu_result,                // 32
        inst_PC                    // 32
    };

    assign MEM_to_BY_bus = {
        sel_rf_w_data_valid_stage, // 3
        data_ram_b_en,             // 4
        RegFile_w_addr,            // 5
        data_ram_id_forward_data,  // 32: timing-isolated ID load response
        alu_result,                // 32
        MEM_forward_to_id_valid,   // 1
        sel_data_ram_wd,           // 2
        sel_data_ram_extend,       // 1
        MEM_valid,                 // 1
        sel_rf_w_en                // 1
    };

endmodule
