grep -o 'initcall_blacklist[^ ]*' /proc/cmdline   # present = extlinux entry actually booted
ls /proc/device-tree/ | grep pps                  # pps node from the merged DTB
cat /sys/class/pps/pps0/name                      # not "ktimer"
readlink -f /sys/class/pps/pps0                   # /devices/platform/pps/... not /virtual/
sudo ppstest /dev/pps0                            # one assert per second


output: 

nido@nido-desktop:~$ ls /proc/device-tree/ | grep pps                  # pps node from the merged DTB
pps
nido@nido-desktop:~$ cat /sys/class/pps/pps0/name                      # not "ktimer"
cat: /sys/class/pps/pps0/name: No such file or directory
nido@nido-desktop:~$ readlink -f /sys/class/pps/pps0                   # /devices/platform/pps/... not /virtual/
/sys/class/pps/pps0
nido@nido-desktop:~$ sudo ppstest /dev/pps0                            # one assert per second
[sudo] password for nido:
trying PPS source "/dev/pps0"
unable to open device "/dev/pps0" (No such file or directory)
nido@nido-desktop:~$ grep -o 'initcall_blacklist[^ ]*' /proc/cmdline
initcall_blacklist=pps_ktimer_init
nido@nido-desktop:~$ ls /proc/device-tree/ | grep pps
pps
nido@nido-desktop:~$ cat /sys/class/pps/pps0/name
cat: /sys/class/pps/pps0/name: No such file or directory
nido@nido-desktop:~$ readlink -f /sys/class/pps/pps0
/sys/class/pps/pps0
nido@nido-desktop:~$ ls /dev/pps*
ls: cannot access '/dev/pps*': No such file or directory
nido@nido-desktop:~$ ls /dev/p*
/dev/port  /dev/ptp0   /dev/ptyp2  /dev/ptyp5  /dev/ptyp8  /dev/ptypb  /dev/ptype
/dev/ppp   /dev/ptyp0  /dev/ptyp3  /dev/ptyp6  /dev/ptyp9  /dev/ptypc  /dev/ptypf
/dev/ptmx  /dev/ptyp1  /dev/ptyp4  /dev/ptyp7  /dev/ptypa  /dev/ptypd

/dev/pts:
0  ptmx
nido@nido-desktop:~$ sudo ppstest /dev/pps0
trying PPS source "/dev/pps0"
unable to open device "/dev/pps0" (No such file or directory)
nido@nido-desktop:~$ sudo ppstest /dev/pps0
trying PPS source "/dev/pps0"
unable to open device "/dev/pps0" (No such file or directory)
nido@nido-desktop:~$

response: 

# Is the driver even present, and is it builtin or a module?
grep -i pps /lib/modules/$(uname -r)/modules.builtin
modinfo pps_gpio 2>/dev/null | head -3

# If it's a module, load it by hand — this alone may finish the job:
sudo modprobe pps_gpio
ls /dev/pps* ; dmesg | tail -5

# What did the kernel say about the node/driver?
sudo dmesg | grep -iE 'pps|2200000'

# Did the platform device get created, and does a pps-gpio driver exist to claim it?
ls /sys/bus/platform/devices/ | grep -i pps
ls /sys/bus/platform/drivers/ | grep -i pps

# Sanity: the overlay's gpios property resolved to real values (phandle + 105 + 0)
xxd /proc/device-tree/pps/gpios


output: 
nido@nido-desktop:~$ grep -i pps /lib/modules/$(uname -r)/modules.builtin
kernel/drivers/pps/pps_core.ko
kernel/drivers/pps/clients/pps-ktimer.ko
kernel/drivers/pps/clients/pps-ldisc.ko
kernel/drivers/pps/clients/pps-gpio.ko
nido@nido-desktop:~$ modinfo pps_gpio 2>/dev/null | head -3
name:           pps_gpio
filename:       (builtin)
version:        1.2.0
nido@nido-desktop:~$ sudo modprobe pps_gpio
nido@nido-desktop:~$ ls /dev/pps* ; dmesg | tail -5
ls: cannot access '/dev/pps*': No such file or directory
dmesg: read kernel buffer failed: Operation not permitted
nido@nido-desktop:~$ sudo dmesg | grep -iE 'pps|2200000'
[    0.000000] Kernel command line: root=/dev/mmcblk0p1 rw rootwait rootfstype=ext4 console=ttyTCU0,115200n8 console=tty0 fbcon=map:0 net.ifnames=0 video=efifb:off nospectre_bhb initcall_blacklist=pps_ktimer_init
[    0.000000] blacklisting initcall pps_ktimer_init
[    0.404826] pps_core: LinuxPPS API ver. 1 registered
[    0.404838] pps_core: Software ver. 5.3.6 - Copyright 2005-2007 Rodolfo Giometti <giometti@linux.it>
[    2.782174] initcall pps_ktimer_init blacklisted
[    2.782183] pps_ldisc: PPS line discipline registered
[    2.782478] pps-gpio pps: failed to request PPS GPIO
[    2.786439] pps-gpio: probe of pps failed with error -22
nido@nido-desktop:~$ sudo ls /dev/pps* ; dmesg | tail -5
ls: cannot access '/dev/pps*': No such file or directory
dmesg: read kernel buffer failed: Operation not permitted
nido@nido-desktop:~$ ls /sys/bus/platform/devices/ | grep -i pps
pps
nido@nido-desktop:~$ ls /sys/bus/platform/drivers/ | grep -i pps
pps-gpio
nido@nido-desktop:~$ xxd /proc/device-tree/pps/gpios
00000000: 0000 000c 0000 0069 0000 0000            .......i....


