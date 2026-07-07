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
