# U-Boot for the ZTE W600D SE (RK3568), chain-loaded from a USB stick

Mainline U-Boot (2027.01-rc1) with a shell **on the laptop's own screen and
keyboard**, plus the [`typewriter`](howto-typewriter-uboot.md) editor (Nano-style,
with Wubi Chinese input). It runs from a USB stick. **Nothing new is written to the
eMMC**: unplug the stick and the laptop boots Android as before.

```
BootROM → SPL → vendor U-Boot 2017.09 (uboot_a, env patched once: USB first)
  → USB stick: boot.scr  → loads u-boot-w600d.bin @0x00800000 + w600d-chain.bin @0x10000000
  → w600d-chain.bin: IRQs off, caches/MMU off, jump 0x00800000
  → mainline U-Boot: takes over the lit eDP panel, USB keyboard → "=>" prompt
```

Tested on one W600D SE (uboot_a v15 → stick → U-Boot → typewriter, 2026-11-06; board `rk3568_r_w600d2`, kernel DTB `rk3568-w600dse-pvt-cs`,
vendor uboot_a built 2024-05-29). Other W600D variants may differ (GPIOs, panel).

> **Warning.** Step 1 rewrites the vendor bootloader partition `uboot_a`. The A/B
> fallback to slot B recovered every failed attempt during development, but you
> can still brick the laptop. Have a full backup and know the MaskROM procedure
> before you start. You do this at your own risk.

## Contents
| Path | What |
|---|---|
| `build.sh` | fetch U-Boot at the pinned commit, patch, build, make the stick files (Linux or macOS) |
| `patch-u-boot.sh [--am\|--check] <u-boot-dir>` | apply the patch series + copy `typewriter/` into `cmd/typewriter/`; safe to re-run |
| `patches/u-boot/0001…0005-*.patch` | `git format-patch` series: USB-keyboard Ctrl chords, video alpha, VOP2 takeover driver, typewriter hooks, board DT + defconfig |
| `typewriter/` | the typewriter editor (goes to `cmd/typewriter/`) |
| `patches/typewriter/w600d-changes.patch` | what was changed in typewriter against upstream (for reference; already applied in `typewriter/`) |
| `chain/chain.S` | the 272-byte cache/MMU-off shim |
| `chain/boot.cmd`, `boot-nc.cmd` | the stick's boot script (with / without comments; `boot-nc.cmd` is what gets built) |
| `chain/mkscr.py` | wraps the script as `boot.scr` **for this vendor U-Boot** (see Notes) |
| `vendor-env/w600d-uboot-a.sh` | step 1 over adb: backup, patch, flash, verify, check, undo |
| `vendor-env/patch-uboot-env.py` | patches the default environment of a `uboot_a` dump (used by the script) |
| `vendor-env/uboot_a-usbfirst.img` | stock uboot_a (2024-05-29) already patched |
| `prebuilt/` | the stick files as tested (`SHA256SUMS`) |
| `howto-typewriter-uboot.md` | using the editor, and what was changed for this board |

## Step 1 (once): make the vendor U-Boot try USB first
The stock `uboot_a` runs `boot_fit; boot_android; run distro_bootcmd`. Android
always boots, so the USB scan is never reached. The fix is to reorder `bootcmd`
in the default environment that is built into `uboot_a`:
```
bootcmd=run bootcmd_usb0;run bootcmd_mmc0;usb stop;boot_fit;boot_android ${devtype} ${devnum};run distro_bootcmd;
```

Requirements:
- Bootloader unlocked, root in Android (`su`), adb.
- You boot from **slot A**, and slot B is bootable (it is the rescue).
- Your `uboot_a` must contain the distro boot variables. **Newer ZTE OTAs
  (e.g. V2.25, 2025) ship a U-Boot with `boot_android` only. Don't install
  ZTE OTAs.** Check with `strings uboot_a.img | grep bootcmd_usb0`.

**With the script** (Linux/macOS, adb connected, Android running on slot A):
```sh
vendor-env/w600d-uboot-a.sh install          # backup -> patch -> confirm -> dd -> read-back -> arm A/B fallback
vendor-env/w600d-uboot-a.sh check            # after the reboot
vendor-env/w600d-uboot-a.sh flash <backup-dir>/uboot_a.img     # undo
```
`install` saves `uboot_a`, `uboot_b` and `misc` to `w600d-uboot-backup-<date>/`, patches your own
`uboot_a` dump, and for the tested stock image (`2375420f…`) checks the result against the expected
`36e264b1…`. A pre-patched image of that is in `vendor-env/uboot_a-usbfirst.img`
(`w600d-uboot-a.sh flash vendor-env/uboot_a-usbfirst.img`). Only use it if your dump is that stock image.
`-s <serial>` selects the adb device; `YES=1` skips the prompts.

