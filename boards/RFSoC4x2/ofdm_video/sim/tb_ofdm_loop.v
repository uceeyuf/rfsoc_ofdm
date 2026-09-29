// Baseband loopback testbench: ofdm_tx_stream -> ofdm_rx -> ofdm_rx_demap.
// The TX input is a byte counter; every received frame is written to rx_bytes.txt,
// every TX pop / RX symbol to tx_pops.txt / rx_syms.txt.
// Copyright (c) 2026, Yijie Yu. BSD-3-Clause.

`timescale 1ns / 1ps

module tb_ofdm_loop;

`ifndef MOD
`define MOD 1
`endif
`ifndef NFRAMES
`define NFRAMES 3
`endif

reg clk = 1'b0;
reg aresetn = 1'b0;
always #2 clk = ~clk;

// ------------------------------------------------------------ AXI-lite masters
reg  [15:0] tx_awaddr, tx_araddr;  reg tx_awvalid, tx_wvalid, tx_arvalid;  reg [31:0] tx_wdata;
wire tx_awready, tx_wready, tx_bvalid, tx_arready, tx_rvalid;  wire [31:0] tx_rdata;
reg  [5:0]  tc_awaddr, tc_araddr;  reg tc_awvalid, tc_wvalid, tc_arvalid;  reg [31:0] tc_wdata;
wire tc_awready, tc_wready, tc_bvalid, tc_arready, tc_rvalid;  wire [31:0] tc_rdata;
reg  [15:0] rx_awaddr, rx_araddr;  reg rx_awvalid, rx_wvalid, rx_arvalid;  reg [31:0] rx_wdata;
wire rx_awready, rx_wready, rx_bvalid, rx_arready, rx_rvalid;  wire [31:0] rx_rdata;
reg  [5:0]  dm_awaddr, dm_araddr;  reg dm_awvalid, dm_wvalid, dm_arvalid;  reg [31:0] dm_wdata;
wire dm_awready, dm_wready, dm_bvalid, dm_arready, dm_rvalid;  wire [31:0] dm_rdata;

`define AXIL_WRITE(P, A, D) begin \
    @(posedge clk); P``_awaddr <= A; P``_wdata <= D; P``_awvalid <= 1; P``_wvalid <= 1; \
    fork \
        begin wait (P``_awready); @(posedge clk); P``_awvalid <= 0; end \
        begin wait (P``_wready);  @(posedge clk); P``_wvalid  <= 0; end \
    join \
    wait (P``_bvalid); @(posedge clk); end

