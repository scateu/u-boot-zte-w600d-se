# ZTE W600D (RK3568) — survey and plan for U-Boot + Linux

Survey date: 2026-11-05. All findings come from **read-only** inspection over `adb`
with root (`su 0`). Nothing on the device was written or changed.

Local backup of firmware: `/Users/K/a/w600d-backup/` (see §4).

---

## 1. TL;DR

* The machine is a **ZTE W600D laptop**: a China Mobile "cloud computer" (`cm.komect.aqb.*`
  apps). It runs Android 11 on a Rockchip **RK3568** with 2 GB RAM and 32 GB eMMC.
* **Good news for Linux:**
  * The bootloader is **unlocked**: `verifiedbootstate=orange`, `flash.locked=0`.
  * The build is `userdebug` and root is available.
  * The SoC has decent mainline support in both Linux and U-Boot.
* **Main risks:**
  1. There is no SD slot (sdmmc0 is disabled in the DT), so a test boot from removable
     media isn't possible without first changing what's on the eMMC.
  2. eDP panel support for RK3568 in **mainline** Linux is the weakest part of the stack.
     This needs checking before you commit. HDMI is fine.
  3. Battery/charging uses a Southchip **SC2021** USB-PD chip with no mainline driver, plus a
     TI **BQ25703** charger.
  4. Secure boot: the newer slot-B U-Boot (2024-07-31) reads the OTP state and passed
     **`androidboot.secureboot=0`** on the kernel command line (see `device_slot_b.dts`).
     That's strong evidence the SoC is **not secure-boot fused**, so it should accept a custom
     loader. Slot A's older U-Boot doesn't print this flag.
* **Recommendation:** first set up a recovery path you have proven works (UART +
  rockusb/maskrom over USB). Only then flash anything. Start with **Linux booted by the stock
  vendor U-Boot**. Replace U-Boot with mainline only once Linux works.

---

## 2. Hardware inventory

| Item | Finding | Source |
|---|---|---|
| Product | ZTE W600D, build `FactoryV1.24.20P2-20240529`, board `rk3568_r_w600d2`, board version V6 / BOM0 | `getprop` |
| SoC | Rockchip RK3568, 4× Cortex-A55 (`0xd05`), features incl. `atomics asimddp` | `/proc/cpuinfo` |
| DT model | `rockchip,rk3568-evb1-ddr4-v10` (vendor reused the EVB name; not the real board) | `/proc/device-tree/compatible` |
| RAM | 2 GB (`MemTotal 2002700 kB`), DDR init blob `DDR V1.18 f366f69a7d 23/07/17` | meminfo, idbloader strings |
| Storage | eMMC `A3A551`, 30310400 KiB (~31 GB), `sdhci@fe310000` → `mmcblk2`; boot0/boot1 4 MiB each (unused) | sysfs |
| SATA | `sata@fc800000` **okay**, `ata1` exists but **no disk attached**. There may be an empty M.2 SATA slot; check when you open the case. | DT, sysfs |
| PCIe | all three controllers disabled | DT |
| Ethernet | both GMACs disabled (no wired LAN) | DT |
| SD card | `dwmmc@fe2b0000` disabled → no SD slot (or not wired) | DT |
| Wi-Fi / BT | MediaTek **MT7663** over SDIO (`037A:7603` / `7663`) on `dwmmc@fe2c0000` | sysfs, lsmod |
| Display | eDP panel `edp_name=guoxian-30NK`, `simple-panel` (timing from EDID), 1920×1080; HDMI-A-1 also present | cmdline, DRM |
| Backlight / lid | `backlight` node; `hall-gpios` on the panel node (lid sensor) | DT |
| Keyboard | USB "SINO WEALTH USB KEYBOARD" (`258a:0001`) | input devices |
| Touchpad | I2C-HID `093A:0255` (PixArt) on i2c4 @ 0x2c | input devices |
| Camera | OmniVision **OS04A10** (MIPI CSI, i2c4 @ 0x36) and a USB "HD WebCam" (`1bcf:2ced`) | i2c, input |
| PMIC | **RK809** @ i2c0 0x20 | i2c |
| CPU/GPU regulators | RK860-0/1 (`syr827`/`syr828`, fan53555-compatible) @ 0x40/0x41, TCS4525 @ 0x1c | i2c |
| Charger | TI **BQ25703** @ 0x6b | i2c |
| USB-PD | Southchip **SC2021** @ 0x21 | i2c |
| Battery | SBS smart battery @ 0x0b, 2S (7.4 V) | power_supply |
| USB | 1× USB3 OTG (dwc3 `fcc00000`, currently `host` mode), USB3 host, 2× USB2 EHCI/OHCI | DT, lsusb |
| Debug UART | `ttyFIQ0` = **UART2 @ 0xfe660000, 115200 baud**. Note: not the usual Rockchip 1500000. | cmdline `earlycon`, DT `fiq-debugger` |

