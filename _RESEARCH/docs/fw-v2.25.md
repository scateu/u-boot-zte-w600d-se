# ZTE firmware V2.25.20P06 (W6XX_W52X-RK3568-T): what's inside

Source: `W6XX_W52X-RK3568-T-ALLV2.25.20P06-Firmware.zip` (URL in `ref-issue3681.md`), unpacked to
`W6XX_W52X-RK3568-T-ALLV2.25.20P06-Firmware/`. Extracted by me into **`fw-v2.25/`**. Examined 2026-11-05.

## 1. Summary

- It is a **full Android A/B OTA** (`ota-type=AB`, no `pre-build`), **not** a Rockchip factory
  `update.img`. There is **no loader** (`MiniLoaderAll.bin` / idbloader), **no GPT**, no trust,
  vbmeta, misc, logo or baseparameter.
- Built 2025-10-19, `V2.25.20P06-20251019`, for `rk3568_r_w600d2`. Product types: W600D SE, W601E,
  W601ES, W521D(-L22/L24/L27), W621D. Ours runs `FactoryV1.24.20P2-20240529`.
- **Don't let it get installed.** Its U-Boot has **no distro fallback** (see §3). The OTA would go
  into the inactive slot (B) and switch to it.

## 2. Package structure

```
W6XX_…-Firmware/
├── imageinfo, update.json, complete.log      metadata (version, md5/sha, ZTE signature)
└── …-Firmware.tar.gz (949 MB)
    ├── W6XX_W52X-RK3568-T-ALLV2.25.20P06-ota.zip      SignApk-signed A/B OTA
    │   ├── payload.bin (840 MB)                       ← all partition images
    │   ├── payload_properties.txt, META-INF/…
    ├── update.xml                                     internal OTA server 10.234.23.4
    ├── firmware.ini + config/firmware/                peripheral MCU firmware (below)
    ├── config/*_config.zip, config/install.sh         per-SKU props (W600DSE-T, -TZTE, -TAI, W521D…)
    └── custom/*.zip, custom/install.sh                per-SKU branding: logo.img, bootanimation,
                                                       ZTE apps, ui_logo
```

### payload.bin partitions (all hashes verified ✅)

| Partition | Size | Notes |
|---|---|---|
| `boot` | 142 233 600 | Android boot v2, page 2048, kernel + ramdisk + RSCE (27 DTBs) |
| `uboot` | 4 194 304 | FIT: U-Boot 2017.09 **Oct 19 2025** + ATF + OP-TEE |
| `dtbo` | 4 096 | |
| `system` | 1 015 472 128 | ext4 |
| `vendor` | 611 282 944 | ext4 (Wi-Fi/BT firmware, modules) |
| `product` | 213 708 800 | ext4 |
| `system_ext` | 107 278 336 | ext4 |
| `odm` | 630 784 | ext4 |

Extracted to `fw-v2.25/img/` with `tools/payload-extract.py` (pure Python, full OTAs only):
```sh
cd fw-v2.25
unzip W6XX_W52X-RK3568-T-ALLV2.25.20P06-ota.zip payload.bin
python3 -I ../tools/payload-extract.py payload.bin            # list
python3 -I ../tools/payload-extract.py payload.bin img        # extract + verify sha256
```

### Peripheral firmware (`config/firmware/`, `firmware.ini`)

EC/dock `dock.bin`, keyboard MCU `keyboard.hex` / `KBC_SH68F83Q_ZTE_V1.13…hex`, touchpad
firmwares (HTX / YML / SA variants per model), USB cameras (`camera_*.bin`), 5G module `lierda.bin`.
Android flashes these at runtime. Not needed for Linux, but useful if a peripheral ever gets bricked.

## 3. Findings that matter for us

### 3.1 U-Boot: V2.25 has no fallback

| | `bootcmd` | build |
|---|---|---|
| our `uboot_a` | `boot_fit; boot_android …; run distro_bootcmd;` ✅ | May 29 2024 |
| our `uboot_b` | `boot_android …;` | Jul 31 2024 |
| **V2.25 `uboot`** | `boot_android …;` | Oct 19 2025 |

So ZTE removed the extlinux/USB fallback after May 2024, and it stays removed. **Our `uboot_a` is
the valuable one.** Keep it, copy it to `uboot_b`, and keep OTAs from replacing it.

All three FITs are signed `sha256,rsa2048`, `key-name-hint = "dev"`. Secure boot isn't enforced on
our unit (`ro.boot.secureboot` empty, slot B cmdline `secureboot=0`).

### 3.2 `trust_a` / `trust_b` are empty

The FIT in `uboot` already carries **ATF (BL31) + OP-TEE** (`loadables = uboot, atf-2…6, optee`).
Our dumped `trust_a.img`/`trust_b.img` are **100 % zeros**. The "copy trust_a → trust_b" step in
`usb-boot.md` is therefore unnecessary (harmless, but a no-op).