`define AXIL_READ(P, A, D) begin \
    @(posedge clk); P``_araddr <= A; P``_arvalid <= 1; \
    wait (P``_arready); @(posedge clk); P``_arvalid <= 0; \
    wait (P``_rvalid); D = P``_rdata; @(posedge clk); end

// ------------------------------------------------------------ DUTs
reg  [31:0] src_word;
wire        src_ready;
wire [31:0] bb_tdata;
wire        bb_tvalid, bb_tlast;
wire [31:0] sym_tdata;
wire        sym_tvalid, sym_tlast;
wire [31:0] rx_tdata;
wire [3:0]  rx_tkeep;
wire        rx_tvalid, rx_tlast;

ofdm_tx_stream tx (
    .aclk(clk), .aresetn(aresetn),
    .s_axi_awaddr(tx_awaddr), .s_axi_awvalid(tx_awvalid), .s_axi_awready(tx_awready),
    .s_axi_wdata(tx_wdata), .s_axi_wstrb(4'hf), .s_axi_wvalid(tx_wvalid), .s_axi_wready(tx_wready),
    .s_axi_bresp(), .s_axi_bvalid(tx_bvalid), .s_axi_bready(1'b1),
    .s_axi_araddr(tx_araddr), .s_axi_arvalid(tx_arvalid), .s_axi_arready(tx_arready),
    .s_axi_rdata(tx_rdata), .s_axi_rresp(), .s_axi_rvalid(tx_rvalid), .s_axi_rready(1'b1),
    .s_axi_ctl_awaddr(tc_awaddr), .s_axi_ctl_awvalid(tc_awvalid), .s_axi_ctl_awready(tc_awready),
    .s_axi_ctl_wdata(tc_wdata), .s_axi_ctl_wstrb(4'hf), .s_axi_ctl_wvalid(tc_wvalid), .s_axi_ctl_wready(tc_wready),
    .s_axi_ctl_bresp(), .s_axi_ctl_bvalid(tc_bvalid), .s_axi_ctl_bready(1'b1),
    .s_axi_ctl_araddr(tc_araddr), .s_axi_ctl_arvalid(tc_arvalid), .s_axi_ctl_arready(tc_arready),
    .s_axi_ctl_rdata(tc_rdata), .s_axi_ctl_rresp(), .s_axi_ctl_rvalid(tc_rvalid), .s_axi_ctl_rready(1'b1),
    .s_axis_tdata(src_word), .s_axis_tkeep(4'hf), .s_axis_tlast(1'b0), .s_axis_tvalid(1'b1), .s_axis_tready(src_ready),
    .m_axis_tdata(bb_tdata), .m_axis_tvalid(bb_tvalid), .m_axis_tready(1'b1), .m_axis_tlast(bb_tlast)
);

ofdm_rx rx (
    .IPCORE_CLK(clk), .IPCORE_RESETN(aresetn),
    .AXI4_Stream_Master_TREADY(1'b1),
    .AXI4_Stream_Slave_TDATA(bb_tdata), .AXI4_Stream_Slave_TVALID(bb_tvalid),
    .AXI4_Lite_ACLK(clk), .AXI4_Lite_ARESETN(aresetn),
    .AXI4_Lite_AWADDR(rx_awaddr), .AXI4_Lite_AWVALID(rx_awvalid),
    .AXI4_Lite_WDATA(rx_wdata), .AXI4_Lite_WSTRB(4'hf), .AXI4_Lite_WVALID(rx_wvalid),
    .AXI4_Lite_BREADY(1'b1),
    .AXI4_Lite_ARADDR(rx_araddr), .AXI4_Lite_ARVALID(rx_arvalid), .AXI4_Lite_RREADY(1'b1),
    .AXI4_Stream_Master_TDATA(sym_tdata), .AXI4_Stream_Master_TVALID(sym_tvalid),
    .AXI4_Stream_Master_TLAST(sym_tlast), .AXI4_Stream_Slave_TREADY(),
    .AXI4_Lite_AWREADY(rx_awready), .AXI4_Lite_WREADY(rx_wready), .AXI4_Lite_BRESP(),
    .AXI4_Lite_BVALID(rx_bvalid), .AXI4_Lite_ARREADY(rx_arready), .AXI4_Lite_RDATA(rx_rdata),
    .AXI4_Lite_RRESP(), .AXI4_Lite_RVALID(rx_rvalid)
);

ofdm_rx_demap dm (
    .aclk(clk), .aresetn(aresetn),
    .s_axi_awaddr(dm_awaddr), .s_axi_awvalid(dm_awvalid), .s_axi_awready(dm_awready),
    .s_axi_wdata(dm_wdata), .s_axi_wstrb(4'hf), .s_axi_wvalid(dm_wvalid), .s_axi_wready(dm_wready),
    .s_axi_bresp(), .s_axi_bvalid(dm_bvalid), .s_axi_bready(1'b1),
    .s_axi_araddr(dm_araddr), .s_axi_arvalid(dm_arvalid), .s_axi_arready(dm_arready),
    .s_axi_rdata(dm_rdata), .s_axi_rresp(), .s_axi_rvalid(dm_rvalid), .s_axi_rready(1'b1),
    .s_axis_tdata(sym_tdata), .s_axis_tlast(sym_tlast), .s_axis_tvalid(sym_tvalid), .s_axis_tready(),
    .m_axis_tdata(rx_tdata), .m_axis_tkeep(rx_tkeep), .m_axis_tvalid(rx_tvalid),
    .m_axis_tready(1'b1), .m_axis_tlast(rx_tlast)
);

// ------------------------------------------------------------ source: byte counter or xorshift32
reg [7:0]  src_byte;
reg [31:0] src_rand;
always @(posedge clk) begin
    if (!aresetn) begin
        src_byte <= 8'd0;
        src_rand <= 32'h12345678;
    end else if (src_ready) begin
        src_byte <= src_byte + 8'd4;
        src_rand <= src_rand ^ (src_rand << 13) ^ ((src_rand ^ (src_rand << 13)) >> 17)
                    ^ ((src_rand ^ (src_rand << 13) ^ ((src_rand ^ (src_rand << 13)) >> 17)) << 5);
    end
end
`ifdef SRC_RANDOM
always @* src_word = src_rand;
`else
always @* src_word = {src_byte + 8'd3, src_byte + 8'd2, src_byte + 8'd1, src_byte};
`endif

