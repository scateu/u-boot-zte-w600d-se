# HOWTO: U-Boot shell on the laptop screen + keyboard (mainline U-Boot chain-loaded from USB)

Status (2026-11-06):
- Run 1: ✅ **`=>` prompt on the laptop screen** (VOP2 takeover works). ❌ Keyboard dead.
  Cause (from Android, `/sys/kernel/debug/gpio`): the keyboard's power pin **GPIO3_A3** (`gpio-keyboarpower`)
  is driven high only by Android's ZTE `zte-gpio-ctl` driver, never by the vendor U-Boot. The keyboard is
  `258a:0001`, **low-speed**, directly on xHCI `fd000000`'s USB2 root port (bus 7, no hub), interface 0 = HID boot keyboard.
- Run 2: DT gpio-hog drives GPIO3_A3 high (+ `CONFIG_GPIO_HOG`), `preboot` adds `usb tree` → **keyboard works ✅**
  (`0035f6ad…`, kept as `b/stick-prev/u-boot-w600d-kbd.bin`).
- Run 3 ✅: + the user's `typewriter` editor in `u-boot/cmd/typewriter/` (default `usb 0:1 a.txt`,
  RK3399 power-save code behind new `TW_RK3399_POWERSAVE`, restored no-EC stub). 1.8 MB. User: Ctrl-Space gave `)` → `common/usb_kbd.c` Ctrl chords fixed (terminal codes, NUL for Ctrl-Space): `3d596f72…` → **typewriter runs, Ctrl-Space toggles Wubi ✅**.
- Publishable package: `../u-boot-zte-w600d-se/` (README, build.sh, patch, typewriter, shim, env tool, prebuilt). Not published yet.
Nothing is written to the eMMC. Unplug the stick and the laptop boots Android as before.

## Chain
```
BootROM → idbloader/SPL → uboot_a (vendor 2017.09, patched env v13/v14)
  → bootcmd_usb0 → stick FAT p1 /boot.scr (vendor script header, mkscr.py)
     load u-boot-w600d.bin → 0x00800000, w600d-chain.bin → 0x10000000, usb stop, go 0x10000000
  → w600d-chain.bin: IRQs masked, D-cache clean+inv (set/way), MMU + D-cache off, again, I-cache/TLB inv, jump 0x00800000
  → mainline U-Boot 2027.01-rc (`../u-boot`, defconfig zte-w600d-chain-rk3568)
     display: VOP2 takeover (panel stays lit), preboot: usb start + stdin usbkbd + stdout vidconsole
     bootdelay=-1 → `=>` prompt
```

## Files
| Where | What |
|---|---|
| `b/stick/` | what's on the stick: `boot.scr` (`47374c83…`), `u-boot-w600d.bin` (`3d596f72…`), `w600d-chain.bin` (`fccb0bfa…`), `SHA256SUMS` |
| `b/chain/chain.S` | the shim (272 bytes). `-DTARGET=` changes the jump address |
| `b/chain/boot.cmd` | the script with comments. `boot-nc.cmd` is the same without comments, and that's what goes into `boot.scr` |
| `b/scripts/mk.sh` | macOS build wrapper: `b/scripts/mk.sh <outdir> <targets>` (Homebrew `aarch64-elf-gcc`, bison; `NO_PYTHON=1`; skips the bash-4 `check-local-export`) |
| `u-boot/configs/zte-w600d-chain-rk3568_defconfig` | the config |
| `u-boot/arch/arm/dts/rk3568-w600d.dts` (+ `-u-boot.dtsi`) | minimal board DT: UART2, eMMC, xHCI fd000000 (keyboard), EHCI/OHCI ×2, USB 5 V GPIO regulators (GPIO3_A0, GPIO0_C4), display-takeover |
| `u-boot/drivers/video/rockchip/rk3568_vop2_takeover.c` | the new video driver |
| `u-boot/drivers/video/video-uclass.c` | 32-bpp colours get alpha 0xff (VOP2 has no XRGB, only ARGB) |

Rebuild:
```sh
b/scripts/mk.sh w600d zte-w600d-chain-rk3568_defconfig u-boot.bin
cp b/w600d/u-boot.bin b/stick/u-boot-w600d.bin
cd b/chain && aarch64-elf-gcc -c chain.S -o chain.o && aarch64-elf-ld -Ttext=0x10000000 chain.o -o chain.elf \
  && aarch64-elf-objcopy -O binary chain.elf ../stick/w600d-chain.bin
python3 -I a/usb-demo/src/mkscr.py b/chain/boot-nc.cmd b/stick/boot.scr
```
Stick: MBR + FAT32 partition 1 (`HOWTO-usb-drive.md` §2), files in the root, `dot_clean`, eject.

