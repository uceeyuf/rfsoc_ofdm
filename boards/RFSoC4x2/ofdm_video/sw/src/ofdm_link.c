/*
 * OFDM packet link: framing, AXI DMA and packet recovery.
 *
 * TX: payload -> link packet (ASM, length, sequence, CRC32) -> MM2S -> tx_fifo ->
 *     ofdm_tx_stream. The PL inserts PRBS words whenever the FIFO is empty.
 * RX: ofdm_rx_demap writes one DMA packet per OFDM frame; the bytes of all frames are
 *     concatenated and scanned for the ASM, checked with the CRC and delivered.
 *
 * Copyright (c) 2026, Yijie Yu. BSD-3-Clause.
 */

#include <string.h>
#include "xparameters.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xaxidma.h"
#include "ofdm_link.h"

#define TXQ_N       64
#define TXQ_SLOT    1536
#define RXBUF_N     2
#define RXBUF_SZ    32768
#define PARSE_SZ    65536
#define ST_LEN      1316            /* self-test payload, same size as 7 TS packets */

link_stats_t link_stats;

static XAxiDma dma;
static u8  txq[TXQ_N][TXQ_SLOT] __attribute__((aligned(64)));
static u16 txq_len[TXQ_N];
static int txq_head, txq_tail, tx_busy;
static u16 tx_seq;

static u8  rxbuf[RXBUF_N][RXBUF_SZ] __attribute__((aligned(64)));
static int rx_cur;
static u8  pbuf[PARSE_SZ];
static u32 pn;
static int rx_have_seq;
static u16 rx_last_seq;
static link_rx_cb rx_cb;

static int cur_mod;
static int st_on;
static u32 st_tx_id;

/* ------------------------------------------------------------------ CRC32 */
static u32 crc_tab[256];

static void crc_init(void)
{
    for (u32 i = 0; i < 256; i++) {
        u32 c = i;
        for (int k = 0; k < 8; k++)
            c = (c & 1) ? 0xEDB88320U ^ (c >> 1) : c >> 1;
        crc_tab[i] = c;
    }
}

u32 crc32(const u8 *p, u32 n)
{
    u32 c = 0xFFFFFFFFU;
    while (n--)
        c = crc_tab[(c ^ *p++) & 0xFF] ^ (c >> 8);
    return c ^ 0xFFFFFFFFU;
}

static inline u16 rd16(const u8 *p) { return p[0] | (p[1] << 8); }
static inline u32 rd32(const u8 *p) { return p[0] | (p[1] << 8) | (p[2] << 16) | ((u32)p[3] << 24); }
static inline void wr16(u8 *p, u16 v) { p[0] = v; p[1] = v >> 8; }
static inline void wr32(u8 *p, u32 v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }

/* ------------------------------------------------------------------ hardware */
static void rx_arm(int i)
{
    Xil_DCacheInvalidateRange((UINTPTR)rxbuf[i], RXBUF_SZ);
    XAxiDma_SimpleTransfer(&dma, (UINTPTR)rxbuf[i], RXBUF_SZ, XAXIDMA_DEVICE_TO_DMA);
}

