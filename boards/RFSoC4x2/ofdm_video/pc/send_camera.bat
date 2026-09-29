@echo off
rem Send a webcam over the link. List cameras with:
rem   ffmpeg -list_devices true -f dshow -i dummy
rem Usage: send_camera.bat "Integrated Camera"
ffmpeg -f dshow -video_size 1280x720 -framerate 30 -i video="%~1" -an ^
  -c:v libx264 -preset ultrafast -tune zerolatency -b:v 2M -maxrate 2M -bufsize 1M -g 30 -pix_fmt yuv420p ^
  -f mpegts -muxrate 4M "udp://192.168.1.10:5000?pkt_size=1316"
