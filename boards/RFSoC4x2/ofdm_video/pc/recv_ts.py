"""Record the stream received over the OFDM link (UDP 5001) to an MPEG-TS file,
optionally relaying it to a local player port.

    python recv_ts.py rx.ts --seconds 30
    python recv_ts.py rx.ts --relay 5002      # then: ffplay udp://127.0.0.1:5002

Copyright (c) 2026, Yijie Yu. BSD-3-Clause.
"""
import argparse
import socket
import time

ap = argparse.ArgumentParser()
ap.add_argument('out')
ap.add_argument('--port', type=int, default=5001)
ap.add_argument('--seconds', type=float, default=1e9)
ap.add_argument('--idle', type=float, default=5.0, help='stop after this many seconds without data')
ap.add_argument('--relay', type=int, default=0, help='also forward to 127.0.0.1:<port>')
args = ap.parse_args()

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 << 20)
s.bind(('', args.port))
s.settimeout(0.5)
fwd = socket.socket(socket.AF_INET, socket.SOCK_DGRAM) if args.relay else None

n = nbytes = 0
t0 = time.time()
t_last = None
with open(args.out, 'wb') as f:
    while time.time() - t0 < args.seconds:
        try:
            d, _ = s.recvfrom(2048)
        except socket.timeout:
            if t_last and time.time() - t_last > args.idle:
                break
            continue
        t_last = time.time()
        f.write(d)
        if fwd:
            fwd.sendto(d, ('127.0.0.1', args.relay))
        n += 1
        nbytes += len(d)
print('received %d datagrams, %d bytes' % (n, nbytes))
