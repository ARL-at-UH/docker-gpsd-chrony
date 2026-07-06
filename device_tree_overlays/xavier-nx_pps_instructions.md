# Jetson Xavier NX — GNSS PPS on GPIO (install + verification guide)

Sets up a real hardware PPS input on the 40-pin header using `pps-gpio` and the
overlay `xavier-nx_gnss-pps-gpio.dts`, and removes the **fake `pps-ktimer`
device** that previously fooled gpsd and chrony (symptom: gpsd warned
`is fake PPS, timing will be inaccurate`, chrony ping-ponged between GPS and
PPS with growing alternating offsets).

All commands run **on the Jetson host** (not inside the container) unless
stated otherwise.

## Background: why ktimer must go

`pps-ktimer` is a kernel *test* module that synthesizes a 1 Hz pulse from the
system clock itself. On L4T it is **built into the kernel** (`rmmod` fails
with "builtin"), and it registers at boot, grabbing the `/dev/pps0` name.
Feeding it to chrony makes the clock discipline itself against its own echo.
Its fingerprints, and how a real pps-gpio source differs:

| Check | ktimer (fake) | pps-gpio (real) |
|---|---|---|
| `cat /sys/class/pps/pps0/name` | `ktimer` | `pps.-1` / `pps` (platform dev name) |
| `readlink -f /sys/class/pps/pps0` | contains `/devices/virtual/pps/` | contains `/devices/platform/pps/` |
| gpsd startup log | `WARN: ... is fake PPS` | no fake-PPS warning |
| Unplug GPS antenna / lose fix | keeps pulsing forever | pulses stop |

Because it is builtin, the fix is the kernel command line:
`initcall_blacklist=pps_ktimer_init` (step 4).

## 0. Wiring

| Receiver | Header |
|---|---|
| PPS output | physical pin **29** (GPIO01) |
| GND | physical pin **30** (adjacent ground) |

The header is **3.3 V logic**. A 5 V PPS output needs a level shifter or
divider first. Receiver must have a fix for a PPS pulse to exist at all —
most modules only pulse (or only pulse accurately) with a fix.

## 1. Host prerequisites

```sh
sudo apt install -y gpiod pps-tools device-tree-compiler

# pps-gpio driver must exist (builtin or module):
grep -i pps /lib/modules/$(uname -r)/modules.builtin
modinfo pps_gpio 2>/dev/null | head -3
```

Expect `pps-gpio`/`pps_gpio` in one of the two outputs (alongside the
unwanted `pps-ktimer`). If it is missing entirely, stop — the kernel needs
`CONFIG_PPS_CLIENT_GPIO`, which is out of scope for this guide.

## 2. Prove the pulse reaches the pin (before any device-tree work)

This validates wiring, pinmux, and the line offset in one shot. Pin 29 is
line offset **105** on the 169-line main GPIO controller:

```sh
CHIP=$(gpiodetect | awk '$3=="[tegra194-gpio]"{print $1}')   # main chip, 169 lines
echo "main chip: $CHIP"

# Sample the pin at 20 Hz for 3 s. A typical PPS pulse is ~100 ms wide at
# 1 Hz, so expect mostly 0s with a few 1s:
for i in $(seq 1 60); do gpioget "$CHIP" 105; sleep 0.05; done | sort | uniq -c
```

- **Mix of 0s and a few 1s** → pulse present, proceed.
- **All 0s** → no fix yet, wiring/pin wrong, or pulse too narrow for polling
  (some receivers default to a very short pulse; configure the receiver for
  ~100 ms pulse width if adjustable).
- **All 1s** → likely inverted pulse (idle-high). Wiring is fine; add
  `assert-falling-edge;` to the overlay's `pps` node.

> Note: `gpiomon` (edge events) is unreliable on Tegra for some lines and can
> fail with `No such file or directory` — that failure does NOT mean the pin
> is bad. Use the polling loop above instead.

## 3. Build the overlay