On the Jetson, the loop is now short since the whole boot pipeline is proven:

# 1. Worth 30 seconds first: confirm the pulse is really on the pin (this test
#    was never run, and the failed probe means the line is currently unclaimed).
#    Receiver needs a fix. Expect mostly 0s with a few 1s:
CHIP=$(gpiodetect | awk '$3=="[tegra194-gpio]"{print $1}')
for i in $(seq 1 60); do gpioget "$CHIP" 105; sleep 0.05; done | sort | uniq -c

# 2. Edit the overlay source: change the gpios line to
#       gpios = <&tegra_main_gpio 133 0>;
#    then recompile and re-merge (output straight to where the FDT line points):
dtc -@ -I dts -O dtb -o xavier-nx_gnss-pps-gpio.dtbo xavier-nx_gnss-pps-gpio.dts
sudo fdtoverlay -i /boot/dtb/kernel_tegra194-p3668-0000-p3509-0000.dtb \
                -o /boot/dtb/kernel_pps-merged.dtb \
                xavier-nx_gnss-pps-gpio.dtbo
sudo reboot

After reboot:

sudo dmesg | grep -i pps     # want: "pps pps0: new PPS source" and NO "error -22"
ls /dev/pps*                 # /dev/pps0
sudo ppstest /dev/pps0       # one assert per second


nido@nido-desktop:~$ sudo dmesg | grep -iE 'pps|gpio'
[    0.000000] Kernel command line: root=/dev/mmcblk0p1 rw rootwait rootfstype=ext4 console=ttyTCU0,115200n8 console=tty0 fbcon=map:0 net.ifnames=0 video=efifb:off nospectre_bhb initcall_blacklist=pps_ktimer_init
[    0.000000] blacklisting initcall pps_ktimer_init
[    0.408966] pps_core: LinuxPPS API ver. 1 registered
[    0.408989] pps_core: Software ver. 5.3.6 - Copyright 2005-2007 Rodolfo Giometti <giometti@linux.it>
[    2.959514] initcall pps_ktimer_init blacklisted
[    2.959532] pps_ldisc: PPS line discipline registered
[    2.959954] pps-gpio pps: failed to request PPS GPIO
[    2.960757] pps-gpio: probe of pps failed with error -22
[    3.123572] gpio-510 (gpio_default): hogged as output/high
[    3.124966] gpio-511 (gpio_default): hogged as output/high
[    3.127889] gpiochip0: registered GPIOs 504 to 511 on max77620-gpio
[    6.057287] gpio-374 (wifi-enable): hogged as output/high
[    6.057591] gpio-431 (camera-control-output-low): hogged as output/low
[    6.057862] gpio-432 (camera-control-output-low): hogged as output/low
[    6.059827] gpiochip1: registered GPIOs 335 to 503 on tegra194-gpio
[    6.062188] gpiochip2: registered GPIOs 305 to 334 on tegra194-gpio-aon
[    6.638281] i2c-mux-gpio cam_i2cmux: 2 port mux on 3180000.i2c adapter
[    6.654656] sdhci-tegra 3400000.sdhci: Got CD GPIO
[    7.083500] input: gpio-keys as /devices/platform/gpio-keys/input/input0



P=$(fdtget /boot/dtb/kernel_pps-merged.dtb /__symbols__ tegra_main_gpio)
echo "symbol resolves to: $P"
fdtget /boot/dtb/kernel_pps-merged.dtb /pps gpios
fdtget /boot/dtb/kernel_pps-merged.dtb "$P" phandle
fdtget /boot/dtb/kernel_pps-merged.dtb "$P" '#gpio-cells'
fdtget /boot/dtb/kernel_pps-merged.dtb "$P" compatible
fdtget /boot/dtb/kernel_pps-merged.dtb "$P" status 2>/dev/null || echo "(no status = enabled)"