/*
 * RFSoC4x2 OFDM compressed-video link (bare metal).
 *
 *   PC (ffmpeg, MPEG-TS/H.264) --UDP 5000--> PS --DMA--> OFDM TX --> DAC_B (tile 228 ch0)
 *                                                                       | SMA loop / antenna
 *   PC (ffplay/VLC) <--UDP 5001-- PS <--DMA-- OFDM RX <-- ADC_B (tile 226 ch0)
 *
 * Clocks: LMK04828 + 2x LMX2594 over PS SPI0 (LMK_LMX.c), RFDC startup after the
 * Xilinx zcu208 dds_ila example, OFDM PHY from strath-sdr/rfsoc_ofdm.
 *
 * Copyright (c) 2026, Yijie Yu. BSD-3-Clause.
 */

#include "xparameters.h"
#include "xil_printf.h"
#include "xuartps_hw.h"
#include "xtime_l.h"
#include "sleep.h"
#include "LMK_LMX.h"
#include "rfdc_util.h"
#include "ofdm_link.h"
#include "net.h"

static int carrier_mhz = 600;
static int verbose = 1;

static void clocks_init(void)
{
    xil_printf("Programming LMK04828 / LMX2594 over SPI0...\r\n");
    write_clk(0);       /* LMK04828 */
    write_clk(1);       /* LMX2594 */
    write_clk(2);       /* LMX2594 */
    sleep(1);
}

static void help(void)
{
    xil_printf("\r\nkeys: 1 BPSK | 2 QPSK | 4 16-QAM | t self-test on/off | s status | v 1 s stats on/off\r\n"
               "      +/- carrier +/-100 MHz | g gain 1.0/0.5/0.25 | c reprogram clocks | h help\r\n\r\n");
}

static void print_rate(void)
{
    static XTime t_last;
    static u32 tx_last, rx_last;
    XTime now;

    XTime_GetTime(&now);
    if (now - t_last < (XTime)COUNTS_PER_SECOND)
        return;
    u32 dt_ms = (u32)((now - t_last) * 1000 / COUNTS_PER_SECOND);
    u32 tx = link_stats.tx_bytes, rx = link_stats.rx_payload;
    t_last = now;
    if (verbose && dt_ms) {
        u32 tx_kbps = (tx - tx_last) * 8 / dt_ms, rx_kbps = (rx - rx_last) * 8 / dt_ms;
        xil_printf("tx %d.%02d Mb/s  rx %d.%02d Mb/s  pkts %d  crc err %d  lost %d  bad frames %d",
                   tx_kbps / 1000, (tx_kbps % 1000) / 10, rx_kbps / 1000, (rx_kbps % 1000) / 10,
                   link_stats.rx_pkts, link_stats.rx_crc_err, link_stats.rx_lost, link_stats.rx_badlen);
        if (selftest_enabled())
            xil_printf("  self-test ok %d bad %d", link_stats.st_ok, link_stats.st_bad);
        else
            xil_printf("  udp in %d out %d", net_rx_udp(), net_tx_udp());
        xil_printf("\r\n");
    }
    tx_last = tx;
    rx_last = rx;
}

static void handle_key(char c)
{
    static const u32 gains[] = {1U << 30, 1U << 29, 1U << 28};
    static int gi;

    switch (c) {
    case '1': link_set_mod(MOD_BPSK);  xil_printf("BPSK\r\n");   break;
    case '2': link_set_mod(MOD_QPSK);  xil_printf("QPSK\r\n");   break;
    case '4': link_set_mod(MOD_QAM16); xil_printf("16-QAM\r\n"); break;
    case 't':
        selftest_enable(!selftest_enabled());
        xil_printf("self-test %s\r\n", selftest_enabled() ? "on" : "off");
        break;
    case 's': link_print_status(); break;
    case 'v': verbose = !verbose; break;
    case '+': carrier_mhz += 100; rfdc_set_carrier(carrier_mhz); break;
    case '-': carrier_mhz -= 100; rfdc_set_carrier(carrier_mhz); break;
    case 'g':
        gi = (gi + 1) % 3;
        link_set_gain(gains[gi]);
        xil_printf("tx gain 1/%d\r\n", 1 << gi);
        break;
    case 'c':
        clocks_init();
        rfdc_init();
        rfdc_set_carrier(carrier_mhz);
        link_init(link_get_mod());
        break;
    case 'h': help(); break;
    default: break;
    }
}

int main(void)
{
    xil_printf("\r\n==== RFSoC4x2 OFDM video link: DAC_B (228 ch0) -> ADC_B (226 ch0) ====\r\n");

    clocks_init();
    if (rfdc_init())
        xil_printf("RF tiles not ready - check the clock chips, then press 'c'\r\n");
    rfdc_set_carrier(carrier_mhz);

    if (link_init(MOD_QPSK))
        return -1;
    link_set_rx_cb(net_forward);
    net_init();
    help();

    for (;;) {
        net_poll();
        selftest_poll();
        link_poll();
        print_rate();
        if (XUartPs_IsReceiveData(STDIN_BASEADDRESS))
            handle_key(XUartPs_ReadReg(STDIN_BASEADDRESS, XUARTPS_FIFO_OFFSET));
    }
    return 0;
}
