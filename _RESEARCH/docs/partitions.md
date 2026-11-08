# partitions.md: ZTE W600D eMMC layout and contents

eMMC `A3A551`, 60 620 800 sectors × 512 B (≈ 31 GB), GPT. Sector numbers are from
`w600d-backup/partitions.txt`, and contents were checked against the dumps in `w600d-backup/`.

## 1. Map (today, stock)

```
 sector      size     name            content
 ─────────┬─────────┬───────────────┬──────────────────────────────────────────────────────
        0 │  512 B  │ (MBR)         │ protective MBR
        1 │ 16.5 KB │ (GPT)         │ primary GPT header + entries
       64 │ ≤4 MiB  │ (idbloader)   │ "RKNS": DDR init V1.18 + U-Boot SPL 2017.09 (2021-12-03)
 ─────────┼─────────┼───────────────┼──────────────────────────────────────────────────────
     8192 │  4 MiB  │ p1  security  │ "/dirf.db" Rockchip secure storage (OP-TEE)
    16384 │  4 MiB  │ p2  uboot_a   │ FIT: U-Boot 2017.09 (2024-05-29) ★ has distro_bootcmd fallback
    24576 │  4 MiB  │ p3  uboot_b   │ FIT: U-Boot 2017.09 (2024-07-31)   boot_android only
    32768 │  4 MiB  │ p4  trust_a   │ empty (all zeros); ATF + OP-TEE live inside the uboot FIT
    40960 │  4 MiB  │ p5  trust_b   │ empty (all zeros)
    49152 │  4 MiB  │ p6  misc      │ A/B metadata + BCB (see §3)
    57344 │  4 MiB  │ p7  dtbo_a    │ Android DT overlays (magic d7b7ab1e)
    65536 │  4 MiB  │ p8  dtbo_b    │ "
    73728 │  1 MiB  │ p9  vbmeta_a  │ AVB0 verified-boot metadata
    75776 │  1 MiB  │ p10 vbmeta_b  │ "
 ─────────┼─────────┼───────────────┼──────────────────────────────────────────────────────
    77824 │ 160 MiB │ p11 boot_a    │ Android boot img v2: kernel 4.19 + ramdisk + RSCE resource (§2)
   405504 │ 160 MiB │ p12 boot_b    │ same, slot B build (2024-07-31)
   733184 │ 1.5 GiB │ p13 backup    │ ext4, empty
  3878912 │ 384 MiB │ p14 cache     │ ext4 (Android)
  4665344 │  16 MiB │ p15 metadata  │ Android FBE metadata
  4698112 │  1 MiB  │ p16 baseparam │ "BASP": display modes DISP_0..4 (read by U-Boot + kernel)
  4700160 │  32 MiB │ p17 logo      │ BMP 1920×1080×24 "中国移动云电脑": ★ the power-on logo
  4765696 │  32 MiB │ p18 zteparam  │ ext4, ZTE factory data (SN, MAC?)
  4831232 │ ~5 GiB  │ p19 super     │ dynamic: system, vendor, product, odm, system_ext  (NOT backed up)
 15325184 │ ~21.6GiB│ p20 userdata  │ /data
 60620767 │ 16.5 KB │ (GPT)         │ secondary GPT
 ─────────┴─────────┴───────────────┴──────────────────────────────────────────────────────
```

Boot flow over this layout:

```
 BootROM ──► idbloader@64 ──► reads misc (A/B) ──► uboot_x + trust_x ──► U-Boot
                                                                           │
            ┌───────────────── logo partition (p17) ◄── power-on logo ─────┤
            │                  baseparameter (p16) ◄── display mode ───────┤
            │                  boot_x "second" = RSCE ◄── kernel DTB ──────┤ (eDP config!)
            │                                        ◄── battery_*.bmp ────┤ (charge mode)
            ▼                                                              ▼
        screen                                   boot_android ► kernel/ramdisk from boot_x
                                                 (uboot_a only) ► distro_bootcmd: mmc1 mmc0 usb0
```

## 2. Inside `boot_a` (p11, 160 MiB)

