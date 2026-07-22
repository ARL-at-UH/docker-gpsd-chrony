# Jetson Orin Nano devkit — GNSS PPS on GPIO (install + verification guide)

Sets up a real hardware PPS input on the 40-pin header using `pps-gpio` and
the overlay `orin-nano_gnss-pps-gpio.dts`. Targets **JetPack 6.x (L4T r36,
kernel 5.15+)** on the Orin Nano devkit (p3768 carrier).

This mirrors `agx-orin_pps_instructions.md` — read that guide's linked
Xavier "Background: why ktimer must go" section for the fake-PPS failure
mode this setup avoids (gpsd warning `is fake PPS`, chrony ping-ponging
between GPS and PPS). Sections below only spell out what differs on the
Orin Nano.

All commands run **on the Jetson host** (not inside the container) unless
stated otherwise.

## 0. Wiring

| Receiver | Header |
|---|---|
| PPS output | physical pin **22** (SoC pad PY.01, CVM name SPI1_MISO) |
| GND | physical pin **20** (adjacent ground) |

The header is **3.3 V logic**; a 5 V PPS output needs a level shifter or
divider. The receiver must have a fix for a (meaningful) pulse to exist.

> **This is the same physical pin as the AGX Orin guide, but NOT the same
> signal.** AGX Orin's pin 22 is CVM `GPIO17` (pad PP.04). The Orin Nano
> module wires this header position to a completely different SoC pad,
> PY.01, whose peripheral name is `SPI1_MISO`. There is no pin named
> `GPIO17` anywhere on the Orin Nano/NX header — do not reuse the AGX
> `gpios = <&gpio 116 0>;` value here; it decodes to the wrong pad on this
> module and will either fail probe or read the wrong line.
>
> Despite the peripheral name, this pin defaults to plain GPIO/tristate on
> the stock devkit device tree, the same as every other unused header pin
> — SPI1 is only "live" if something explicitly claims it (a loaded
> `spidev`, a Jetson-IO config change, or another overlay). Step 2 below
> proves that before you touch the device tree.

> **Super Mode devkits:** if `cat /proc/device-tree/compatible` shows a
> `-super` suffix (e.g. `nvidia,p3768-0000+p3767-0005-super`), that's the
> Jetson Orin Nano Super power/clock firmware — it's the same p3767-0005
> module and the same pinout, so pin 22 is still PY.01 and none of the
> GPIO numbers below change. Only the `compatible` string in the overlay
> (step 3) needs the `-super` suffix to match.

## 1. Host prerequisites

```sh
sudo apt install -y gpiod pps-tools device-tree-compiler

grep -i pps /lib/modules/$(uname -r)/modules.builtin   # what's builtin?
modinfo pps_gpio 2>/dev/null | head -3                 # module or builtin?
```

No internet on the Jetson? [../deps/](../deps/) has these three packages
(and their dependencies) pre-downloaded for arm64/JetPack 6.x, with an
offline install README.

`pps-gpio` must exist as builtin or module. While there, note how
**pps-ktimer** ships, because neutralizing it differs by build type:

- listed in `modules.builtin` → kernel command line (step 4):
  `initcall_blacklist=pps_ktimer_init`
- `modinfo pps_ktimer` shows a `.ko` file → modprobe blacklist instead:

  ```sh
  echo "blacklist pps-ktimer" | sudo tee /etc/modprobe.d/blacklist-pps-ktimer.conf
  sudo update-initramfs -u
  ```

- neither → nothing to do (some r36 kernels drop it entirely).

## 2. Prove the pulse reaches the pin (before any device-tree work)

Pin 22 is **packed** line offset 123 on the main (`tegra234-gpio`) chip —
userspace tools use packed offsets; only the device tree uses the sparse
encoding (145). Do not mix them.

```sh
gpiodetect     # find the main chip: label tegra234-gpio (NOT -aon), the big one
CHIP=$(gpiodetect | awk '$2=="[tegra234-gpio]"{print $1}')
echo "chip: $CHIP"   # if empty, read gpiodetect output and set CHIP by hand

# Sample at 20 Hz for 3 s; a typical PPS pulse is ~100 ms wide at 1 Hz,
# so expect mostly 0s with a few 1s:
for i in $(seq 1 60); do gpioget "$CHIP" 123; sleep 0.05; done | sort | uniq -c
```

All 0s → no fix, wrong pin, or too-narrow pulse. All 1s → likely inverted;
add `assert-falling-edge;` to the overlay. If every sample errors out
instead of reading 0/1, something (spidev, another overlay) already owns
the pin in SPI mode — check `dmesg` and `cat /sys/kernel/debug/pinctrl/*/pinmux-pins`
for a conflicting claim before going further. (`gpiomon` edge events are
unreliable on Tegra — a `No such file or directory` from it means nothing;
trust the polling loop.)

## 3. Build the overlay

```sh
cat /proc/device-tree/compatible | tr '\0' '\n' | head -1
```

Make the overlay's `compatible` match exactly (devkit module variants:
p3767-0005-super devkit SD-card 8GB with Super Mode firmware, p3767-0005
same without Super Mode, -0003 commercial eMMC 8GB, -0004 4GB), then:

