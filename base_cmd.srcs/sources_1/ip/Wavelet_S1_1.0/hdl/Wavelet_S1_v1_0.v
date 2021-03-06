`timescale 1 ns / 1 ps
/*
=================================================================================
Wavelet_S1_v1_0.v
Top module for first stage of wavelet engine. Receives pixel data from the
CMV_Input block and performs a 2D DWT via separate horizontal and then vertical
wavelet cores. The results are passed to encoders (HH1, HL1, LH1) or to the next
wavelet stage (LL1). Control and configuration is done through an AXI-Lite slave.
=================================================================================
*/

// Color field enumeration.
`define COLOR_G1 2'b00
`define COLOR_R1 2'b01
`define COLOR_B1 2'b10
`define COLOR_G2 2'b11

module Wavelet_S1_v1_0 #
(
	// Users to add parameters here
    parameter integer PX_MATH_WIDTH = 12,
	// User parameters ends
	// Do not modify the parameters beyond this line

	// Parameters of Axi Slave Bus Interface S00_AXI
	parameter integer C_S00_AXI_DATA_WIDTH	= 32,
	parameter integer C_S00_AXI_ADDR_WIDTH	= 5
)
(
	// Users to add ports here
		
	input wire px_clk,
	input wire px_clk_2x,
	input wire signed [23:0] px_count,
	input wire [9:0] px_ctr,
	input wire [639:0] px_chXX_concat,
		
    output wire [1023:0] HH1_concat,
	output wire [1023:0] HL1_concat,
	output wire [1023:0] LH1_concat,
	output wire [1023:0] LL1_concat,
	
	// User ports ends
		
	// Do not modify the ports beyond this line

	// Ports of Axi Slave Bus Interface S00_AXI
	input wire  s00_axi_aclk,
	input wire  s00_axi_aresetn,
	input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
	input wire [2 : 0] s00_axi_awprot,
	input wire  s00_axi_awvalid,
	output wire  s00_axi_awready,
	input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
	input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
	input wire  s00_axi_wvalid,
	output wire  s00_axi_wready,
	output wire [1 : 0] s00_axi_bresp,
	output wire  s00_axi_bvalid,
	input wire  s00_axi_bready,
	input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
	input wire [2 : 0] s00_axi_arprot,
	input wire  s00_axi_arvalid,
	output wire  s00_axi_arready,
	output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
	output wire [1 : 0] s00_axi_rresp,
	output wire  s00_axi_rvalid,
	input wire  s00_axi_rready
);

// AXI Slave module control signals.
wire SS;
wire signed [23:0] px_count_v1_G1B1_offset;
wire signed [23:0] px_count_v1_R1G2_offset;

// Debug port for peeking at wavelet core data through AXI.
wire signed [23:0] debug_px_count_trig;
wire [31:0] debug_core_addr;
reg [31:0] debug_core_HH1_data;
reg [31:0] debug_core_HL1_data;
reg [31:0] debug_core_LH1_data;
reg [31:0] debug_core_LL1_data;

// Instantiation of Axi Bus Interface S00_AXI
Wavelet_S1_v1_0_S00_AXI 
#( 
    .C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
	.C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
) 
Wavelet_S1_v1_0_S00_AXI_inst 
(
  .SS(SS),
  .px_count_v1_G1B1_offset(px_count_v1_G1B1_offset),
  .px_count_v1_R1G2_offset(px_count_v1_R1G2_offset),
    .debug_px_count_trig(debug_px_count_trig),
    .debug_core_addr(debug_core_addr),
    .debug_core_HH1_data(debug_core_HH1_data),
    .debug_core_HL1_data(debug_core_HL1_data),
    .debug_core_LH1_data(debug_core_LH1_data),
    .debug_core_LL1_data(debug_core_LL1_data),
	.S_AXI_ACLK(s00_axi_aclk),
	.S_AXI_ARESETN(s00_axi_aresetn),
	.S_AXI_AWADDR(s00_axi_awaddr),
	.S_AXI_AWPROT(s00_axi_awprot),
	.S_AXI_AWVALID(s00_axi_awvalid),
	.S_AXI_AWREADY(s00_axi_awready),
	.S_AXI_WDATA(s00_axi_wdata),
	.S_AXI_WSTRB(s00_axi_wstrb),
	.S_AXI_WVALID(s00_axi_wvalid),
	.S_AXI_WREADY(s00_axi_wready),
	.S_AXI_BRESP(s00_axi_bresp),
	.S_AXI_BVALID(s00_axi_bvalid),
	.S_AXI_BREADY(s00_axi_bready),
	.S_AXI_ARADDR(s00_axi_araddr),
	.S_AXI_ARPROT(s00_axi_arprot),
	.S_AXI_ARVALID(s00_axi_arvalid),
	.S_AXI_ARREADY(s00_axi_arready),
	.S_AXI_RDATA(s00_axi_rdata),
	.S_AXI_RRESP(s00_axi_rresp),
	.S_AXI_RVALID(s00_axi_rvalid),
	.S_AXI_RREADY(s00_axi_rready)
);

// Add user logic here

genvar i;

// Extract pixel data valid bit from CMV control channel data.
wire px_dval;
assign px_dval = px_ctr[0];

// Extract pixel index within a row from master pixel counter.
wire [6:0] px_idx;
assign px_idx = px_count[6:0];

// Extract pixel data array from concatenated input.
wire [9:0] px_data [63:0];
for(i = 0; i < 32; i = i + 1)
begin
    // Channel-level X-flip to go along with CMV12000 pixel-level X-flip. 
    assign px_data[31-i] = px_chXX_concat[10*i+:10];        // G1 and R1 row.
    assign px_data[63-i] = px_chXX_concat[10*(32+i)+:10];   // B1 and G2 row.
end

// Declare I/O arrays for the horizontal wavelet cores.
wire signed [15:0] S_pp0_fromR_R1 [31:0];
wire signed [15:0] D_pp0_fromR_R1 [31:0];
wire signed [15:0] S_pp1_fromR_R1 [31:0];
wire signed [15:0] S_pp0_toL_R1 [31:0];
wire signed [15:0] D_pp0_toL_R1 [31:0];
wire signed [15:0] S_pp1_toL_R1 [31:0];
wire signed [15:0] S_out_R1 [31:0];
wire signed [15:0] D_out_R1 [31:0];

wire signed [15:0] S_pp0_fromR_G1 [31:0];
wire signed [15:0] D_pp0_fromR_G1 [31:0];
wire signed [15:0] S_pp1_fromR_G1 [31:0];
wire signed [15:0] S_pp0_toL_G1 [31:0];
wire signed [15:0] D_pp0_toL_G1 [31:0];
wire signed [15:0] S_pp1_toL_G1 [31:0];
wire signed [15:0] S_out_G1 [31:0];
wire signed [15:0] D_out_G1 [31:0];

wire signed [15:0] S_pp0_fromR_G2 [31:0];
wire signed [15:0] D_pp0_fromR_G2 [31:0];
wire signed [15:0] S_pp1_fromR_G2 [31:0];
wire signed [15:0] S_pp0_toL_G2 [31:0];
wire signed [15:0] D_pp0_toL_G2 [31:0];
wire signed [15:0] S_pp1_toL_G2 [31:0];
wire signed [15:0] S_out_G2 [31:0];
wire signed [15:0] D_out_G2 [31:0];

wire signed [15:0] S_pp0_fromR_B1 [31:0];
wire signed [15:0] D_pp0_fromR_B1 [31:0];
wire signed [15:0] S_pp1_fromR_B1 [31:0];
wire signed [15:0] S_pp0_toL_B1 [31:0];
wire signed [15:0] D_pp0_toL_B1 [31:0];
wire signed [15:0] S_pp1_toL_B1 [31:0];
wire signed [15:0] S_out_B1 [31:0];
wire signed [15:0] D_out_B1 [31:0];

// 2K Mode: Four rows are read in at once, so each color field needs two cores per channel.
// ---------------------------------------------------------------------------------------------------------------------
wire signed [15:0] S_pp0_fromR_R1_SS [31:0];
wire signed [15:0] D_pp0_fromR_R1_SS [31:0];
wire signed [15:0] S_pp1_fromR_R1_SS [31:0];
wire signed [15:0] S_pp0_toL_R1_SS [31:0];
wire signed [15:0] D_pp0_toL_R1_SS [31:0];
wire signed [15:0] S_pp1_toL_R1_SS [31:0];
wire signed [15:0] S_out_R1_SS [31:0];
wire signed [15:0] D_out_R1_SS [31:0];

wire signed [15:0] S_pp0_fromR_G1_SS [31:0];
wire signed [15:0] D_pp0_fromR_G1_SS [31:0];
wire signed [15:0] S_pp1_fromR_G1_SS [31:0];
wire signed [15:0] S_pp0_toL_G1_SS [31:0];
wire signed [15:0] D_pp0_toL_G1_SS [31:0];
wire signed [15:0] S_pp1_toL_G1_SS [31:0];
wire signed [15:0] S_out_G1_SS [31:0];
wire signed [15:0] D_out_G1_SS [31:0];

wire signed [15:0] S_pp0_fromR_G2_SS [31:0];
wire signed [15:0] D_pp0_fromR_G2_SS [31:0];
wire signed [15:0] S_pp1_fromR_G2_SS [31:0];
wire signed [15:0] S_pp0_toL_G2_SS [31:0];
wire signed [15:0] D_pp0_toL_G2_SS [31:0];
wire signed [15:0] S_pp1_toL_G2_SS [31:0];
wire signed [15:0] S_out_G2_SS [31:0];
wire signed [15:0] D_out_G2_SS [31:0];

wire signed [15:0] S_pp0_fromR_B1_SS [31:0];
wire signed [15:0] D_pp0_fromR_B1_SS [31:0];
wire signed [15:0] S_pp1_fromR_B1_SS [31:0];
wire signed [15:0] S_pp0_toL_B1_SS [31:0];
wire signed [15:0] D_pp0_toL_B1_SS [31:0];
wire signed [15:0] S_pp1_toL_B1_SS [31:0];
wire signed [15:0] S_out_B1_SS [31:0];
wire signed [15:0] D_out_B1_SS [31:0];
// ---------------------------------------------------------------------------------------------------------------------

// Tie adjacent cores together (in circular fashion).
for(i = 0; i < 32; i = i + 1)
begin
    // Link data from pixel pairs 0 and 1 across cores from right to left.
    // The link is circular, i.e. core 31 is linked to core 0.
    assign S_pp0_fromR_R1[i] = S_pp0_toL_R1[(i+1) & 32'h1F];
    assign D_pp0_fromR_R1[i] = D_pp0_toL_R1[(i+1) & 32'h1F];
    assign S_pp1_fromR_R1[i] = S_pp1_toL_R1[(i+1) & 32'h1F];
    
    assign S_pp0_fromR_G1[i] = S_pp0_toL_G1[(i+1) & 32'h1F];
    assign D_pp0_fromR_G1[i] = D_pp0_toL_G1[(i+1) & 32'h1F];
    assign S_pp1_fromR_G1[i] = S_pp1_toL_G1[(i+1) & 32'h1F];
    
    assign S_pp0_fromR_G2[i] = S_pp0_toL_G2[(i+1) & 32'h1F];
    assign D_pp0_fromR_G2[i] = D_pp0_toL_G2[(i+1) & 32'h1F];
    assign S_pp1_fromR_G2[i] = S_pp1_toL_G2[(i+1) & 32'h1F];
    
    assign S_pp0_fromR_B1[i] = S_pp0_toL_B1[(i+1) & 32'h1F];
    assign D_pp0_fromR_B1[i] = D_pp0_toL_B1[(i+1) & 32'h1F];
    assign S_pp1_fromR_B1[i] = S_pp1_toL_B1[(i+1) & 32'h1F];
end

// 2K Mode: Tie the extra cores for odd subsampled rows together in the same fasion.
// ---------------------------------------------------------------------------------------------------------------------
for(i = 0; i < 32; i = i + 1)
begin
    // Link data from pixel pairs 0 and 1 across cores from right to left.
    // The link is circular, i.e. core 31 is linked to core 0.
    assign S_pp0_fromR_R1_SS[i] = S_pp0_toL_R1_SS[(i+1) & 32'h1F];
    assign D_pp0_fromR_R1_SS[i] = D_pp0_toL_R1_SS[(i+1) & 32'h1F];
    assign S_pp1_fromR_R1_SS[i] = S_pp1_toL_R1_SS[(i+1) & 32'h1F];
    
    assign S_pp0_fromR_G1_SS[i] = S_pp0_toL_G1_SS[(i+1) & 32'h1F];
    assign D_pp0_fromR_G1_SS[i] = D_pp0_toL_G1_SS[(i+1) & 32'h1F];
    assign S_pp1_fromR_G1_SS[i] = S_pp1_toL_G1_SS[(i+1) & 32'h1F];
    
    assign S_pp0_fromR_G2_SS[i] = S_pp0_toL_G2_SS[(i+1) & 32'h1F];
    assign D_pp0_fromR_G2_SS[i] = D_pp0_toL_G2_SS[(i+1) & 32'h1F];
    assign S_pp1_fromR_G2_SS[i] = S_pp1_toL_G2_SS[(i+1) & 32'h1F];
    
    assign S_pp0_fromR_B1_SS[i] = S_pp0_toL_B1_SS[(i+1) & 32'h1F];
    assign D_pp0_fromR_B1_SS[i] = D_pp0_toL_B1_SS[(i+1) & 32'h1F];
    assign S_pp1_fromR_B1_SS[i] = S_pp1_toL_B1_SS[(i+1) & 32'h1F];
end
// ---------------------------------------------------------------------------------------------------------------------

// Instantiate 128 horizontal wavelet cores (32 each for R1, G1, G2, and B1 color fields).
generate
for (i = 0; i < 32; i = i + 1)
begin : dwt26_h1_array

    // Bottom channel pixels drive the R1 and G1 color fields.
    dwt26_h1
    #(
        .PX_MATH_WIDTH(PX_MATH_WIDTH),
        .COLOR(`COLOR_R1),
        .SS_ODD_ROW(1'b0)
    ) 
    R1
    (
        .SS(SS),
        .px_clk(px_clk),
        .px_dval(px_dval),
        .px_idx(px_idx),
        .px_data(px_data[i]),
        .S_pp0_fromR(S_pp0_fromR_R1[i]),
        .D_pp0_fromR(D_pp0_fromR_R1[i]),
        .S_pp1_fromR(S_pp1_fromR_R1[i]),
        .S_pp0_toL(S_pp0_toL_R1[i]),
        .D_pp0_toL(D_pp0_toL_R1[i]),
        .S_pp1_toL(S_pp1_toL_R1[i]),
        .S_out(S_out_R1[i]),
        .D_out(D_out_R1[i])
    );
    
    dwt26_h1
    #(
        .PX_MATH_WIDTH(PX_MATH_WIDTH),
        .COLOR(`COLOR_G1),
        .SS_ODD_ROW(1'b0)
    )
    G1
    (
        .SS(SS),
        .px_clk(px_clk),
        .px_dval(px_dval),
        .px_idx(px_idx),
        .px_data(px_data[i]),
        .S_pp0_fromR(S_pp0_fromR_G1[i]),
        .D_pp0_fromR(D_pp0_fromR_G1[i]),
        .S_pp1_fromR(S_pp1_fromR_G1[i]),
        .S_pp0_toL(S_pp0_toL_G1[i]),
        .D_pp0_toL(D_pp0_toL_G1[i]),
        .S_pp1_toL(S_pp1_toL_G1[i]),
        .S_out(S_out_G1[i]),
        .D_out(D_out_G1[i])
    );
    
    // Top channel pixels drive the G2 and B1 color fields.
    dwt26_h1
    #(
        .PX_MATH_WIDTH(PX_MATH_WIDTH),
        .COLOR(`COLOR_G2),
        .SS_ODD_ROW(1'b0)
    )
    G2
    (
        .SS(SS),
        .px_clk(px_clk),
        .px_dval(px_dval),
        .px_idx(px_idx),
        .px_data(px_data[i+32]),
        .S_pp0_fromR(S_pp0_fromR_G2[i]),
        .D_pp0_fromR(D_pp0_fromR_G2[i]),
        .S_pp1_fromR(S_pp1_fromR_G2[i]),
        .S_pp0_toL(S_pp0_toL_G2[i]),
        .D_pp0_toL(D_pp0_toL_G2[i]),
        .S_pp1_toL(S_pp1_toL_G2[i]),
        .S_out(S_out_G2[i]),
        .D_out(D_out_G2[i])
    );
    
    dwt26_h1
    #(
        .PX_MATH_WIDTH(PX_MATH_WIDTH),
        .COLOR(`COLOR_B1),
        .SS_ODD_ROW(1'b0)
    )
    B1
    (
        .SS(SS),
        .px_clk(px_clk),
        .px_dval(px_dval),
        .px_idx(px_idx),
        .px_data(px_data[i+32]),
        .S_pp0_fromR(S_pp0_fromR_B1[i]),
        .D_pp0_fromR(D_pp0_fromR_B1[i]),
        .S_pp1_fromR(S_pp1_fromR_B1[i]),
        .S_pp0_toL(S_pp0_toL_B1[i]),
        .D_pp0_toL(D_pp0_toL_B1[i]),
        .S_pp1_toL(S_pp1_toL_B1[i]),
        .S_out(S_out_B1[i]),
        .D_out(D_out_B1[i])
    );
    
end : dwt26_h1_array
endgenerate

// 2K Mode: 128 more cores for the odd subsampled rows.
// Merge Safe: Yes.
// ---------------------------------------------------------------------------------------------------------------------
generate
for (i = 0; i < 32; i = i + 1)
begin : dwt26_h1_array_SS

    // Bottom channel pixels drive the R1 and G1 color fields.
    dwt26_h1
    #(
        .PX_MATH_WIDTH(PX_MATH_WIDTH),
        .COLOR(`COLOR_R1),
        .SS_ODD_ROW(1'b1)
    ) 
    R1
    (
        .SS(SS),
        .px_clk(px_clk),
        .px_dval(px_dval),
        .px_idx(px_idx),
        .px_data(px_data[i]),
        .S_pp0_fromR(S_pp0_fromR_R1_SS[i]),
        .D_pp0_fromR(D_pp0_fromR_R1_SS[i]),
        .S_pp1_fromR(S_pp1_fromR_R1_SS[i]),
        .S_pp0_toL(S_pp0_toL_R1_SS[i]),
        .D_pp0_toL(D_pp0_toL_R1_SS[i]),
        .S_pp1_toL(S_pp1_toL_R1_SS[i]),
        .S_out(S_out_R1_SS[i]),
        .D_out(D_out_R1_SS[i])
    );
    
    dwt26_h1
    #(
        .PX_MATH_WIDTH(PX_MATH_WIDTH),
        .COLOR(`COLOR_G1),
        .SS_ODD_ROW(1'b1)
    )
    G1
    (
        .SS(SS),
        .px_clk(px_clk),
        .px_dval(px_dval),
        .px_idx(px_idx),
        .px_data(px_data[i]),
        .S_pp0_fromR(S_pp0_fromR_G1_SS[i]),
        .D_pp0_fromR(D_pp0_fromR_G1_SS[i]),
        .S_pp1_fromR(S_pp1_fromR_G1_SS[i]),
        .S_pp0_toL(S_pp0_toL_G1_SS[i]),
        .D_pp0_toL(D_pp0_toL_G1_SS[i]),
        .S_pp1_toL(S_pp1_toL_G1_SS[i]),
        .S_out(S_out_G1_SS[i]),
        .D_out(D_out_G1_SS[i])
    );
    
    // Top channel pixels drive the G2 and B1 color fields.
    dwt26_h1
    #(
        .PX_MATH_WIDTH(PX_MATH_WIDTH),
        .COLOR(`COLOR_G2),
        .SS_ODD_ROW(1'b1)
    )
    G2
    (
        .SS(SS),
        .px_clk(px_clk),
        .px_dval(px_dval),
        .px_idx(px_idx),
        .px_data(px_data[i+32]),
        .S_pp0_fromR(S_pp0_fromR_G2_SS[i]),
        .D_pp0_fromR(D_pp0_fromR_G2_SS[i]),
        .S_pp1_fromR(S_pp1_fromR_G2_SS[i]),
        .S_pp0_toL(S_pp0_toL_G2_SS[i]),
        .D_pp0_toL(D_pp0_toL_G2_SS[i]),
        .S_pp1_toL(S_pp1_toL_G2_SS[i]),
        .S_out(S_out_G2_SS[i]),
        .D_out(D_out_G2_SS[i])
    );
    
    dwt26_h1
    #(
        .PX_MATH_WIDTH(PX_MATH_WIDTH),
        .COLOR(`COLOR_B1),
        .SS_ODD_ROW(1'b1)
    )
    B1
    (
        .SS(SS),
        .px_clk(px_clk),
        .px_dval(px_dval),
        .px_idx(px_idx),
        .px_data(px_data[i+32]),
        .S_pp0_fromR(S_pp0_fromR_B1_SS[i]),
        .D_pp0_fromR(D_pp0_fromR_B1_SS[i]),
        .S_pp1_fromR(S_pp1_fromR_B1_SS[i]),
        .S_pp0_toL(S_pp0_toL_B1_SS[i]),
        .D_pp0_toL(D_pp0_toL_B1_SS[i]),
        .S_pp1_toL(S_pp1_toL_B1_SS[i]),
        .S_out(S_out_B1_SS[i]),
        .D_out(D_out_B1_SS[i])
    );
    
end : dwt26_h1_array_SS
endgenerate
// ---------------------------------------------------------------------------------------------------------------------

// Pixel counters at the interface between the vertical and horizontal first-stage cores.
// These are offset for the known latency of the horizontal cores:
// G1 and B1 color field horizontal cores: 15 px_clk.
// R1 and G2 color field horizontal cores: 16 px_clk.
wire signed [23:0] px_count_v1_G1B1;
assign px_count_v1_G1B1 = px_count - px_count_v1_G1B1_offset;
wire signed [23:0] px_count_v1_R1G2;
assign px_count_v1_R1G2 = px_count - px_count_v1_R1G2_offset;

// Arrays for first-stage vertical core output data.
wire [31:0] HH1_R1 [7:0];
wire [31:0] HL1_R1 [7:0];
wire [31:0] LH1_R1 [7:0];
wire [31:0] LL1_R1 [7:0];
wire [31:0] HH1_G1 [7:0];
wire [31:0] HL1_G1 [7:0];
wire [31:0] LH1_G1 [7:0];
wire [31:0] LL1_G1 [7:0];
wire [31:0] HH1_G2 [7:0];
wire [31:0] HL1_G2 [7:0];
wire [31:0] LH1_G2 [7:0];
wire [31:0] LL1_G2 [7:0];
wire [31:0] HH1_B1 [7:0];
wire [31:0] HL1_B1 [7:0];
wire [31:0] LH1_B1 [7:0];
wire [31:0] LL1_B1 [7:0];

// These arrays are concatenated into 1024-bit interfaces to the encoder (HH1, HL1, LH1)
// or to the second-stage wavelet cores (LL1).
for(i = 0; i < 8; i = i + 1)
begin
    assign HH1_concat[32*i+:32] = HH1_R1[i];
    assign HH1_concat[(32*i+256)+:32] = HH1_G1[i];
    assign HH1_concat[(32*i+512)+:32] = HH1_G2[i];
    assign HH1_concat[(32*i+768)+:32] = HH1_B1[i];
    assign HL1_concat[32*i+:32] = HL1_R1[i];
    assign HL1_concat[(32*i+256)+:32] = HL1_G1[i];
    assign HL1_concat[(32*i+512)+:32] = HL1_G2[i];
    assign HL1_concat[(32*i+768)+:32] = HL1_B1[i];
    assign LH1_concat[32*i+:32] = LH1_R1[i];
    assign LH1_concat[(32*i+256)+:32] = LH1_G1[i];
    assign LH1_concat[(32*i+512)+:32] = LH1_G2[i];
    assign LH1_concat[(32*i+768)+:32] = LH1_B1[i];
    assign LL1_concat[32*i+:32] = LL1_R1[i];
    assign LL1_concat[(32*i+256)+:32] = LL1_G1[i];
    assign LL1_concat[(32*i+512)+:32] = LL1_G2[i];
    assign LL1_concat[(32*i+768)+:32] = LL1_B1[i];
end

// Instantiate 32 vertical wavelet cores (8 each for R1, G1, G2, and B1 color fields).
// Each vertical core input is fed by the outputs of four adjacent horizontal cores.
generate
for (i = 0; i < 8; i = i + 1)
begin : dwt26_v1_array

    dwt26_v1
    #(
        .PX_MATH_WIDTH(PX_MATH_WIDTH)
    )
    R1
    (
        .SS(SS),
        .px_clk(px_clk),
        .px_clk_2x(px_clk_2x),
        .px_count_v1(px_count_v1_R1G2),
        .S_in_0(S_out_R1[4*i+0]),
        .D_in_0(D_out_R1[4*i+0]),
        .S_in_1(S_out_R1[4*i+1]),
        .D_in_1(D_out_R1[4*i+1]),
        .S_in_2(S_out_R1[4*i+2]),
        .D_in_2(D_out_R1[4*i+2]),
        .S_in_3(S_out_R1[4*i+3]),
        .D_in_3(D_out_R1[4*i+3]),
        .S_in_0_SS(S_out_R1_SS[4*i+0]),
        .D_in_0_SS(D_out_R1_SS[4*i+0]),
        .S_in_1_SS(S_out_R1_SS[4*i+1]),
        .D_in_1_SS(D_out_R1_SS[4*i+1]),
        .S_in_2_SS(S_out_R1_SS[4*i+2]),
        .D_in_2_SS(D_out_R1_SS[4*i+2]),
        .S_in_3_SS(S_out_R1_SS[4*i+3]),
        .D_in_3_SS(D_out_R1_SS[4*i+3]),

        .HH1_out(HH1_R1[i]),
        .HL1_out(HL1_R1[i]),
        .LH1_out(LH1_R1[i]),
        .LL1_out(LL1_R1[i])
    );
    
    dwt26_v1
    #(
        .PX_MATH_WIDTH(PX_MATH_WIDTH)
    )
    G1
    (
        .SS(SS),
        .px_clk(px_clk),
        .px_clk_2x(px_clk_2x),
        .px_count_v1(px_count_v1_G1B1),
        .S_in_0(S_out_G1[4*i+0]),
        .D_in_0(D_out_G1[4*i+0]),
        .S_in_1(S_out_G1[4*i+1]),
        .D_in_1(D_out_G1[4*i+1]),
        .S_in_2(S_out_G1[4*i+2]),
        .D_in_2(D_out_G1[4*i+2]),
        .S_in_3(S_out_G1[4*i+3]),
        .D_in_3(D_out_G1[4*i+3]),
        .S_in_0_SS(S_out_G1_SS[4*i+0]),
        .D_in_0_SS(D_out_G1_SS[4*i+0]),
        .S_in_1_SS(S_out_G1_SS[4*i+1]),
        .D_in_1_SS(D_out_G1_SS[4*i+1]),
        .S_in_2_SS(S_out_G1_SS[4*i+2]),
        .D_in_2_SS(D_out_G1_SS[4*i+2]),
        .S_in_3_SS(S_out_G1_SS[4*i+3]),
        .D_in_3_SS(D_out_G1_SS[4*i+3]),

        .HH1_out(HH1_G1[i]),
        .HL1_out(HL1_G1[i]),
        .LH1_out(LH1_G1[i]),
        .LL1_out(LL1_G1[i])
    );
    
    dwt26_v1
    #(
        .PX_MATH_WIDTH(PX_MATH_WIDTH)
    )
    G2
    (
        .SS(SS),
        .px_clk(px_clk),
        .px_clk_2x(px_clk_2x),
        .px_count_v1(px_count_v1_R1G2),
        .S_in_0(S_out_G2[4*i+0]),
        .D_in_0(D_out_G2[4*i+0]),
        .S_in_1(S_out_G2[4*i+1]),
        .D_in_1(D_out_G2[4*i+1]),
        .S_in_2(S_out_G2[4*i+2]),
        .D_in_2(D_out_G2[4*i+2]),
        .S_in_3(S_out_G2[4*i+3]),
        .D_in_3(D_out_G2[4*i+3]),
        .S_in_0_SS(S_out_G2_SS[4*i+0]),
        .D_in_0_SS(D_out_G2_SS[4*i+0]),
        .S_in_1_SS(S_out_G2_SS[4*i+1]),
        .D_in_1_SS(D_out_G2_SS[4*i+1]),
        .S_in_2_SS(S_out_G2_SS[4*i+2]),
        .D_in_2_SS(D_out_G2_SS[4*i+2]),
        .S_in_3_SS(S_out_G2_SS[4*i+3]),
        .D_in_3_SS(D_out_G2_SS[4*i+3]),

        .HH1_out(HH1_G2[i]),
        .HL1_out(HL1_G2[i]),
        .LH1_out(LH1_G2[i]),
        .LL1_out(LL1_G2[i])
    );
    
    dwt26_v1 
    #(
        .PX_MATH_WIDTH(PX_MATH_WIDTH)
    )
    B1
    (
        .SS(SS),
        .px_clk(px_clk),
        .px_clk_2x(px_clk_2x),
        .px_count_v1(px_count_v1_G1B1),
        .S_in_0(S_out_B1[4*i+0]),
        .D_in_0(D_out_B1[4*i+0]),
        .S_in_1(S_out_B1[4*i+1]),
        .D_in_1(D_out_B1[4*i+1]),
        .S_in_2(S_out_B1[4*i+2]),
        .D_in_2(D_out_B1[4*i+2]),
        .S_in_3(S_out_B1[4*i+3]),
        .D_in_3(D_out_B1[4*i+3]),
        .S_in_0_SS(S_out_B1_SS[4*i+0]),
        .D_in_0_SS(D_out_B1_SS[4*i+0]),
        .S_in_1_SS(S_out_B1_SS[4*i+1]),
        .D_in_1_SS(D_out_B1_SS[4*i+1]),
        .S_in_2_SS(S_out_B1_SS[4*i+2]),
        .D_in_2_SS(D_out_B1_SS[4*i+2]),
        .S_in_3_SS(S_out_B1_SS[4*i+3]),
        .D_in_3_SS(D_out_B1_SS[4*i+3]),

        .HH1_out(HH1_B1[i]),
        .HL1_out(HL1_B1[i]),
        .LH1_out(LH1_B1[i]),
        .LL1_out(LL1_B1[i])
    );
    
end : dwt26_v1_array
endgenerate

// Debug access to core output data.
/*
always @(posedge px_clk)
begin
if (px_count == debug_px_count_trig)
begin
    case (debug_core_addr[4:3])
        `COLOR_R1:
        begin 
            debug_core_HH1_data <= HH1_R1[debug_core_addr[2:0]];
            debug_core_HL1_data <= HL1_R1[debug_core_addr[2:0]];
            debug_core_LH1_data <= LH1_R1[debug_core_addr[2:0]];
            debug_core_LL1_data <= LL1_R1[debug_core_addr[2:0]];
        end
        `COLOR_G1:
        begin 
            debug_core_HH1_data <= HH1_G1[debug_core_addr[2:0]];
            debug_core_HL1_data <= HL1_G1[debug_core_addr[2:0]];
            debug_core_LH1_data <= LH1_G1[debug_core_addr[2:0]];
            debug_core_LL1_data <= LL1_G1[debug_core_addr[2:0]];
        end
        `COLOR_G2:
        begin 
            debug_core_HH1_data <= HH1_G2[debug_core_addr[2:0]];
            debug_core_HL1_data <= HL1_G2[debug_core_addr[2:0]];
            debug_core_LH1_data <= LH1_G2[debug_core_addr[2:0]];
            debug_core_LL1_data <= LL1_G2[debug_core_addr[2:0]];
        end
        `COLOR_B1:
        begin 
            debug_core_HH1_data <= HH1_B1[debug_core_addr[2:0]];
            debug_core_HL1_data <= HL1_B1[debug_core_addr[2:0]];
            debug_core_LH1_data <= LH1_B1[debug_core_addr[2:0]];
            debug_core_LL1_data <= LL1_B1[debug_core_addr[2:0]];
        end
    endcase
end
end
*/
// User logic ends

endmodule
