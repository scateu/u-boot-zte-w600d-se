# HOWTO: change the power-on logo on the ZTE W600D

**Status (2026-11-05): done and confirmed on the device.** The stock "中国移动云电脑" logo now has
"W600D LINUX" underneath. Only the `logo` partition (p17) was written.

## 1. Which program draws the logo

```
 power button
   │
   ▼
 BootROM ─► idbloader (DDR init + SPL)          no display code; screen still dark
   │
   ▼
 U-Boot 2017.09 (ZTE/Rockchip vendor build,     ◄── THIS draws the logo
 uboot_a or uboot_b, picked via misc A/B data)
   │  1. reads kernel DTB from the RSCE resource image (boot_x "second") → VOP2, eDP, panel, backlight
   │  2. reads display mode from baseparameter (p16)
   │  3. reads the BMP from the logo partition (p17) → framebuffer → eDP panel
   │  4. hands the framebuffer to the kernel ("rockchip,drm-logo" reserved memory)
   ▼
 Android kernel 4.19   keeps showing the U-Boot framebuffer until the boot animation starts
```

So the **Rockchip vendor U-Boot (2017.09), in ZTE's build** puts the logo on the screen. It uses the
Rockchip DRM display stack (`rockchip_display` / VOP2 / analogix eDP / `simple-panel`). Both slots'
U-Boot builds (uboot_a 2024-05-29, uboot_b 2024-07-31) contain the same logo code.

Evidence from the U-Boot binary (`strings w600d-backup/uboot_a.img`):

| String | Meaning |
|---|---|
| `failed to display uboot logo`, `failed to load bmp %s`, `failed to decode bmp %s` | U-Boot's own BMP loader/decoder |
| `logo.bmp`, `logo_kernel.bmp`, `logo,uboot`, `logo,kernel` | two logo slots: one shown by U-Boot, one handed on for the kernel |
| `rockchip,drm-logo`, `logo,offset/width/height/bpp/ymirror` | the framebuffer is passed to the kernel through reserved memory |
| `rockchip_get_baseparameter`, `vop2_initial`, `rockchip_panel_probe`, `edp_name=guoxian-30NK` | display init: baseparameter, VOP2, panel table |
| `battery_0..5.bmp`, `battery_fail.bmp`, `Enable charge animation display` | the charge animation, read from the RSCE resource image |

## 2. Why writing p17 works

- Stock Rockchip U-Boot normally takes `logo.bmp`/`logo_kernel.bmp` from the **resource image**.
  ZTE's build takes them from the **`logo` partition** instead. The resource image has a different
  logo (ZTE "中兴云电脑"), yet the screen showed China Mobile, and changing p17 changed the
  screen. That experiment proves it.
  Rockchip's code doesn't do this by default. The bare string `logo` isn't visible in `strings`
  (most likely merged into the tail of `rockchip,drm-logo`), so the exact function wasn't traced.
  The result is what matters.
- p17 isn't signed or covered by AVB (vbmeta only covers boot/system/vendor…), so nothing rejects
  a modified image.
- The BMP header was kept byte-for-byte. Only pixel bytes changed (94 800 bytes differ), so the
  size, format and offsets U-Boot expects are unchanged.

### Layout of p17 (32 MiB)

```
 offset     size           content
 0x000000   6 220 854 B    BMP #1  (U-Boot logo, "logo,uboot")
 0x5eee00   6 220 854 B    BMP #2  (identical copy; kernel logo, "logo,kernel")
            rest           zeros
```
0x5eee00 = 6 220 854 rounded up to the next 512-byte sector. Both copies were patched, so the
U-Boot and kernel stages show the same picture.

### The BMP format quirk

Header: `BM`, 54-byte header, 1920 × **+1080**, 24 bpp, no compression. A positive height means
"rows stored bottom-up", **but the pixel rows are really stored top-down**. Opened on a Mac or PC,
the stock logo looks upside down. U-Boot shows it the right way up, so when editing,
**write row 0 = top of the screen**. (Probably ZTE's code, or the VOP y-mirror setting,
cancels out the sign. Not traced. The rule above is what was tested.)

To preview a p17 BMP correctly on the Mac: `sips -s format png -f vertical file.bmp --out p.png`.

## 3. Tools

- `tools/make-logo.py <stock logo.img> <out.img> [TEXT]`: copies the stock image, draws TEXT
  (5×7 pixel font scaled ×10, orange, centered at y = 820) into the pixels, and writes both copies.
  It also writes `<out.img>.bmp` for previewing. The font only has the glyphs `W 6 0 D L I N U X`
  and space. Add more in `FONT` if needed.
- `logo/logo_w600d.img`: the image that was flashed.
- `w600d-backup/logo.img`: the stock partition (the undo).

```sh
cd /Users/K/a
python3 -I tools/make-logo.py w600d-backup/logo.img logo/logo_w600d.img
sips -s format png -f vertical -Z 640 logo/logo_w600d.img.bmp --out /tmp/logo_new.png   # preview
```

Using a completely different picture: make a 1920×1080, 24-bit, uncompressed BMP stored top-down,
keep the stock 54-byte header, and put it at both offsets (zeros elsewhere). Keep the file the
same size (6 220 854 B). Other sizes/bit depths may work, but that hasn't been tested.

## 4. Flashing (from Android, root via adb)

```sh
S=10.0.0.66:5555
adb -s $S shell su 0 id                                     # uid=0(root)
adb -s $S shell su 0 ls -l /dev/block/by-name/logo          # -> /dev/block/mmcblk2p17
adb -s $S push logo/logo_w600d.img /data/local/tmp/
shasum -a 256 logo/logo_w600d.img
adb -s $S shell sha256sum /data/local/tmp/logo_w600d.img    # must match
adb -s $S shell "su 0 dd if=/data/local/tmp/logo_w600d.img of=/dev/block/by-name/logo bs=1048576"
adb -s $S shell "su 0 sync"
adb -s $S shell "su 0 sh -c 'dd if=/dev/block/by-name/logo bs=1048576 2>/dev/null | sha256sum'"   # must match
adb -s $S shell rm /data/local/tmp/logo_w600d.img
```
Then power off completely and power on.

**`of=` must be exactly `/dev/block/by-name/logo`.** Any other target overwrites a different partition.

### Undo
```sh
adb -s $S push w600d-backup/logo.img /data/local/tmp/
adb -s $S shell "su 0 dd if=/data/local/tmp/logo.img of=/dev/block/by-name/logo bs=1048576"
adb -s $S shell "su 0 sync"
```
Without Android: `dd` the same file to p17 from Linux, or via U-Boot `ums 0 mmc 0`, or use
`rkdeveloptool wl 4700160 w600d-backup/logo.img` (see `debrick.md`).

### Risk
Low. If p17 is broken, the expected worst case is "no logo"; booting doesn't depend on it. The
eDP setup comes from the RSCE resource image, not from p17.

## 5. What this means for the Linux plan

- Keep **p17 `logo`** (and p16 `baseparameter`) when wiping Android. We now control the logo there.
- The charge animation (`battery_*.bmp`) and the eDP config (`rk-kernel.dtb`) still come from the
  **RSCE**. Keep a `resource` partition, see `usb-boot.md` §2a and `partitions.md` §5. ZTE's own custom installer uses the same `dd … of=/dev/block/by-name/logo` (`fw-v2.25.md` §3.5), and a ZTE custom update with `UpdateLogo=1` would overwrite our logo.
- Writing p17 was the first successful write to the eMMC, and it confirms the adb-root `dd` workflow
  for the later steps.
