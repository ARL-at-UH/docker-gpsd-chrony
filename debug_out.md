
nido@nido-desktop:~$ cat /proc/cmdline
root=/dev/mmcblk0p1 rw rootwait rootfstype=ext4 mminit_loglevel=4 console=ttyTCU0,115200n8 console=tty0 fbcon=map:0 net.ifnames=0 rootfstype=ext4 video=efifb:off
nido@nido-desktop:~$ cat /boot/extlinux/extlinux.conf
TIMEOUT 30
DEFAULT primary

MENU TITLE L4T boot options

LABEL primary
      MENU LABEL primary kernel
      LINUX /boot/Image
      FDT /boot/dtb/kernel_pps-merged.dtb
      INITRD /boot/initrd
      APPEND ${cbootargs} root=/dev/mmcblk0p1 rw rootwait rootfstype=ext4 console=ttyTCU0,115200n8 console=tty0 fbcon=map:0 net.ifnames=0 video=efifb:off nospectre_bhb initcall_blacklist=pps_ktimer_init fdt_overlays=xavier-nx_gnss-pps-gpio.dtbo

# When testing a custom kernel, it is recommended that you create a backup of
# the original kernel and add a new entry to this file so that the device can
# fallback to the original kernel. To do this:
#
# 1, Make a backup of the original kernel
#      sudo cp /boot/Image /boot/Image.backup
#
# 2, Copy your custom kernel into /boot/Image
#
# 3, Uncomment below menu setting lines for the original kernel
#
# 4, Reboot

# LABEL backup
#    MENU LABEL backup kernel
#    LINUX /boot/Image.backup
#    FDT /boot/dtb/kernel_tegra194-p3668-0000-p3509-0000.dtb
#    INITRD /boot/initrd
#    APPEND ${cbootargs}

nido@nido-desktop:~$ findmnt /
TARGET SOURCE         FSTYPE OPTIONS
/      /dev/mmcblk0p1 ext4   rw,relatime
nido@nido-desktop:~$ ls -l /boot/kernel_pps-merged.dtb
-rw-r--r-- 1 root root 326831 Jul  6 20:33 /boot/kernel_pps-merged.dtb
nido@nido-desktop:~$
