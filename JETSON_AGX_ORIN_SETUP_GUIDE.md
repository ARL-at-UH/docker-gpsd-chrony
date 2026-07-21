# Jetson AGX Orin — from a fresh JetPack 6.x install to a verified time server

End-to-end walkthrough for standing up this container on a Jetson AGX Orin
devkit that has nothing on it yet but JetPack 6.x (L4T r36). Each step links
to the doc that covers it in full detail — this guide is the order to do
them in, not a replacement for them.

Estimate: 30–45 minutes of hands-on time, plus however long your GNSS
receiver needs to get a first fix (can be several minutes cold, outdoors,
antenna with sky view).

## 0. Prerequisites

- AGX Orin devkit (p3737 carrier) already flashed with JetPack 6.x. Flashing
  itself is out of scope here — see
  [NVIDIA's SDK Manager / JetPack install docs](https://docs.nvidia.com/jetson/)
  if you haven't done that yet.
- A USB GNSS receiver with a PPS output (this repo is tested with the
  [SparkFun ZED-F9P](https://www.sparkfun.com/sparkfun-gps-rtk-sma-breakout-zed-f9p-qwiic.html)).
  PPS is a separate signal wire — USB alone does not carry it.
- Jumper wires to bring the receiver's PPS pin to the 40-pin header, plus a
  clear-sky antenna position.
- A host network connection (for `apt`, Docker Hub / git clone).

## 1. Install Docker

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"   # log out/in for this to take effect
```

Confirm:

```bash
docker compose version
```

## 2. Disable competing time services on the host

The container's `chronyd` must be the only thing steering the clock:

```bash
sudo systemctl stop systemd-timesyncd
sudo systemctl disable systemd-timesyncd
timedatectl | grep 'NTP service'          # want: inactive
systemctl is-enabled systemd-timesyncd    # want: disabled or masked
```

If any other `chronyd`/`ntpd` is installed on the host itself (not the
container), stop and disable it too — two daemons steering the same clock
produces the oscillating-offset symptoms described in the PPS guide's
"Background" section (step 5 below).

## 3. Wire the GNSS receiver

- USB → any AGX Orin USB port (enumerates as `/dev/ttyACM0`, no driver
  config needed).
- PPS output → header **pin 22** (GPIO17), GND → header **pin 20** (adjacent
  ground) — see the wiring table in
  [agx-orin_pps_instructions.md](./device_tree_overlays/agx-orin_pps_instructions.md#0-wiring).
  The header is 3.3 V logic; a 5 V PPS signal needs a level shifter first.
- Power the board, plug in the receiver, and give it a clear-sky antenna
  position — most receivers only pulse PPS once they have a fix.

## 4. Set up the PPS device tree overlay

This is the step most likely to trip you up (wrong GPIO numbering scheme,
`pps-ktimer` masquerading as the real device) — follow the full guide, don't
skip steps:

**→ [device_tree_overlays/agx-orin_pps_instructions.md](./device_tree_overlays/agx-orin_pps_instructions.md)**

It walks through: host prerequisites, proving the raw pulse reaches the pin
*before* touching the device tree, building and merging the overlay,
blacklisting the fake `pps-ktimer` source, and verifying `/dev/pps0` is
real and pulsing after reboot. **No internet on the Jetson?**
[deps/](./deps/) has the three host packages it needs (`gpiod`,
`pps-tools`, `device-tree-compiler`) pre-downloaded for offline install.
Do not proceed past this step until
`sudo ppstest /dev/pps0` shows one assert per second.

## 5. (Optional) Install the udev rule for a stable GPS device name

USB serial devices can re-enumerate (`ttyACM0` → `ttyACM1`) across reboots
or replugs. The rule in this repo pins the receiver to `/dev/gps0` by USB
vendor/product ID and is identical on every board, including AGX Orin — no
board-specific edits needed:

```bash
cd udev_rules
sudo cp 99-usb-gps.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
ls -l /dev/gps0
```

Full details, including why the two-sided `devices:` mapping form matters:
[udev_rules/README.md](./udev_rules/README.md).

## 6. Clone the repo and configure the container

```bash
git clone https://github.com/ARL-at-UH/docker-gpsd-chrony
cd docker-gpsd-chrony
```

`compose.yaml` already ships with the AGX Orin's exact device mapping as
its default (`/dev/ttyACM0:/dev/gps0`, `/dev/pps0:/dev/pps0`) — no edit
needed unless you installed the udev rule in step 5, in which case swap the
GPS line's host side:

```yaml
devices:
    - /dev/gps0:/dev/gps0      # only if the udev rule is installed
    - /dev/pps0:/dev/pps0
```

Check `GPS_SPEED` in [config.env](./config.env) — USB CDC-ACM receivers
(like the ZED-F9P) ignore it, so the default is fine unless you're using a
UART receiver instead.

## 7. Build or pull, and bring the container up

```bash
sudo docker build -t arluhdev/docker-gpsd-chrony .   # or: sudo docker image pull arluhdev/docker-gpsd-chrony
sudo docker compose up -d
sudo docker logs -f gpsd-chrony
```

`restart: unless-stopped` in `compose.yaml` makes this boot-persistent
automatically — no systemd unit needed, only `sudo systemctl enable docker`
if it isn't already enabled.

## 8. Verify end-to-end

Follow the layered procedure in
[VERIFICATION.md](./VERIFICATION.md) — it checks host devices, container
startup, kernel PPS, gpsd fix status, the gpsd→chrony handoff, and finally
chrony's lock, in that order, so a failure tells you which layer to look
at. The quick health check once things settle (a few minutes):

```bash
sudo docker exec gpsd-chrony chronyc sources
```

```
MS Name/IP address         Stratum Poll Reach LastRx Last sample
===============================================================================
#x NMEA                          0   0   377     0    +87ms[  +87ms] +/- 1000us
#* PPS                           0   3   377    10   -310ns[   +9ns] +/-   13ms
```

`#*` on the `PPS` line is the pass condition. `#x` on `NMEA` is expected and
fine — the jittery serial time is only used to number PPS seconds, not to
steer the clock.

## 9. Calibrate (optional, once verification passes)

[calibration/CHRONY_OFFSET_CALIBRATION.md](calibration/CHRONY_OFFSET_CALIBRATION.md)
covers fine-tuning chrony's offset once the basic setup is confirmed
working.

## Troubleshooting

Almost every failure mode at this stage is a PPS device-tree issue, not a
container issue — see the Troubleshooting section at the bottom of
[agx-orin_pps_instructions.md](./device_tree_overlays/agx-orin_pps_instructions.md#5-verify-after-reboot)
first. For container/gpsd/chrony-side issues once `/dev/pps0` is confirmed
real, use [VERIFICATION.md](./VERIFICATION.md)'s troubleshooting matrix.
