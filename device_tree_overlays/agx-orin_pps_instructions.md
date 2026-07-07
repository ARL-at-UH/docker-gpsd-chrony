# Jetson AGX Orin devkit — GNSS PPS on GPIO (install + verification guide)

Sets up a real hardware PPS input on the 40-pin header using `pps-gpio` and
the overlay `agx-orin_gnss-pps-gpio.dts`. Targets **JetPack 6.x (L4T r36,
kernel 5.15+)** on the AGX Orin devkit (p3737 carrier).

This mirrors `xavier-nx_pps_instructions.md` — read that guide's
"Background: why ktimer must go" section for the fake-PPS failure mode this
setup avoids (gpsd warning `is fake PPS`, chrony ping-ponging between GPS
and PPS). Sections below only spell out what differs on Orin/JetPack 6.

All commands run **on the Jetson host** (not inside the container) unless
stated otherwise.

## 0. Wiring

| Receiver | Header |
|---|---|
| PPS output | physical pin **22** (GPIO17, pad PP.04) |
| GND | physical pin **20** (adjacent ground) |

The header is **3.3 V logic**; a 5 V PPS output needs a level shifter or
divider. The receiver must have a fix for a (meaningful) pulse to exist.

> **Do not reuse the Xavier pin/values.** The AGX Orin header assigns
> different functions: pin 29 (the Xavier guide's choice) is `CAN0_DIN`
> here, on the AON GPIO controller. Stick to main-controller pins (see the
> table at the end) unless you want to re-derive the AON phandle and
> numbering.

## 1. Host prerequisites

```sh
sudo apt install -y gpiod pps-tools device-tree-compiler

grep -i pps /lib/modules/$(uname -r)/modules.builtin   # what's builtin?
modinfo pps_gpio 2>/dev/null | head -3                 # module or builtin?
```

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

Pin 22 is **packed** line offset 96 on the main (`tegra234-gpio`) chip —
userspace tools use packed offsets; only the device tree uses the sparse
encoding (116). Do not mix them.

```sh
gpiodetect     # find the main chip: label tegra234-gpio (NOT -aon), the big one
CHIP=$(gpiodetect | awk '$2=="[tegra234-gpio]"{print $1}')
echo "chip: $CHIP"   # if empty, read gpiodetect output and set CHIP by hand

# Sample at 20 Hz for 3 s; a typical PPS pulse is ~100 ms wide at 1 Hz,
# so expect mostly 0s with a few 1s:
for i in $(seq 1 60); do gpioget "$CHIP" 96; sleep 0.05; done | sort | uniq -c
```

All 0s → no fix, wrong pin, or too-narrow pulse. All 1s → likely inverted;
add `assert-falling-edge;` to the overlay. (`gpiomon` edge events are
unreliable on Tegra — a `No such file or directory` from it means nothing;
trust the polling loop.)

## 3. Build the overlay

```sh
cat /proc/device-tree/compatible | tr '\0' '\n' | head -1
```

Make the overlay's `compatible` match exactly (devkit module variants:
p3701-0000 32GB, -0004/-0005 64GB, -0008 Industrial), then:

```sh
dtc -@ -I dts -O dtb -o agx-orin_gnss-pps-gpio.dtbo agx-orin_gnss-pps-gpio.dts
```

## 4. Merge into the DTB, register, and (if builtin) blacklist ktimer

```sh
ls /boot/dtb/        # r36 names look like kernel_tegra234-p3737-0000+p3701-0000-nv.dtb
BASE=/boot/dtb/kernel_tegra234-p3737-0000+p3701-0000-nv.dtb   # adjust to yours

# The gpio phandle must resolve; this prints a path like /bus@0/gpio@2200000:
fdtget "$BASE" /__symbols__ gpio

sudo fdtoverlay -i "$BASE" -o /boot/dtb/kernel_pps-merged.dtb \
                agx-orin_gnss-pps-gpio.dtbo

# Verify BEFORE rebooting — middle value must be the sparse number:
fdtget /boot/dtb/kernel_pps-merged.dtb /pps gpios    # expect: <phandle> 116 0
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

Same as the Xavier guide: with `ppstest` running, disconnect/cover the
antenna — pulses must stop when the fix drops (a fake source ticks
forever). And ensure exactly one clock-steering daemon on the host:

```sh
timedatectl | grep 'NTP service'                     # want: inactive
systemctl is-enabled systemd-timesyncd 2>/dev/null   # want: disabled/masked
```

## 7. Container bring-up

Identical to the Xavier guide step 7: `compose.yaml` already maps
`/dev/pps0:/dev/pps0`; recreate the container, confirm gpsd starts without
`is fake PPS`, and after ~10 minutes `chronyc sources` shows `#* PPS` at
microsecond offsets (`GPS` at `#x` falseticker is expected — it only
numbers the PPS seconds via `lock GPS`).

## AGX Orin 40-pin pin reference (main controller only)

Grounds at 6, 9, 14, 20, 25, 30, 34, 39. Sparse = `port_index × 8 + pin`
with Tegra234 MAIN ports A=0 … N=13, P=14, Q=15, R=16, X=17, Y=18, Z=19
(**no port O — indices differ from Tegra194!**).

| Header pin | gpioget offset (packed) | DT `gpios` cell (sparse) | Pad | Name |
|---|---|---|---|---|
| 22 | 96  | 116 | PP.04 | GPIO17 (this guide; GND at 20) |
| 7  | 106 | 126 | PQ.06 | MCLK05 (between GND 6 and 9) |
| 15 | 85  | 105 | PN.01 | GPIO27 (next to GND 14; has PWM alt) |
| 18 | 43  | 56  | PH.00 | GPIO35 (next to GND 20; has PWM alt) |

Pins 16, 29, 31, 32, 33, 37 are on the AON controller — different phandle
(`&gpio_aon`) and port numbering; avoid them for this overlay.
