/*
 * UDP bridge between the PC and the OFDM link (lwIP 2.1.1 raw API on the PS GEM).
 *   PC -> UDP 5000 -> link_send()          (MPEG-TS from ffmpeg, <= 1472 bytes each)
 *   link rx -> UDP 5001 -> PC              (to ffplay / VLC)
 * The PC address is taken from the last packet received on port 5000.
 * Copyright (c) 2026, Yijie Yu. BSD-3-Clause.
 */

#include <string.h>
#include "xparameters.h"
#include "xil_printf.h"
#include "xil_exception.h"
#include "xscugic.h"
#include "xtime_l.h"
#include "lwip/init.h"
#include "lwip/udp.h"
#include "lwip/etharp.h"
#include "netif/xadapter.h"
#include "ofdm_link.h"
#include "net.h"

#define EMAC_BASEADDR   XPAR_XEMACPS_0_BASEADDR

static struct netif nif;
static struct udp_pcb *pcb;
static ip_addr_t pc_ip;
static u32 udp_rx, udp_tx;
static unsigned char mac[6] = {0x00, 0x0a, 0x35, 0x04, 0x02, 0x10};

u32 net_rx_udp(void) { return udp_rx; }
u32 net_tx_udp(void) { return udp_tx; }

static void udp_in(void *arg, struct udp_pcb *upcb, struct pbuf *p, const ip_addr_t *addr, u16_t port)
{
    static u8 buf[LINK_MAX_PAYLOAD];

    ip_addr_copy(pc_ip, *addr);
    if (p->tot_len <= LINK_MAX_PAYLOAD && !selftest_enabled()) {
        pbuf_copy_partial(p, buf, p->tot_len, 0);
        link_send(buf, p->tot_len);
        udp_rx++;
    }
    pbuf_free(p);
}

void net_forward(u16 seq, const u8 *payload, u16 len)
{
    struct pbuf *q = pbuf_alloc(PBUF_TRANSPORT, len, PBUF_RAM);
    if (!q)
        return;
    memcpy(q->payload, payload, len);
    if (udp_sendto(pcb, q, &pc_ip, UDP_PORT_OUT) == ERR_OK)
        udp_tx++;
    pbuf_free(q);
}

int net_init(void)
{
    ip_addr_t ip, mask, gw;

    Xil_ExceptionInit();
    XScuGic_DeviceInitialize(XPAR_SCUGIC_SINGLE_DEVICE_ID);
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_IRQ_INT,
                                 (Xil_ExceptionHandler)XScuGic_DeviceInterruptHandler,
                                 (void *)XPAR_SCUGIC_SINGLE_DEVICE_ID);

    BOARD_IP(&ip);
    IP4_ADDR(&mask, 255, 255, 255, 0);
    IP4_ADDR(&gw, 192, 168, 1, 1);
    PC_IP_DEFAULT(&pc_ip);

    lwip_init();
    if (!xemac_add(&nif, &ip, &mask, &gw, mac, EMAC_BASEADDR)) {
        xil_printf("Ethernet: xemac_add failed\r\n");
        return -1;
    }
    netif_set_default(&nif);
    Xil_ExceptionEnableMask(XIL_EXCEPTION_IRQ);
    netif_set_up(&nif);

    pcb = udp_new();
    if (!pcb || udp_bind(pcb, IP_ADDR_ANY, UDP_PORT_IN) != ERR_OK) {
        xil_printf("Ethernet: udp bind failed\r\n");
        return -1;
    }
    udp_recv(pcb, udp_in, NULL);
    xil_printf("Ethernet: board 192.168.1.10, UDP in :%d, out -> PC :%d\r\n", UDP_PORT_IN, UDP_PORT_OUT);
    return 0;
}

void net_poll(void)
{
    static XTime t_arp, t_link;
    XTime now;

    xemacif_input(&nif);

    XTime_GetTime(&now);
    if (now - t_arp > (XTime)COUNTS_PER_SECOND * 5) {
        t_arp = now;
        etharp_tmr();
    }
    if (now - t_link > (XTime)COUNTS_PER_SECOND) {
        t_link = now;
        eth_link_detect(&nif);
    }
}