```
 offset (bytes)   size          part
 ──────────────┬─────────────┬───────────────────────────────────────────────
             0 │ 2048        │ "ANDROID!" header v2 (page 2048), cmdline
          2048 │ 34 570 256  │ kernel Image 4.19.193
           ... │ 85 911 373  │ ramdisk (Android first stage + recovery)
   120 485 888 │ 15 003 648  │ second = RSCE resource image  → resource_a.img
           ... │             │ (dtb section, padding)
 ──────────────┴─────────────┴───────────────────────────────────────────────

 RSCE (resource_a/):
   rk-kernel.dtb                    ← copy of the selected board DTB, used by U-Boot
   rk3568-w500d*.dtb, w520d2*, w600dse-*, w600e*, w620d*   (17 board DTBs, picked by
        SARADC ch1/ch4; ours 938/779 → rk3568-w600dse-pvt-cs)
   battery_0..5.bmp, battery_fail.bmp   ← charge animation (seen when charging after
                                          reconnecting the battery)
   logo.bmp = logo_kernel.bmp       ← "中兴云电脑" (ZTE), 1920×1080 top-down.
                                      NOT the power-on logo; shown by the kernel/Android
                                      if at all.
```

## 2a. Inside `logo` (p17, 32 MiB)

```
 0x000000  BMP 1920×1080×24, 6 220 854 B  ← U-Boot power-on logo
 0x5eee00  same BMP again (identical)     ← kernel logo slot
 rest      zeros
```
Quirk: the header says bottom-up (height +1080), but the rows are stored top-down, so it looks
upside down on a PC. `tools/make-logo.py` builds a patched image (header unchanged, both copies
written). The first test image is `logo/logo_w600d.img`. Full guide: `HOWTO-change-logo.md`.

## 3. Inside `misc` (p6, 4 MiB)

```
 0x0000  zeros
 0x0800  "\0AB0" Rockchip A/B metadata: active slot _a, both bootable + successful
 0x0910  DTB with "fit-images" (U-Boot FIT bookkeeping)
 0x4000  BCB: command "boot-recovery", recovery "recovery\n--wipe_all"
         (stale; the device boots normally. Leave misc alone, or restore from misc.img.)
```

## 4. What the display needs (observed)

| Screen | Source | Confirmed by |
|---|---|---|
| Power-on logo "中国移动云电脑" | **p17 `logo`** | user: logo after power button ≠ resource bmps |
| Charge animation | `battery_*.bmp` in **RSCE** (boot_x) | user: shown when charging after battery reconnect |
| eDP timing/panel/GPIOs for both | `rk-kernel.dtb` in **RSCE** | U-Boot's own DTB has no display nodes |
| Display mode | p16 `baseparameter` | Rockchip convention |

So U-Boot's screen depends on **p16, p17 and the RSCE**. If the RSCE goes away with boot_a/b, the
logo partition alone won't light the panel, because the eDP config is missing.

## 5. Proposed layout after wiping Android (nothing written yet)

```
 sector      name            action
 ─────────┬───────────────┬──────────────────────────────────────────────
  0..8191 │ MBR/GPT/idbl  │ KEEP (GPT edited: entries below)
     8192 │ p1  security  │ KEEP
    16384 │ p2  uboot_a   │ KEEP
    24576 │ p3  uboot_b   │ ← copy of uboot_a   (fallback in both slots)
    32768 │ p4  trust_a   │ KEEP
    40960 │ p5  trust_b   │ KEEP (empty)
    49152 │ p6  misc      │ KEEP
    57344 │ p7..p10       │ KEEP or erase (dtbo/vbmeta are unused once boot_android fails)
    77824 │ p11 boot_a    │ ERASE  → boot_android fails → distro_bootcmd
   405504 │ p12 boot_b    │ ERASE
   733184 │ p13 resource  │ renamed from "backup"; dd resource_a.img (later: our DTB)
  3878912 │ p14,p15       │ free
  4698112 │ p16 baseparam │ KEEP
  4700160 │ p17 logo      │ KEEP (or replace with our own BMP, same format)
  4765696 │ p18 zteparam  │ KEEP (factory data; tiny)
  4831232 │ p19+p20       │ → one Linux partition (~26 GiB): /boot + rootfs, optional
 ─────────┴───────────────┴──────────────────────────────────────────────
 USB stick: p1 ext4 with /boot/extlinux/extlinux.conf (see usb-boot.md)
```