## Why it's built like this
- **Mainline has no VOP2 driver**, and U-Boot's video layer can't use the vendor's 24-bpp logo buffer.
  So the driver finds the enabled VOP2 window (prefers one whose address lies inside the vendor
  `drm-logo` memory: on this board **Smart0 → VP1 → eDP**, `rockchip,primary-plane = 4`). It reads its
  size from DSP_INFO, then points it at a U-Boot framebuffer: ARGB8888, stride = width, y-mirror off
  (the vendor logo uses `logo,ymirror`), RB swap off, then `REG_CFG_DONE`. The CRTC, eDP, PHY,
  panel power and backlight are left exactly as the vendor U-Boot set them.
- **`CONFIG_SYS_MEM_TOP_HIDE=0x2100000`**: U-Boot relocates to the top of RAM. Hiding the top 33 MiB keeps
  it below 0x7df00000 (drm-logo + cubic LUT).
- **Shim instead of a plain `go` into U-Boot**: the vendor `go` jumps with MMU + caches on, and mainline
  U-Boot builds new page tables and relocates over memory the old tables may live in.
  Tested in QEMU (`virt,virtualization=on`, EL2, cortex-a55): QEMU U-Boot → shim → second U-Boot →
  prompt ✅. QEMU doesn't model caches, so the flush itself is only proven on hardware.
- **`usb stop` before `go`**: the vendor xHCI/EHCI must stop DMA before mainline resets them.
- Environment is `ENV_IS_NOWHERE`: `saveenv` can't write the eMMC. (`mmc write`, `gpt`, `ums`,
  `rockusb` exist but only do something when typed.)
- Mainline's CRU probe re-locks APLL/CPLL/GPLL to its defaults. The eDP pixel clock is on VPLL (untouched).
  Expect at most a one-frame flicker.

## Run it
1. Stick in the **right-side** port (EHCI, proven in run 5). Power on.
2. Expected: logo → (vendor scan, ~3 s) → screen goes **black** (takeover) → U-Boot banner in large
   text (16×32 font) → `usb start` scan → `=>`. Type on the laptop keyboard.
3. Useful first commands: `usb tree`, `mmc info`, `mmc part`, `bdinfo`, `meminfo`, `ls usb 0:1`, `reset`.

## Reading a failure
| What you see | Meaning |
|---|---|
| Logo → Android, as before | script didn't run or a load failed. `adb shell su 0 cat /proc/cmdline \| tr ' ' '\n' \| grep w6`: `w6ub=1` = script ran, `w6ubload=1b90c0` (typewriter build; `ea360` before) + `w6shim=110` = both loads OK, `w6ubfail=1` = `go` was not reached |
| Logo stays, hangs | the shim or mainline crashed before video came up. Hold power, **unplug the stick** (else it repeats), boot Android. Next step: UART2 at 1500000, or a marker build |
| Black screen, hangs | the takeover happened (window switched), console didn't come up, or the alpha/format guess is wrong |
| Text upside down / mirrored | y-mirror: flip `SMART_CTRL1_YMIRROR` handling in the driver |
| Red/blue swapped | set `WIN_RB_SWAP` instead of clearing it |
| `=>` visible but keys don't work | read the `usb tree` printed above the prompt: no `258a` device → power/port problem (GPIO3_A3, usb2phy0 host port); device listed → usbkbd/polling problem. A USB keyboard in the right-side port is the fallback |

## Android GPIO state with a working keyboard (2026-11-06)
| Pin | Android label | State |
|---|---|---|
| GPIO3_A3 (99) | `gpio-keyboarpower` (ztegpioctl) | out **hi** |
| GPIO3_A1 (97) | `hid-reseten` (touchpad 4-002c) | out hi |
| GPIO3_B4 (108) | `hid-power` | out hi |
| GPIO3_A0 (96) | `vcc5v0_host` | out hi |
| GPIO0_C4 (20) | `vcc5v0_otg` | out hi |
| GPIO2_A1 (65) | `gpio-keyboardled` (active low) | out lo |
| GPIO0_B0 (8) | `gpio-usb2hubrst` in DT | unclaimed, not used |
