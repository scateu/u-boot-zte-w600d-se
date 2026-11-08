# W600D: chain-load mainline U-Boot (laptop screen + keyboard) from this USB stick.
# Run by the vendor U-Boot (uboot_a v13/v14: bootcmd_usb0 -> distro scan -> boot.scr).
# Flat on purpose (no `if`, see a/HOWTO-patch-uboot.md). Needs the vendor script header (mkscr.py).
# If a load fails, the script returns and Android boots; read the w6* markers from /proc/cmdline.
setenv bootargs ${bootargs} w6ub=1
load ${devtype} ${devnum}:${distro_bootpart} 0x00800000 ${prefix}u-boot-w600d.bin && setenv bootargs ${bootargs} w6ubload=${filesize}
load ${devtype} ${devnum}:${distro_bootpart} 0x10000000 ${prefix}w600d-chain.bin && setenv bootargs ${bootargs} w6shim=${filesize}
load ${devtype} ${devnum}:${distro_bootpart} 0x00800000 ${prefix}u-boot-w600d.bin && load ${devtype} ${devnum}:${distro_bootpart} 0x10000000 ${prefix}w600d-chain.bin && usb stop && go 0x10000000
setenv bootargs ${bootargs} w6ubfail=1
