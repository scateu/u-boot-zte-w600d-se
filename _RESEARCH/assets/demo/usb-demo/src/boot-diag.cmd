setenv bootargs ${bootargs} w6scr=1
load ${devtype} ${devnum}:${distro_bootpart} 0x10000000 ${prefix}w600d-demo.bin && setenv bootargs ${bootargs} w6load=${filesize}
go 0x10000000 && setenv bootargs ${bootargs} w6go=0
setenv bootargs ${bootargs} w6back=1
rockchip_show_bmp battery_2.bmp && setenv bootargs ${bootargs} w6bmp=1
sleep 3
setenv bootargs ${bootargs} w6end=1