// ------------------------------------------------------------ logging
integer f_pop, f_sym, f_byte, f_word;
integer cyc = 0;
integer frames_rx = 0;
integer i;
always @(posedge clk) cyc <= cyc + 1;

always @(posedge clk) begin
    if (tx.ext_pop)
        $fwrite(f_pop, "%0d %0d %0d %03x\n", cyc, tx.idx_now, tx.in_win, tx.ext_data);
    if (src_ready)
        $fwrite(f_word, "%08x\n", src_word);
    if (sym_tvalid)
        $fwrite(f_sym, "%0d %0d %08x\n", cyc, dm.idx_now, sym_tdata);
    if (rx_tvalid) begin
        for (i = 0; i < 4; i = i + 1)
            if (rx_tkeep[i]) $fwrite(f_byte, "%02x ", rx_tdata[i*8 +: 8]);
        if (rx_tlast) begin
            $fwrite(f_byte, "\n");
            frames_rx = frames_rx + 1;
        end
    end
end

reg [31:0] rd;
initial begin
    f_pop  = $fopen("tx_pops.txt", "w");
    f_sym  = $fopen("rx_syms.txt", "w");
    f_byte = $fopen("rx_bytes.txt", "w");
    f_word = $fopen("tx_words.txt", "w");
    {tx_awvalid, tx_wvalid, tx_arvalid, tc_awvalid, tc_wvalid, tc_arvalid} = 0;
    {rx_awvalid, rx_wvalid, rx_arvalid, dm_awvalid, dm_wvalid, dm_arvalid} = 0;
    repeat (20) @(posedge clk);
    aresetn = 1'b1;
    repeat (20) @(posedge clk);

    `AXIL_WRITE(dm, 6'h00, `MOD)
    `AXIL_WRITE(rx, 16'h0000, 1)            // reset rx core
    `AXIL_WRITE(tx, 16'h0108, 32'h40000000) // gain 1.0
    `AXIL_WRITE(tx, 16'h0100, `MOD)         // modScheme
    `AXIL_WRITE(tx, 16'h0104, 1)            // enable

    // one frame is 20640 samples x 12 clocks
    repeat (`NFRAMES) begin
        repeat (20640*12) @(posedge clk);
        `AXIL_READ(dm, 6'h18, rd) $display("t=%0t rx frames %0d", $time, rd);
        `AXIL_READ(dm, 6'h1C, rd) $display("  symbols in last rx frame %0d, dropped beats %0d", rd[15:0], rd[31:16]);
        `AXIL_READ(tc, 6'h1C, rd) $display("  pops in last tx frame %0d", rd);
    end
    $display("packets written: %0d", frames_rx);
    $fclose(f_pop); $fclose(f_sym); $fclose(f_byte); $fclose(f_word);
    $finish;
end

endmodule