**By hand:**
```sh
# 0. Back up. Keep these files safe (also back up the rest of your eMMC).
adb shell "su 0 dd if=/dev/block/by-name/uboot_a of=/data/local/tmp/uboot_a.img bs=1048576"
adb shell "su 0 dd if=/dev/block/by-name/uboot_b of=/data/local/tmp/uboot_b.img bs=1048576"
adb pull /data/local/tmp/uboot_a.img; adb pull /data/local/tmp/uboot_b.img
strings uboot_a.img | grep -m1 'U-Boot 2017.09 ('     # ours: May 29 2024
strings uboot_a.img | grep -c bootcmd_usb0             # must be > 0

# 1. Patch (offline, on the PC). The tool checks the FIT hash and patches only the
#    first of the two FIT copies.
python3 -I vendor-env/patch-uboot-env.py uboot_a.img uboot_a-usbfirst.img
#    Stock 2375420f37c0d1c4… gives 36e264b12dc757a2…; bootdelay stays at the stock 0.

# 2. Write uboot_a ONLY. Check of= twice.
adb push uboot_a-usbfirst.img /data/local/tmp/
adb shell "su 0 dd if=/data/local/tmp/uboot_a-usbfirst.img of=/dev/block/by-name/uboot_a bs=1048576"
adb shell "su 0 sync"
adb shell "su 0 sh -c 'dd if=/dev/block/by-name/uboot_a bs=1048576 2>/dev/null | sha256sum'"
#    must equal: shasum -a 256 uboot_a-usbfirst.img

# 3. Arm the A/B fallback (slot A unverified, with tries; B stays bootable), then reboot.
adb shell "su 0 bootctl set-active-boot-slot 0"
adb reboot
```
Without a stick, Android should boot normally (slightly later than before: the USB scan).
**Boot Android once (no stick) right after flashing.** Android then marks slot A successful again.
Until it does, every boot, including stick boots, uses one of slot A's 7 tries, and at 0 the laptop
switches to slot B (stock U-Boot, no USB boot). `w600d-uboot-a.sh check` should show `0f 00 01 00`.
- **Boot loop:** power-cycle and leave it. After about 7–8 failed boots the vendor
  U-Boot gives up slot A and boots slot B (the stock U-Boot).
  Then restore your backup: `dd if=uboot_a.img of=/dev/block/by-name/uboot_a`, and run `bootctl set-active-boot-slot 0`.

**Never write a mainline U-Boot into `uboot_a`.** SPL only falls back to slot B
when the FIT fails to *load*. A loadable but broken U-Boot leaves only MaskROM recovery.

## Step 2: build (or use `prebuilt/`)
Linux (Debian/Ubuntu):
```sh
sudo apt install gcc-aarch64-linux-gnu make bison flex libssl-dev device-tree-compiler python3 git bc
./build.sh
```
macOS (Apple Silicon or Intel):
```sh
brew install aarch64-elf-gcc aarch64-elf-binutils make bison openssl@3 dtc
./build.sh
```
`build.sh` clones `https://source.denx.de/u-boot/u-boot.git` into `./u-boot` at
`709a97a05df66e394f40d249105d0baade46f107`. Set `U_BOOT_DIR` to use an existing
checkout, and `CROSS_COMPILE` to use another toolchain. The result is in `out/stick/`.

Manual build, in your own U-Boot checkout at that commit:
```sh
/path/to/u-boot-zte-w600d-se/patch-u-boot.sh .     # or --am for one commit per patch
make CROSS_COMPILE=aarch64-linux-gnu- zte-w600d-chain-rk3568_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- NO_PYTHON=1 -j8 u-boot.bin
```

## Step 3: the stick
MBR partition table, partition 1 FAT32. Copy `boot.scr`, `u-boot-w600d.bin`
and `w600d-chain.bin` to the root. Other files on the stick don't matter.
On macOS, run `dot_clean /Volumes/<stick>` before ejecting.
Then use the **right-side USB-A port** (EHCI). The left-side port is the OTG
controller, and the vendor U-Boot did not boot from it in our tests.