### 3.3 Resource / DTBs

`fw-v2.25/resource/` (extracted with `tools/rsce.py img/boot.img resource`):
- **27 board DTBs** (ours had 17). New: w600dse-25wh_v11, w600dsewifi6_v10/v4-40w, w600e*,
  w603es*, w620d…
- **Ours is still there:** `rk3568-w600dse-pvt-cs` (ADC 938/779), decompiled to
  `fw-v2.25/resource/w600dse-pvt-cs.dts`.
- Diff against our current DTB (1202 lines, almost all phandle renumbering). The real changes:
  - Wi-Fi SDIO node (`dwmmc@fe2c0000`): `mmc-pwrseq`, `non-removable`, `keep-power-in-suspend`
    removed, ZTE `zte-super-lowpower` added (vendor power management of the MT7663)
  - `adc-keys` disabled
  - some LEDs: `retain-state-suspended` removed
  - new `hardware_info { terminal_type = "2"; }`, `bq25700: ti,minimum-sys-voltage-new`
  - **panel, eDP, backlight, GPIOs unchanged.** For our Linux DTS the current dump stays the reference.
- Battery images are new (72 656 B each vs ~6.3 KB) plus `battery_error.bmp`. `logo.bmp` is still in the
  resource (and still not what's displayed, see `HOWTO-change-logo.md`).

### 3.4 MT7663 Wi-Fi/BT firmware ✅

From `vendor.img` (7-Zip can read ext4: `7z e img/vendor.img etc/firmware/…`) → `fw-v2.25/fw-wifi/`:

| File | Size | Role |
|---|---|---|
| `WIFI_RAM_CODE_MT7663.bin` | 448 792 | N9 RAM code (`MT7663_E2_ASIC_ROM_RAM_Mobile-20230629193401`) |
| `mt7663_patch_e2_hdr.bin` | 278 558 | ROM patch (`7663mp1827 20230629`) |
| `EEPROM_MT7663.bin` | 1 536 | EEPROM/calibration defaults |
| `woble_setting_7663.bin` | 2 503 | wake-on-BLE settings |
| `mtk_*.sh`, `*.rc`, `bt_vendor.conf` | | Android helpers (reset, power mode) |

**sha256 is identical to the files on our running laptop** (checked 2026-11-05), so this is the
matching N9 + ROM-patch pair the issue #3681 comment asks for. We no longer need to pull them
from the device before the wipe.
Mainline `mt7663s` expects `mediatek/mt7663pr2h.bin` + `mediatek/mt7663_n9_v3.bin`. Whether the
vendor pair can be renamed into those slots must be tested (headers may differ).

The vendor kernel modules are there too: `lib/modules/btmtksdio.ko`, and `wlan_mt7663_sdio.ko`
(built from `drivers/net/wireless/rockchip_wlan/mt7661/…`, i.e. the Rockchip BSP tree has the
vendor driver).

### 3.5 ZTE custom installer (`custom/install.sh`)

- It writes the boot logo with `dd if=logo.img of=/dev/block/by-name/logo`, the same method as
  `HOWTO-change-logo.md`. If a ZTE "custom" update with `UpdateLogo=1` runs, **our logo gets
  overwritten**. The W600DSE-TZTE bundle's `logo.img` (12 442 166 B) differs from our stock one.
- It **writes `uboot.img` to `uboot_a`** if `ro.boot.secureboot == 1` **and** slot = 0 **and**
  `splrollback != 1` **and** model doesn't start with W5 **and** `ro.AIO.support != 1`.
  On our unit `ro.boot.secureboot` is **empty**, so it does nothing. But this is exactly the
  kind of update that would silently kill our USB fallback. `/data/tombstones/update_custom_file.log`
  doesn't exist, so it has never run here.
- It disables SELinux (`setenforce 0`) while running.

## 4. Can this restore Android after a wipe?

Partly:
- `boot`, `dtbo`, `uboot` can be `dd`'d directly (to `boot_a`, `dtbo_a`; `uboot` only if wanted).
- `system/vendor/product/system_ext/odm` must be packed into a **`super` image** (`lpmake` from
  AOSP otatools, using the dynamic-partition sizes) and written to p19. There's no ready `super.img`.
- `vbmeta` isn't in the OTA. Our backup `vbmeta_a.img` is for the old build, but with the bootloader
  unlocked (orange) a mismatch only warns.
- Still missing for a "factory" restore: `misc`, `logo`, `baseparameter`, `zteparameter`. We have those
  in `w600d-backup/`.

So it's a workable route back to Android (much better than nothing), but dumping our own `super`
before the wipe is still the simplest guarantee.

## 5. Action items

- Keep OTA / carrier update apps from installing anything before the wipe (TR-069, uSmart).
- `usb-boot.md`: drop the `trust_a → trust_b` step. Only `uboot_a → uboot_b` matters.
- Linux: Wi-Fi firmware ready in `fw-v2.25/fw-wifi/`.