### Software / boot chain
| Item | Value |
|---|---|
| Android | 11 (RQ3A.210705.001), userdebug, release-keys |
| Kernel | Linux 4.19.193 (Rockchip BSP), built 2024-05-29 |
| U-Boot | Rockchip vendor **U-Boot 2017.09** (2024-05-29), A/B slots, AVB |
| TF-A / OP-TEE | in `trust_a`/`trust_b` (version strings not readable; likely encrypted/packed) |
| Loader | Rockchip `RKNS` idbloader at eMMC sector 64 (DDR init + SPL) |
| Slots | **A and B hold different builds** (see §2a). Running `_a` at survey time; the user's dump (`device.dtb`, 18:49) was taken from `_b`. |
| AVB | `orange` (unlocked); `veritymode=enforcing` but irrelevant once unlocked |

### 2a. A/B slots differ

| | Slot A (`_a`) | Slot B (`_b`) |
|---|---|---|
| U-Boot | 2017.09, built 2024-05-29 | 2017.09, built **2024-07-31** (ZTE additions: `androidboot.ztebootmode`, `androidboot.secureboot`) |
| Kernel | 4.19.193 #207, 2024-05-29 | 4.19.193 #63, 2024-07-31 |
| cmdline | `pmic_on=0x08 pmic_off=0x04` | `pmic_on=0x40 pmic_off=0x00 … androidboot.secureboot=0` |
| DT differences | Wi-Fi `WIFI,vbat_gpio`, `keep-power-in-suspend`, `non-removable` + `mmc-pwrseq` on SDIO, BT `wake_host_irq`, `m2-wakeup-ap-gpios`, `retain-state-suspended` | Wi-Fi `WIFI,poweren_gpio` + `WIFI,reset_gpio`, `zte-super-lowpower` (SDIO + Wi-Fi), two extra nodes set `disabled`, ZTE battery IDs `NB0333-3678B9` / `NB0318-2895B4` (GF2/GF3 38 Wh) |

The slot B build looks like the later OTA, and it's the better reference for a Linux DTS
(correct Wi-Fi power/reset GPIOs, battery data). At 21:44, `bootctl` reported both slots as
bootable and marked successful, with slot 0 (`_a`) current. Something (a manual slot switch,
the factory stress-test app `com.cghs.stresstest`, or update_engine) moved the device from B
to A between the two dumps. Keep an eye on which slot you're on before flashing either
`boot_*`.

### Other observations (privacy/security)
* `adbd` is listening on **TCP 5555** (10.0.0.66) and `su` grants root without a prompt.
  Anyone on your LAN can get root on this machine.
* The device has a **TR-069** management client pointing to `218.98.6.253:28002` and
  carrier OTA (`cm.komect.aqb.android.ota`, `com.zte.usmartupdate`). An OTA could overwrite
  the bootloader. Keep the machine off the network, or disable those packages, while you work
  on it.

---

## 3. eMMC layout (GPT, 512-byte sectors)

Standard Rockchip layout: the GPT sits in sectors 0–33, the idbloader at sector **64**, and
partitions start at 4 MiB.

| # | Name | Start sector | Size | Notes |
|---|---|---|---|---|
| — | GPT + idbloader | 0 | 4 MiB | `RKNS` header @ sector 64 |
| p1 | security | 8192 | 4 MiB | |
| p2 | uboot_a | 16384 | 4 MiB | vendor U-Boot (FIT) |
| p3 | uboot_b | 24576 | 4 MiB | |
| p4 | trust_a | 32768 | 4 MiB | BL31 + OP-TEE |
| p5 | trust_b | 40960 | 4 MiB | |
| p6 | misc | 49152 | 4 MiB | A/B + recovery BCB |
| p7 | dtbo_a | 57344 | 4 MiB | |
| p8 | dtbo_b | 65536 | 4 MiB | |
| p9 | vbmeta_a | 73728 | 1 MiB | |
| p10 | vbmeta_b | 75776 | 1 MiB | |
| p11 | boot_a | 77824 | 160 MiB | Android boot image (kernel + ramdisk + DTB) |
| p12 | boot_b | 405504 | 160 MiB | |
| p13 | backup | 733184 | 1.5 GiB | ext4, **empty** |
| p14 | cache | 3878912 | 384 MiB | ext4, nearly empty |
| p15 | metadata | 4665344 | 16 MiB | |
| p16 | baseparameter | 4698112 | 1 MiB | display settings |
| p17 | logo | 4700160 | 32 MiB | |
| p18 | zteparameter | 4765696 | 32 MiB | ext4, ZTE factory data — **keep** |
| p19 | super | 4831232 | ~5 GiB | system/vendor/product/odm (dynamic) |
| p20 | userdata | 15325184 | ~21.6 GiB | encrypted `/data` |

