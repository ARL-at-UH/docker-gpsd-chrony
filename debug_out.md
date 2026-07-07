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
