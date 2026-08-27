`default_nettype none

`ifdef VERILATOR
// The HDL lint environment does not load the Xilinx UNISIM library. These
// declarations are lint-only black boxes; Vivado resolves the real primitives.
(* black_box *) module MMCME2_BASE #(
    parameter BANDWIDTH = "OPTIMIZED",
    parameter real CLKIN1_PERIOD = 0.0,
    parameter integer DIVCLK_DIVIDE = 1,
    parameter real CLKFBOUT_MULT_F = 5.0,
    parameter real CLKOUT0_DIVIDE_F = 1.0,
    parameter real CLKOUT0_DUTY_CYCLE = 0.5,
    parameter STARTUP_WAIT = "FALSE"
) (
    input  wire CLKIN1,
    input  wire RST,
    input  wire PWRDWN,
    input  wire CLKFBIN,
    output wire CLKFBOUT,
    output wire CLKOUT0,
    output wire LOCKED
);
endmodule

(* black_box *) module BUFG (
    input  wire I,
    output wire O
);
endmodule
`endif

// 50 MHz input -> 106 MHz CPU clock.
module cpu_pll (
    input  wire clk_in,
    input  wire reset,
    output wire clk_out,
    output wire locked
);
    wire clk_fb;
    wire clk_fb_buf;
    wire clk_raw;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(20.000),
        // VCO = 50 MHz * 19.875 = 993.75 MHz.
        // CPU = 993.75 MHz / 9.375 = 106 MHz.
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(19.875),
        .CLKOUT0_DIVIDE_F(9.375),
        .CLKOUT0_DUTY_CYCLE(0.500),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKIN1(clk_in),
        .RST(reset),
        .PWRDWN(1'b0),
        .CLKFBIN(clk_fb_buf),
        .CLKFBOUT(clk_fb),
        .CLKOUT0(clk_raw),
        .LOCKED(locked)
    );

    BUFG u_fb_buf  (.I(clk_fb),  .O(clk_fb_buf));
    BUFG u_out_buf (.I(clk_raw), .O(clk_out));
endmodule

`default_nettype wire
