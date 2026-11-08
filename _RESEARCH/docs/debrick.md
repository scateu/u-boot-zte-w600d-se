# debrick.md: recovering the ZTE W600D (RK3568)

Three tools, from least to most invasive: **serial console** (see what's happening, get a U-Boot
shell), **USB rockusb/UMS** (U-Boot still works), **MaskROM** (nothing on the eMMC works).

Everything below uses the backups in `w600d-backup/` (`SHA256SUMS` included). Check them before
writing anything:

```sh
cd /Users/K/a/w600d-backup && shasum -a 256 -c SHA256SUMS
```

## 0. What can break, and what fixes it

| Symptom | Likely cause | Fix |
|---|---|---|
| Linux/kernel doesn't boot, U-Boot logo shows | kernel / DTB / extlinux problem | serial or U-Boot prompt; fix the USB stick on the Mac |
| Stuck at `=>` prompt | nothing bootable found | type commands (§2), or `rockusb 0 mmc 0` / `ums 0 mmc 0` (§3) |
| Black screen, no logo, nothing on USB | U-Boot or SPL broken, **or** U-Boot running without a kernel DTB (no display) | serial first (§1); then §3 or §4 |
| Mac sees `Maskrom` device | BootROM couldn't find a valid loader | §4 |
| Nothing at all, not even MaskROM | power/battery, or the BootROM still finds a broken loader | charge, then force MaskROM (§4.2) |

## 1. Serial console

**Hardware:** a 3.3 V USB-TTL adapter (CP2102/CH340/FT232/PL2303). **Never 5 V.** Connect GND, and
adapter RX ↔ board TX, adapter TX ↔ board RX. Don't connect VCC.

**Where:** UART2 M0, the RK3568 debug UART. SoC pins: **GPIO0_D1 = UART2_TX**, **GPIO0_D0 = UART2_RX**.
Open the bottom cover and look for 3–4 test pads labeled `TX/RX/GND`, `UART2`, `DBG`, often near the
SoC or the eMMC. To find TX: power on with a multimeter on candidate pads; TX idles at ~3.3 V and
flickers during boot.

**Settings:**
- **U-Boot: 1500000 8N1** (its environment has `baudrate=1500000`, checked 2026-11-06). The DDR blob
  and SPL normally use 1500000 too.
- **Android kernel: 115200 8N1** (`fiq-debugger` baudrate 0x1c200). If the first lines are readable
  and the kernel part is garbage (or the other way round), it's this baud switch.
- Not all USB-TTL chips can do 1.5 Mbaud. CP2102N, FT232R and CH340 can.

**On the Mac:**
```sh
ls /dev/tty.usb*                      # e.g. /dev/tty.usbserial-0001
screen /dev/tty.usbserial-0001 115200 # quit: Ctrl-A then K
# or: brew install tio && tio -b 115200 /dev/tty.usbserial-0001
```

**Getting the U-Boot prompt:** at 1500000 baud, hold **Ctrl+C** in the terminal and power on. U-Boot has
`bootdelay=0`, but still checks for a key once (`Hit key to stop autoboot('CTRL+C')`). You'll get `=>`.
Rockchip serial hotkeys (`Hotkey: ctrl+<x>`) are also compiled in.

## 2. Useful U-Boot commands (stock Rockchip U-Boot 2017.09)

```
help                                  # what's compiled in
mmc list; mmc dev 0; mmc part         # eMMC (sdhci) and its GPT
part list mmc 0
usb start; usb storage; usb tree      # find USB sticks / keyboard
ls usb 0:1 /boot                      # browse a USB stick (ext4/FAT)
run bootcmd_usb0                      # try booting the USB stick via extlinux/boot.scr
run distro_bootcmd                    # full scan: mmc1 mmc0 usb0
setenv stdin serial,usbkbd            # after `usb start`: use the laptop keyboard
setenv stdout serial,vidconsole       # print on the laptop screen
rockusb 0 mmc 0                       # USB flashing mode on the OTG port (§3.1)
ums 0 mmc 0                           # eMMC appears as a USB disk on the Mac (§3.2)
rbrom                                 # reboot into BootROM MaskROM mode (§4)
reset
```

## 3. USB recovery while U-Boot still works

Use the **USB-C (OTG)** port to the Mac. The OTG controller is `dwc3@fcc00000`. Try the other ports
if the Mac doesn't see anything.

### 3.1 Rockusb ("Loader" mode) + rkdeveloptool

**Ways in:**
- Android running: `adb reboot loader`
- Linux (Rockchip BSP kernel) running: `reboot loader`
- U-Boot prompt: `rockusb 0 mmc 0`
- Recovery key held at power-on (`volumeup-key` in U-Boot). Whether the laptop has such a key is
  unknown.

