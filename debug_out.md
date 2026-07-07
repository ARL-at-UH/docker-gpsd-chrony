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
