# Booting Linux from USB with the stock U-Boot (W600D)

Decision (2026-11-05): **wipe Android completely, keep the stock ZTE U-Boot for now.**

## 1. What the stock bootloader does (from `w600d-backup/uboot_{a,b}.img`, `emmc_first16MiB.bin`)

Boot chain: BootROM → **idbloader** @ sector 64 (DDR init + `U-Boot SPL 2017.09 … Dec 03 2021`) →
SPL reads the A/B metadata in **`misc`** and loads **`uboot_a` or `uboot_b`** (FIT: U-Boot + ATF +
OP-TEE) → U-Boot runs `bootcmd`.

| | uboot_a (2024-05-29) | uboot_b (2024-07-31, ZTE update) |
|---|---|---|
| `bootcmd` | `boot_fit; boot_android ${devtype} ${devnum}; run distro_bootcmd;` | `boot_android ${devtype} ${devnum};` **only** |
| Falls back to distro boot? | **yes** | **no** |

Common to both:
- `boot_targets=mmc1 mmc0 usb0 pxe dhcp`. Each target scans the **partitions flagged bootable
  (`legacy_boot`), or partition 1 if none is flagged**, for `/extlinux/extlinux.conf`,
  `/boot/extlinux/extlinux.conf`, `/boot.scr(.uimg)`, `/boot/boot.scr(.uimg)`. FAT and ext4 are
  both supported (`fatload`, `ext4load`, `sysboot`).
- **USB mass storage is built in** (xHCI/EHCI, `usb start`, "scanning usb for storage devices").
- `stdin=serial,usbkbd`, `stdout=serial,vidconsole` (prompt on the laptop screen).
- `bootdelay=0`, and the environment is not persistent (no `saveenv`).
- Addresses: `kernel_addr_r=0x00a80000`, `fdt_addr_r=0x0a100000`, `ramdisk_addr_r=0x0a200000`,
  `scriptaddr=0x00c00000`.
- `rockusb` and `ums mmc 0` (exposes the eMMC as a USB disk) are compiled in.

The device is on **slot A** now, so `uboot_a` (with the fallback) is what runs.

## 2. Do we have to write a boot partition?

**No new bootloader and no kernel in `boot_a`/`boot_b`.** What's needed:

1. **Make `boot_fit` and `boot_android` fail**, so U-Boot reaches `distro_bootcmd`. Erasing
   `boot_a` and `boot_b` (and `vbmeta_*`, `dtbo_*`) does that. Wiping Android does this anyway.
2. **Make sure the U-Boot with the fallback always runs, whichever slot SPL picks.** Copy the stock
   slot-A U-Boot into slot B (`uboot_a → uboot_b`). `trust_a/_b` are empty: ATF + OP-TEE are inside
   the `uboot` FIT (`fw-v2.25.md` §3.2), so trust needs no copy. These are still
   ZTE's own binaries, so this isn't really "replacing U-Boot". Without it, if U-Boot or SPL ever
   marks slot A as failed and switches to B, the board would only run `boot_android` and never reach
   USB.
3. **Keep the GPT entries and contents of p1–p10** (`security`, `uboot_*`, `trust_*`, `misc`, `dtbo_*`,
   `vbmeta_*`). SPL finds U-Boot by partition name. **Don't `dd` a full Armbian/ophub `.img` onto
   the eMMC**: that replaces the GPT and the idbloader.
4. **Also keep `baseparameter` (p16) and `logo` (p17)**: the power-on logo comes from p17. Everything
   else from `boot_a` (p11) to the end can be deleted and reused. See `partitions.md` §5.

Then put a USB stick with an ext4 (or FAT) **partition 1** containing `/boot/extlinux/extlinux.conf`
+ kernel + DTB into a USB port. U-Boot finds it via `usb0`.

Later, to boot Linux from the **eMMC** without a new U-Boot: create a partition after p10, set its
GPT `legacy_boot` attribute, and put `/boot/extlinux/extlinux.conf` there. `mmc0`/`mmc1` are scanned
before `usb0`, so to keep USB first, don't flag the eMMC partition, or use a `boot.scr` that tries
USB first.

Unknowns to watch on the first boot: `init zte_retry` (ZTE retry logic in U-Boot), whether
`boot_android` resets instead of returning on failure, and which USB port U-Boot powers
(try USB3 Type-A first).

## 2a. Keeping the SCREEN in U-Boot (important)

