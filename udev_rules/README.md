# Stable USB device naming with udev

USB serial devices enumerate in whatever order the kernel finds them, so
the GNSS receiver that is `/dev/ttyACM0` today can be `/dev/ttyACM1` after
a reboot or replug. The rule in this directory gives the receiver a
persistent name — `/dev/gps0` — that the compose file can rely on.

## 1. Find your receiver's USB attributes

With the receiver plugged in (adjust `ttyACM0` to its current name):

```bash
udevadm info -a -n /dev/ttyACM0 | grep -iE 'idVendor|idProduct|serial'
```

For the SparkFun ZED-F9P you should see `idVendor=="1546"` (u-blox) and
`idProduct=="01a9"` — the shipped rule already matches these. For any
other receiver, edit [99-usb-gps.rules](./99-usb-gps.rules) and fill in
your values (variants for serial-number and physical-port matching are
included as comments).

## 2. Install the rule (on the host, not the container)

```bash
sudo cp 99-usb-gps.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
```

(`udevadm trigger` applies the rule to already-plugged devices; replugging
the receiver works too.)

> **Torizon OS note:** `/etc/udev/rules.d` lives in the writable `/etc`
> merge, so the rule persists across OSTree updates — unlike device tree
> overlays, no TorizonCore Builder step is needed.

## 3. Verify

```bash
ls -l /dev/gps0
# lrwxrwxrwx 1 root root 7 ... /dev/gps0 -> ttyACM0
```

Dry-run the rule processing if the symlink doesn't appear:

```bash
sudo udevadm test $(udevadm info -q path -n /dev/ttyACM0) 2>&1 | grep -iE 'gps0|symlink'
```

## 4. Use it in compose

Reference the symlink on the **host side (left)** of an explicit
two-sided device mapping in [compose.yaml](../compose.yaml):

```yaml
devices:
    - /dev/gps0:/dev/gps0
```

## How Docker handles device symlinks (read this before debugging)

Passing udev symlinks into containers fails in non-obvious ways unless
you know four things:

1. **Symlinks are resolved once, at container create** (supported since
   Docker 1.11). Docker follows the host symlink, creates a *real*
   character-device node inside the container, and allows that
   major:minor in the device cgroup. The symlink itself never exists
   inside the container.
2. **Always use the explicit `host:container` form.** With the one-sided
   form (`- /dev/gps0`), the node can appear inside the container at the
   *resolved* kernel name (`/dev/ttyACM0`) instead of `/dev/gps0`, and
   software configured for `/dev/gps0` finds nothing.
3. **`privileged: true` breaks custom device names.** A privileged
   container gets *all* host device nodes under their raw kernel names,
   and `devices:` mappings are ignored — your custom container path never
   appears. This is why this project's compose file uses specific
   `cap_add` entries instead of privileged mode. If you re-enable
   privileged, the stable-naming scheme stops working.
4. **A replug while the container is running goes stale.** The
   in-container node is pinned to the device resolved at create time; if
   the receiver re-enumerates, udev updates the *host* symlink but the
   container still points at the old device. Recover with:

   ```bash
   sudo docker compose up -d --force-recreate
   ```

## Optional: PPS devices

GPIO PPS devices (`/dev/pps0`, `/dev/pps1`, …) are numbered by discovery
order and can also shift when multiple PPS sources exist. Rather than a
udev rule, this project handles it in the compose mapping: put the
platform's PPS name on the host side and keep the container side fixed at
`/dev/pps0` (which `chrony.conf` expects), e.g. on Apalis:

```yaml
devices:
    - /dev/pps1:/dev/pps0
```
