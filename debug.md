[2026-07-06 17:38:11] PPS device found: /dev/pps0
[2026-07-06 17:38:11] Executing: gpsd -G -n -N -b -D1 -F /var/run/gpsd.sock -s 38400 /dev/gps0 /dev/pps0
gpsd:WARN: removing stale control socket /var/run/gpsd.sock failed: No such file or directory(2)
[2026-07-06 17:38:11] GPSD started with PID: 45
gpsd:WARN: KPPS:/dev/gps0 kernel PPS unavailable, PPS accuracy will suffer
gpsd:WARN: KPPS:/dev/pps0 is fake PPS, timing will be inaccurate
gpsd:WARN: KPPS:/dev/pps0 missing PPS_CAPTURECLEAR, pulse may be offset
2026-07-06T17:38:16Z Selected source GPS
[2026-07-06 17:38:21] All services started successfully
[2026-07-06 17:38:21] Monitoring services...
2026-07-06T17:38:41Z Detected falseticker GPS
2026-07-06T17:38:41Z Selected source PPS
2026-07-06T17:38:41Z System clock wrong by -0.144189 seconds
2026-07-06T17:38:42Z Detected falseticker GPS
2026-07-06T17:38:43Z Selected source GPS
2026-07-06T17:38:43Z System clock wrong by 0.139053 seconds
2026-07-06T17:38:49Z Detected falseticker GPS
2026-07-06T17:38:49Z Selected source PPS
2026-07-06T17:38:49Z System clock wrong by -0.339455 seconds
2026-07-06T17:38:50Z Detected falseticker GPS
2026-07-06T17:38:57Z System clock wrong by -0.195630 seconds
2026-07-06T17:39:00Z Selected source GPS
2026-07-06T17:39:00Z System clock wrong by 0.532663 seconds
2026-07-06T17:39:06Z Detected falseticker GPS
2026-07-06T17:39:06Z Selected source PPS
2026-07-06T17:39:06Z System clock wrong by -0.673518 seconds
2026-07-06T17:39:07Z Detected falseticker GPS
2026-07-06T17:39:09Z Selected source GPS
2026-07-06T17:39:09Z System clock wrong by 0.673032 seconds
2026-07-06T17:39:14Z Detected falseticker GPS
2026-07-06T17:39:14Z Selected source PPS
2026-07-06T17:39:14Z System clock wrong by -0.853743 seconds
2026-07-06T17:39:15Z Detected falseticker GPS
2026-07-06T17:39:22Z Selected source GPS
2026-07-06T17:39:22Z System clock wrong by 0.867085 seconds
2026-07-06T17:39:27Z Detected falseticker GPS
2026-07-06T17:39:30Z Selected source PPS
2026-07-06T17:39:32Z Detected falseticker GPS
2026-07-06T17:40:14Z Selected source GPS
2026-07-06T17:40:14Z System clock wrong by -0.106403 seconds
2026-07-06T17:40:35Z Detected falseticker GPS
2026-07-06T17:40:35Z Selected source PPS
2026-07-06T17:40:35Z System clock wrong by 0.163680 seconds
2026-07-06T17:40:36Z Detected falseticker GPS
2026-07-06T17:41:32Z Selected source GPS
2026-07-06T17:41:40Z Detected falseticker GPS
2026-07-06T17:41:40Z Selected source PPS
2026-07-06T17:41:41Z Detected falseticker GPS
nido@nido-desktop:~/docker-gpsd-chrony$ sudo docker exec -it gpsd-chrony bash
52ce6acafc05:/# chronyc sources
MS Name/IP address         Stratum Poll Reach LastRx Last sample
===============================================================================
#x GPS                           0   0   377     0    +17ms[  +17ms] +/- 1000us
#* PPS                           0   3   275     6   -273ms[ -322ms] +/-   12ms
52ce6acafc05:/# chronyc tracking
Reference ID    : 50505300 (PPS)
Stratum         : 1
Ref time (UTC)  : Mon Jul 06 17:44:10 2026
System time     : 0.029517686 seconds slow of NTP time
Last offset     : -0.016810805 seconds
RMS offset      : 0.038481969 seconds
Frequency       : 271.323 ppm slow
Residual freq   : -13.694 ppm
Skew            : 569.180 ppm
Root delay      : 0.000000001 seconds
Root dispersion : 0.063559324 seconds
Update interval : 8.0 seconds
Leap status     : Normal
