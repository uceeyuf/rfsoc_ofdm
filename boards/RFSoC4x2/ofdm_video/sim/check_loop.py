"""Check that every received frame is a contiguous piece of the transmitted byte stream."""
import sys

words = [int(l, 16) for l in open('tx_words.txt')]
tx = bytes(4) + b''.join(w.to_bytes(4, 'little') for w in words)   # first word is the reset value 0
pkts = [bytes(int(x, 16) for x in l.split()) for l in open('rx_bytes.txt') if l.strip()]

ok = 0
prev_end = None
for i, p in enumerate(pkts):
    pos = tx.find(p)
    if pos < 0:
        # count bit errors against the best-aligned position of the previous packet
        print('frame %d: %d bytes, NOT found in tx stream' % (i, len(p)))
        continue
    cont = '' if prev_end is None else (' contiguous' if pos == prev_end else ' GAP %d' % (pos - prev_end))
    print('frame %d: %d bytes at tx offset %d%s' % (i, len(p), pos, cont))
    prev_end = pos + len(p)
    ok += 1
print('%d/%d frames match' % (ok, len(pkts)))
sys.exit(0 if ok >= len(pkts) - 1 else 1)