Check the board's compatible string and make the overlay match it exactly
(the bootloader silently skips overlays whose `compatible` doesn't match):

```sh
cat /proc/device-tree/compatible | tr '\0' '\n' | head -1
```

Edit `xavier-nx_gnss-pps-gpio.dts` if needed (compatible string; offset if
you wired a different pin), then compile and install:

```sh
dtc -@ -I dts -O dtb -o xavier-nx_gnss-pps-gpio.dtbo xavier-nx_gnss-pps-gpio.dts
sudo cp xavier-nx_gnss-pps-gpio.dtbo /boot/
```

(dtc warnings about unit names/addresses are harmless; errors are not.)

## 4. Register the overlay AND blacklist ktimer (one edit, one reboot)

```sh
sudo nano /boot/extlinux/extlinux.conf
```

In the active `LABEL primary` block:

1. Add the overlay line (or append to an existing `OVERLAYS` line,
   comma-separated):

   ```
   OVERLAYS /boot/xavier-nx_gnss-pps-gpio.dtbo
   ```

2. Append to the end of the existing `APPEND` line (same line, space-separated):

   ```
   initcall_blacklist=pps_ktimer_init
   ```

Save, then `sudo reboot`.

## 5. Verify on the host after reboot

Each check below distinguishes the real source from a ktimer relapse:

```sh
# 5a. Blacklist took effect:
grep -o 'initcall_blacklist=[^ ]*' /proc/cmdline     # prints the blacklist
ls /sys/devices/virtual/pps 2>/dev/null              # should NOT exist / be empty

# 5b. Exactly one PPS device, and it is hardware-backed:
ls /dev/pps*                                         # exactly /dev/pps0
cat /sys/class/pps/pps0/name                         # NOT "ktimer"
readlink -f /sys/class/pps/pps0                      # .../devices/platform/pps/... (not /virtual/)

# 5c. Overlay landed in the live device tree and the driver bound:
cat /proc/device-tree/pps/compatible                 # "pps-gpio"
sudo dmesg | grep -i pps                             # "new PPS source" from pps-gpio, no ktimer line

# 5d. Live pulses with correct timing:
sudo ppstest /dev/pps0
```

`ppstest` must print one `assert` line per second, sequence number
incrementing by exactly 1. Ctrl-C to stop.

**Two /dev/pps devices?** The blacklist didn't take (typo, wrong LABEL block,
or edited a non-active boot entry): `pps0` is ktimer again and the real one is
`pps1`. Fix the `APPEND` line rather than remapping devices.

## 6. Acid test: prove it is not another self-referential source

A fake PPS ticks no matter what the receiver does; a real one is slaved to
the sky. While `sudo ppstest /dev/pps0` is running, disconnect the GPS
antenna (or cover it) and wait for the receiver to drop its fix:

- **Pulses stop** (or the receiver's holdover behavior per its datasheet)
  → genuinely GPS-derived. Reconnect and confirm they resume.
- **Pulses continue indefinitely at exactly 1 Hz** → you are looking at a
  fake/self-clocked source again; recheck step 5a/5b.

Also confirm no second time daemon is steering the host clock (a competing
daemon re-creates the oscillation symptoms even with a real PPS):

```sh
timedatectl | grep 'NTP service'    # want: inactive
systemctl is-enabled systemd-timesyncd 2>/dev/null   # want: disabled/masked
```

## 7. Bring the container up and verify end-to-end

`compose.yaml` already maps `/dev/pps0:/dev/pps0`, so no config changes:

```sh
sudo docker compose up -d --force-recreate
sudo docker logs -f gpsd-chrony
```

Healthy startup, in order:

1. gpsd starts **without** `is fake PPS` or `missing PPS_CAPTURECLEAR`
   warnings.
2. No alternating `Selected source GPS` / `Selected source PPS` /
   `Detected falseticker` churn after the first few minutes.
3. After ~5–10 minutes:

```sh
sudo docker exec gpsd-chrony chronyc sources
sudo docker exec gpsd-chrony chronyc tracking
```

- `sources`: `#* PPS` selected, with offset/error in **microseconds**
  (was ±hundreds of ms with the fake source). `GPS` showing `#x`
  (falseticker) or unselected is **normal and expected** — with a real PPS
  the jittery NMEA source only numbers the PPS seconds via `lock GPS`.
- `tracking`: `Reference ID ... (PPS)`, `System time` offset in the
  microseconds, `Frequency` settling to a stable value, `Skew` dropping
  well below 1 ppm over time, `Root dispersion` in the microseconds.

## Troubleshooting

- **No `/dev/pps0` at all after reboot** — overlay skipped. Check
  `sudo dmesg | grep -iE 'dtbo|overlay'`; usual causes are a `compatible`
  mismatch (step 3) or a wrong path on the `OVERLAYS` line.
- **`/proc/device-tree/pps` exists but no `/dev/pps0`** — driver didn't bind:
  `sudo dmesg | grep -iE 'pps|gpio'` for probe errors. An out-of-range or
  already-claimed GPIO offset shows up here.
- **`/dev/pps0` exists, `ppstest` shows no asserts** — receiver has no fix,
  wiring, or wrong pin: redo step 2's polling test.
- **Asserts but timestamps drift wildly in the container** — check step 6's
  timesyncd test; two daemons are fighting over the clock.
- **Alternate pins** (all on the main `tegra194-gpio` chip; grounds at
  6, 9, 14, 20, 25, 30, 34, 39):

  | Header pin | Offset | Pad | Name |
  |---|---|---|---|
  | 29 | 105 | PQ.05 | GPIO01 (this guide) |
  | 31 | 106 | PQ.06 | GPIO11 (also next to GND pin 30) |
  | 7  | 118 | PS.04 | GPIO09 (next to GND pin 9) |
  | 33 | 84  | PN.01 | GPIO13 (next to GND pin 34) |
