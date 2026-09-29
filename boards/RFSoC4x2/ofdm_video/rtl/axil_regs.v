// Minimal AXI4-Lite register file: 8 x 32-bit registers.
// Register i is read/write when WMASK[i] = 1, otherwise it reads ro_vals.
// Copyright (c) 2026, Yijie Yu. BSD-3-Clause.

`timescale 1ns / 1ps

module axil_regs #(
    parameter [7:0]     WMASK = 8'h0f,
    parameter [255:0]   RESET = 256'd0
) (
    input  wire         clk,
    input  wire         rst,

    input  wire [5:0]   s_axi_awaddr,
    input  wire         s_axi_awvalid,
    output reg          s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output reg          s_axi_wready,
    output wire [1:0]   s_axi_bresp,
    output reg          s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [5:0]   s_axi_araddr,
    input  wire         s_axi_arvalid,
    output reg          s_axi_arready,
    output reg  [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output reg          s_axi_rvalid,
    input  wire         s_axi_rready,

    output wire [255:0] rw_vals,
    input  wire [255:0] ro_vals
);

reg [31:0] regs [0:7];
reg [2:0]  aw_idx;
reg        aw_seen, w_seen;
reg [31:0] w_data;
reg [3:0]  w_strb;

assign s_axi_bresp = 2'b00;
assign s_axi_rresp = 2'b00;

genvar g;
generate
    for (g = 0; g < 8; g = g + 1) begin : g_out
        assign rw_vals[g*32 +: 32] = regs[g];
    end
endgenerate

integer i;
always @(posedge clk) begin
    s_axi_awready <= 1'b0;
    s_axi_wready  <= 1'b0;
    s_axi_arready <= 1'b0;

    if (s_axi_awvalid && !aw_seen && !s_axi_awready) begin
        s_axi_awready <= 1'b1;
        aw_seen <= 1'b1;
        aw_idx  <= s_axi_awaddr[4:2];
    end
    if (s_axi_wvalid && !w_seen && !s_axi_wready) begin
        s_axi_wready <= 1'b1;
        w_seen <= 1'b1;
        w_data <= s_axi_wdata;
        w_strb <= s_axi_wstrb;
    end
    if (aw_seen && w_seen && !s_axi_bvalid) begin
        if (WMASK[aw_idx]) begin
            for (i = 0; i < 4; i = i + 1)
                if (w_strb[i]) regs[aw_idx][i*8 +: 8] <= w_data[i*8 +: 8];
        end
        s_axi_bvalid <= 1'b1;
        aw_seen <= 1'b0;
        w_seen  <= 1'b0;
    end
    if (s_axi_bvalid && s_axi_bready)
        s_axi_bvalid <= 1'b0;

    if (s_axi_arvalid && !s_axi_rvalid && !s_axi_arready) begin
        s_axi_arready <= 1'b1;
        s_axi_rvalid  <= 1'b1;
        s_axi_rdata   <= WMASK[s_axi_araddr[4:2]] ? regs[s_axi_araddr[4:2]]
                                                  : ro_vals[s_axi_araddr[4:2]*32 +: 32];
    end
    if (s_axi_rvalid && s_axi_rready)
        s_axi_rvalid <= 1'b0;

    if (rst) begin
        s_axi_bvalid <= 1'b0;
        s_axi_rvalid <= 1'b0;
        aw_seen <= 1'b0;
        w_seen  <= 1'b0;
        for (i = 0; i < 8; i = i + 1)
            regs[i] <= RESET[i*32 +: 32];
    end
end

endmodule
