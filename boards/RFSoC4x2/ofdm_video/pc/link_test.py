"""End-to-end UDP test through the OFDM link: PC -> board:5000 -> RF -> board -> PC:5001.

    python link_test.py --rate 8 --seconds 10

Sends numbered 1316-byte packets at the given rate (Mb/s) and reports what comes back.
Copyright (c) 2026, Yijie Yu. BSD-3-Clause.
"""
import argparse
import os
import socket
import struct
import time

ap = argparse.ArgumentParser()
ap.add_argument('--board', default='192.168.1.10')
ap.add_argument('--rate', type=float, default=5.0, help='offered load in Mb/s')
ap.add_argument('--seconds', type=float, default=10.0)
ap.add_argument('--size', type=int, default=1316)
args = ap.parse_args()

tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
rx.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 << 20)
rx.bind(('', 5001))
rx.setblocking(False)

body = os.urandom(args.size - 4)
interval = args.size * 8 / (args.rate * 1e6)
sent = got = bad = 0
seen = set()
t0 = time.perf_counter()
t_next = t0
t_end = t0 + args.seconds

while True:
    now = time.perf_counter()
    if now < t_end and now >= t_next:
        tx.sendto(struct.pack('<I', sent) + body, (args.board, 5000))
        sent += 1
        t_next += interval
    try:
        while True:
            d, _ = rx.recvfrom(2048)
            n = struct.unpack('<I', d[:4])[0]
            if d[4:] != body:
                bad += 1
            elif n not in seen:
                seen.add(n)
                got += 1
    except BlockingIOError:
        pass
    if now > t_end + 1.0:
        break
    time.sleep(0.0002)

dt = args.seconds
print('sent %d  received %d  corrupted %d  lost %.2f %%' % (sent, got, bad, 100.0 * (sent - got) / max(sent, 1)))
print('offered %.2f Mb/s  delivered %.2f Mb/s' % (sent * args.size * 8 / dt / 1e6, got * args.size * 8 / dt / 1e6))
