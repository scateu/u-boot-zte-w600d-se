# Reference: Sunniwell Z96A Linux port vs. our ZTE W600D

Sources in `ref/`:
- `rk3568_laptop_sunniwell_z96a/`: bingo1991's repo (README, `rk3568-z96a.dts`, `rk3568_z96a_defconfig`).
  The last commit is `72201d2` (2024-02-20, "bluetooth, camera, hall-sensor worked").
- `云笔记本，刷linux，天翼云笔记本rk3568_朝歌z96a刷armbian-CSDN博客.html`: the CSDN blog post (readable; summarized
  in "Blog summary" below). An earlier save, `…技术栈.htm`, is 0 bytes and can be deleted.

## What they did (Z96A)

From the screenshots and the repo:

1. **Build system: Armbian** (`armbian/build`), with a custom board config:
   ```
   ./compile.sh build BOARD=z96a-rk3568-laptop BRANCH=legacy BUILD_DESKTOP=yes BUILD_MINIMAL=no \
     DESKTOP_ENVIRONMENT=xfce DESKTOP_ENVIRONMENT_CONFIG_NAME=config_base \
     DESKTOP_APPGROUPS_SELECTED='3dsupport browsers chat desktop_tools editors internet multimedia office' \
     KERNEL_CONFIGURE=no RELEASE=bookworm
   ```
   Output: `Armbian-unofficial_24.2.0-trunk_Z96a-rk3568-laptop_bookworm_legacy_5.10.160_xfce_desktop.img`
   (6.02 GiB), built in about 10 minutes.
2. **Bootloader: Rockchip vendor U-Boot 2017.09.** The Armbian package is
   `linux-u-boot-z96a-rk3568-laptop-legacy_…_2017.09-…deb`, and Armbian writes it into the image
   (idbloader @ sector 64 + `u-boot.itb`). So they **replaced** the stock U-Boot with Armbian's
   build of the same vendor 2017.09 tree, not with mainline.
3. **Kernel: Rockchip BSP 5.10.160** (`linux-5.10.y-rk35xx`, Armbian "legacy" branch), built with
   `rk3568_z96a_defconfig` + `rk3568-z96a.dts`.
4. **Rootfs on a USB 3.0 stick** (SanDisk 62 GB, GPT: `armbi_boot` 268 MB FAT + `armbi_root` ext4).
   `/boot/armbianEnv.txt`:
   ```
   overlay_prefix=rk3568-z96a
   fdtfile=rockchip/rk3568-z96a.dtb
   rootdev=UUID=c8086801-…-1b8c7b81395f
   rootfstype=ext4
   usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
   ```
   They also had DT variants `rk3568-z96a-usb302.dtb` / `-usb311.dtb` for the two Type-C controller
   options on that board.
5. **Results:** XFCE desktop at 1920×1080 on eDP, Chromium/LibreOffice/mpv, **4K H.265 playback at
   ~19% CPU** via rkmpp (ffmpeg with `*_rkmpp` decoders), Panfrost GPU (glmark2 ~470), Wi-Fi/BT,
   battery, lid. The README says "everything works".

## How close is the W600D to the Z96A?

**Same SoC, different board.** The Z96A DTS can be used as a template for structure, but **almost
every GPIO, the power/charging design and the Wi-Fi chip are different**. Booting our laptop
with `rk3568-z96a.dtb` would probably reach a kernel, but the screen, Wi-Fi, touchpad and
charging would not work.

The W600D values below were decoded from the stock **slot B** DT (`w600d-backup/device_slot_b.dts`).