## Step 4: boot
Power on with the stick in place. You should see: the logo, then about 3 s of
vendor USB scan, then the screen goes black for a moment, then the U-Boot banner
in large text, a `usb tree` listing, and `=>`. Type on the laptop keyboard.
Useful commands: `typewriter`, `ls usb 0:1`, `usb tree`, `mmc info`, `bdinfo`, `reset`.
Unplug the stick before `reset` if you want Android.

The environment is not saved (`ENV_IS_NOWHERE`): nothing you set in U-Boot
touches the eMMC. Commands like `mmc write`, `gpt`, `ums` and `rockusb` are
included and **can** write the eMMC if you type them.

## Troubleshooting
To debug from Android, the boot script appends markers to the kernel command
line: `adb shell su 0 cat /proc/cmdline | tr ' ' '\n' | grep w6`.

| What you see | Meaning |
|---|---|
| Logo → Android, as before | Step 1 isn't active, or the script/load failed. No `w6ub=1`: `boot.scr` never ran (wrong port, not FAT32 partition 1, or a `mkimage` script instead of `mkscr.py`). `w6ubload=…` + `w6shim=…` but `w6ubfail=1`: `go` was not reached |
| Logo stays, hangs | the shim or mainline U-Boot died before video came up. Hold power, **unplug the stick**, boot Android. Serial: UART2, 1500000 8N1 |
| Black screen, hangs | the display was taken over, but the console didn't come up |
| `=>` but no keyboard | look at `usb tree` above the prompt: no `258a:0001` means power or port (GPIO3_A3, see Notes). An external USB keyboard on the right-side port also works |
| Text mirrored / red-blue swapped | the panel window setup differs from ours. See `rk3568_vop2_takeover.c` (y-mirror, `WIN_RB_SWAP`) |

## Notes: why it works this way
- **Display:** mainline U-Boot has no RK3568 VOP2 driver, and the vendor
  framebuffer is a 24-bpp boot logo. `rk3568_vop2_takeover.c` finds the VOP2
  window the vendor U-Boot enabled (on this laptop: Smart0 → VP1 → eDP, with its
  address in the vendor `drm-logo` memory `0x7df00000`). It reads the resolution from
  `DSP_INFO` and points the window at a new ARGB8888 framebuffer, with y-mirror and
  RB swap off, then latches it with `REG_CFG_DONE`. The CRTC, eDP, panel power and backlight stay as the vendor set them.
  VOP2 has no XRGB format, so `video-uclass.c` sets alpha `0xff` on 32-bpp colours.
- `CONFIG_SYS_MEM_TOP_HIDE=0x2100000` keeps U-Boot's relocation below the vendor
  logo and cubic-LUT memory, which the VOP may still be reading.
- **Keyboard:** `258a:0001`, low-speed, on the USB2 port of xHCI `fd000000`
  (usb2phy0 host). Its power switch **GPIO3_A3** is turned on only by Android's ZTE
  driver, so the DT turns it on with a `gpio-hog`.
- **Shim:** the vendor `go` jumps with MMU and D-cache on. Mainline U-Boot builds its own page
  tables and relocates over memory the old ones may use. `chain.S` cleans and
  invalidates the caches (set/way), turns the MMU and caches off at EL2 or EL1,
  invalidates the I-cache and TLBs, and then jumps.
- **`usb stop` before `go`:** stops the vendor's USB DMA before mainline resets the controllers.
- **`boot.scr`:** this vendor U-Boot's `source` expects the image-length table
  to end with `0xFFFFFFFF`, not `0`. A standard `mkimage -T script` image runs
  garbage, so use `chain/mkscr.py`.
- Vendor bootloader rules: no `if … fi` directly in `bootcmd` (a later `boot_android`
  then resets the board). `&&` is fine. Keep `boot.scr` flat.
- **Ctrl keys:** U-Boot's `usb_kbd` sent Ctrl + any key as `scancode - 3` (Ctrl-Space came out as `)`). It is fixed to send terminal control codes, see `howto-typewriter-uboot.md`.
- Mainline's clock driver re-locks APLL/CPLL/GPLL. The eDP pixel clock is on VPLL,
  which is left alone.

## License
U-Boot changes, the shim and the scripts: GPL-2.0+ (same as U-Boot).
`typewriter/`: GPL-2.0+, by its author (<https://github.com/scateu/u-boot-typewriter>).
Its embedded font is a subset of GNU Unifont (GPL-2.0+ with the font embedding
exception / OFL-1.1). See `typewriter/README-upstream.md` for the Wubi table's origin.