```sh
dtc -@ -I dts -O dtb -o orin-nano_gnss-pps-gpio.dtbo orin-nano_gnss-pps-gpio.dts
```

## 4. Merge into the DTB, register, and (if builtin) blacklist ktimer

```sh
ls /boot/dtb/        # r36 names look like kernel_tegra234-p3768-0000+p3767-0005-super-nv.dtb
                      # (unconfirmed exact filename for the -super variant -- check `ls` output)
BASE=/boot/dtb/kernel_tegra234-p3768-0000+p3767-0005-super-nv.dtb   # adjust to yours

# The gpio phandle must resolve; this prints a path like /bus@0/gpio@2200000:
fdtget "$BASE" /__symbols__ gpio

sudo fdtoverlay -i "$BASE" -o /boot/dtb/kernel_pps-merged.dtb \
                orin-nano_gnss-pps-gpio.dtbo

# Verify BEFORE rebooting — middle value must be the sparse number:
fdtget /boot/dtb/kernel_pps-merged.dtb /pps gpios    # expect: <phandle> 145 0
```

Then edit `/boot/extlinux/extlinux.conf` in the `LABEL` block named by
`DEFAULT`:

1. `FDT /boot/dtb/kernel_pps-merged.dtb` — the path must be exact. **A
   missing file anywhere in the boot entry makes the bootloader silently
   abandon extlinux.conf and boot partition defaults, discarding your
   `APPEND` edits too** (symptom: additions vanish from `/proc/cmdline`).
2. Only if ktimer is *builtin* (step 1): append
   `initcall_blacklist=pps_ktimer_init` to the `APPEND` line.

Save, `sudo reboot`.

> Re-run the `fdtoverlay` merge after any JetPack/kernel update — a new
> stock DTB does not regenerate your merged blob.

## 5. Verify after reboot

```sh
grep -o 'initcall_blacklist=[^ ]*' /proc/cmdline   # only if you added it
ls /proc/device-tree/ | grep pps                   # node present
ls /dev/pps*                                       # exactly /dev/pps0
cat /sys/class/pps/pps0/name                       # NOT "ktimer"
readlink -f /sys/class/pps/pps0                    # .../platform/pps/..., not /virtual/
sudo ppstest /dev/pps0                             # one assert per second
```

**Node present but no `/dev/pps0`, dmesg shows `probe of pps failed with
error -22` *before* the `gpiochip ... tegra234-gpio` registration line?**
That's the L4T boot-order bug (GPIO controller module loads after builtin
pps-gpio, which fails instead of deferring — confirmed on r35, may or may
not affect your r36 build). Confirm with a manual rebind:

```sh
echo pps | sudo tee /sys/bus/platform/drivers/pps-gpio/bind
ls /dev/pps*
```

If that produces `/dev/pps0`, install the retry unit from this directory:

```sh
sudo cp pps-gpio-rebind.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now pps-gpio-rebind.service
```

If `-22` appears *after* the gpiochip registered, the `gpios` cell is wrong
(packed vs sparse — see the table below).

## 6. Acid test + single-daemon check

Same as the Xavier/AGX guides: with `ppstest` running, disconnect/cover the
antenna — pulses must stop when the fix drops (a fake source ticks
forever). And ensure exactly one clock-steering daemon on the host:

```sh
timedatectl | grep 'NTP service'                     # want: inactive
systemctl is-enabled systemd-timesyncd 2>/dev/null   # want: disabled/masked
```

## 7. Container bring-up

Identical to the AGX/Xavier guides: `compose.yaml` already maps
`/dev/pps0:/dev/pps0`; recreate the container, confirm gpsd starts without
`is fake PPS`, and after ~10 minutes `chronyc sources` shows `#* PPS` at
microsecond offsets (`GPS` at `#x` falseticker is expected — it only
numbers the PPS seconds via `lock GPS`).

## Orin Nano 40-pin pin reference (main controller only)

Grounds at 6, 9, 14, 20, 25, 30, 34, 39. Sparse = `port_index × 8 + pin`
with Tegra234 MAIN ports A=0 … N=13, P=14, Q=15, R=16, X=17, Y=18, Z=19
(**no port O — same MAIN port table as the AGX Orin guide**, since it's a
property of the Tegra234 die, not the carrier board).

Values below come from NVIDIA's `jetson-gpio` channel table for
`JETSON_ORIN_NX`/Nano, cross-checked against the documented sysfs GPIO
numbers (base 348 + packed offset).

| Header pin | gpioget offset (packed) | DT `gpios` cell (sparse) | Pad | CVM name |
|---|---|---|---|---|
| 22 | 123 | 145 | PY.01 | SPI1_MISO (this guide; GND at 20) |
| 29 | 105 | 125 | PQ.05 | GPIO01 (plain GPIO, no PWM alt) |
| 31 | 106 | 126 | PQ.06 | GPIO11 (plain GPIO, no PWM alt) |
| 15 | 85  | 105 | PN.01 | GPIO12 (has PWM alt on 3280000.pwm) |
| 33 | 43  | 56  | PH.00 | GPIO13 (has PWM alt on 32c0000.pwm) |

Pin 7 (`GPIO09`) uses pad `PAC.06`, on a port letter (`AC`) outside the
table above — its sparse index isn't derived here; don't guess it from
this table.
