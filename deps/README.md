# Offline dependencies — PPS/GPS host verification tools

Pre-downloaded `.deb` packages for the host-side tools needed to verify PPS
and GPS **before bringing up the container** (the container itself carries
its own copies of `gpsd`/`chrony` — these are separate, host-only tools).
Meant for a Jetson AGX Orin (or Xavier NX) that has no internet access at
setup time — download this repo (including this folder) on a machine that
does have internet, copy it to the Jetson (USB drive, `scp`, etc.), and
install from the local files.

## What's here and why

These are exactly the packages [`agx-orin_pps_instructions.md`](../device_tree_overlays/agx-orin_pps_instructions.md)
and [`xavier-nx_pps_instructions.md`](../device_tree_overlays/xavier-nx_pps_instructions.md)
step 1 ask you to `apt install`, plus their non-base dependencies (anything
already part of a stock Ubuntu 22.04 install — `libc6`, `libgcc-s1`,
`libstdc++6` — is **not** included here; it's already on the device):

| File | Provides | Used for |
|---|---|---|
| `pps-tools_1.0.2-2_arm64.deb` | `ppstest`, `ppsfind`, `ppswatch` | Proving the kernel PPS device is really pulsing (`ppstest /dev/pps0`) |
| `gpiod_1.6.3-1build1_arm64.deb` | `gpiodetect`, `gpioget`, `gpioinfo`, `gpiomon` | Proving the raw PPS pulse reaches the header pin *before* any device-tree work |
| `libgpiod2_1.6.3-1build1_arm64.deb` | shared library | Runtime dependency of `gpiod` |
| `device-tree-compiler_1.6.1-1_arm64.deb` | `dtc`, `fdtoverlay`, `fdtget`, `fdtput`, `fdtdump` | Compiling the `.dts` overlay to `.dtbo`, merging it into the base DTB, and inspecting the result before rebooting |
| `libfdt1_1.6.1-1_arm64.deb` | shared library | Runtime dependency of `device-tree-compiler` |
| `libyaml-0-2_0.2.2-1build2_arm64.deb` | shared library | Runtime dependency of `device-tree-compiler` |

Built for **arm64 / Ubuntu 22.04 "jammy"**, matching JetPack 6.x (L4T r36) —
the same package set installs on Xavier NX's JetPack 5 (Ubuntu 20.04
"focal"), but focal's package versions differ; re-download from
`packages.ubuntu.com` for `focal`/`arm64` if targeting a Xavier NX instead.

**GPS itself needs no separate host tool** — the receiver enumerates as a
standard USB serial device (`/dev/ttyACM0`) with no driver install, and its
NMEA/fix status before container bring-up is normally checked by the
gpsd inside the image after `docker compose up`. If you want to inspect raw
NMEA sentences from the host with no container running at all, `cat
/dev/ttyACM0` (Ctrl-C to stop) works with tools already on any base Linux
install — no package needed.

## Check if you even need this first

JetPack 6.x's base image does not ship `pps-tools`, `gpiod`, or
`device-tree-compiler` by default. Confirm before bothering with an offline
install:

```bash
command -v ppstest gpiodetect dtc fdtoverlay
```

If all four print a path, skip this folder entirely — everything needed is
already on the device.

## Install (offline, on the Jetson)

Order matters: install the shared-library dependencies before the tools
that need them, or `dpkg` will report unmet dependencies (harmless if you
then run the second command below, which resolves the ordering for you).

```bash
cd deps
sudo dpkg -i libfdt1_1.6.1-1_arm64.deb libyaml-0-2_0.2.2-1build2_arm64.deb libgpiod2_1.6.3-1build1_arm64.deb
sudo dpkg -i device-tree-compiler_1.6.1-1_arm64.deb gpiod_1.6.3-1build1_arm64.deb pps-tools_1.0.2-2_arm64.deb
```

If `dpkg` stops on a missing dependency, resolve it without touching the
network:

```bash
sudo apt-get install -f --no-download
```

## Verify integrity before installing

Confirm the files weren't corrupted in transit (e.g. over a USB copy):

```bash
sha256sum -c SHA256SUMS
```

## Verify the install

```bash
dpkg -l | grep -E 'pps-tools|gpiod|libgpiod2|device-tree-compiler|libfdt1|libyaml'
ppstest 2>&1 | head -1        # usage message = binary present and runs
gpiodetect                     # lists GPIO chips
dtc --version                  # >= 1.6.0
```

Then continue with step 2 of the PPS instructions doc for your board.

## Re-generating / updating this folder

If a package version changes upstream or you need a different board's OS
release (e.g. Xavier NX's focal instead of jammy), re-download from
`https://packages.ubuntu.com/<release>/arm64/<package>/download` — that
page lists the exact filename, the `pool/...` subpath, and SHA256/MD5
checksums to verify against. The arm64 archive lives at
`http://ports.ubuntu.com/ubuntu-ports/<pool-path>` (arm64 is not in the
primary `archive.ubuntu.com` mirror).
