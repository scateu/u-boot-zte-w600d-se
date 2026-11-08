#!/usr/bin/env bash
# Flash a test image into uboot_a, arm slot A (fresh tries), reboot.  Slot B stays stock = rescue.
#   tools/uboot-test.sh flash <image>     write + verify + set-active 0 + reboot
#   tools/uboot-test.sh check             after the device is back: slot, uboot_a hash, misc
set -euo pipefail
S=${ADB_SERIAL:-10.0.0.66:5555}
STOCK=2375420f37c0d1c435e6e359d9e25fab13120007869457b4ff8d7d81fd38ad1c
sh_root() { adb -s "$S" shell "su 0 sh -c '$1'" | tr -d '\r'; }

case ${1:-} in
flash)
    img=$2
    want=$(shasum -a 256 "$img" | cut -d' ' -f1)
    adb -s "$S" push "$img" /data/local/tmp/uboot_test.img >/dev/null 2>&1
    got=$(sh_root 'sha256sum /data/local/tmp/uboot_test.img' | cut -d' ' -f1)
    [ "$got" = "$want" ] || { echo "push hash mismatch: $got"; exit 1; }
    sh_root 'dd if=/data/local/tmp/uboot_test.img of=/dev/block/by-name/uboot_a bs=1048576 && sync'
    got=$(sh_root 'dd if=/dev/block/by-name/uboot_a bs=1048576 2>/dev/null | sha256sum' | cut -d' ' -f1)
    [ "$got" = "$want" ] || { echo "READBACK MISMATCH $got: do not reboot"; exit 1; }
    echo "uboot_a = $(basename "$img") ($want)"
    sh_root 'rm /data/local/tmp/uboot_test.img; bootctl set-active-boot-slot 0'
    adb -s "$S" reboot
    echo "rebooting"
    ;;
check)
    sh_root 'echo slot=$(getprop ro.boot.slot_suffix) uptime=$(cut -d" " -f1 /proc/uptime)
dd if=/dev/block/by-name/uboot_a bs=1048576 2>/dev/null | sha256sum | cut -c1-16
dd if=/dev/block/by-name/misc bs=2048 skip=1 count=1 2>/dev/null | od -A n -t x1 | head -1
dd if=/dev/block/by-name/misc bs=1024 skip=3 count=1 2>/dev/null | od -A n -t x1 | head -1'
    echo "(stock uboot_a starts ${STOCK:0:16})"
    ;;
*) sed -n 2,4p "$0"; exit 1 ;;
esac