The stock U-Boot drives the eDP (VOP2 + analogix eDP + panel table incl. `guoxian-30NK`), but **its
own embedded DTB (14 KB, `rockchip,rk3568-evb`) has no display nodes**. The display config comes
from the **kernel DTB in a Rockchip resource image (`RSCE`)**, which it reads from:
1. the `second` section of the Android boot image in `boot_a`/`boot_b` (today), or
2. a GPT partition named **`resource`** (`No resource partition` code path; Rockchip's Linux SDK layout).

`boot_a`'s resource image (`w600d-backup/resource_a.img`, extracted into `resource_a/`) holds 17
ZTE board DTBs, selected by SARADC ch1/ch4. Ours reads **938/779 → `rk3568-w600dse-pvt-cs`** (also
copied to `rk-kernel.dtb`), plus the battery images (the charge animation, confirmed on the device) and `logo.bmp`/`logo_kernel.bmp`
(the ZTE logo; **not** the power-on logo, which comes from the `logo` partition p17).

**So if `boot_a`/`boot_b` are simply erased, U-Boot probably loses the screen.** To keep it:
- write `resource_a.img` into a partition **named `resource`**. For example, reuse the unused `backup`
  partition (p13): rename its GPT entry to `resource` and `dd` the image in. This can be done from
  Android root before the wipe, with GPT edited on the Mac and the CRCs recomputed.
- later, repack the resource with our own `rk3568-w600d.dtb` as `rk-kernel.dtb`.

## 3. Getting a U-Boot shell

1. **Serial (reliable).** UART2, 3.3 V, **1500000 8N1** for U-Boot (kernel: 115200), pads on the mainboard. Hold **Ctrl+C** while
   powering on. With `bootdelay=0`, U-Boot 2017.09 still checks for a key once. Rockchip serial
   hotkeys (`Hotkey: ctrl+<x>`) are also compiled in.
2. **Built-in keyboard + screen (maybe).** `stdin` includes `usbkbd` and `stdout` includes
   `vidconsole`, but USB is probably not started before the autoboot check, so Ctrl+C on the
   laptop keyboard likely won't stop autoboot. It may work at the prompt once USB has been started.
3. **USB keyboard:** at power-on USB isn't started, so `usbkbd` isn't attached to stdin yet.
   Put a **`boot.scr`** on the stick that does
   `usb start; setenv stdin serial,usbkbd; setenv stdout serial,vidconsole; setenv stderr serial,vidconsole`
   and then **doesn't boot**. `distro_bootcmd` continues, finds nothing else, and U-Boot ends at `=>`
   on the screen, typed on the laptop keyboard.
4. **Fall-through.** If nothing bootable is found, `bootcmd` ends and U-Boot drops to the `=>` prompt
   on screen. With Android wiped and no USB stick inserted, that's what happens. `distro_bootcmd`
   will already have run `usb start` (target `usb0`), so the USB keyboard may then work.
5. **`boot.scr` on the stick.** A U-Boot script can run any command: set variables, try
   several devices, print diagnostics, or end without booting to leave you at the prompt.

## 3a. Is there a key combination to boot from USB? (checked 2026-11-06)

**No.** The stock U-Boot (`uboot_a`) has no "boot from USB" key. What it does have:
- **Serial hotkeys** (`Hotkey: ctrl+%c`, plus Ctrl+C to stop autoboot): read from **UART2 only**.
  The laptop keyboard is a USB device (`258a:0001`), and USB isn't started until `distro_bootcmd`
  runs, so keys on it are never seen at that point.
- **"Download key"** (`volumeup-key` in `adc-keys`, SARADC ch0 pulled to GND at power-on) →
  rockusb/loader mode, not USB boot. The laptop has no such button (EVB leftover; V2.25 even
  disables `adc-keys`). It might exist as a pad on the board.
- **Power key**: power on, charge-screen handling only.
- The environment can't be saved (no `saveenv`), so `bootcmd` can't be changed to add a key check.

How USB boot happens instead:
- While Android is installed, `boot_android` succeeds and U-Boot never reaches `usb0`. Only serial
  Ctrl+C → `run bootcmd_usb0` boots USB.
- After `boot_a/boot_b` are erased, `uboot_a` falls through to `distro_bootcmd` and **boots a
  USB stick automatically if one is plugged in**. No key needed.
- With Linux later on the eMMC: an eMMC `boot.scr` can do `usb start` and boot the stick first if it
  has `/boot/extlinux/extlinux.conf`, otherwise the eMMC. "Plug in the stick" becomes the key.

## 4. Building the USB image (on this Mac, Apple M1 = native arm64)

Needs a Linux container: Docker Desktop, OrbStack or Colima (none installed yet). On arm64 no
cross-compiler or qemu is needed.

1. **Kernel:** `unifreq/linux-5.10.y-rk35xx` (5.10.160, as used by the Z96A port and ophub).
   Config: start from bingo1991's `rk3568_z96a_defconfig`, adjusted for the W600D (see
   `ref-z96a-comparison.md`). Make sure **USB storage, xHCI/EHCI, ext4 and the eMMC driver are
   built in (`=y`)** so no initramfs is needed.
2. **DTS:** `rk3568-w600d.dts`, using the Z96A structure with W600D values from
   `w600d-backup/device_slot_b.dts`.
3. **Rootfs:** `debootstrap --arch=arm64 bookworm` (or trixie). Add a user, network tools, firmware,
   desktop later. Install the kernel modules, and pin `linux-image*` as in the blog.
4. **USB stick layout:** GPT, **partition 1 = ext4 rootfs** (`/boot` inside it):
   ```
   /boot/Image
   /boot/rk3568-w600d.dtb
   /boot/extlinux/extlinux.conf
   ```
   ```
   default linux
   timeout 3
   label linux
       kernel /boot/Image
       fdt /boot/rk3568-w600d.dtb
       append root=PARTUUID=<usb-p1-partuuid> rootwait rw console=ttyFIQ0 console=tty1 earlycon=uart8250,mmio32,0xfe660000
   ```
5. **Test order:** first boot uses HDMI + a USB keyboard as a fallback if the eDP part of the
   DTS is wrong.

## 5. Order of operations

1. ☐ Build the kernel + DTB + rootfs and prepare the USB stick (no device changes).
2. ☐ Strongly recommended: UART adapter connected, and/or MaskROM entry proven.
3. ☐ From Android (root), the last chance to dump anything: `super` if you want it archived.
4. ☐ `uboot_a → uboot_b` (stock binary; trust is empty, nothing to copy). Don't install ZTE OTAs: V2.25 U-Boot has no fallback.
5. ☐ Erase `boot_a`, `boot_b` (then `vbmeta_*`, `dtbo_*`, `super`, `userdata`, …). After this Android
   is gone and `adb` with it.
6. ☐ Insert the USB stick, reboot → U-Boot → `usb0` → extlinux → Linux.
7. ☐ If it stops at `=>`: `usb start; usb storage; ls usb 0:1 /boot` and `run bootcmd_usb0` to see
   why.
