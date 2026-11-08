# HOWTO: prepare a USB drive the W600D boots from

Requires the patched uboot_a (v13 or v14, `HOWTO-patch-uboot.md`), which scans `usb 0` before Android.
Status (2026-11-06): **works**. The demo stick (`usb-demo/`) ran from the stick and drew the rainbow banner,
then Android booted. (The battery picture after it didn't appear, see §4.)

## 1. What U-Boot looks for
The distro scan (`bootcmd_usb0` → `usb_boot` → `scan_dev_for_boot_part`):

1. `usb start`, then **USB storage device 0** (with one stick plugged in, that's the stick).
2. Partitions flagged bootable, or **partition 1** if none is flagged.
3. Filesystem: **FAT** or **ext2/3/4** (`fatload`/`ext4load` are built in; no exFAT).
4. In `/`, then in `/boot/`, the first one found of:
   - `extlinux/extlinux.conf` → `sysboot` (a Linux kernel + initrd + DTB menu). **Use this for Linux.**
   - `boot.scr.uimg`, `boot.scr` → `source` (a U-Boot script). **Vendor format only, see §3.**
5. Nothing found, or the script returns → eMMC scan → Android.

Ports: tested on the **right-side** port (EHCI `fd800000`, USB 2.0). The other external port is on
the USB 3 OTG controller `fcc00000`. Run 1 there failed only because of the `boot.scr` bug (§3),
so it probably works too, but that's not retested. Plug in only one USB disk.

## 2. Format the drive (macOS)
**MBR + one FAT32 partition.** macOS's default (GPT) puts a hidden EFI partition first, and U-Boot
would scan that one.
```sh
diskutil list                                          # find the stick, e.g. /dev/disk5 — CHECK THE SIZE
diskutil eraseDisk FAT32 ZTE_TEST MBRFormat /dev/diskN # ERASES the whole drive
```
Result: `FDisk_partition_scheme` with `DOS_FAT_32` as partition 1. For Linux later, a second
ext4 partition can hold the root filesystem. Keep the FAT one first, or flag the boot partition
bootable.

Copy files, then clean up and eject:
```sh
cp <files> /Volumes/ZTE_TEST/
dot_clean /Volumes/ZTE_TEST          # remove macOS ._ files
diskutil eject /Volumes/ZTE_TEST
```
If Android mounts the stick, it creates `Android/` and `LOST.DIR/`. They're harmless.

## 3. ⚠ boot.scr quirk: this U-Boot needs a non-standard script header
A `boot.scr` is a legacy uImage of type script: 64-byte header, then a table of part lengths, then
the text. Mainline U-Boot and `mkimage` end the table with `0`. **This vendor U-Boot's `source`
skips table words until one equals `0xFFFFFFFF`** (disassembly at `0xa07f4c` in uboot_a). With a
normal `mkimage` script it runs past the table into memory and executes garbage, silently: nothing
happens and boot continues to Android (runs 1–4, see `usb-demo/README.md`).

- Build scripts with **`usb-demo/src/mkscr.py boot.cmd boot.scr`**: it writes `len, 0xFFFFFFFF, text`.
- A distro's `boot.scr` (made with `mkimage`) will **not** work. For Linux use
  `extlinux/extlinux.conf`, which needs no header.
- Inside scripts: keep them flat. `&&` is fine. Avoid top-level `if` (`HOWTO-patch-uboot.md` rule 1),
  at least before anything that boots.

Useful script variables set by the scan: `${devtype} ${devnum}:${distro_bootpart}` (here
`usb 0:1`), `${prefix}` (`/` or `/boot/`), `${scriptaddr}` = 0x00c00000. Free RAM for loading:
0x10000000 (kernel 0x00a80000, fdt 0x0a100000, ramdisk 0x0a200000).

## 4. Seeing what happened (no serial console)
- On screen: **draw it yourself**, like `w600d-demo.bin` (reliable). `rockchip_show_bmp battery_N.bmp`
  is **unreliable**: in v9 (from `bootcmd`) only 2 of 5 pictures appeared, and in run 5 (from
  `boot.scr`, after the demo) none did. U-Boot's text console doesn't show on the panel (`lcdputs` untested).
- Markers: `setenv bootargs ${bootargs} w6step=1` after each step, then in Android:
  `adb shell su 0 cat /proc/cmdline | tr ' ' '\n' | grep w6`. `boot_android` keeps `bootargs`.
  Example: `usb-demo/src/boot-diag.cmd`.

## 5. The demo stick (what's on ZTE_TEST now)
`usb-demo/` (details: `usb-demo/README.md`):
- `boot.scr` = `src/boot-diag.cmd` (markers + demo + battery picture), or `src/boot.cmd` (demo +
  battery animation 0→5 + `lcdputs` test).
- `w600d-demo.bin`: 6 KB bare-metal ARM64 program, started with `go 0x10000000`. It finds the logo
  framebuffer in RAM and draws the rainbow banner for ~11 s, then returns.
Rebuild everything: `usb-demo/src/build.sh` (also writes `boot.scr` from `boot.cmd`).

## 6. Next: Linux from the stick (later)
Plan: FAT partition 1 with `extlinux/extlinux.conf`, `Image`, the W600D DTB, optionally an initrd,
and the rootfs on partition 2 (ext4). Example:
```
default linux
timeout 3
label linux
    kernel /Image
    fdt /rk3568-w600d.dtb
    append console=ttyS2,1500000 root=/dev/sda2 rootwait rw
```
(The kernel console on this board is 115200 in Android's setup, but mainline usually uses
1500000. Pick it when the kernel is built. See `W600D-linux.md`.)
