# memory.md — ZTE W600D (RK3568) project notes

Running log of what we know and what's been done. Newest first within each section.

## Device facts
- **ZTE W600D** laptop (China Mobile "cloud computer"), board `rk3568_r_w600d2` V6/BOM0, SN `291005541789`.
- RK3568 4×A55, 2 GB RAM, 32 GB eMMC (`mmcblk2`, `sdhci@fe310000`), no SD slot, no Ethernet. SATA controller is enabled but no disk is attached.
- Android 11 userdebug, kernel 4.19.193, vendor U-Boot 2017.09, A/B slots.
- Bootloader **unlocked** (`orange`). Slot B U-Boot reports **`androidboot.secureboot=0`**.
- Root: `adb shell su 0 …` (not `su -c`).
- adb is over **TCP 10.0.0.66:5555**: open root on the LAN.
- Debug UART: UART2 @ 0xfe660000, **115200** baud (`ttyFIQ0`).
- Peripherals: RK809 PMIC, RK860 ×2 + TCS4525 regulators, BQ25703 charger, SC2021 USB-PD (no mainline driver), SBS 2S battery, MT7663 SDIO Wi-Fi/BT, eDP `guoxian-30NK` 1080p + HDMI, I2C-HID touchpad `093A:0255`, USB keyboard `258a:0001`, OS04A10 MIPI cam + USB webcam.
- Carrier OTA / TR-069 (`218.98.6.253:28002`) present. It could overwrite firmware.

## A/B slots
- Slot A: U-Boot + kernel built 2024-05-29. Slot B: 2024-07-31 (newer).
- The user's `device.dtb` / `zte-book.dts` (18:49) came from **slot B**. My `live.dtb` (21:33) came from **slot A**.
- `bootctl` (2026-11-05 21:44): current slot 0 (`_a`), both slots bootable and successful.