The mainline U-Boot layout uses the same offsets: `idbloader.img` @ sector 64 and
`u-boot.itb` @ sector 16384. Flashing mainline overwrites the start of `uboot_a`.

---

## 4. Backup taken (on this Mac)

`/Users/K/a/w600d-backup/` (~530 MB, `SHA256SUMS` included):

| File | Contents |
|---|---|
| `emmc_first16MiB.bin` | sectors 0–32767: protective MBR, GPT, **idbloader**, security, uboot_a, uboot_b |
| `emmc_backup_gpt.bin` | last 33 sectors (secondary GPT) |
| `uboot_a.img`, `uboot_b.img`, `trust_a.img`, `security.img`, `misc.img` | firmware partitions |
| `dtbo_a.img`, `vbmeta_a.img`, `boot_a.img` | Android boot chain (`boot_a` = 4.19 kernel + DTB) |
| `baseparameter.img`, `logo.img`, `zteparameter.img` | device-specific data |
| `live.dtb` / `live.dts` | DT from the **slot A** boot (survey time) |
| `device_slot_b.dtb` / `device_slot_b.dts` | user's dump from the **slot B** boot (copies of `/Users/K/a/device.dtb`, `zte-book.dts`). **Preferred reference for a Linux DTS.** |
| `trust_b.img`, `dtbo_b.img`, `vbmeta_b.img`, `boot_b.img` | slot B boot chain (newer build) |
| `getprop.txt`, `partitions.txt` | properties and partition table |

**Not yet backed up:** `super` (~5 GB, Android itself), `backup`, `cache`, `metadata`, `userdata`.
If you might ever want Android back, also dump `super`:

```sh
adb exec-out "su 0 dd if=/dev/block/by-name/super bs=4M 2>/dev/null" > w600d-backup/super.img
```

A full eMMC image (`rkdeveloptool rl 0 60620800 full.img` in loader mode) is the gold
standard. It's 31 GB and includes your Android user data.

---

## 5. Recovery paths (set these up BEFORE flashing anything)

