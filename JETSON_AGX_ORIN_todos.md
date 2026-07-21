Modify the xavier nx portions of this project to be able to be used on the JETSON AGX ORIN

- [x] select GPIO pins to use — header pin 22 / GPIO17 (pad PP.04), GND on
      pin 20. See `device_tree_overlays/agx-orin_pps_instructions.md`.
- [ ] connect 1pps output from GPS — **requires physical access to the
      board**: wire receiver PPS → pin 22, GND → pin 20, per the wiring
      table in the instructions doc.
- [ ] verify gps 1pps is seen by the AGX Orin — **requires physical
      hardware**: run the pin-polling test (step 2) and `ppstest` (step 5)
      in `agx-orin_pps_instructions.md` after wiring.

1. [x] Select a GPIO pin to use — done above.
2. [ ] Connect GPS 1PPS output to the ORIN pins — hardware step, see above.
3. [ ] Verify signal is seen by the ORIN — hardware step, see above.

Verify K timer is disabled

- [ ] **Hardware step.** `agx-orin_pps_instructions.md` step 1 identifies
      whether `pps-ktimer` is builtin or a module and how to neutralize it
      (`initcall_blacklist=pps_ktimer_init` or a modprobe blacklist); step 5
      gives the exact commands to confirm it's gone
      (`cat /sys/class/pps/pps0/name` must not read `ktimer`).

Verify no other clock services are active, deactivate if necessary

- [ ] **Hardware step.** Documented in `JETSON_AGX_ORIN_SETUP_GUIDE.md`
      step 2 and `agx-orin_pps_instructions.md` step 6:
      `timedatectl | grep 'NTP service'` (want inactive),
      `systemctl is-enabled systemd-timesyncd` (want disabled/masked).

Device tree overlay

- [x] modify existing xavier dts to match the xavier pinout and GPIO chip
      specs — `device_tree_overlays/agx-orin_gnss-pps-gpio.dts` (Tegra234
      MAIN controller, sparse GPIO encoding, correct port-index table for
      Orin vs Xavier's Tegra194).
- [x] Build dbo and transfer to device, ensure that github action includes
      the new branch — `.github/workflows/device_tree_overlay_build.yaml`
      now triggers on `JETSON_AGX_ORIN` and compiles every `*.dts` in
      `device_tree_overlays/` (was hardcoded to the Xavier file only).
      Transfer-to-device and merge (`fdtoverlay`) is still a per-device
      manual step — see instructions doc step 4.
- [ ] verify AGX Orin can see the 1pps signal and it is mapped correctly —
      **hardware step**, same as above.

Udev rules

- [x] create an appropriate udev rule for the xavier — N/A for this item:
      the existing `udev_rules/99-usb-gps.rules` matches on USB
      vendor/product ID, not board, so it already applies unchanged to AGX
      Orin. No new rule needed.
- [x] Ensure that the container can access the 1PPS GPS signal — covered by
      `compose.yaml`'s existing `/dev/pps0:/dev/pps0` mapping (unchanged,
      board-agnostic) plus the udev rule for the GPS serial device.
- [ ] verify that the udev rule works no matter what order the usb devices
      are plugged in — **hardware step**: install the rule (README /
      `udev_rules/README.md`) and confirm `/dev/gps0` resolves correctly
      after replugging in different orders.

GPS

- [x] Wiring and bring-up sequence documented end-to-end in
      `JETSON_AGX_ORIN_SETUP_GUIDE.md`.

Update README

- [x] Jetson section split into Xavier NX / AGX Orin subsections, each
      linking its dedicated instructions doc; table row updated with a link
      to the new setup guide.

Create a step by step guide for implementation of the gpsd-chrony container
from a fresh jetson agx orin install of jetson 6.x

- [x] `JETSON_AGX_ORIN_SETUP_GUIDE.md` — Docker install through verified
      `chronyc sources` output, linking out to the PPS instructions, udev
      rule, and VERIFICATION.md for the parts that need full detail.

---

**Remaining work needs the physical AGX Orin + wired GPS receiver** — the
docs and commands are ready; someone with hardware access needs to run
`JETSON_AGX_ORIN_SETUP_GUIDE.md` end-to-end and check off the boxes above
as each verification passes.