## Files
- `../u-boot-zte-w600d-se/` (2026-11-06): **publishable, self-contained package** (user: keep all changes in here, don't fix upstream U-Boot). `patches/u-boot/0001-0005` (format-patch series vs 709a97a0: usb_kbd Ctrl chords, video alpha, VOP2 takeover, typewriter hooks, board DT+defconfig), `typewriter/` (→ cmd/typewriter/), `patch-u-boot.sh [--am|--check] <dir>` (idempotent), `build.sh` (clone+patch+build+stick files; tested macOS from clean clone), README, `howto-typewriter-uboot.md`, `chain/`, `vendor-env/patch-uboot-env.py`, `prebuilt/` (u-boot `3d596f72…`). Verified 2026-11-06: fresh clone + patch-u-boot.sh == `../u-boot` working tree (23/23 files), --am == apply. Author in patches = git config `k <k@example.com>`. **Not published, ask before pushing.** Typewriter changes vs user's repo (untouched): `TW_RK3399_POWERSAVE` guard, `TW_DEFAULT_*`, restored `tw_poweroff_event_pending` no-EC stub; in `patches/typewriter/w600d-changes.patch`.
  - TODO next session: (1) **`PATCHING.md` guide** not written yet (README still describes single patch/manual steps → update to the series + patch-u-boot.sh). (2) **Reset `../u-boot` to pristine** (changes still in its working tree; the reset was blocked by the permission check; the package is the source of truth; `b/scripts/mk.sh` then needs `patch-u-boot.sh` run first). (3) adb uboot_a script DONE: `vendor-env/w600d-uboot-a.sh` (install/backup/flash/check, YES=1, -s), tested check+backup; pre-patched `vendor-env/uboot_a-usbfirst.img` = **v15** (`36e264b1…`, v13 bootcmd + bootdelay stock 0; `a/uboot-patch/v15-usb-first-bd0.img`; patch-uboot-env.py DEFAULT no longer sets bootdelay). ZTE blob in the package: user's call on redistribution. **v15 flashed 2026-11-06** by me via `w600d-uboot-a.sh flash` (user asked; dd over adb went through this time): uboot_a = `36e264b1…` read-back verified, misc slot A `0f 07 00 00` (7 tries), B `0e 00 01 00`; rebooted with the stick in → **v15 boots the stick → mainline U-Boot → typewriter ✅ (user, 2026-11-06)**. **TODO: boot Android once without the stick** so it marks slot A successful (`w600d-uboot-a.sh check` → `0f 00 01 00`). Until then every boot (stick boots too) uses one of slot A's 7 tries; at 0 the vendor U-Boot switches to slot B (stock, no USB boot). Backup of v14 state: `a/uboot-backup-20261106-v14/`.
- `HOWTO-uboot-shell.md`: **mainline U-Boot 2027.01-rc chain-loaded from the USB stick** (boot.scr → `w600d-chain.bin` shim → `u-boot-w600d.bin`) with a new VOP2 takeover video driver (reuses the vendor-lit eDP, Smart0/VP1) + USB keyboard → `=>` on screen. Sources in `../u-boot` (defconfig `zte-w600d-chain-rk3568`, `rk3568-w600d.dts`), build/stick files in `../b`. Run 1 (2026-11-06): **`=>` on screen ✅, keyboard dead** → keyboard power GPIO3_A3 is only set by Android's zte-gpio-ctl; run 2 DT gpio-hog → **keyboard works ✅**. Run 3 = + typewriter: runs; Ctrl-Space gave `)` (mainline usb_kbd Ctrl = scancode-3 bug) → fixed in common/usb_kbd.c, stick `3d596f72…` → **Ctrl-Space toggles Wubi ✅ (user, 2026-11-06)**. Mac toolchain: Homebrew `aarch64-elf-gcc` + `b/scripts/mk.sh`.
- `HOWTO-usb-drive.md`: how to make a USB drive the patched U-Boot boots (MBR+FAT32 p1, vendor boot.scr header quirk, debug via bootargs, extlinux plan).
- `usb-demo/` (README.md): USB stick test for v13: `boot.scr` (flat) runs `w600d-demo.bin` (bare-metal ARM64, finds the logo framebuffer in drm-logo RAM 0x7df00000 by content, draws a rainbow band + scrolling text) + battery animation, then Android. Built on the Mac with clang + `src/link.py`. Host-tested. Stick: MBR + FAT32 partition 1. **Run 1 (2026-11-06): boot.scr never ran: the stick was on the OTG controller `fcc00000` (U-Boot DT `dr_mode=otg`, not a host in U-Boot). Correction: the vendor U-Boot uses the kernel DTB after early init (fcc00000 = host there, EHCIs okay), so the cause is unknown. Ports: right side = EHCI fd800000 (USB2), other = OTG fcc00000, keyboard = fd000000, webcam = EHCI fd880000.**
- `ab-tries.md` + `tools/re/`: SPL/U-Boot disassembly, who decrements A/B tries.
- `HOWTO-patch-uboot.md` + `tools/patch-uboot-env.py`: patched uboot_a env (usb start; 3 s Ctrl+C window via `sleep`; distro usb0/mmc0 before boot_android). v1 (6baad100…) and v2 (+usb stop, 1ef8e622…) both **boot-loop before the kernel**; A/B fallback to slot B rescued both. Control (stock + set-active) boots fine → cause is in the patched env (timing/watchdog or `usb start`). v3 bootdelay=3, v4 usb start/stop, v5 sleep 3 all **boot fine** → suspect `run distro_bootcmd` before boot_android (mmc0 scan of eMMC p1?) or the `if` wrapper. v9-diag (flat list: usb start, usb0+mmc0 scans, usb stop, boot_android) also boots. v8 (minimal `if sleep 1;then boot_fit;boot_android…;fi`) and v11 (literal `boot_android mmc 0` inside `if`) loop → **root cause: `boot_android` inside a hush `if`/`for` block resets the board. Never do that.** v12 (635e5a30…): `if sleep 3` only sets `bdev=mmc|none`, then flat `run bootcmd_usb0;usb stop;boot_fit;boot_android ${bdev} 0`. v12 loops too → **no top-level `if` in bootcmd at all** (`if` inside `run` scripts is OK). v13 (b94f333f…) = flat USB-first `run bootcmd_usb0;run bootcmd_mmc0;usb stop;boot_fit;boot_android…;run distro_bootcmd;` **boots ✅.** v14-diag (8de8c9f8…) = v13 + `&&`-guarded USB checks appended to bootargs as `w6dbg=…` (read /proc/cmdline as root). **uboot_a = v14** (2026-11-06), **now v15** (see u-boot-zte-w600d-se entry). Result `w6dbg=us.d0..fat..s0...usb0`: the stick is found and boot.scr exists, but the script shows no effect. **`bootargs` → /proc/cmdline is a working debug channel.** Script never ran: vendor `source` ends the legacy length table at 0xFFFFFFFF, not 0 (0xa07f4c). mkscr.py fixed. Standard mkimage boot.scr won't work → use extlinux.conf for Linux. **Run 5 ✅: rainbow demo ran from the USB stick** (right-side port, EHCI). rockchip_show_bmp after it didn't show (unreliable). Guides: HOWTO-patch-uboot.md §0, HOWTO-usb-drive.md. On-screen U-Boot text: re-setting stdout=vidconsole doesn't work; lcdputs untested. See HOWTO §8.
- `fw-v2.25.md`: ZTE V2.25.20P06 firmware = full A/B OTA (payload.bin: boot, uboot, dtbo, system, vendor, product, system_ext, odm). No loader/GPT. Extracted to `fw-v2.25/` (`img/`, `resource/`, `fw-wifi/`). Tools: `tools/payload-extract.py`, `tools/rsce.py`.
- `ref-issue3681.md`: ophub issue #3681 (W6XX/W600D2 AI report + MT7663 comment). ZTE firmware zip URL, MT7663 stability analysis, corrections (boot0/1 are empty on ours).
- `HOWTO-change-logo.md`: how the power-on logo works (vendor U-Boot reads p17) and how it was changed. `tools/make-logo.py`, `logo/logo_w600d.img`.
- `partitions.md`: eMMC map diagram, boot_a/RSCE/misc internals, proposed post-wipe layout.
- `debrick.md`: recovery guide (serial, rockusb, UMS, MaskROM, restore commands).
- `usb-boot.md`: plan to boot Linux from USB with the **stock** U-Boot (decision 2026-11-05: wipe Android, keep U-Boot for now).
- `ref-z96a-comparison.md`: comparison with the Sunniwell Z96A Linux port (`ref/`): proven path is Armbian + vendor U-Boot 2017.09 + BSP 5.10.160, rootfs on USB. Our board differs in nearly all GPIOs, PMIC (RK809), Wi-Fi (MT7663), charging (BQ25703 + SC2021 PD + SBS battery).
- `ref/`: bingo1991/rk3568_laptop_sunniwell_z96a clone + CSDN blog (`…朝歌z96a刷armbian-CSDN博客.html`, readable; older `…技术栈.htm` is 0 bytes). Blog: kernel `unifreq/linux-5.10.y-rk35xx`; image flashed to eMMC (method not stated), rootfs moved to USB via `rootdev=UUID=` in eMMC `/boot/armbianEnv.txt`; HW video via `jellyfin-ffmpeg7` + mpv `hwdec=rkmpp`.
- `W600D-linux.md`: full hardware survey + U-Boot/Linux plan.
- `back-key.md`: how the Windows → Back remap was found and done.
- `map-winkey-back.sh`: reusable adb script for that remap (`--esc`, `--undo`, `-s`, `-k`).
- `keymap/`: `Generic.kl` pulled from the device + the first hand-made `Vendor_258a_Product_0001.kl`.
- `w600d-backup/`: firmware dumps (first 16 MiB of eMMC incl. GPT + idbloader, uboot/trust/dtbo/vbmeta/boot for both slots, misc, logo, baseparameter, zteparameter, security), `live.dtb/dts` (slot A), `device_slot_b.dtb/dts` (slot B), `getprop.txt`, `partitions.txt`, `SHA256SUMS`.
- `device.dtb`, `zte-book.dts`: the user's original slot B dumps.

## Changes made to the device
- 2026-11-05: installed `/data/system/devices/keylayout/Vendor_258a_Product_0001.kl` (Windows key `125` → `BACK`). Esc unchanged. Undo with `./map-winkey-back.sh --undo`.
- 2026-11-05: **p17 `logo` overwritten** with `logo/logo_w600d.img` (stock + "W600D LINUX"). The user ran the dd. Confirmed on screen. Undo: dd `w600d-backup/logo.img` back.
- 2026-11-06: patched uboot_a v1/v2 tested (loops) → **restored stock uboot_a** (2375420f…), `set-active-boot-slot 0`, back on slot A, successful. uboot_b never touched. Net state = as before except p17 logo.
- misc @0xc00 = ZTE retry record `STRS` (boot counter, slot-change counter).

## Not done yet / next steps
- The ZTE firmware has no MaskROM loader → still need rkbin `rk356x_spl_loader` for `debrick.md` §4. Android restore from the OTA needs `lpmake` to build `super`.
- Write `rk3568-w600d.dts` (Z96A DTS structure + W600D GPIOs from `device_slot_b.dts`) and an Armbian board config based on `z96a-rk3568-laptop`.
- MT7663 SDIO on a 5.10 kernel needs a backport or the out-of-tree driver (mainline `mt7663s` is 5.11+).
- Back up `super` (~5 GB) if Android might be wanted again.
- Install `rkdeveloptool` and test `adb reboot loader` → `rkdeveloptool ld` over USB-C.
- Open the case: find the UART2 pads, the MaskROM pad, and any M.2 SATA slot.
- Decide: dual-boot (Linux in `boot_b` via vendor U-Boot) vs. replace Android (mainline U-Boot).
- Kernel choice: Rockchip BSP first (eDP + charging work), mainline later.
- Consider turning off adb-over-TCP and the OTA/TR-069 apps while working.

## Bootloader facts (from dumps)
- **Running U-Boot is uboot_a**: only uboot_b has the string `androidboot.secureboot`, and today's cmdline lacks it. Device uboot_a/b hashes = backups.
- Each uboot partition holds **two identical FIT copies** (0x0 and 0x200000). SPL checks sha256 hashes and has no RSA public key → signatures not enforced.
- misc @0x800 is libavb_ab format: `\0AB0` v1.0, slot A prio 15 / tries 0 / ok 1, slot B prio 14 / tries 0 / ok 1, crc32 at the end.
- U-Boot console baud is **1500000** (`baudrate=1500000`). The kernel uses 115200.
- **trust_a/trust_b are all zeros**: ATF + OP-TEE are inside the uboot FIT. No trust copy needed.
- V2.25 (2025-10) U-Boot is `boot_android` only, like uboot_b. **Only our uboot_a (2024-05) has the distro fallback.** Never install ZTE OTAs. ZTE `custom/install.sh` can dd uboot_a when `ro.boot.secureboot==1` (empty on ours → no-op). All FITs signed rsa2048 key "dev", not enforced.
- MT7663 firmware (N9 `WIFI_RAM_CODE_MT7663.bin` + `mt7663_patch_e2_hdr.bin` + EEPROM) in `fw-v2.25/fw-wifi/`, sha256 identical to the device.
- eMMC `mmcblk2boot0/1` are all zeros, `PARTITION_CONFIG=0x00` (checked 2026-11-05). The loader is only at user-area sector 64.
- uboot_a `bootcmd=boot_fit; boot_android; run distro_bootcmd` → falls back to extlinux/boot.scr on `mmc1 mmc0 usb0`. uboot_b (ZTE 2024-07) is `boot_android` only, with **no fallback**. Plan: copy uboot_a/trust_a over the _b slots before wiping.
- SPL (2017.09, 2021-12-03) picks uboot_a/_b from `misc` A/B metadata and finds partitions by GPT name → keep GPT + p1–p10.
- U-Boot: USB storage yes, `stdin=serial,usbkbd`, `stdout=serial,vidconsole`, `bootdelay=0` (Ctrl+C still checked once on serial), no saveenv, `rockusb` + `ums` built in.
- Mac is Apple M1 (arm64). No Docker or other container runtime installed yet.

- **Exact board DTB:** boot_a's resource (RSCE) has 17 ZTE DTBs chosen by SARADC ch1/ch4. Ours is 938/779 → `rk3568-w600dse-pvt-cs` (= W600D SE PVT-CS). Extracted to `w600d-backup/resource_a/` (+ `resource_a.img`).
- U-Boot gets its **display** config from that kernel DTB (boot partition resource, or a GPT partition named `resource`). Its own embedded DTB has no VOP/eDP → erasing boot_a/b without a `resource` partition likely blanks U-Boot's screen.
- Mainline U-Boot (checked 2026-11-04) has **no RK3568 VOP2 display driver** → screen in U-Boot needs the Rockchip vendor U-Boot.
- `debrick.md`: serial / rockusb / UMS / MaskROM recovery procedures.
- User observed (2026-11-05): power-on logo is the **China Mobile** one from p17 `logo` (≠ RSCE logo.bmp, which is ZTE). The **charge animation** (battery_*.bmp from the RSCE) shows when USB-charging after reconnecting the battery → stock U-Boot drives eDP. Keep p16 baseparameter + p17 logo + an RSCE (`resource` partition) after the wipe.
- misc @0x4000 has a stale BCB `boot-recovery` / `recovery --wipe_all`.

## Gotchas learned
- A/B tries (`ab-tries.md`, disassembly): vendor U-Boot decrements at init (before bootcmd); SPL only when both FIT copies fail. → A **loadable foreign U-Boot in uboot_a has NO fallback** (MaskROM only). Run mainline/custom U-Boot via v13 `boot.scr` chain-load from USB instead. rk3128/rk3399 images in `typerwriter/` can't run on RK3568.
- U-Boot env rule: no `if` written directly in `bootcmd` (v1/v2/v8/v11/v12 all looped); `if`/`for` inside `run` scripts is fine (v9).
- U-Boot experiments: slot A loop → ~7–8 resets → automatic switch to stock slot B. Restore = dd stock uboot_a + `bootctl set-active-boot-slot 0`. Keep slot B stock.
- p17 BMPs: header says bottom-up (+1080), but the rows are stored top-down. Two identical copies at 0 and 0x5eee00.
- The auto-mode permission check blocks adb `dd` to block devices. The user runs those steps.
- `adb shell su -c id` fails on this su ("invalid uid/gid '-c'"). Use `su 0 <cmd>`.
- `/proc/cmdline` needs root. `/sys/firmware/fdt` is readable via `su`.
- In scripts with `set -o pipefail`, `adb shell … | awk '…{exit}'` causes SIGPIPE (exit 141). Let awk read to the end instead.
- `adb push` progress goes to stderr. Redirect `2>&1` to keep output clean.
