# docker-gpsd-chrony

This Docker image facilitates the running of the Linux GPS daemon (gpsd) on a 
Raspberry Pi connected to an instance of Chrony. `gpsd` is a daemon 
that monitors one or more GPSes or AIS receivers attached to a host computer 
through serial or USB ports. `Chrony` is an NTP service.  

Together these services allow for a GPS 1PPS corrected timeserver. 

## Resources: 



Repo:  [ARL-at-UH/docker-gpsd-chrony](https://github.com/ARL-at-UH/docker-gpsd-chrony) <br>
Docker Hub: [arluhdev/docker-gpsd-chrony](https://hub.docker.com/repository/docker/arluhdev/docker-gpsd-chrony/general) <br>
Source Tutorial:  [Revisiting Microsecond Accurate NTP for Raspberry Pi with GPS PPS in 2025 - Austin's Nerdy Things](https://austinsnerdythings.com/2025/02/14/revisiting-microsecond-accurate-ntp-for-raspberry-pi-with-gps-pps-in-2025/) <br>
GPSD references:  [GPSD Time Service HOWTO](https://gpsd.gitlab.io/gpsd/gpsd-time-service-howto.html) <br>
PPS tools resources: https://github.com/redlab-i/pps-tools?tab=readme-ov-file <br>
Chrony resource: https://chrony-project.org/ <br>
Raspberry Pi configuration: [UART Confguration](https://www.raspberrypi.com/documentation/computers/configuration.html#primary-uart) <br>


## Prerequisites

- Raspberry Pi 4 with Docker installed.
    - tested on RPI 4 Model B (8GB RAM) 
    - tested on Debian 12 (Bookworm) with Kernal version 6.6.51+rpt-rpi-v8 (64 bit)
    - tested on Docker version 27.5.1 [64-bit Debian Docker installation](https://docs.docker.com/engine/install/debian/)
- GPS module (timing model preferred)
    - tested on [Sparkfun Zed-9P](https://www.sparkfun.com/sparkfun-gps-rtk-sma-breakout-zed-f9p-qwiic.html)
- 5 wires needed – +VDC/RX/TX/GND/PPS

## Setup and Configuration Steps

### 1. Copy github project 

```bash
git clone https://github.com/dkaulukukui/rpi-docker-gpsd-chrony
```

### 2. Setup Raspi GPIO
1. Enable the PPS dignal on Pin 18. In /boot/firmware/config.txt add the below to a new line.

    ```bash
    sudo bash -c "echo '# GPS PPS signals Information' >> /boot/firmware/config.txt"
    sudo bash -c "echo 'dtoverlay=pps-gpio,gpiopin=18' >> /boot/firmware/config.txt"
    ``` 

2. Enable UART and set the initial baud rate. 

    Note: Set baud rate for the specific GPS unit you have, if avaialble use the highest most frequently updated GPS output settings.  GPSD can parse most common GPS receiver outputs automatically and for the most part anything is better than the default 9600 NMEA.

    ```bash
    sudo bash -c "echo 'enable_uart=1' >> /boot/firmware/config.txt"
    sudo bash -c "echo 'init_uart_baud=38400' >> /boot/firmware/config.txt"
    ```

    The matching GPS speed will also need to be set on line 7 of [entrypoint.sh](./entrypoint.sh)

    ```bash
    GPS_SPEED="${GPS_SPEED:-38400}"
    ```


3. In /etc/modules, add ‘pps-gpio’ to a new line.

    ```bash 
    sudo bash -c "echo 'pps-gpio' >> /etc/modules"
    ```

4. Modify Device tree overlay to disable bluetooth

	```bash
	sudo bash -c "echo '# Disable Bluetooth' >> /boot/firmware/config.txt"
	sudo bash -c "echo 'dtoverlay=disable-bt' >> /boot/firmware/config.txt"
	```

    Disable the system service that initializes the BT

    ```bash
    sudo systemctl disable hciuart
    ```

5. Disable systemd-timesyncd service

    ```bash
    sudo systemctl stop systemd-timesyncd
    sudo systemctl disable systemd-timesyncd
    ```


### 4. Enable the serial hardware port

Run raspi-config -> 3 – Interface options -> I6 – Serial Port -> Would you like a login shell to be available over serial -> No. -> Would you like the serial port hardware to be enabled -> Yes.

Reboot -> Yes

### 4. Wire up the GPS module

Determine the voltage requirements of your GPS module first. 

Pin connections:

1. GPS PPS to RPi GPIO pin 12 (GPIO 18)
2. GPS VIN to RPi 5V pin 2 or 4 (or for 3.3V pin 1 or 17)
3. GPS GND to RPi GND pin 6,9,14,20,25,30,34 or 39
4. GPS RX to RPi UART TX pin 8 (GPIO14)
5. GPS TX to RPi UART RX pin 10 (GPIO15)

![RASPI PINOUT](https://www.raspberrypi.com/documentation/computers/images/GPIO-Pinout-Diagram-2.png?hash=df7d7847c57a1ca6d5b2617695de6d46)

### 5. Build Image

```bash
cd rpi-docker-gpsd-chrony
```

```bash
sudo docker build -t dkaulukukui/rpi-docker-gpsd-chrony .
```

Alternatively a pre-built image (using 38400 baud) can be downloaded and installed from docker hub

```bash
sudo docker image pull dkaulukukui/rpi-docker-gpsd-chrony
```

### 6. Bring up the container

The command to bring up container (attached to the stdio terminal, useful for debugging) is:

```bash
cd rpi-docker-gpsd-chrony
```

```bash 
sudo docker compose up 
```

The command to bring up container in the background is (RECOMMENDED):

```bash 
sudo docker compose up --detach
```

## Verficition steps

1. Ensure that the container starts up successfully

    Monitor docker console logs for any error messages.  Successful container start up should look similar to the below: 

<Insert Image of Console output showing successful container startup>


2. Check GPSD 

    - If opened as attached, open a new terminal window.
    
    - Attach container terminal 

        ```bash
        sudo docker exec -it gpsd-chrony bash
        ```

    - Verify PPS signal.

        ```bash
        sudo ppstest /dev/pps0 
        ```

        - Successful PPS connectivity should look like the below

            ```bash
            trying PPS source "/dev/pps0"
            found PPS source "/dev/pps0"
            ok, found 1 source(s), now start fetching data...
            source 0 - assert 1739485509.000083980, sequence: 100 - clear  0.000000000, sequence: 0
            source 0 - assert 1739485510.000083988, sequence: 101 - clear  0.000000000, sequence: 0
            source 0 - assert 1739485511.000083348, sequence: 102 - clear  0.000000000, sequence: 0
            source 0 - assert 1739485512.000086343, sequence: 103 - clear  0.000000000, sequence: 0
            ```

    - Verify GPS data



        - Example of GPS data being recieved and shown with gpsmon

        ```bash
        gpsmon
        ```

        ```bash
        lqqqqqqqqqqqqqqqqqqqqqqqqqqklqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqk _minor":15}
        xCh PRN  Az  El S/N FLAG U xxECEF Pos:            m            m            m x ver":"u-blox","sernum":"2b41ba159f"
        x 0   1 313  22  43 191f Y xxECEF Vel:          m/s          m/s          m/s x 60,FWVER=HPG 1.32,PROTVER=27.31,MOD
        x 1   2 340  43  36 191f Y xx                                                 x s":1,"native":1,"bps":38400,"parity
        x 2   3 261  29  29 191f Y xxLTP Pos:                                       m x pps0","driver":"PPS","activated":"2
        x 3   4 204   5   0 1211   xxLTP Vel:        m/s      o                       x
        x 4   8 283  72  25 191c Y xx                                                 x false,"timing":false,"split24":fals
        x 5  10  40  17  32 191f Y xxTime:                                            x
        x 6  16 188  13   0 1211   xxTime GPS:                     Day:               x
        x 7  27 164  60  18 191c Y xx                                                 x
        x 8  28 116  12   0 1211   xxEst Pos Err       m Est Vel Err       m/s        x
        x 9  31 144  10   0 1211   xxPRNs: 20 PDOP:  1.4 Fix 0x..                     x
        x10  32  54  42  31 191f Y xmqqqqqqqqqqqqqqqqqqqqq NAV qqqqqqqqqqqqqqqqqqqqqqqj
        x11 129 265   5   0 0701   xlqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqk
        x12 131 113  38   0 0701   xxDOP [H]      [V]      [P]      [T]      [G]      x
        x13 133 123  49   0 0701   xmqqqqqqqqqqqqqqqqqqq NAV_DOP qqqqqqqqqqqqqqqqqqqqqj
        x14 212 307   7   0 1211   xlqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqk
        x15 214  91  58  20 191c Y xxTOFF:  0.086981486       PPS: -0.000000396       x
        mqqqqqq NAV-SAT qqqqqqqqqqqjmqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqj
        ```



        - Example of GPS data being received and shown with CGPS

        ```bash
        cgps
        ```

        ```bash
        lqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqklqqqqqqqqqqqqqqqqSeen 38/Used 19qqk
        x Time         2025-06-06T00:09:12.000Z (18)xxGNSS  S PRN  Elev  Azim   SNR Usex
        x Latitude          21.30927740 N           xxGP  1     1  23.0 314.0  44.0  Y x
        x Longitude        157.80876950 W           xxGP  2     2  43.0 341.0  36.0  Y x
        x Alt (HAE, MSL)     188.668,    179.754 ft xxGP  3     3  29.0 261.0  27.0  Y x
        x Speed              0.11               mph xxGP  8     8  73.0 280.0  24.0  Y x
        x Track (true, var)     327.0,   9.4    deg xxGP 10    10  17.0  41.0  27.0  Y x
        x Climb              8.86            ft/min xxGP 27    27  59.0 164.0  13.0  Y x
        x Status          3D FIX (7 secs)           xxGL  2    66  31.0 209.0  18.0  Y x
        x Long Err  (XDOP, EPX)   0.42, +/- 19.7 ft xxGL  8    72  35.0  25.0  32.0  Y x
        x Lat Err   (YDOP, EPY)   0.48, +/- 23.6 ft xxGL 22    86  18.0 113.0  25.0  Y x
        x Alt Err   (VDOP, EPV)   1.22, +/- 18.7 ft xxGL 23    87  49.0  71.0  22.0  Y x
        x 2D Err    (HDOP, CEP)   0.63, +/- 12.1 ft xxGL 24    88  32.0 344.0  41.0  Y x
        x 3D Err    (PDOP, SEP)   1.38, +/-  105 ft xxQZ  2   194  26.0 285.0  42.0  Y x
        x Time Err  (TDOP)        0.77              xxQZ  3   195  22.0 294.0  44.0  Y x
        x Geo Err   (GDOP)        1.58              xxGA  4   304  58.0  90.0  27.0  Y x
        x Speed Err (EPS)            +/- 32.2 mph   xxGA 10   310  46.0  39.0  18.0  Y x
        x Track Err (EPD)         n/a               xxGA 11   311  46.0 356.0  36.0  Y x
        x Time offset             0.554616724     s xxGA 16   316  28.0 231.0  10.0  Y x
        x Grid Square             BL11ch24wf        xxGA 25   325  28.0 258.0  29.0  Y x
        x ECEF X, VX  -18059130.879 ft   -0.033 ft/sxxGA 36   336  16.0 308.0  38.0  Y x
        x ECEF Y, VY   -7366570.594 ft   -0.098 ft/sxxGP  4     4   6.0 204.0   0.0  N x
        x ECEF Z, VZ    7556926.370 ft   -0.131 ft/sxxGP 16    16  12.0 187.0  20.0  N x
        mqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqjmMore...qqqqqqqqqqqqqqqqqqqqqqqqqqj
        ```


3. Check Chrony

    - Verify Chrony is seeing both the GPS and 1 PPS signals as valid and is using 1 PPS

        ```bash
        chronyc sources
        ```

        - Good Syncing with GPS and 1PPS 

        ```bash
        aa24e5ed30b7:/# chronyc sources
        MS Name/IP address         Stratum Poll Reach LastRx Last sample
        ===============================================================================
        #x NMEA                          0   0   377     0    +87ms[  +87ms] +/- 1000us
        #* PPS                           0   3   377    10   -310ns[   +9ns] +/-   13ms
        ```


    - Verify that chrony is tracking and updating the system clock

        ```bash
        chronyc tracking
        ```

        - Good tracking data output

        ```bash
        aa24e5ed30b7:/# chronyc tracking
        Reference ID    : 50505300 (PPS)
        Stratum         : 1
        Ref time (UTC)  : Fri Jun 06 00:05:35 2025
        System time     : 0.000000374 seconds fast of NTP time
        Last offset     : +0.000000443 seconds
        RMS offset      : 0.003629697 seconds
        Frequency       : 11.747 ppm fast
        Residual freq   : -0.012 ppm
        Skew            : 0.090 ppm
        Root delay      : 0.000000001 seconds
        Root dispersion : 0.007316423 seconds
        Update interval : 8.0 seconds
        Leap status     : Normal
        ```

	[Chronyc Tracking Field Explanation](https://chrony-project.org/doc/3.3/chronyc.html)


4. Verify System time

    ```bash
    date
    ```

5. Perform additional offset calbiration and fine tuning

   Follow calibration README instructions found in [Calibration Procedure](calibration/CHRONY_OFFSET_CALIBRATION.md)
			
## To do: 
- dial back docker --privlidged flag and make sure everything still works

