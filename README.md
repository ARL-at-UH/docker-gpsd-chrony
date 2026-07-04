# docker-gpsd-chrony

A containerized GPS-disciplined stratum-1 NTP time server for Linux single
board computers (SBCs).

This Docker image runs the Linux GPS daemon (`gpsd`) together with `chrony`.
`gpsd` reads NMEA sentences from a GPS/GNSS receiver (serial or USB) and
timestamps the receiver's pulse-per-second (PPS) signal via the kernel PPS
subsystem. It hands both to `chrony` through a shared-memory refclock;
`chrony` disciplines the system clock to the PPS edge and serves NTP to the
network.

Together these services provide a GPS 1PPS corrected time server with
microsecond-level accuracy on any Linux SBC that can expose:

- a serial or USB connection to a GNSS receiver, and
- a GPIO pin bound to the kernel `pps-gpio` driver (for the PPS signal).

Tested platforms:

| Platform | Host GPS device | Host PPS device | Notes |
|---|---|---|---|
| Raspberry Pi 4 (Debian 12) | `/dev/ttyAMA0` | `/dev/pps0` | UART + `pps-gpio` overlay |
| Toradex Verdin iMX8M Plus (Mallow carrier, Torizon OS) | `/dev/ttyACM0` | `/dev/pps0` | USB GNSS + GPIO PPS overlay (see [device_tree_overlays](./device_tree_overlays/)) |
| Toradex Apalis (Ixora carrier) | `/dev/apalis-uart2` | `/dev/pps1` | UART + GPIO PPS |
| NVIDIA Jetson Xavier NX | `/dev/ttyACM0` | `/dev/pps0` | prebuilt image tag `xavier-nx` |

Host device names go on the **left side** of the `devices:` mappings in
[compose.yaml](./compose.yaml); inside the container they always appear as
`/dev/gps0` and `/dev/pps0`, so [config.env](./config.env) and
[chrony.conf](./chrony_config/chrony.conf) are platform-independent. Example
mappings for each platform are in the comments of both files.

## Resources

