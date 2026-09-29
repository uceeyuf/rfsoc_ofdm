/*
 * OFDM packet link over the RFSoC4x2 DAC_B -> ADC_B loop.
 * Copyright (c) 2026, Yijie Yu. BSD-3-Clause.
 */

#ifndef OFDM_LINK_H_
#define OFDM_LINK_H_

#include "xil_types.h"

/* AXI-Lite map, see make_project.tcl */
#define TXCORE_BASE     0xA0050000U     /* strath-sdr ofdm_tx registers */
#define TXCTL_BASE      0xA0060000U     /* ofdm_tx_stream bit source */
#define RXCORE_BASE     0xA0070000U     /* strath-sdr ofdm_rx registers */
#define RXDM_BASE       0xA0080000U     /* ofdm_rx_demap */

/* modulation schemes shared by ofdm_tx and ofdm_rx_demap */
#define MOD_BPSK        0
#define MOD_QPSK        1
#define MOD_QAM16       3

/* link packet: ASM(4) | len(2) | seq(2) | payload | crc32(4) | pad to 4 bytes */
#define LINK_ASM        0x1DFCCF1AU     /* bytes 1A CF FC 1D on air */
#define LINK_HDR        8
#define LINK_MAX_PAYLOAD 1472

typedef void (*link_rx_cb)(u16 seq, const u8 *payload, u16 len);

typedef struct {
    u32 tx_pkts, tx_drops, tx_bytes;
    u32 rx_frames, rx_bytes;
    u32 rx_pkts, rx_crc_err, rx_lost, rx_payload;
    u32 st_ok, st_bad;          /* self-test payload check */
} link_stats_t;

extern link_stats_t link_stats;

int  link_init(int mod);
void link_set_mod(int mod);
int  link_get_mod(void);
void link_set_gain(u32 gain_q30);
int  link_send(const u8 *payload, u16 len);     /* 0 = queued, -1 = queue full */
int  link_tx_free(void);
void link_poll(void);
void link_set_rx_cb(link_rx_cb cb);
void link_print_status(void);

/* self-test traffic: fills the link with numbered PRBS packets and checks them */
void selftest_enable(int on);
int  selftest_enabled(void);
void selftest_poll(void);

u32  crc32(const u8 *p, u32 n);

#endif
