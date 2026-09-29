// OFDM transmitter with an AXI4-Stream data input.
//
// Wraps ofdm_txs (strath-sdr ofdm_tx with the PRBS source replaced by ext_data/ext_pop)
// and feeds it from s_axis. Each OFDM frame the modulator requests 127 x 48 data
// symbols (ext_pop). The HDL Coder pipeline never transmits the symbol popped at
// position SKIP_POS of every 48-symbol OFDM symbol, so that pop carries PRBS; the
// first N_DATA remaining pops of the frame carry user bits, the rest carry PRBS.
// Whole 32-bit PRBS words are inserted when s_axis is empty. Bits go on air LSB first,
// so byte 0 of each 32-bit word is sent first. ofdm_rx_demap undoes this framing.
//
// s_axi     : strath-sdr ofdm_tx registers (0x100 modScheme, 0x104 enable, 0x108 gain)
// s_axi_ctl : 0x00 n_data, 0x04 blk_len, 0x08 skip_pos, 0x0C ctrl (bit0 force PRBS)
//             0x10 frames, 0x14 data words, 0x18 fill words, 0x1C pops in last frame
//
// Copyright (c) 2026, Yijie Yu. BSD-3-Clause.

`timescale 1ns / 1ps

module ofdm_tx_stream #(
    parameter N_DATA   = 5960,
    parameter BLK_LEN  = 48,
    parameter SKIP_POS = 45,
    parameter GAP      = 2048
) (
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi:s_axi_ctl:s_axis:m_axis, ASSOCIATED_RESET aresetn" *)
    input  wire         aclk,
    input  wire         aresetn,

    // strath-sdr OFDM TX registers
    input  wire [15:0]  s_axi_awaddr,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output wire [1:0]   s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [15:0]  s_axi_araddr,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output wire [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready,

    // bit source control / status
    input  wire [5:0]   s_axi_ctl_awaddr,
    input  wire         s_axi_ctl_awvalid,
    output wire         s_axi_ctl_awready,
    input  wire [31:0]  s_axi_ctl_wdata,
    input  wire [3:0]   s_axi_ctl_wstrb,
    input  wire         s_axi_ctl_wvalid,
    output wire         s_axi_ctl_wready,
    output wire [1:0]   s_axi_ctl_bresp,
    output wire         s_axi_ctl_bvalid,
    input  wire         s_axi_ctl_bready,
    input  wire [5:0]   s_axi_ctl_araddr,
    input  wire         s_axi_ctl_arvalid,
    output wire         s_axi_ctl_arready,
    output wire [31:0]  s_axi_ctl_rdata,
    output wire [1:0]   s_axi_ctl_rresp,
    output wire         s_axi_ctl_rvalid,
    input  wire         s_axi_ctl_rready,

    // payload bytes
    input  wire [31:0]  s_axis_tdata,
    input  wire [3:0]   s_axis_tkeep,       // unused, packets are padded to 4 bytes
    input  wire         s_axis_tlast,       // unused
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,

    // baseband samples {Q[15:0], I[15:0]}
    output wire [31:0]  m_axis_tdata,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready,
    output wire         m_axis_tlast
);

wire rst = ~aresetn;

localparam [31:0] N_DATA32   = N_DATA;
localparam [31:0] BLK_LEN32  = BLK_LEN;
localparam [31:0] SKIP_POS32 = SKIP_POS;

wire [31:0] mod_scheme;
wire [9:0]  ext_data;
wire        ext_pop;

ofdm_txs ofdm_txs_inst (
    .IPCORE_CLK                 (aclk),
    .IPCORE_RESETN              (aresetn),
    .AXI4_Stream_Master_TREADY  (m_axis_tready),
    .AXI4_Lite_ACLK             (aclk),
    .AXI4_Lite_ARESETN          (aresetn),
    .AXI4_Lite_AWADDR           (s_axi_awaddr),
    .AXI4_Lite_AWVALID          (s_axi_awvalid),
    .AXI4_Lite_WDATA            (s_axi_wdata),
    .AXI4_Lite_WSTRB            (s_axi_wstrb),
    .AXI4_Lite_WVALID           (s_axi_wvalid),
    .AXI4_Lite_BREADY           (s_axi_bready),
    .AXI4_Lite_ARADDR           (s_axi_araddr),
    .AXI4_Lite_ARVALID          (s_axi_arvalid),
    .AXI4_Lite_RREADY           (s_axi_rready),
    .AXI4_Stream_Master_TDATA   (m_axis_tdata),
    .AXI4_Stream_Master_TVALID  (m_axis_tvalid),
    .AXI4_Stream_Master_TLAST   (m_axis_tlast),
    .AXI4_Lite_AWREADY          (s_axi_awready),
    .AXI4_Lite_WREADY           (s_axi_wready),
    .AXI4_Lite_BRESP            (s_axi_bresp),
    .AXI4_Lite_BVALID           (s_axi_bvalid),
    .AXI4_Lite_ARREADY          (s_axi_arready),
    .AXI4_Lite_RDATA            (s_axi_rdata),
    .AXI4_Lite_RRESP            (s_axi_rresp),
    .AXI4_Lite_RVALID           (s_axi_rvalid),
    .mod_scheme                 (mod_scheme),
    .ext_data                   (ext_data),
    .ext_pop                    (ext_pop)
);

// control registers
wire [255:0] rw_vals;
reg  [31:0]  frames, data_words, fill_words, last_pops;

axil_regs #(
    .WMASK(8'h0f),
    .RESET({32'd0, 32'd0, 32'd0, 32'd0, 32'd0, SKIP_POS32, BLK_LEN32, N_DATA32})
) ctl_regs (
    .clk(aclk), .rst(rst),
    .s_axi_awaddr(s_axi_ctl_awaddr), .s_axi_awvalid(s_axi_ctl_awvalid), .s_axi_awready(s_axi_ctl_awready),
    .s_axi_wdata(s_axi_ctl_wdata), .s_axi_wstrb(s_axi_ctl_wstrb), .s_axi_wvalid(s_axi_ctl_wvalid),
    .s_axi_wready(s_axi_ctl_wready), .s_axi_bresp(s_axi_ctl_bresp), .s_axi_bvalid(s_axi_ctl_bvalid),
    .s_axi_bready(s_axi_ctl_bready), .s_axi_araddr(s_axi_ctl_araddr), .s_axi_arvalid(s_axi_ctl_arvalid),
    .s_axi_arready(s_axi_ctl_arready), .s_axi_rdata(s_axi_ctl_rdata), .s_axi_rresp(s_axi_ctl_rresp),
    .s_axi_rvalid(s_axi_ctl_rvalid), .s_axi_rready(s_axi_ctl_rready),
    .rw_vals(rw_vals),
    .ro_vals({last_pops, fill_words, data_words, frames, 128'd0})
);

wire [15:0] n_data     = rw_vals[0*32 +: 16];
wire [7:0]  blk_len    = rw_vals[1*32 +: 8];
wire [7:0]  skip_pos   = rw_vals[2*32 +: 8];
wire        force_fill = rw_vals[3*32];

// bits per symbol; user data is carried only when it divides 32
reg  [3:0] bps;
always @(posedge aclk)
    bps <= (mod_scheme[3:0] > 4'd9) ? 4'd10 : mod_scheme[3:0] + 4'd1;
wire data_mode = (bps == 4'd1) || (bps == 4'd2) || (bps == 4'd4) || (bps == 4'd8);

// PRBS-23 (x^23 + x^18 + 1), 32 new bits per step
reg  [22:0] lfsr;
reg  [22:0] lfsr_nx;
reg  [31:0] prbs_word;
integer k;
always @* begin
    lfsr_nx = lfsr;
    for (k = 0; k < 32; k = k + 1) begin
        prbs_word[k] = lfsr_nx[22];
        lfsr_nx = {lfsr_nx[21:0], lfsr_nx[22] ^ lfsr_nx[17]};
    end
end

// frame tracking: a gap of GAP cycles without pops starts a new frame
reg  [15:0] gap_cnt;
reg  [15:0] pop_cnt;
reg  [7:0]  blk_pos;
reg  [15:0] dcnt;
wire        new_frame = (gap_cnt >= GAP);
wire [15:0] idx_now   = new_frame ? 16'd0 : pop_cnt;
wire [7:0]  pos_now   = new_frame ? 8'd0  : blk_pos;
wire [15:0] dcnt_now  = new_frame ? 16'd0 : dcnt;
wire        in_win    = data_mode && !force_fill && (pos_now != skip_pos) && (dcnt_now < n_data);

// current word being serialised
reg  [31:0] cur;
reg  [4:0]  pos;
wire [5:0]  pos_sum   = pos + bps;
wire        word_done = ext_pop && in_win && pos_sum[5];

// In the idle time between frames, move to the next byte boundary so that every frame
// starts on a byte (needed after a modulation change; a no-op in steady state).
wire        realign   = (gap_cnt == GAP / 2) && (pos[2:0] != 3'd0);
wire [5:0]  pos_align = {1'b0, pos[4:3], 3'b000} + 6'd8;
wire        next_word = word_done || (realign && pos_align[5]);

assign ext_data      = in_win ? (cur >> pos) : prbs_word[9:0];
assign s_axis_tready = next_word;

always @(posedge aclk) begin
    if (ext_pop) begin
        gap_cnt <= 16'd0;
        pop_cnt <= idx_now + 16'd1;
        blk_pos <= (pos_now == blk_len - 8'd1) ? 8'd0 : pos_now + 8'd1;
        dcnt    <= dcnt_now + in_win;
        if (new_frame) begin
            frames    <= frames + 32'd1;
            last_pops <= pop_cnt;
        end
    end else if (gap_cnt != 16'hffff) begin
        gap_cnt <= gap_cnt + 16'd1;
    end

    if (ext_pop && !in_win)
        lfsr <= lfsr_nx;

    if (ext_pop && in_win)
        pos <= pos_sum[5] ? 5'd0 : pos_sum[4:0];
    else if (realign)
        pos <= pos_align[4:0];

    if (next_word) begin
        if (s_axis_tvalid) begin
            cur <= s_axis_tdata;
            data_words <= data_words + 32'd1;
        end else begin
            cur <= prbs_word;
            lfsr <= lfsr_nx;
            fill_words <= fill_words + 32'd1;
        end
    end

    if (rst) begin
        gap_cnt    <= 16'hffff;
        pop_cnt    <= 16'd0;
        blk_pos    <= 8'd0;
        dcnt       <= 16'd0;
        lfsr       <= 23'h7fffff;
        cur        <= 32'd0;
        pos        <= 5'd0;
        frames     <= 32'd0;
        data_words <= 32'd0;
        fill_words <= 32'd0;
        last_pops  <= 32'd0;
    end
end

endmodule
