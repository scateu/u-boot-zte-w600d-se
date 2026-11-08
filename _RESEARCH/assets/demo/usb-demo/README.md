# W600D USB boot demo

Proves that the laptop boots from a USB stick (uboot_a v13: `run bootcmd_usb0` first), and
shows something on screen while doing it. **Nothing is written to the eMMC.** Unplug the stick and
the laptop boots exactly as before.

## What you'll see (power on with the stick plugged in)
1. Logo (China Mobile + "W600D LINUX"), as always.
2. **~8 s: a rainbow band with "BOOTED FROM USB! * ZTE W600D * RK3568 …" scrolling** over the
   emblem, then "USB BOOT OK / STARTING ANDROID..." for 3 s. This is `w600d-demo.bin`, a 6 KB
   bare-metal ARM64 program started by U-Boot with `go`.
3. **Battery animation 0 → 5** (1 s each). This is the vendor U-Boot's `rockchip_show_bmp`,
   called from `boot.scr`. The stock boot never shows it at power-on, so **seeing it = the USB
   script ran**, even if step 2 didn't work.
4. Maybe a line of text (`lcdputs`, untested), then Android boots as usual.

Without the stick: logo → Android, about 3 s slower than stock (v13's `bootdelay=3`).

## Prepare the stick (on the Mac)
The stick must have an **MBR** partition table with **FAT32 as partition 1**. U-Boot scans
partition 1 when none is marked bootable. macOS's default GPT layout puts a hidden EFI partition first.

```sh
diskutil list                                   # find the stick, e.g. /dev/disk4 — CHECK THE SIZE
diskutil eraseDisk FAT32 W600D MBRFormat /dev/diskN     # ERASES the whole stick
cp usb-demo/stick/boot.scr usb-demo/stick/w600d-demo.bin /Volumes/W600D/
dot_clean /Volumes/W600D; diskutil eject /Volumes/W600D
```
The files must be in the root (or in `/boot/`).

## If something goes wrong
| Symptom | Meaning / action |
|---|---|
| Logo → Android, no rainbow, no batteries | the script wasn't found: stick not FAT32/MBR, file not in root, or the stick isn't `usb 0` (e.g. the 5G modem enumerates as a USB disk first). Try another port. |
| Batteries but no rainbow | the demo didn't find the logo in RAM (returns 1) or `load` failed. The USB boot itself works. |
| Hang / black screen / reset loop | the demo crashed (likely cause: instruction cache not cleaned after `load`, since the vendor U-Boot has no `dcache flush` command). **Unplug the stick and hold power**. Slot A stays marked successful, so it just boots normally again. |

## How it works
- `boot.scr` (legacy uImage script, built from `src/boot.cmd` by `src/mkscr.py`): flat command list
  (no `if`, see HOWTO-patch-uboot.md §8). `load … 0x10000000 w600d-demo.bin && go 0x10000000`, then
  the battery BMPs. When it returns, U-Boot prints `SCRIPT FAILED: continuing...` (normal) and
  continues with eMMC → `boot_android`.
- `w600d-demo.bin` (`src/demo.c`):
  - **Finds the framebuffer by content:** searches the `drm-logo` reserved memory
    (0x7df00000, 32 MiB, from the live DT) byte by byte for 64 pixels of the emblem's most colourful
    row, confirms a second row, and handles top-down/bottom-up layouts. It draws into every copy found (max 4).
  - Writes only the band rows (y 250–689), then `dc cvac` (clean to RAM) so the display controller sees them.
  - Uses the ARM generic timer for timing, no libc, no writable data. Returns 0 to U-Boot.
- Build: `src/build.sh` (clang `--target=aarch64-none-elf`, plus `src/link.py`: a 100-line linker,
  since macOS has no ELF linker). `src/mksig.py` takes the signature from `logo/logo_w600d.img`.
  **If the logo (p17) changes, rebuild.**
- Host test: `cd src && cc -DHOST -O2 test-host.c -o /tmp/t && /tmp/t ../../logo/logo_w600d.img /tmp/out.bmp` runs
  the same code on a fake memory image (BMP file at +0, pixel copy 4 KiB-aligned after it).
  Preview with `sips -f vertical out.bmp`.

Next steps after this works: replace the demo with a real kernel (`extlinux/extlinux.conf` on the
stick, picked up by the same scan), or chain-load an RK3568 U-Boot with `typewriter`.

## Test log

### 2026-11-06, run 1: ❌ "didn't work"
- Stick: 8 GB, MBR, FAT32 `ZTE_TEST` = partition 1 (disk5s1), files in the root, hashes verified
  after copying: `boot.scr` `eb7311b8…`, `w600d-demo.bin` `1fadd856…`. uboot_a = v13 (`b94f333f…`).
- Result: **logo → Android, no battery animation** (outcome 1: boot.scr never ran). No loop:
  slot A, successful, ZTE counter 0x6f→0x74.
- **Cause: the stick was on the OTG controller, which U-Boot doesn't use as a host.** Android shows:

  | Controller | Device in Android | vendor U-Boot DT (`uboot_a` FIT `fdt`, 0x19d200) |
  |---|---|---|
  | `fcc00000.dwc3` (usbdrd, USB3 OTG) | **stick** 346d:5678 "Disk 2.0" | `dr_mode = "otg"`: Rockchip U-Boot uses it as a gadget (rockusb/fastboot), not scanned by `usb start` |
  | `fd000000.dwc3` (usbhost, USB3) | laptop keyboard 258a:0001 | `dr_mode = "host"` → scanned |
  | `fd880000` EHCI | HD WebCam 1bcf:2ced | — |

  Inferred from the DT and how Rockchip's U-Boot handles OTG ports; not yet proven by a run on `fd000000`.
- **Port map (Android, 2026-11-06):**

  | Physical port | Controller | Type | In run 1 |
  |---|---|---|---|
  | **right side** | `fd800000` EHCI (`usb_host0_ehci`) | USB 2.0 | — |
  | other port (left?) | `fcc00000` dwc3 (usbdrd, OTG) | USB 3 | stick was here → not booted |
  | internal | `fd000000` dwc3 (usbhost) | USB 3 | laptop keyboard |
  | internal | `fd880000` EHCI | USB 2.0 | HD WebCam |
- Correction: the vendor U-Boot switches to the **kernel DTB** (boot_a resource) after early
  init (`Failed to get kernel dtb`), and that one has `fcc00000` `dr_mode = "host"` and both EHCIs
  enabled. So the OTG theory above is unproven; why run 1 didn't see the stick is unknown.
- Next: run 2 with the stick on the right port (EHCI). If it still doesn't run, a diagnostic
  v14 that appends `&&`-guarded markers (`usb start`, `usb dev 0`, `fstype`, `test -e boot.scr`)
  to `bootargs`, read back from `/proc/cmdline` in Android.
- Old next step: put the stick in the port that lands on `fd000000` (check in Android:
  `/sys/bus/usb/devices/*` → `readlink`). If no external port is on `fd000000`: patch the U-Boot
  DTB `dr_mode` of `usb@fcc00000` to `"host"` (new uboot_a; costs U-Boot rockusb on that port).
- What each outcome would mean:

  | Seen | Cause to look at |
  |---|---|
  | logo → Android, no batteries | script not found/run: `usb 0` isn't the stick (5G modem / camera enumerate first?), USB port, or `usb_boot` fails. The v9 `usb tree` output was never seen. To find out, we need U-Boot's output: on-screen text (not working yet) or a serial adapter. |
  | batteries, no rainbow | USB boot works. Demo: logo not found in drm-logo RAM (wrong region/format/orientation), or `go` returned at once. |
  | hang / reset loop with the stick | demo crashed: stale I-cache after `load` (no cache flush), or the RAM scan touched something unmapped. |

### 2026-11-06, run 2: right-side port (EHCI), uboot_a v13: ❌ nothing seen
### 2026-11-06, run 3: same port, uboot_a v14-diag: `w6dbg=us.d0..fat..s0...usb0`
U-Boot sees the stick as `usb 0`, FAT on partition 1, `/boot.scr` present, and the distro scan
selects it. So the problem is in running `boot.scr` (or its visible effect), not in USB.
Next: a marker `boot.scr` (`setenv bootargs ${bootargs} w6scr=…` after each step), read back from
`/proc/cmdline`.

### Run 4 (prepared): marker boot.scr
`src/boot-diag.cmd` → stick `boot.scr` (`5b2276b2…`), no comments. Each step appends to `bootargs`:
`w6scr=1` (script started) · `w6load=<size>` (demo loaded, expect 181a = 6170) · `w6go=0` (demo returned 0 =
logo found and drawn) · `w6back=1` · `w6bmp=1` (battery_2 shown) · `w6end=1`.
Read: `adb shell su 0 cat /proc/cmdline | tr ' ' '\n' | grep w6`. The normal stick script stays at `src/boot.cmd`.
(Android had mounted the stick and created `Android/` and `LOST.DIR/`: harmless.)

### Run 4 result: no battery picture, no `w6*` markers from the script (only v14's `w6dbg=us.d0..fat..s0...usb0`)
→ The script never ran. **Root cause (disassembly of the vendor `source`, `0xa07e60`):** for legacy
scripts it checks magic, header CRC, data CRC (if `verify`) and type 6, takes the length from the
first table word, then **skips table words until one equals `0xFFFFFFFF`** (`0xa07f4c`:
`ldr w2,[x0],#4; cmn w2,#1; b.ne`), while mainline/mkimage end the table with `0`. With a
standard `boot.scr` it runs past the table into memory and executes garbage, silently.
**Fix:** `src/mkscr.py` now writes `len, 0xFFFFFFFF, text`. Such scripts are vendor-only. (A
`mkimage`-made `boot.scr`, e.g. from a distro image, will NOT work with this U-Boot. Use
`extlinux/extlinux.conf` for Linux, which goes through `sysboot` instead.)
Rebuilt: `boot.scr` `9f1d50d4…` (demo), `boot-diag.scr` `8a152a2c…` (markers).

### Run 5 (prepared): boot-diag.scr as boot.scr on the stick
Stick: `boot.scr` = `boot-diag.scr` (`8a152a2c…`, 0xFFFFFFFF table end), right-side port, uboot_a v14.
**Result: ✅ the rainbow banner showed. USB boot + `source` + `load` + `go` + the demo all work.**
The battery picture after it (`rockchip_show_bmp battery_2.bmp`, 3 s) did **not** show.
`rockchip_show_bmp` is unreliable (v9: only 2 of 5 shown). Markers (`w6go`, `w6bmp`, `w6end`):
adb was offline, read them on the next boot that still has this stick in. Android booted afterwards.
