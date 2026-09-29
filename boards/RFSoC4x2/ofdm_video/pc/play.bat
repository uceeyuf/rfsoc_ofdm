@echo off
rem Play the stream received over the OFDM link (UDP 5001).
ffplay -fflags nobuffer -flags low_delay -framedrop -probesize 500000 ^
  "udp://@:5001?fifo_size=1000000&overrun_nonfatal=1"
