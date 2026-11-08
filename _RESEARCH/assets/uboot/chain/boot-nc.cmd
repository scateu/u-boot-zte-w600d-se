setenv bootargs ${bootargs} w6ub=1
load ${devtype} ${devnum}:${distro_bootpart} 0x00800000 ${prefix}u-boot-w600d.bin && setenv bootargs ${bootargs} w6ubload=${filesize}
load ${devtype} ${devnum}:${distro_bootpart} 0x10000000 ${prefix}w600d-chain.bin && setenv bootargs ${bootargs} w6shim=${filesize}
load ${devtype} ${devnum}:${distro_bootpart} 0x00800000 ${prefix}u-boot-w600d.bin && load ${devtype} ${devnum}:${distro_bootpart} 0x10000000 ${prefix}w600d-chain.bin && usb stop && go 0x10000000
setenv bootargs ${bootargs} w6ubfail=1
