/*
 * UDP bridge between the PC and the OFDM link (lwIP raw API, PS GEM).
 * Copyright (c) 2026, Yijie Yu. BSD-3-Clause.
 */

#ifndef NET_H_
#define NET_H_

#include "xil_types.h"

#define BOARD_IP(a)     IP4_ADDR(a, 192, 168, 1, 10)
#define PC_IP_DEFAULT(a) IP4_ADDR(a, 192, 168, 1, 100)
#define UDP_PORT_IN     5000    /* PC -> board: stream to transmit */
#define UDP_PORT_OUT    5001    /* board -> PC: received stream */

int  net_init(void);
void net_poll(void);
void net_forward(u16 seq, const u8 *payload, u16 len);     /* link rx callback */
u32  net_rx_udp(void);
u32  net_tx_udp(void);

#endif