| Function | Z96A (ref) | **W600D (ours)** | Reuse? |
|---|---|---|---|
| SoC | RK3568B2 | RK3568 | ✅ |
| RAM | 4 GB LPDDR4X | 2 GB DDR4 | DDR blob differs: use the stock idbloader or the matching rkbin blob |
| PMIC | **RK817** (with charger) | **RK809** @ i2c0 0x20, int GPIO0_A3 | ⚠ same driver family (`rk808`/`rk817` MFD); regulator map differs, no RK817 charger/battery nodes |
| vdd_cpu | SYR827 @0x40 | TCS4525 @0x1c / RK860-0 @0x40 / RK860-1 @0x41 (board variants, all in the DT) | ⚠ |
| vdd_gpu / vdd_logic | RK817 DCDC2 / DCDC1 | RK809 DCDC2 / DCDC1 (+ DCDC4 = vdd_npu) | ⚠ |
| Power input | DC 12 V barrel | **USB-C PD** | ❌ |
| Charger | CN3705 (no software control) | **TI BQ25703** @0x6b, int GPIO3_B7 | ❌ BSP has `bq25700_charger` (check) |
| USB-PD / Type-C | HUSB311 or FUSB302 | **Southchip SC2021** @0x21, int GPIO0_A4, `pdotg` GPIO4_C5, `dpdm` GPIO4_C6 | ❌ no public driver |
| Battery gauge | ADC + hand-written patch on RK817 driver | **SBS smart battery** @0x0b (`zte,smart_battery`), 2S 38 Wh | ❌; try `sbs,sbs-battery` |
| eDP routing | VP1 → eDP, VP0 → HDMI | VP1 → eDP, VP0 → HDMI, **same plane masks** (VP0 0x2a, VP1 0x15) | ✅ |
| eDP panel | BOE NV140FHM-N48, `simple-panel`, `force-hpd` | guoxian-30NK 1080p, `simple-panel`, `force-hpd` | ✅ structure |
| Panel enable | GPIO3_A3 | **GPIO2_D4** | ❌ |
| Panel power | GPIO0_C7 (`vcc3v3_lcd0_n`) | **GPIO2_D5** (`vcc3v3_lcd_edp`) | ❌ |
| Backlight | `pwm10` | **`pwm2`** (fdd70020), enable **GPIO2_D3** | ❌ |
| Lid (hall) | GPIO0_C6 | **GPIO0_B7**, active low | ❌ |
| Wi-Fi | RTL8821CS (SDIO on sdmmc1) | **MediaTek MT7663** (SDIO on sdmmc1 / `dwmmc@fe2c0000`); power GPIO0_A5, reset GPIO0_B5, host-wake GPIO2_B2 | ❌ different driver |
| Bluetooth | RTL8821CS on UART1 (H5) | **MT7663 over SDIO** (`btmtksdio`); UART1 BT node is vestigial | ❌ |
| Keyboard | USB, power GPIO0_C5 | USB `258a:0001`; power-enable GPIO **unknown** (no named regulator) | ⚠ |
| Touchpad | USB | **I2C-HID** on i2c4 @0x2c, `hid-descr-addr 0x20`, irq GPIO3_B3, reset GPIO3_A1, power GPIO3_B4 | ❌ |
| Webcam | USB AU3841, power GPIO2_C0 | USB `1bcf:2ced` (+ MIPI OV5695/OS04A10 on i2c4, mostly unused) | ⚠ |
| Audio codec | RK817 codec on i2s1 | RK809 codec on i2s1 (`rockchip,rk809-codec`) | ✅ same driver |
| USB 5 V | host GPIO3_B6, OTG GPIO2_D5 | host **GPIO3_A0**, OTG **GPIO0_C4** | ❌ |
| G-sensor | — | MXC6655XA on i2c5 @0x15 | n/a |
| SD slot | sdmmc0 enabled | sdmmc0 **disabled** (no slot) | ❌ |
| Debug UART | UART2, **1500000** | UART2, **115200** | ⚠ |

## What this means for our plan

1. **The path is proven:** Armbian + vendor U-Boot 2017.09 + BSP 5.10.160 on this SoC in a laptop
   form factor, booting the rootfs from USB. Follow the same route instead of mainline first.
2. **Work needed:** a **W600D board config for Armbian** (copy `z96a-rk3568-laptop`), plus a
   **`rk3568-w600d.dts`**. Write it like the Z96A DTS (same includes and structure), but fill in
   the GPIOs and devices from `device_slot_b.dts` using the table above.
3. **Kernel config deltas vs `rk3568_z96a_defconfig`:**
   - drop `RTL8821CS`, `BT_HCIUART_RTL`, `TYPEC_HUSB311/FUSB302`, `BATTERY_RK817/CHARGER_RK817`
   - add MT7663 SDIO Wi-Fi + `BT_MTKSDIO`. Mainline `mt7663s` arrived in **5.11**, so 5.10 needs a
     backport or the out-of-tree MediaTek driver (Android loads `wlan_mt7663_sdio.ko`).
     Firmware: `mediatek/mt7663*`.
   - add `CHARGER_BQ25700` (Rockchip BSP), `BATTERY_SBS`, `I2C_HID_OF`, `KEYBOARD_GPIO` (lid)
