# W600D USB-boot demo. Run by the vendor U-Boot v13 (bootcmd_usb0 -> distro scan -> boot.scr).
# Flat script on purpose: no `if` blocks (see HOWTO-patch-uboot.md §8). `&&` guards the jump.
# When this script returns, U-Boot prints "SCRIPT FAILED: continuing..." (normal for a script
# that doesn't boot a kernel) and goes on to eMMC and Android.
echo "== W600D: boot.scr from ${devtype} ${devnum}:${distro_bootpart} =="

# 1. bare-metal demo: draws into the logo still on screen (~8 s + 3 s), then returns
load ${devtype} ${devnum}:${distro_bootpart} 0x10000000 ${prefix}w600d-demo.bin && go 0x10000000

# 2. the unmistakable "USB script ran" sign: battery animation empty -> full -> fail
rockchip_show_bmp battery_0.bmp
sleep 1
rockchip_show_bmp battery_1.bmp
sleep 1
rockchip_show_bmp battery_2.bmp
sleep 1
rockchip_show_bmp battery_3.bmp
sleep 1
rockchip_show_bmp battery_4.bmp
sleep 1
rockchip_show_bmp battery_5.bmp
sleep 1

# 3. untested: U-Boot's own text on the framebuffer
setcurs 2 2
lcdputs "W600D: booted from USB stick, continuing to Android"
sleep 3
echo "== W600D: boot.scr done =="