Repo: [ARL-at-UH/docker-gpsd-chrony](https://github.com/ARL-at-UH/docker-gpsd-chrony) <br>
Docker Hub: [arluhdev/docker-gpsd-chrony](https://hub.docker.com/repository/docker/arluhdev/docker-gpsd-chrony/general) <br>

**GPSD / chrony / PPS:**

- [GPSD Time Service HOWTO](https://gpsd.gitlab.io/gpsd/gpsd-time-service-howto.html)
- [chrony project documentation](https://chrony-project.org/)
- [pps-tools](https://github.com/redlab-i/pps-tools)
- Source tutorial: [Revisiting Microsecond Accurate NTP for Raspberry Pi with GPS PPS in 2025 — Austin's Nerdy Things](https://austinsnerdythings.com/2025/02/14/revisiting-microsecond-accurate-ntp-for-raspberry-pi-with-gps-pps-in-2025/)

**Raspberry Pi:**

- [Raspberry Pi UART configuration](https://www.raspberrypi.com/documentation/computers/configuration.html#primary-uart)
- [Raspberry Pi device tree overlays](https://www.raspberrypi.com/documentation/computers/configuration.html#device-trees-overlays-and-parameters)

**Toradex (Apalis / Verdin):**

- [Apalis SoM family](https://developer.toradex.com/hardware/apalis-som-family/)
- [Verdin SoM family](https://developer.toradex.com/hardware/verdin-som-family/)
- [Device tree overlays overview](https://developer.toradex.com/software/linux-resources/device-tree/device-tree-overlays-overview/)
- [UART on Toradex Linux BSPs](https://developer.toradex.com/software/linux-resources/linux-features/uart-linux/)
- [GPIO on Toradex Linux BSPs](https://developer.toradex.com/software/linux-resources/linux-features/gpio-linux/)
- This repo's [Verdin iMX8MP PPS overlay + instructions](./device_tree_overlays/)

**NVIDIA Jetson:**

- [Jetson Linux documentation](https://docs.nvidia.com/jetson/)
- [Jetson Linux Developer Guide — kernel and device tree customization](https://docs.nvidia.com/jetson/archives/r36.3/DeveloperGuide/SD/Kernel.html)
- Expansion header configuration tool: `sudo /opt/nvidia/jetson-io/jetson-io.py`
- [Jetson Xavier NX GPIO header pinout (JetsonHacks)](https://jetsonhacks.com/nvidia-jetson-xavier-nx-gpio-header-pinout/)

## Prerequisites

- A Linux SBC with:
  - Docker installed (with `docker compose`)
  - a kernel providing the PPS subsystem and `pps-gpio` client
    (`CONFIG_PPS`, `CONFIG_PPS_CLIENT_GPIO`) — standard on Raspberry Pi OS,
    Torizon OS, and Jetson Linux
- A GPS/GNSS module with a PPS output (timing-grade module preferred)
  - tested with the [SparkFun ZED-F9P](https://www.sparkfun.com/sparkfun-gps-rtk-sma-breakout-zed-f9p-qwiic.html)
- 5 wires for a UART-connected receiver — VDC / RX / TX / GND / PPS
  (USB-connected receivers still need the PPS line wired to a GPIO)
- An antenna position with a clear sky view

## Setup overview

The flow is the same on every platform; only step 1 is platform-specific:

1. **Enable the serial port and PPS GPIO** on the host (see
   [Platform setup](#platform-setup) below). After this step the host must
   have a GPS device node (e.g. `/dev/ttyAMA0`, `/dev/ttyACM0`,
   `/dev/apalis-uart2`) and a PPS node (e.g. `/dev/pps0`).
2. **Disable competing time services** on the host:

   ```bash
   sudo systemctl stop systemd-timesyncd
   sudo systemctl disable systemd-timesyncd
   ```

   (Also disable any host-side `chronyd` or `ntpd`.)
3. **Wire the GPS module**: receiver TX → SBC RX, receiver RX → SBC TX,
   PPS → the GPIO you configured, plus power and ground. Check your
   module's voltage requirements first.
4. **Configure the container**: put your platform's host device names on
   the left side of the `devices:` mappings in
   [compose.yaml](./compose.yaml) (the container side stays `/dev/gps0` /
   `/dev/pps0`), and set `GPS_SPEED` in [config.env](./config.env).
   Optionally install the [udev rule](./udev_rules/) for a
   re-enumeration-proof host name.
5. **Build or pull the image** and bring it up.

## Platform setup

### Raspberry Pi

Tested on RPi 4 Model B (8 GB), Debian 12 (Bookworm), kernel 6.6 (64-bit).

1. Enable the PPS signal on a GPIO (pin 18 shown) in
   `/boot/firmware/config.txt`:

    ```bash
    sudo bash -c "echo '# GPS PPS signal' >> /boot/firmware/config.txt"
    sudo bash -c "echo 'dtoverlay=pps-gpio,gpiopin=18' >> /boot/firmware/config.txt"
    ```

2. Enable the UART and set the initial baud rate to match your receiver
   (anything is better than the 9600 NMEA default; use the highest rate
   your module supports):

    ```bash
    sudo bash -c "echo 'enable_uart=1' >> /boot/firmware/config.txt"
    sudo bash -c "echo 'init_uart_baud=38400' >> /boot/firmware/config.txt"
    ```

   Set the matching `GPS_SPEED` in [config.env](./config.env).

3. Load the `pps-gpio` module at boot:

    ```bash
    sudo bash -c "echo 'pps-gpio' >> /etc/modules"
    ```

4. Free the PL011 UART from Bluetooth:

    ```bash
    sudo bash -c "echo 'dtoverlay=disable-bt' >> /boot/firmware/config.txt"
    sudo systemctl disable hciuart
    ```

5. Disable the serial login shell and enable the serial port hardware:
   `sudo raspi-config` → *3 Interface Options* → *I6 Serial Port* →
   login shell **No** → serial hardware **Yes** → reboot.

6. Wiring (UART receiver):
   - GPS PPS → RPi pin 12 (GPIO 18)
   - GPS VIN → RPi 5 V pin 2/4 (or 3.3 V pin 1/17)
   - GPS GND → any RPi GND pin
   - GPS RX → RPi UART TX pin 8 (GPIO 14)
   - GPS TX → RPi UART RX pin 10 (GPIO 15)

   ![RASPI PINOUT](https://www.raspberrypi.com/documentation/computers/images/GPIO-Pinout-Diagram-2.png?hash=df7d7847c57a1ca6d5b2617695de6d46)

Typical compose mapping: `- /dev/ttyAMA0:/dev/gps0` and
`- /dev/pps0:/dev/pps0`.

### Toradex Apalis / Verdin

Toradex modules expose UARTs as named device nodes (e.g.
`/dev/apalis-uart2`, `/dev/verdin-uart1`) and take PPS input on any free
GPIO via a `pps-gpio` device tree overlay.

- **Verdin iMX8M Plus (Mallow carrier, Torizon OS)** — this repo ships a
  ready-made overlay and step-by-step instructions:
  - overlay source and GPIO-selection guide:
    [device_tree_overlays/gps_pps_gpio.dts](./device_tree_overlays/gps_pps_gpio.dts)
    and the accompanying
    [readme](./device_tree_overlays/verdin_imx8mp_device_tree_overlays_readme.md)
  - installing/activating the compiled `.dtbo` on Torizon OS (OSTree):
    [device_tree_overlays/DTO_instructions.md](./device_tree_overlays/DTO_instructions.md)
  - a GitHub Actions workflow
    ([device_tree_overlay_build.yaml](./.github/workflows/device_tree_overlay_build.yaml))
    builds the `.dtbo` artifact.
- **Apalis (Ixora carrier)** — same approach: write a `pps-gpio` overlay
  targeting a free GPIO (see Toradex's
  [device tree overlays overview](https://developer.toradex.com/software/linux-resources/device-tree/device-tree-overlays-overview/)),
  and connect the receiver to an Apalis UART.

Typical compose mapping (Apalis): `- /dev/apalis-uart2:/dev/gps0` and
`- /dev/pps1:/dev/pps0`. On Torizon OS, note that overlays live inside the
active OSTree deployment and should be baked in with TorizonCore Builder
for production (see the instructions above).

### NVIDIA Jetson

Tested on Jetson Xavier NX (a prebuilt image is published with the
`xavier-nx` tag).

1. **Serial**: a USB GNSS receiver enumerates as `/dev/ttyACM0` with no
   extra configuration. For a UART receiver, configure the 40-pin header
   UART with the expansion header tool:

    ```bash
    sudo /opt/nvidia/jetson-io/jetson-io.py
    ```

2. **PPS**: bind a header GPIO to the `pps-gpio` driver with a device tree
   overlay, the same pattern as the Verdin overlay in
   [device_tree_overlays](./device_tree_overlays/) but with
   `compatible` and the GPIO phandle set for your Jetson module/carrier.
   See the [Jetson Linux Developer Guide](https://docs.nvidia.com/jetson/)
   for compiling and registering overlays, and the
   [JetsonHacks pinout](https://jetsonhacks.com/nvidia-jetson-xavier-nx-gpio-header-pinout/)
   for header GPIO numbering.
3. Verify after reboot: `ls /dev/pps*` and `dmesg | grep -i pps` should
   show the `pps-gpio` device.

Typical compose mapping: `- /dev/ttyACM0:/dev/gps0` and
`- /dev/pps0:/dev/pps0` (or `- /dev/gps0:/dev/gps0` with the udev rule
from [udev_rules](./udev_rules/) installed).

## Container configuration

All runtime settings live in [config.env](./config.env) — key variables:

| Variable | Purpose |
|---|---|
| `GPS_DEVICE` | GNSS receiver device node passed to gpsd (container-side, normally `/dev/gps0`) |
| `PPS_DEVICE` | kernel PPS device node (container-side, normally `/dev/pps0`) |
| `GPS_SPEED` | serial baud rate (ignored for USB CDC-ACM receivers) |
| `ENABLE_MONITORING` / `RESTART_ON_FAILURE` | supervise gpsd/chronyd and restart them if they die |

Devices are passed through in [compose.yaml](./compose.yaml) with explicit
two-sided mappings — the platform's host device name on the left, a fixed
container name on the right:

```yaml
devices:
    - /dev/ttyACM0:/dev/gps0
    - /dev/pps0:/dev/pps0
```

Only the left side ever changes per platform. `config.env` and the
`refclock PPS /dev/pps0` line in
[chrony_config/chrony.conf](./chrony_config/chrony.conf) always refer to
the fixed container-side names.

### Stable USB device naming (udev)

USB serial receivers can re-enumerate (`/dev/ttyACM0` → `/dev/ttyACM1`)
across reboots and replugs, silently breaking the device mapping. The
[udev_rules](./udev_rules/) directory ships a udev rule that pins the
receiver to a persistent host name (`/dev/gps0`) by USB vendor/product ID,
plus install and verification instructions. Once installed, use the
symlink on the host side of the mapping:

```yaml
devices:
    - /dev/gps0:/dev/gps0
```

Two rules of engagement, explained in detail in
[udev_rules/README.md](./udev_rules/README.md):

- Docker resolves the host symlink **once, at container create** — after
  replugging the receiver, run
  `sudo docker compose up -d --force-recreate` to re-resolve it.
- **Do not add `privileged: true`** to the compose file: privileged mode
  makes Docker ignore `devices:` mappings entirely (all host devices
  appear under their raw kernel names), which breaks the fixed
  container-side naming. The compose file grants the specific capabilities
  chrony needs (`SYS_TIME`, `SYS_NICE`, `IPC_LOCK`) instead.

### Changing configuration or the startup script — no rebuild needed

`entrypoint.sh`, `chrony_config/`, and `config.env` are all mounted or read
from the repo checkout when the container starts (see `volumes:` and
`env_file:` in [compose.yaml](./compose.yaml)). After editing any of them,
just recreate the container:

```bash
sudo docker compose up -d --force-recreate
```

Use `--force-recreate` rather than `docker compose restart`: single-file
bind mounts pin the file at container-create time, so an editor that
replaces the file can leave a plain restart running the old content.

Rebuilding the image (`docker build`) is only needed when the
[Dockerfile](./Dockerfile) itself changes (e.g. installed packages). The
image still carries a baked-in copy of `entrypoint.sh` as a fallback, so it
remains usable standalone without the repo checkout.

### Serving NTP to external hosts

The compose file publishes NTP on the host's UDP port 123
(`"123:123/udp"` under `ports:` — the `/udp` suffix is required; a bare
`123:123` publishes TCP only and NTP clients will never connect).
Client access is controlled in
[chrony_config/chrony.conf](./chrony_config/chrony.conf): `allow all`
serves any client — tighten it to your network with e.g.
`allow 192.168.1.0/24`. If the host runs a firewall, open the port
(e.g. `sudo ufw allow 123/udp`). Remote `chronyc` monitoring is
intentionally disabled (`cmdport 0`); only time service is exposed. See
[VERIFICATION.md](./VERIFICATION.md) Layer 6 for client-side checks.

> **Possible future change — `network_mode: host`.** Bridge networking
> routes every NTP packet through veth/NAT (or the UDP userland proxy),
> which adds asymmetric latency (tens to hundreds of µs of client offset
> error on an SBC), hides real client IPs from `chronyc clients` (breaking
> per-client rate limiting and subnet-scoped `allow` rules), and creates a
> conntrack entry per client. Switching to `network_mode: host` fixes all
> three and enables proper socket timestamping — the better end state for
> a dedicated LAN time server — but it is **not** a bare one-liner: the
> `ports:` mapping must be removed (it would be ignored), firewalling
> becomes entirely the host's job, nothing else on the host may hold UDP
> 123, and critically **gpsd's TCP 2947 becomes reachable on all host
> interfaces** because gpsd runs with `-G` — so the switch must ship with
> `GPSD_LISTEN_ALL=false` (or a firewall rule for 2947) and a scoped
> `allow` in chrony.conf. Until then, bridge mode is kept for its
> isolation and out-of-the-box safety.

## Build and run

Clone and build:

```bash
git clone https://github.com/ARL-at-UH/docker-gpsd-chrony
cd docker-gpsd-chrony
sudo docker build -t arluhdev/docker-gpsd-chrony .
```

Or pull a prebuilt image:

```bash
sudo docker image pull arluhdev/docker-gpsd-chrony
```

Bring up the container attached to the terminal (useful for debugging):

```bash
sudo docker compose up
```

Or in the background (recommended):

```bash
sudo docker compose up --detach
```

## Run as a service (start at boot)

The compose file sets `restart: unless-stopped`, so the container is a
boot-persistent service by default — bring it up once with
`sudo docker compose up -d` and Docker restores it on every boot, until
you deliberately `docker compose stop`/`down` it.

The only host requirement is that the Docker daemon itself starts at boot:

- **Raspberry Pi OS / Jetson Linux:** `sudo systemctl enable docker`
  (usually already enabled by the standard install)
- **Torizon OS:** Docker is the native application runtime and is enabled
  by default — nothing to do

No systemd wrapper unit is needed. One would only add value if the
container had to be ordered against other host services; for the standard
deployment the restart policy is simpler and works identically on all
supported platforms.

### How the pieces self-heal

- **Boot:** daemon starts → container starts → the `devices:` mappings
  (including the `/dev/gps0` udev symlink) are re-resolved fresh.
- **Slow USB enumeration at boot:** the entrypoint waits up to
  `DEVICE_WAIT_TIMEOUT` (default 60 s) for the GPS device instead of
  exiting immediately. This also satisfies Docker's *10-second rule*: a
  container that exits within 10 seconds of starting is never restarted
  by any restart policy, so the entrypoint guarantees a minimum uptime
  before any failure exit.
- **USB replug / re-enumeration while running:** gpsd loses the device,
  the in-container monitor exhausts `MAX_RESTART_ATTEMPTS` (default 5)
  and exits the container; the restart policy starts it again with
  freshly resolved device mappings — no manual intervention.

## Verification

Follow the layered procedure in [VERIFICATION.md](./VERIFICATION.md). It
walks from host device nodes through kernel PPS (`ppstest`), gpsd fix
status (`cgps`, `gpspipe`), the gpsd→chrony shared-memory handoff, chrony
lock (`chronyc sources` / `chronyc tracking`), and finally NTP service to
network clients — with expected outputs, pass criteria, and a
troubleshooting matrix.

The short version of a healthy system:

```bash
sudo docker exec -it gpsd-chrony chronyc sources
```

```
MS Name/IP address         Stratum Poll Reach LastRx Last sample
===============================================================================
#x NMEA                          0   0   377     0    +87ms[  +87ms] +/- 1000us
#* PPS                           0   3   377    10   -310ns[   +9ns] +/-   13ms
```

`#*` on the PPS line means chrony is locked to the pulse-per-second
signal. (`x` on the NMEA line is normal — serial NMEA time is jittery and
chrony correctly rejects it for steering while still using it to number
the PPS pulses.)

## Calibration

Once verification passes, perform offset calibration and fine tuning:
[calibration/CHRONY_OFFSET_CALIBRATION.md](calibration/CHRONY_OFFSET_CALIBRATION.md)

## To do

- ~~dial back the docker `privileged` flag and make sure everything still works~~
  — done: replaced with `cap_add: SYS_TIME, SYS_NICE, IPC_LOCK` (pending
  on-hardware validation, see [VERIFICATION.md](./VERIFICATION.md))
- evaluate switching to `network_mode: host` for better served-time
  accuracy and real client IPs — see the note under
  [Serving NTP to external hosts](#serving-ntp-to-external-hosts) for the
  required mitigations (`GPSD_LISTEN_ALL=false`, scoped `allow`, host
  firewall)
