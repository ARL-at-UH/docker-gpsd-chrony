grep -o 'initcall_blacklist[^ ]*' /proc/cmdline   # present = extlinux entry actually booted
ls /proc/device-tree/ | grep pps                  # pps node from the merged DTB
cat /sys/class/pps/pps0/name                      # not "ktimer"
readlink -f /sys/class/pps/pps0                   # /devices/platform/pps/... not /virtual/
sudo ppstest /dev/pps0                            # one assert per second