1. **Rockusb ("loader") mode.** This is the vendor U-Boot's USB flashing mode.
   * `adb reboot loader` (or hold the recovery/V+ key at power-on, if the board has one).
   * Connect the **USB-C OTG port** to the Mac. Which port that is: try each.
   * On the Mac: `brew install rkdeveloptool` (or build from
     https://github.com/rockchip-linux/rkdeveloptool), then `rkdeveloptool ld`. It should list a
     device in `Loader` mode.
   * Read/write sectors: `rkdeveloptool rl <start> <count> out.bin`,
     `rkdeveloptool wl <start> in.bin`.
   * This only works **while the vendor U-Boot still boots**.
2. **MaskROM mode.** This is the BootROM's USB mode and works even with a wiped or broken
   loader.
   * Enter it with **no** valid loader on eMMC. On a working board, that means shorting the
     eMMC CLK test pad to GND (or eMMC D0) while powering on. Find the pad near the eMMC chip.
     Some boards have a "MASKROM" button.
   * Then: `rkdeveloptool db rk356x_spl_loader_v1.xx.bin` (from
     https://github.com/rockchip-linux/rkbin, `RKBOOT/RK3568MINIALL.ini` → `boot_merger`), then
     `rl`/`wl` as above.
   * **This is the real safety net.** Confirm you can enter MaskROM before you replace the
     bootloader.
3. **Serial console.** UART2, 3.3 V TTL, **115200 8N1**. Look for TX/RX/GND test pads on the
   mainboard (often near the SoC or labeled `UART2`/`DBG`). Without serial, debugging a
   non-booting U-Boot or kernel is guesswork. A USB-TTL adapter (CP2102/CH340/FT232, 3.3 V) is
   enough.

Also needed on the Mac: an aarch64 cross toolchain (`brew install aarch64-elf-gcc`, or build
in a Linux VM/container, which is easier for kernel + U-Boot). None of `rkdeveloptool`,
`upgrade_tool`, or an aarch64 gcc is installed right now.

---

## 6. Options

### Option A: keep vendor U-Boot, boot Linux from it (lowest risk, recommended first)
The vendor U-Boot 2017.09 already boots Android boot images from `boot_a`/`boot_b`.

1. Build a kernel (see "kernel choice" below) plus a DTB for this board.
2. Pack it as an Android boot image (`mkbootimg`, matching `boot_a.img` header: kernel at
   `0x10008000`, page size 2048, DTB as "second" or appended, as Rockchip expects).
   `unpack_bootimg` on `w600d-backup/boot_a.img` shows the exact layout to copy.
3. Put the rootfs on a USB stick (or SATA SSD if there's a slot). Later you can put it on the
   eMMC by reusing `backup` + `cache` + `userdata`.
4. Flash the image to **`boot_b`** only, then switch slots. `boot_a` and Android stay intact,
   and you can switch back. Alternatively: flash `boot_a` via rockusb and restore it from the
   backup if needed.
5. With serial attached, you can also stop autoboot (Ctrl-C) and use the vendor U-Boot's own
   commands (`ext4load`/`booti` or `boot_android`), depending on what it was built with.

### Option B: mainline U-Boot (do this after A works, or skip)
* Mainline U-Boot supports RK3568 (`evb-rk3568_defconfig` as a starting point; write a
  `rk3568-zte-w600d` board DTS from `live.dts`).
* Ingredients: mainline TF-A BL31 (`PLAT=rk3568`) or rkbin `rk3568_bl31_v*.elf`, plus the
  **closed-source DDR init blob** `rk3568_ddr_1560MHz_v*.bin` from rkbin (no open DDR init
  exists).
* Write `idbloader.img` @ sector 64 and `u-boot.itb` @ sector 16384. Then boot Linux via
  standard distro boot / extlinux / EFI from eMMC, USB or SATA.
* Android will **no longer boot** (mainline U-Boot can't really do Rockchip Android + AVB).
  To go back, restore `emmc_first16MiB.bin` (and `trust_a`) via MaskROM.
* Display in U-Boot over eDP is probably not worth the trouble. Use serial, or HDMI if it
  works.

### Kernel choice
| | Rockchip BSP kernel (5.10 / 6.1 `develop` branch) | Mainline (6.12+) |
|---|---|---|
| eDP panel | works (vendor DT reusable almost as-is) | RK3568 eDP via analogix-dp is new/limited; **verify** before relying on it |
| HDMI | works | works (VOP2 + dw-hdmi) |
| GPU | Mali-G52 blob or Panfrost | Panfrost (OpenGL ES 3.1 / GL 3.1) |
| Video decode | full (MPP) | partial (hantro/rkvdec) |
| MT7663 Wi-Fi/BT | vendor or mt76 | `mt7663s` in mt76 + `btmtksdio` (needs `mediatek/mt7663*` firmware) |
| RK809 / RK860 / TCS4525 | yes | yes |
| BQ25703 charger | vendor driver | `bq257xx` driver is very recent; check your version |
| SC2021 USB-PD | vendor driver only | **none**. Charging may still work via hardware defaults; test carefully. |
| SBS battery | yes | `sbs-battery` |
| I2C-HID touchpad, USB keyboard | yes | yes |
| OS04A10 MIPI camera | vendor ISP stack | no |
| Long-term | stuck on old kernel | upstream updates |

Practical path: **boot first with the BSP kernel + the extracted `live.dtb`**, because it
matches the hardware. Then work towards a mainline DTS using the BSP DT as a reference.
Existing RK3568 distributions you could base the rootfs on: Armbian (rk35xx), Debian/Ubuntu
arm64 generic rootfs, postmarketOS, or Manjaro ARM.

---

## 6a. Reference port

A similar RK3568 cloud laptop (Sunniwell Z96A) runs Armbian bookworm (BSP 5.10.160, vendor U-Boot
2017.09, rootfs on USB). See **`ref-z96a-comparison.md`**: same SoC and display routing, but
different GPIOs, PMIC, Wi-Fi and charging. Use it as a template, not as a drop-in DTB.

## 7. Suggested step-by-step

1. ☐ Disconnect the device from the internet, or disable the OTA/TR-069 packages, so firmware
   can't change under you.
2. ☐ (Optional) Dump `super` and any data you care about (§4).
3. ☐ Open the case: find **UART2 pads**, the **MaskROM pad/button**, and check for an **M.2
   SATA slot**. Take photos of the board.
4. ☐ Install `rkdeveloptool`. Test `adb reboot loader` → `rkdeveloptool ld` from the Mac over
   USB-C. Read back sector 64 and compare with the backup.
5. ☐ Test MaskROM entry once (it doesn't change anything; power-cycle to exit).
6. ☐ Set up a Linux build environment (container/VM). Build the kernel + DTB. Prepare the
   rootfs on USB.
7. ☐ Option A: flash `boot_b` and boot Linux with serial attached.
8. ☐ Fix drivers (eDP, Wi-Fi, charging, suspend, lid).
9. ☐ (Optional) Option B: mainline U-Boot, then move the rootfs onto the eMMC (repartition
   `backup`…`userdata`). Keep the first 16 MiB backup safe.

---

## 8. Android tweak: Windows key → Back

On this Android build, Esc doesn't act as Back. The keyboard is USB `258a:0001` ("SINO WEALTH
USB KEYBOARD") and was using `/system/usr/keylayout/Generic.kl`, where `key 125 META_LEFT` is
the Windows key.

Fix: put a device-specific layout in the writable `/data/system/devices/keylayout/`. Android
picks a `Vendor_XXXX_Product_YYYY.kl` file over `Generic.kl`. No `/system` change is needed,
and it survives reboots and slot switches. A factory reset removes it.

* File: `/data/system/devices/keylayout/Vendor_258a_Product_0001.kl`. Local copy:
  `/Users/K/a/keymap/`. It's `Generic.kl` with one change:
  `key 125   BACK` (the same keycode as `input keyevent 4`).
* Install:
  ```sh
  adb push keymap/Vendor_258a_Product_0001.kl /data/local/tmp/
  adb shell "su 0 sh -c 'mkdir -p /data/system/devices/keylayout && \
    cp /data/local/tmp/Vendor_258a_Product_0001.kl /data/system/devices/keylayout/ && \
    chown -R system:system /data/system/devices && chmod 644 /data/system/devices/keylayout/*.kl && \
    restorecon -R /data/system/devices'"
  ```
* Apply without rebooting: re-enumerate the keyboard
  (`echo 0 > /sys/bus/usb/devices/7-1/authorized; echo 1 > …/authorized`), or just reboot.
* Check: `dumpsys input | grep KeyLayoutFile` should show the `/data/...` path for the three
  SINO WEALTH entries.
* Undo: `su 0 rm /data/system/devices/keylayout/Vendor_258a_Product_0001.kl`, then
  re-enumerate or reboot.
* To make **Esc** act as Back too: change `key 1     ESCAPE` to `key 1     BACK` in the same
  file.
* Side effect: the Windows key no longer works as Meta (Android's Meta shortcuts).

## 9. Commands used for this survey (all read-only)

```sh
adb shell cat /proc/cpuinfo
adb shell getprop
adb shell "su 0 sh -c 'cat /proc/cmdline; ls -l /dev/block/by-name; cat /proc/partitions'"
adb shell "su 0 sh -c 'for p in /sys/block/mmcblk2/mmcblk2p*; do ...start/size/PARTNAME...; done'"
adb shell "su 0 sh -c 'dd if=/dev/block/by-name/uboot_a bs=1M count=4 | strings | grep U-Boot'"
adb shell "su 0 sh -c 'cat /sys/bus/i2c/devices/*/name; cat /sys/bus/sdio/devices/*/uevent'"
adb exec-out "su 0 dd if=/dev/block/<part> bs=1M" > <part>.img       # backups
adb exec-out "su 0 sh -c 'cat /sys/firmware/fdt'" > live.dtb
dtc -I dtb -O dts -o live.dts live.dtb
```

See also `partitions.md` (eMMC map diagram + contents).
See also `ref-issue3681.md` (ophub issue #3681: ZTE firmware URL, MT7663 notes).
See also `fw-v2.25.md` (ZTE V2.25 OTA contents, MT7663 firmware, U-Boot without fallback).
See also `HOWTO-patch-uboot.md` (patched uboot_a env: USB first, Ctrl+C window).
- See also `ab-tries.md`: who decrements the A/B tries (SPL vs U-Boot), and why foreign U-Boot images must not go into uboot_a.
- See also `usb-demo/README.md`: first USB-stick boot test (boot.scr + bare-metal demo).
- See also `HOWTO-usb-drive.md`: preparing a USB drive this U-Boot boots (MBR+FAT32, boot.scr quirk, extlinux).
