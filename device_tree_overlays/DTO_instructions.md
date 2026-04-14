# Applying the Device Tree Overlay (Torizon OS)

These steps install a compiled `.dtbo` onto a running Torizon OS device and activate it on next boot.

> **Note:** Torizon OS uses OSTree, so the active boot directory lives under a deployment-specific hash that changes after every OS update. The commands below resolve it dynamically so they keep working.

## 1. Copy the overlay to the device

From your build host:

```sh
scp verdin-imx8mp_gnss-pps-gpio.dtbo torizon@<device-ip>:/tmp/
```

## 2. Find the active deployment's overlay directory

On the device:

```sh
OVERLAY_DIR=$(dirname $(readlink -f /boot/ostree/*/dtb/overlays.txt))
echo "$OVERLAY_DIR"
```

You should see something like `/boot/ostree/torizon-<hash>/dtb/overlays`. If multiple deployments are present, pick the active one explicitly with `ostree admin status`.

## 3. Install the overlay

```sh
sudo cp /tmp/verdin-imx8mp_gnss-pps-gpio.dtbo "$OVERLAY_DIR/"
```

## 4. Register it in `overlays.txt`

Open the file:

```sh
sudo nano "$(dirname $OVERLAY_DIR)/overlays.txt"
```

Append the filename on its own line (or to the existing space-separated `fdt_overlays=` entry, depending on your BSP version — check what's already there and match the format):

```
verdin-imx8mp_gnss-pps-gpio.dtbo
```

Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X`).

## 5. Flush to disk and reboot

```sh
sudo sync
sudo reboot
```

## 6. Verify after reboot

```sh
dmesg | grep -i pps
ls /dev/pps*
cat /proc/device-tree/pps/compatible
```

You should see a `pps-gpio` driver bind message, a `/dev/pps0` device, and the overlay's node present in the live device tree. Test pulses with:

```sh
sudo ppstest /dev/pps0
```

(from the `pps-tools` package).

## Troubleshooting

- **Overlay not applied** — check `dmesg | grep -i overlay` for parse errors. A malformed `overlays.txt` entry or wrong format (newline-separated vs `fdt_overlays=` assignment) will silently skip the overlay.
- **`/dev/pps0` missing** — pin may not be muxed to GPIO mode, or `CONFIG_PPS_CLIENT_GPIO` isn't enabled in the running kernel. Check `zcat /proc/config.gz | grep PPS` if available.
- **Changes lost after OS update** — OSTree updates create a new deployment with a fresh hash; overlays in the old deployment's directory don't carry over. For persistent customization across updates, use TorizonCore Builder to bake the overlay into the image rather than copying it manually.