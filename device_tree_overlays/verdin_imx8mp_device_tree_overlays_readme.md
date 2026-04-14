# PPS GPIO Device Tree Overlay — Verdin iMX8M Plus

This overlay enables the `pps-gpio` driver on a Toradex Verdin iMX8M Plus module, letting the kernel treat a GPIO input as a Pulse-Per-Second source (e.g., from a GNSS receiver).

```dts
/dts-v1/;
/plugin/;

/ {
    compatible = "toradex,verdin-imx8mp";

    fragment@0 {
        target-path = "/";
        __overlay__ {
            pps {
                compatible = "pps-gpio";
                gpios = <&gpio1 6 0>; // Verdin GPIO_4, SODIMM 212, GPIO1_IO06, GPIO_ACTIVE_HIGH
                status = "okay";
            };
        };
    };
};
```

## How to change the GPIO

The line you edit is:

```
gpios = <&gpio1 6 0>;
```

It has three fields:

1. **Controller phandle** (`&gpio1`) — which GPIO bank on the SoC.
2. **Pin offset** (`6`) — which bit within that bank.
3. **Flags** (`0`) — `0` = `GPIO_ACTIVE_HIGH`, `1` = `GPIO_ACTIVE_LOW`.

### Step 1 — Find the ball name for the Verdin pin

Open the Toradex Verdin iMX8M Plus datasheet and look up the SODIMM pin you want to use. Each Verdin GPIO lists a **ball name** of the form `GPIOx_IOyy`.

Examples from the datasheet:

| Verdin pin | SODIMM | Ball name    |
|------------|--------|--------------|
| GPIO_1     | 206    | GPIO1_IO00   |
| GPIO_2     | 208    | GPIO1_IO01   |
| GPIO_3     | 210    | GPIO1_IO05   |
| GPIO_4     | 212    | GPIO1_IO06   |

(Always confirm against the current datasheet — pin assignments can differ across module variants.)

### Step 2 — Translate the ball name into phandle + offset

`GPIOx_IOyy` maps directly:

- `x` → controller: `&gpio1`, `&gpio2`, `&gpio3`, `&gpio4`, or `&gpio5`
- `yy` → pin offset, as a decimal number

So `GPIO1_IO06` → `<&gpio1 6 0>`, `GPIO3_IO14` → `<&gpio3 14 0>`, etc.

### Step 3 — Pick the active level

For a typical PPS source that pulses high once per second, leave the flag as `0` (active high). Use `1` if your signal is inverted.

### Step 4 — Check pinmuxing

The pin must be muxed to its GPIO function, not to an alternate peripheral (UART, I²C, PWM, etc.). If the base device tree already assigns the pin to another function, you'll need to add a `pinctrl` entry to this overlay to reassign it. If the pin is unused by default, the overlay alone is usually enough.

You can check with:

```sh
cat /sys/kernel/debug/pinctrl/<pinctrl-device>/pinmux-pins
```

after boot, or inspect `imx8mp.dtsi` / the Toradex BSP device tree for conflicting users.

## Building and deploying

Compile the overlay:

```sh
dtc -@ -I dts -O dtb -o pps-gpio.dtbo pps-gpio.dts
```

On Toradex BSPs, place the `.dtbo` in `/boot/overlays/` (or the BSP-specific overlay directory) and add it to `overlays.txt`:

```
fdt_overlays=pps-gpio.dtbo
```

Reboot, then verify:

```sh
dmesg | grep pps
ls /dev/pps*
```

You should see a `/dev/pps0` device. Test with `ppstest /dev/pps0` from the `pps-tools` package.

## Troubleshooting

- **No `/dev/pps0`** — driver didn't bind. Check `dmesg` for errors from `pps-gpio`; usually a pinmux conflict or missing kernel config (`CONFIG_PPS_CLIENT_GPIO`).
- **Device registers but no pulses counted** — the pin isn't actually in GPIO mode, or active level is wrong. Try toggling the flag between `0` and `1`.
- **Overlay won't apply** — confirm the `compatible` string matches your module and that the base device tree exposes the `gpioX` label you're referencing.