**Install rkdeveloptool on the Mac** (it isn't in Homebrew core):
```sh
brew install libusb automake autoconf pkg-config
git clone https://github.com/rockchip-linux/rkdeveloptool && cd rkdeveloptool
autoreconf -i && ./configure && make      # if it fails on macOS, try a maintained fork
sudo cp rkdeveloptool /usr/local/bin/
```

**Use:**
```sh
rkdeveloptool ld                          # should list:  DevNo=1 Vid=0x2207,Pid=0x350a ... Loader
rkdeveloptool ppt                         # print GPT
rkdeveloptool rl 0 32768 check.bin        # read first 16 MiB
rkdeveloptool wl <sector> file.img        # write raw at sector
rkdeveloptool wlx <partname> file.img     # write a GPT partition by name
rkdeveloptool rd                          # reset / reboot
```

**Restore the stock boot chain** (sector numbers from `partitions.txt`):
```sh
cd /Users/K/a/w600d-backup
rkdeveloptool wl 0      emmc_first16MiB.bin   # GPT + idbloader + security + uboot_a + uboot_b
rkdeveloptool wl 32768  trust_a.img
rkdeveloptool wl 40960  trust_b.img
rkdeveloptool wl 49152  misc.img
rkdeveloptool wl 57344  dtbo_a.img
rkdeveloptool wl 65536  dtbo_b.img
rkdeveloptool wl 73728  vbmeta_a.img
rkdeveloptool wl 75776  vbmeta_b.img
rkdeveloptool wl 77824  boot_a.img
rkdeveloptool wl 405504 boot_b.img
rkdeveloptool wl 60620767 emmc_backup_gpt.bin # secondary GPT (last 33 sectors)
rkdeveloptool rd
```
This brings back a working bootloader + kernel. **Android itself (`super`) was not backed up**, so
the system will not fully boot Android again unless `super.img` is dumped before the wipe.

### 3.2 UMS: eMMC as a USB disk on the Mac

At the U-Boot prompt: `ums 0 mmc 0`. The eMMC shows up on the Mac as a ~31 GB disk:
```sh
diskutil list                                 # find it, e.g. /dev/disk6
diskutil unmountDisk /dev/disk6
sudo dd if=emmc_first16MiB.bin of=/dev/rdisk6 bs=1m          # restore first 16 MiB
sudo dd if=/dev/rdisk6 of=emmc-full.img bs=4m status=progress # or take a full backup
```
Ctrl+C on the U-Boot side ends UMS. **Double-check the disk number**: `dd` to the wrong disk
destroys the Mac's data.

### 3.3 From a Linux USB stick

If Linux boots from USB, the eMMC is `/dev/mmcblk*` and everything can be done with `dd`/`sgdisk`
directly. Copy `w600d-backup/` onto the stick ahead of time.

## 4. MaskROM (last resort, always available)

The BootROM in the SoC enters **MaskROM USB mode** when it finds no valid loader on any boot medium.
It can't be erased, so a bricked RK3568 can always be recovered this way as long as it powers on.
The Mac sees `Vid=0x2207, Pid=0x350a, Maskrom`.

### 4.1 Loader file (needed in MaskROM)

MaskROM only has a tiny USB stack. First you upload a loader that initializes DRAM and runs a USB
flashing plug:
```sh
git clone --depth 1 https://github.com/rockchip-linux/rkbin
# needs: bin/rk35/rk3568_ddr_1560MHz_v1.xx.bin + rk356x_usbplug_v1.xx.bin, merged by tools/boot_merger:
cd rkbin && ./tools/boot_merger RKBOOT/RK3568MINIALL.ini    # → rk356x_spl_loader_v1.xx.xxx.bin
```
`boot_merger` is an x86-64 Linux binary. On the M1, run it in an x86-64 Linux container (Rosetta), or
use a prebuilt `rk356x_spl_loader_*.bin` from a board vendor (Radxa, Firefly, …). Any RK3568 loader
works for flashing; the DDR blob version doesn't need to match the stock one exactly.

```sh
rkdeveloptool ld                                   # Maskrom
rkdeveloptool db rk356x_spl_loader_v1.xx.xxx.bin   # download & run loader → now in "Loader" mode
rkdeveloptool ld                                   # Loader
# then the same rl / wl / wlx as §3.1, e.g. the full restore
```
To install the loader permanently on the eMMC: `rkdeveloptool ul rk356x_spl_loader_….bin`.
Restoring `emmc_first16MiB.bin` (stock idbloader) achieves the same thing with the original loader.

### 4.2 Getting into MaskROM

| Method | Needs | Notes |
|---|---|---|
| `rbrom` at the U-Boot prompt | U-Boot shell (serial or keyboard) | cleanest |
| `adb reboot loader` → then exit rockusb | Android | U-Boot's preboot is `rockusb …; rbrom`, so leaving rockusb drops into MaskROM |
| `rkdeveloptool rd 3` from Loader mode | rockusb running | subcode 3 = reset to MaskROM on most loaders |
| **Short eMMC CLK (or D0) to GND** while powering on, release after ~1 s | screwdriver/tweezers, case open | works with any software state; find the eMMC chip's CLK test point or a `MASKROM` pad/button on the board |
| Erase the idbloader (sector 64) | working OS | **destructive**: only do this when the next step is MaskROM flashing |

Power-on sequence for the CLK short: unplug USB-C power, battery connected → hold the short → press
power (or plug in USB-C from the Mac) → release after ~1 s → `rkdeveloptool ld`.

## 5. Pre-flight checklist before any risky write

- [ ] `w600d-backup/` verified (`shasum -c`), and copied somewhere off the Mac
- [ ] `rkdeveloptool` built and **tested once** (`adb reboot loader` → `ld` → `ppt` → `rd`)
- [ ] Serial adapter wired and showing the boot log, **or** MaskROM entry tested once
- [ ] RK3568 loader `.bin` ready on the Mac
- [ ] Battery charged (> 50 %)
- [ ] `super.img` dumped, if you might ever want Android back