4. **Charging / USB-C is the riskiest part.** With no SC2021 driver, PD negotiation may stay at
   whatever the chip does by itself. Test charging with the battery monitored before relying on it.
5. **Bootloader:** Armbian writes its own idbloader + U-Boot to the eMMC start. Before that, make
   sure you can recover with rockusb/MaskROM (see `W600D-linux.md` §5). Our backup
   `w600d-backup/emmc_first16MiB.bin` restores the stock loader.

## Blog summary (CSDN, 朝歌z96a刷armbian)

What the author says, translated and condensed:

- **Why:** carrier cloud laptops (RK3566/RK3568, 4+32 GB, 14" IPS, metal) sell for ¥170–260 second-hand.
  **ZTE and China Telecom (天翼) models go for ¥150–180** and also work, but "you have to modify the
  DTB yourself". The Z96A is recommended because bingo1991's DTS already exists.
- **Kernel:** the DTS targets **Linux 5.10**. It works with Armbian, or with ophub's Debian/Ubuntu/fnOS
  images. Kernel source: **https://github.com/unifreq/linux-5.10.y-rk35xx** (5.10.160).
- **Two builds shown:**
  1. Armbian (`compile.sh BOARD=z96a-rk3568-laptop BRANCH=legacy …`, see above).
  2. A **hand-assembled Debian 13 rootfs**: debootstrap, then copy in the kernel `Image` +
     `rk3568-z96a.dtb` → `/boot/` and the modules → `/lib/modules/5.10.160-…/`. Then pin
     `linux-image*`/`linux-headers*` to priority -1 in `/etc/apt/preferences.d/block-linux-update`,
     so apt never replaces the custom kernel.
- **How it's installed:**
  1. **Flash the image to the internal eMMC first.** The blog does **not** say how. Normally this means
     loader/MaskROM mode + RKDevTool/`rkdeveloptool` with the whole `.img`.
  2. `dd` the same image to a USB stick/SSD.
  3. On the USB root partition, change the ext4 UUID so it differs from the eMMC copy
     (`tune2fs -U <new> /dev/sda2; e2fsck -f /dev/sda2`). They changed the last hex digit.
  4. In **`/boot/armbianEnv.txt` on the eMMC**, comment out the old `rootdev` and set
     `rootdev=UUID=<usb uuid>`.

  So **U-Boot, kernel and DTB stay on the eMMC; only the rootfs lives on USB.** USB 3.0 speed
  tests show this costs no performance.
- **Hardware video decode:** install `jellyfin-ffmpeg7 libjemalloc2` (Jellyfin's repo ships RK MPP
  ffmpeg). Check with `ffmpeg -decoders | grep rkmpp` and `ls /dev/mpp_service`.
  `~/.config/mpv/mpv.conf`:
  ```
  hwdec=rkmpp
  hwdec-codecs=av1,h263,h264,hevc,mpeg1,mpeg2,mpeg4,vp8,vp9
  vo=gpu
  gpu-context=x11
  cache-secs=5
  ```
  Result: 4K HEVC at 19% CPU.
- **Misc desktop tips:** trust XFCE desktop launchers
  (`gio set -t string f metadata::xfce-exe-checksum "$(sha256sum f | awk '{print $1}')"`), and autostart
  Fcitx5 by copying `org.fcitx.Fcitx5.desktop` to `~/.config/autostart/`.

**Not covered by the blog:** how to enter loader/MaskROM mode, which flashing tool was used, UART
pads, or any battery/charging details. Use `W600D-linux.md` §5 for our recovery plan.

### Impact on our plan
- **Kernel tree:** `unifreq/linux-5.10.y-rk35xx` (what ophub uses), with our own `rk3568-w600d.dts`.
- **Boot layout:** idbloader + U-Boot + `/boot` on eMMC, rootfs on USB/SATA. This avoids the 32 GB
  eMMC limit, and Android's `super`/`userdata` space can be reused later.
- Flashing the full image to eMMC **wipes Android**, because an Armbian image has its own GPT. The
  dual-boot alternative (keep the stock U-Boot, put a kernel in `boot_b`) is still in `W600D-linux.md`
  §6 Option A.
