@echo off
rem Encode a video file to H.264 in MPEG-TS and send it to the board (UDP 5000).
rem Usage: send_video.bat input.mp4 [video bitrate, default 2M]
rem QPSK carries ~11.6 Mb/s, BPSK ~5.8 Mb/s, 16-QAM ~23 Mb/s of payload.
set IN=%~1
set BR=%~2
if "%BR%"=="" set BR=2M
ffmpeg -re -stream_loop -1 -i "%IN%" -an -c:v libx264 -preset veryfast -tune zerolatency ^
  -b:v %BR% -maxrate %BR% -bufsize %BR% -g 30 -pix_fmt yuv420p ^
  -f mpegts -muxrate 4M "udp://192.168.1.10:5000?pkt_size=1316"
