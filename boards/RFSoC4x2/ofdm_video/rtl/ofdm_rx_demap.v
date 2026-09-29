// Hard-decision demapper and byte packer for the strath-sdr OFDM receiver.
//
// Takes the equalised data sub-carriers {Q[15:0], I[15:0]} (sfix16_En14) from ofdm_rx,
// slices them (BPSK / QPSK / 16-QAM, same bit mapping as the ofdm_tx generators) and
// packs the bits LSB first into 32-bit words. Per OFDM frame the first START symbols
// and the symbol at position SKIP_POS of every 48-symbol OFDM symbol are discarded
// (they repeat a symbol of the previous one), then N_DATA symbols are kept; this
// matches the framing of ofdm_tx_stream. Each OFDM frame becomes one AXI4-Stream
// packet (tlast, tkeep on the last beat) for an AXI DMA S2MM channel.
// A gap of GAP cycles without symbols marks a frame boundary.
//
// s_axi: 0x00 mod (0 BPSK, 1 QPSK, 3 16-QAM)   0x04 16-QAM threshold (En14)
//        0x08 start  0x0C blk_len  0x10 skip_pos  0x14 n_data
//        0x18 frames (RO)  0x1C {dropped beats[15:0], symbols in last frame[15:0]} (RO)
//
// Copyright (c) 2026, Yijie Yu. BSD-3-Clause.