static int dma_init(void)
{
    XAxiDma_Config *cfg = XAxiDma_LookupConfig(XPAR_AXIDMA_0_DEVICE_ID);
    if (!cfg || XAxiDma_CfgInitialize(&dma, cfg) != XST_SUCCESS) {
        xil_printf("AXI DMA init failed\r\n");
        return -1;
    }
    XAxiDma_IntrDisable(&dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    rx_cur = 0;
    rx_arm(rx_cur);
    return 0;
}

void link_set_mod(int mod)
{
    cur_mod = mod;
    Xil_Out32(TXCORE_BASE + 0x100, mod);
    Xil_Out32(RXDM_BASE + 0x00, mod);
}

int link_get_mod(void) { return cur_mod; }

void link_set_gain(u32 gain_q30) { Xil_Out32(TXCORE_BASE + 0x108, gain_q30); }

int link_init(int mod)
{
    crc_init();
    memset(&link_stats, 0, sizeof(link_stats));

    Xil_Out32(RXCORE_BASE + 0x0, 1);            /* soft reset ofdm_rx */
    Xil_Out32(TXCORE_BASE + 0x0, 1);            /* soft reset ofdm_tx */
    link_set_gain(1U << 30);                    /* gain 1.0 */
    link_set_mod(mod);
    Xil_Out32(TXCORE_BASE + 0x104, 1);          /* transmit enable */

    return dma_init();
}

void link_set_rx_cb(link_rx_cb cb) { rx_cb = cb; }

/* ------------------------------------------------------------------ transmit */
int link_tx_free(void)
{
    return TXQ_N - 1 - ((txq_head - txq_tail) & (TXQ_N - 1));
}

int link_send(const u8 *payload, u16 len)
{
    if (len == 0 || len > LINK_MAX_PAYLOAD)
        return -1;
    if (link_tx_free() == 0) {
        link_stats.tx_drops++;
        return -1;
    }
    u8 *p = txq[txq_head];
    wr32(p, LINK_ASM);
    wr16(p + 4, len);
    wr16(p + 6, tx_seq++);
    memcpy(p + LINK_HDR, payload, len);
    wr32(p + LINK_HDR + len, crc32(p + 4, 4 + len));
    u32 n = LINK_HDR + len + 4;
    while (n & 3)
        p[n++] = 0;
    txq_len[txq_head] = n;
    Xil_DCacheFlushRange((UINTPTR)p, n);
    txq_head = (txq_head + 1) & (TXQ_N - 1);
    link_stats.tx_pkts++;
    link_stats.tx_bytes += len;
    return 0;
}

static void tx_poll(void)
{
    if (tx_busy) {
        if (XAxiDma_Busy(&dma, XAXIDMA_DMA_TO_DEVICE))
            return;
        tx_busy = 0;
        txq_tail = (txq_tail + 1) & (TXQ_N - 1);
    }
    if (txq_tail != txq_head) {
        XAxiDma_SimpleTransfer(&dma, (UINTPTR)txq[txq_tail], txq_len[txq_tail], XAXIDMA_DMA_TO_DEVICE);
        tx_busy = 1;
    }
}

/* ------------------------------------------------------------------ receive */
static void deliver(u16 seq, const u8 *payload, u16 len)
{
    if (rx_have_seq) {
        u16 gap = (u16)(seq - rx_last_seq - 1);
        if (gap < 4096)
            link_stats.rx_lost += gap;
    }
    rx_have_seq = 1;
    rx_last_seq = seq;
    link_stats.rx_pkts++;
    link_stats.rx_payload += len;

    if (st_on) {
        /* payload: id(4) then bytes of a simple LCG seeded with the id */
        u32 id = rd32(payload), x = id * 2654435761U + 1;
        int ok = (len == ST_LEN);
        for (int i = 4; ok && i < len; i++) {
            x = x * 1664525U + 1013904223U;
            ok = (payload[i] == (u8)(x >> 24));
        }
        if (ok) link_stats.st_ok++; else link_stats.st_bad++;
    } else if (rx_cb) {
        rx_cb(seq, payload, len);
    }
}

static void parse(void)
{
    u32 i = 0;
    while (i + LINK_HDR <= pn) {
        if (pbuf[i] != 0x1A || rd32(pbuf + i) != LINK_ASM) {
            i++;
            continue;
        }
        u16 len = rd16(pbuf + i + 4);
        if (len == 0 || len > LINK_MAX_PAYLOAD) {
            i++;
            continue;
        }
        u32 total = LINK_HDR + len + 4;
        if (i + total > pn)
            break;                              /* wait for the next frame */
        if (crc32(pbuf + i + 4, 4 + len) != rd32(pbuf + i + LINK_HDR + len)) {
            link_stats.rx_crc_err++;
            i++;
            continue;
        }
        deliver(rd16(pbuf + i + 6), pbuf + i + LINK_HDR, len);
        i += total;
    }
    memmove(pbuf, pbuf + i, pn - i);
    pn -= i;
}

static void rx_poll(void)
{
    u32 sr = XAxiDma_ReadReg(dma.RegBase, XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET);
    if (sr & XAXIDMA_ERR_ALL_MASK) {
        xil_printf("S2MM error 0x%08x, resetting DMA\r\n", sr);
        XAxiDma_Reset(&dma);
        while (!XAxiDma_ResetIsDone(&dma))
            ;
        tx_busy = 0;
        txq_tail = txq_head;
        rx_arm(rx_cur);
        return;
    }
    if (XAxiDma_Busy(&dma, XAXIDMA_DEVICE_TO_DMA))
        return;

    u32 n = XAxiDma_ReadReg(dma.RegBase, XAXIDMA_RX_OFFSET + XAXIDMA_BUFFLEN_OFFSET);
    int done = rx_cur;
    rx_cur = (rx_cur + 1) % RXBUF_N;
    rx_arm(rx_cur);

    Xil_DCacheInvalidateRange((UINTPTR)rxbuf[done], RXBUF_SZ);
    link_stats.rx_frames++;
    link_stats.rx_bytes += n;
    if (n > RXBUF_SZ)
        n = RXBUF_SZ;
    if (pn + n > PARSE_SZ)
        pn = 0;                                 /* lost sync with the stream */
    memcpy(pbuf + pn, rxbuf[done], n);
    pn += n;
    parse();
}

void link_poll(void)
{
    tx_poll();
    rx_poll();
}

/* ------------------------------------------------------------------ self-test */
void selftest_enable(int on)
{
    st_on = on;
    link_stats.st_ok = link_stats.st_bad = 0;
}

int selftest_enabled(void) { return st_on; }

void selftest_poll(void)
{
    static u8 p[ST_LEN];
    if (!st_on)
        return;
    while (link_tx_free() > 4) {
        u32 x = st_tx_id * 2654435761U + 1;
        wr32(p, st_tx_id++);
        for (int i = 4; i < ST_LEN; i++) {
            x = x * 1664525U + 1013904223U;
            p[i] = x >> 24;
        }
        link_send(p, ST_LEN);
    }
}

/* ------------------------------------------------------------------ status */
void link_print_status(void)
{
    static const char *mods[] = {"BPSK", "QPSK", "?", "16-QAM"};
    xil_printf("mod %s | tx frames %d data words %d fill words %d pops/frame %d\r\n",
               mods[cur_mod & 3], Xil_In32(TXCTL_BASE + 0x10), Xil_In32(TXCTL_BASE + 0x14),
               Xil_In32(TXCTL_BASE + 0x18), Xil_In32(TXCTL_BASE + 0x1C));
    u32 r = Xil_In32(RXDM_BASE + 0x1C);
    xil_printf("rx frames %d symbols/frame %d fifo drops %d | dma mm2s sr 0x%08x s2mm sr 0x%08x\r\n",
               Xil_In32(RXDM_BASE + 0x18), r & 0xFFFF, r >> 16,
               XAxiDma_ReadReg(dma.RegBase, XAXIDMA_TX_OFFSET + XAXIDMA_SR_OFFSET),
               XAxiDma_ReadReg(dma.RegBase, XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET));
    xil_printf("link tx %d pkts (%d dropped) | rx %d pkts, %d crc errors, %d lost",
               link_stats.tx_pkts, link_stats.tx_drops, link_stats.rx_pkts,
               link_stats.rx_crc_err, link_stats.rx_lost);
    if (st_on)
        xil_printf(" | self-test ok %d bad %d", link_stats.st_ok, link_stats.st_bad);
    xil_printf("\r\n");
}