`timescale 1ns / 1ps

module ofdm_rx_demap #(
    parameter START    = 3,
    parameter BLK_LEN  = 48,
    parameter SKIP_POS = 0,
    parameter N_DATA   = 5960,
    parameter GAP      = 2048
) (
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi:s_axis:m_axis, ASSOCIATED_RESET aresetn" *)
    input  wire         aclk,
    input  wire         aresetn,

    input  wire [5:0]   s_axi_awaddr,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output wire [1:0]   s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [5:0]   s_axi_araddr,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output wire [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready,

    // equalised symbols from ofdm_rx
    input  wire [31:0]  s_axis_tdata,
    input  wire         s_axis_tlast,       // unused (ofdm_rx packet size)
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,

    // received bytes, one packet per OFDM frame
    output wire [31:0]  m_axis_tdata,
    output wire [3:0]   m_axis_tkeep,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready,
    output wire         m_axis_tlast
);

wire rst = ~aresetn;

localparam [31:0] START32    = START;
localparam [31:0] BLK_LEN32  = BLK_LEN;
localparam [31:0] SKIP_POS32 = SKIP_POS;
localparam [31:0] N_DATA32   = N_DATA;

wire [255:0] rw_vals;
reg  [31:0]  frames;
reg  [15:0]  last_syms, dropped;

axil_regs #(
    .WMASK(8'h3f),
    .RESET({32'd0, 32'd0, N_DATA32, SKIP_POS32, BLK_LEN32, START32, 32'h2ccc, 32'd1})
) regs (
    .clk(aclk), .rst(rst),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready), .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
    .rw_vals(rw_vals),
    .ro_vals({dropped, last_syms, frames, 192'd0})
);

wire [3:0]  mod        = rw_vals[0*32 +: 4];
wire signed [15:0] thr = rw_vals[1*32 +: 16];
wire [15:0] start      = rw_vals[2*32 +: 16];
wire [7:0]  blk_len    = rw_vals[3*32 +: 8];
wire [7:0]  skip_pos   = rw_vals[4*32 +: 8];
wire [15:0] n_data     = rw_vals[5*32 +: 16];

assign s_axis_tready = 1'b1;

// ---------------------------------------------------------------- slicer
wire signed [15:0] re = s_axis_tdata[15:0];
wire signed [15:0] im = s_axis_tdata[31:16];

function [1:0] qam16_level;     // 0:+3a 1:+a 2:-a 3:-3a
    input signed [15:0] x;
    input signed [15:0] t;
    begin
        if (x >= t)       qam16_level = 2'd0;
        else if (x >= 0)  qam16_level = 2'd1;
        else if (x >= -t) qam16_level = 2'd2;
        else              qam16_level = 2'd3;
    end
endfunction

reg [3:0] bits;
reg [2:0] bps;
always @* begin
    case (mod)
        4'd0:    begin bps = 3'd1; bits = {3'b000, ~re[15]}; end
        4'd3:    begin bps = 3'd4; bits = {qam16_level(im, thr), qam16_level(re, thr)}; end
        default: begin bps = 3'd2; bits = {2'b00, im[15], re[15]}; end
    endcase
end

// ---------------------------------------------------------------- output queue
reg  [36:0] q [0:7];            // {tlast, tkeep, tdata}
reg  [3:0]  q_wr, q_rd;
wire [3:0]  q_used = q_wr - q_rd;

assign m_axis_tvalid = (q_used != 4'd0);
assign {m_axis_tlast, m_axis_tkeep, m_axis_tdata} = q[q_rd[2:0]];

// ---------------------------------------------------------------- framing / packing
reg  [15:0] gap_cnt;
reg  [15:0] sym_cnt;
reg  [7:0]  blk_pos;
reg  [15:0] kcnt;
reg         frame_open;
reg  [39:0] acc;
reg  [5:0]  nb;

wire        new_frame = (gap_cnt >= GAP);
wire [15:0] idx_now   = new_frame ? 16'd0 : sym_cnt;
wire [7:0]  pos_now   = new_frame ? 8'd0  : blk_pos;
wire [15:0] kcnt_now  = new_frame ? 16'd0 : kcnt;
wire        in_win    = s_axis_tvalid && (idx_now >= start) && (pos_now != skip_pos) && (kcnt_now < n_data);
wire        is_last   = in_win && (kcnt_now == n_data - 16'd1);
wire        timeout   = frame_open && (gap_cnt == GAP - 1);

wire [39:0] acc_n     = acc | ({36'd0, bits} << nb);
wire [5:0]  nb_n      = nb + bps;
wire        full_word = nb_n[5];                  // >= 32 bits collected
wire [39:0] acc_r     = full_word ? {32'd0, acc_n[39:32]} : acc_n;
wire [5:0]  nb_r      = full_word ? nb_n - 6'd32 : nb_n;

function [3:0] keep_of;
    input [5:0] n;
    begin
        if (n > 6'd24)      keep_of = 4'b1111;
        else if (n > 6'd16) keep_of = 4'b0111;
        else if (n > 6'd8)  keep_of = 4'b0011;
        else                keep_of = 4'b0001;
    end
endfunction

reg        push0, push1;
reg [36:0] ent0, ent1;

always @* begin
    push0 = 1'b0; push1 = 1'b0;
    ent0  = 37'd0; ent1 = 37'd0;
    if (in_win) begin
        if (full_word) begin
            push0 = 1'b1;
            ent0  = {is_last && (nb_r == 6'd0), 4'b1111, acc_n[31:0]};
            if (is_last && nb_r != 6'd0) begin
                push1 = 1'b1;
                ent1  = {1'b1, keep_of(nb_r), acc_r[31:0]};
            end
        end else if (is_last) begin
            push0 = 1'b1;
            ent0  = {1'b1, keep_of(nb_n), acc_n[31:0]};
        end
    end else if (timeout) begin
        // frame ended early: close the packet (one padding byte if nothing is pending)
        push0 = 1'b1;
        ent0  = {1'b1, (nb != 6'd0) ? keep_of(nb) : 4'b0001, acc[31:0]};
    end
end

wire [3:0] n_push = push0 + push1;
wire       q_ok   = (q_used + n_push) <= 4'd8;

always @(posedge aclk) begin
    if (m_axis_tvalid && m_axis_tready)
        q_rd <= q_rd + 4'd1;

    if (q_ok) begin
        if (push0) q[q_wr[2:0]] <= ent0;
        if (push1) q[q_wr[2:0] + 3'd1] <= ent1;
        q_wr <= q_wr + n_push;
    end else if (push0) begin
        dropped <= dropped + 16'd1;
    end

    if (s_axis_tvalid) begin
        gap_cnt <= 16'd0;
        sym_cnt <= idx_now + 16'd1;
        blk_pos <= (pos_now == blk_len - 8'd1) ? 8'd0 : pos_now + 8'd1;
        kcnt    <= kcnt_now + in_win;
        if (new_frame) begin
            frames    <= frames + 32'd1;
            last_syms <= sym_cnt;
        end
    end else if (gap_cnt != 16'hffff) begin
        gap_cnt <= gap_cnt + 16'd1;
    end

    if (in_win) begin
        if (is_last) begin
            acc <= 40'd0;
            nb  <= 6'd0;
            frame_open <= 1'b0;
        end else begin
            acc <= acc_r;
            nb  <= nb_r;
            frame_open <= 1'b1;
        end
    end else if (timeout) begin
        acc <= 40'd0;
        nb  <= 6'd0;
        frame_open <= 1'b0;
    end

    if (rst) begin
        q_wr <= 4'd0;
        q_rd <= 4'd0;
        gap_cnt <= 16'hffff;
        sym_cnt <= 16'd0;
        blk_pos <= 8'd0;
        kcnt    <= 16'd0;
        frame_open <= 1'b0;
        acc <= 40'd0;
        nb  <= 6'd0;
        frames <= 32'd0;
        last_syms <= 16'd0;
        dropped <= 16'd0;
    end
end

endmodule
