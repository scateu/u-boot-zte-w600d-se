# HOWTO: patch the stock U-Boot (uboot_a) environment

**Status (2026-11-06): working.** uboot_a boots a USB stick first (`boot.scr` / `extlinux.conf`),
then eMMC extlinux, then Android exactly like stock. Proven: the USB demo (`HOWTO-usb-drive.md`) ran from
the stick and drew on screen, then Android booted. Slot B (`uboot_b`, Android B) is untouched stock = rescue.

## 0. Quick guide

### What runs
```
power on → BootROM → idbloader (DDR init + SPL)  → uboot_a FIT (U-Boot 2017.09 + TF-A + OP-TEE)
U-Boot: init, logo (p17), A/B tries−1 if slot unverified, bootdelay 3 (serial only)
bootcmd (v13):
  run bootcmd_usb0      USB stick: /extlinux/extlinux.conf, /boot/extlinux/extlinux.conf, /boot.scr, /boot/boot.scr
  run bootcmd_mmc0      eMMC: same files (for Linux on eMMC later); also resets devtype=mmc devnum=0
  usb stop; boot_fit; boot_android ${devtype} ${devnum}      Android, as stock
  run distro_bootcmd    only if Android fails
```

### The images
| Image | bootcmd | Use |
|---|---|---|
| `uboot-patch/v13-usb-first.img` (`b94f333f…`) | as above | **recommended** |
| `uboot-patch/v14-diag.img` (`8de8c9f8…`) | v13 + USB checks → `w6dbg=…` in `/proc/cmdline` | debugging USB; **on the device now** |
| `w600d-backup/uboot_a.img` (`2375420f…`) | stock `boot_fit;boot_android;run distro_bootcmd` | undo |

Rebuild v13 (the tool's default): `python3 -I tools/patch-uboot-env.py w600d-backup/uboot_a.img out.img`
(identical hash). Custom: add `VAR=VALUE …`: only those change; only existing variables; the env
block is fixed at 3643 bytes (free space by emptying `bootcmd_pxe=`, `bootcmd_dhcp=`, `partitions=`).

### Flash (Android running, adb over Wi-Fi, root via `su 0`)
```sh
tools/uboot-test.sh flash uboot-patch/v13-usb-first.img
#  push → verify hash → dd to /dev/block/by-name/uboot_a → read back + verify
#  → bootctl set-active-boot-slot 0 (slot A unverified, 7 tries) → adb reboot
tools/uboot-test.sh check          # after boot: slot, uboot_a hash, misc A/B bytes, ZTE boot counter
```
Expect `slot=_a`, the image's hash prefix, misc `0f 00 01 00 0e 00 01 00` (A successful again).
Manual commands, step by step: §6.

### If it goes wrong
- **Loops / black screen:** do nothing, or power-cycle. The vendor U-Boot decrements slot A's tries
  on every boot (`ab-tries.md`), so after ~7–8 resets it boots **slot B** by itself (Android B, the
  older build; `/data` is shared). Then restore: `tools/uboot-test.sh flash w600d-backup/uboot_a.img`.
- **Slot B doesn't take over:** MaskROM (`debrick.md`).

### Rules learned the hard way (test log §8)
1. **No `if` written directly in `bootcmd`.** Any top-level `if … fi` (even `if sleep 3;then setenv …;fi`)
   makes the later `boot_android` reset the board (v1, v2, v8, v11, v12). `if`/`for` inside scripts
   started with `run` (the distro scripts) are fine, and so is `&&`.
2. **Only put the vendor U-Boot in uboot_a.** SPL only counts down the A/B tries when **both** FIT
   copies fail to load. A foreign but loadable U-Boot (mainline, EVB) would never fall back to
   slot B (`ab-tries.md`).
3. `boot_fit` can't boot from USB (it reads the eMMC boot partition). USB must come **before**
   `boot_android`, because Android always succeeds.
4. `bootdelay` and Ctrl+C only work on the serial console (UART2, **1500000** baud). The laptop
   keyboard isn't up at that point. A keyboard Ctrl+C window would need `if`, see rule 1.
5. Debug without serial: append results to `bootargs` (`cmd && setenv x …;… setenv bootargs
   ${bootargs} tag=${x}`) and read `/proc/cmdline` in Android as root. `boot_android` keeps `bootargs`.
6. Never install ZTE OTAs: they replace uboot_a/uboot_b with a U-Boot without the distro boot.

---
Everything below is the background and history.

## 1. What changes

| Variable | Stock `uboot_a` (2024-05-29) | Patched |
|---|---|---|
| `bootcmd` | `boot_fit;boot_android ${devtype} ${devnum};run distro_bootcmd;` | `usb start;echo Ctrl+C: U-Boot prompt;if sleep 3;then run distro_bootcmd;boot_fit;boot_android ${devtype} ${devnum};fi;` |
| `boot_targets` | `mmc1 mmc0 usb0 pxe dhcp ` | `usb0 mmc0` |
| `bootcmd_pxe`, `bootcmd_dhcp` | DHCP/PXE scripts | empty (unused now; their bytes are needed for the longer `bootcmd`) |
| `bootdelay` | `0` | `3` (serial-only countdown, see §2) |

Boot flow after the patch:

```
U-Boot init, logo on screen
  └─ bootdelay 3                     serial Ctrl+C only (USB not up yet)
  └─ usb start                       laptop keyboard (USB 258a:0001) + any USB stick come up
  └─ "Ctrl+C: U-Boot prompt", sleep 3
        ├─ Ctrl+C pressed  → sleep fails → bootcmd ends → => prompt (screen + keyboard + serial)
        └─ no key          → distro_bootcmd: usb0, then mmc0 (extlinux.conf / boot.scr)
                              └─ nothing found → boot_fit → boot_android (Android, as before)
```

So: **stick plugged in = boot the stick, no stick = Android, Ctrl+C = U-Boot shell.**
Any stick with `/extlinux/extlinux.conf`, `/boot/extlinux/extlinux.conf`, `boot.scr` or
`/boot/boot.scr` on its bootable partition (or partition 1) will be booted. Unplug other sticks.

## 2. Why `sleep` and not `bootdelay`

`bootdelay` counts down **before** `bootcmd`, when USB isn't started yet. During that countdown only
the **serial** console can stop autoboot, and the laptop keyboard isn't attached yet. The usual fix
(`preboot=usb start`) has a side effect here: Rockchip's charge code skips the charge animation
whenever `preboot` is set (`Exit charge: due to preboot cmd '%s'`), so plugging in the charger while
off would boot the system instead of showing the charging screen.

`sleep` checks Ctrl+C (`ctrlc()`) and fails when it's pressed. Putting `usb start` + `if sleep 3`
at the start of `bootcmd` gives a 3-second window **after** the keyboard is up. Ctrl+C from the
laptop keyboard only works if U-Boot adds `usbkbd` to stdin on `usb start` (`stdin=serial,usbkbd`
suggests it does). If it doesn't, nothing breaks: the laptop just boots on, and serial Ctrl+C
still works.

`bootdelay=3` is set as well (user's choice, 2026-11-06). It adds a 3 s **serial-only** countdown
before `bootcmd`, so the whole wait is about 3 s + `usb start` + 3 s.

## 3. Why it is safe(ish): the failure paths

Facts from the binaries (checked 2026-11-06):

1. **Two FIT copies per U-Boot partition.** `uboot_a.img` contains the same FIT at `0x0` and
   `0x200000`. SPL (`Trying fit image at 0x%lx sector`) tries them in order.
   **Only copy 0 is patched. Copy 1 stays stock.**
2. **SPL checks hashes, not signatures.** SPL has `Bad hash value` / `## Checking …` and RSA code,
   but **no public key** (`rsa,modulus` absent) and verified-boot isn't fused (`secureboot` unset).
   The tool recomputes the `images/uboot/hash` sha256. The FIT's `signature` is now stale and
   unchecked. If SPL *did* reject copy 0 for any reason, it would fall back to stock copy 1.
3. **The change is only text in the default environment.** No code changes, so the patched U-Boot
   can't crash differently from stock. The worst realistic outcome is a typo in `bootcmd` leaving
   you at the `=>` prompt, which is recoverable (§6). Android is still booted by the same
   `boot_android` command.
4. **A/B as a second safety net.** `misc` @0x800 (`\0AB0`): today slot A prio 15 / tries 0 /
   successful 1, slot B prio 14 / tries 0 / successful 1. `bootctl set-active-boot-slot 0` marks A
   *unverified with tries* (AOSP default 7, successful 0). SPL logs
   `SPL: A/B-slot: %s, successful: %d, tries-remain: %d`, so it consumes tries. If A never reaches
   Android (which marks it successful again), SPL should switch to **slot B: stock uboot_b +
   Android B**. ⚠ That SPL decrements tries is inferred from the strings, not tested.

Diff check: 3483 bytes differ, all inside `0x190` (FIT hash) … `0xa21b1` (environment).
Bytes `0x200000–0x3fffff` are identical to stock.

## 4. Which U-Boot is running? (uboot_a vs uboot_b)

- `/proc/cmdline` → `androidboot.slot_suffix=_a`, and SPL loads `uboot` + slot suffix.
- Fingerprint: only `uboot_b` contains the string `androidboot.secureboot` (4×, 0× in uboot_a).
  The slot-B boot had `androidboot.secureboot=0` on its cmdline; today's cmdline doesn't →
  **uboot_a is running**.
- Partition hashes on the device = backups (`uboot_a` `2375420f…`, `uboot_b` `e524fd6b…`).
- After patching: the 3-second "Ctrl+C: U-Boot prompt" window (and +3–4 s boot time) shows the
  **patched copy** runs. No window at all means SPL fell back to copy 1 or to slot B.

## 5. Build

```sh
cd /Users/K/a
python3 -I tools/patch-uboot-env.py w600d-backup/uboot_a.img uboot-patch/uboot_a-w600d.img
# custom: python3 -I tools/patch-uboot-env.py w600d-backup/uboot_a.img out.img bootdelay=3 'boot_targets=usb0 mmc0'
shasum -a 256 uboot-patch/uboot_a-w600d.img
```
With arguments, **only** those variables are changed (defaults not applied). The tool refuses unknown
variables and oversize environments (fixed 3643-byte block).

## 6. Flash (from Android, root; run it yourself, the agent's dd is blocked)

```sh
S=10.0.0.66:5555
# 0. backups are good
cd /Users/K/a/w600d-backup && shasum -a 256 -c SHA256SUMS | grep uboot && cd ..
# 1. copy + verify
adb -s $S push uboot-patch/uboot_a-w600d.img /data/local/tmp/
adb -s $S shell sha256sum /data/local/tmp/uboot_a-w600d.img          # 6baad100…5786a19e3c
# 2. write uboot_a ONLY (uboot_b stays stock)
adb -s $S shell "su 0 dd if=/data/local/tmp/uboot_a-w600d.img of=/dev/block/by-name/uboot_a bs=1048576"
adb -s $S shell "su 0 sync"
adb -s $S shell "su 0 sh -c 'dd if=/dev/block/by-name/uboot_a bs=1048576 2>/dev/null | sha256sum'"   # 6baad100…
# 3. arm the A/B fallback: slot A unverified with tries, B stays bootable
adb -s $S shell "su 0 bootctl set-active-boot-slot 0"
adb -s $S shell "su 0 sh -c 'dd if=/dev/block/by-name/misc bs=2048 skip=1 count=1 2>/dev/null | od -A x -t x1 | head -1'"
#    expect slot A bytes "0f 07 00 00" (prio 15, tries 7, not successful), slot B "0e 00 01 00"
# 4. reboot and watch the screen
adb -s $S reboot
```

**Check `of=` twice: `uboot_a`, nothing else.**

### After the reboot
- **Ctrl+C on the laptop keyboard** during the ~3 s after the logo appears → `=>` prompt?
  - Yes → patched U-Boot runs **and** the keyboard works in U-Boot. Try `usb tree`, `help`, then
    `boot_android mmc 0` or `reset`.
  - Doesn't stop → wait. Android should boot ~4 s later than before.
- Back in Android: verify slot A is marked successful again (`bootctl is-slot-marked-successful 0`,
  or misc bytes `0f 00 01 00`). Android does this itself after a good boot.

### If it goes wrong
| Symptom | What to do |
|---|---|
| Stuck at `=>` (bad bootcmd) | type `boot_android mmc 0` (keyboard or serial), then restore stock (below) |
| Hangs / black screen every boot | power-cycle repeatedly (hold power ~10 s). After the tries run out SPL should start **slot B** (stock U-Boot + Android B). Then restore stock from Android and `bootctl set-active-boot-slot 0` |
| Slot B doesn't take over | serial at **1500000** baud (U-Boot's `baudrate=1500000`), or MaskROM: `debrick.md` |

### Undo
```sh
adb -s $S push w600d-backup/uboot_a.img /data/local/tmp/
adb -s $S shell "su 0 dd if=/data/local/tmp/uboot_a.img of=/dev/block/by-name/uboot_a bs=1048576"
adb -s $S shell "su 0 sync"
```

## 7. How the tool works

1. Checks that the two FIT copies are identical and that the stock `uboot` hash matches its data
   (`images/uboot`: `data-position 0xe00`, `data-size 0xf2f48`, hash at FIT offset `0x190`).
2. Finds the default environment (NUL-separated `var=value` list at `0xa1378`, 3643 bytes),
   replaces values, pads with NULs to the original size (an empty string ends the list).
3. Recomputes sha256 over the U-Boot data and writes it into the FIT header of copy 0.

## 8. Test log

### v1 (sha256 `6baad100…`, bootdelay=3, no `usb stop`): boot loop
- No key pressed: power on → patched logo → reset, over and over. With Ctrl+C pressed repeatedly
  it ended up at the white China Mobile Android boot screen. That was **slot B**.
- After that (checked over adb):
  - running **slot B** (`androidboot.slot_suffix=_b`, `secureboot=0` → stock uboot_b), bootreason `reboot,ota`
  - `misc` A/B: slot A **prio 0 / tries 0 / unsuccessful** (= unbootable), slot B prio 14 / successful
  - `misc` @0xc00 ZTE retry record `STRS` 05 00 00 00 | boot counter 0x3f → **0x49** (+10 boots) |
    slot-change counter 0 → **1**. (`read zte_retry … boot_times … change_times` in U-Boot)
  - `/data` intact (keylayout from 2026-11-05 still there). The "reverted" apps are just the other
    Android build on `system_b` (2024-07).
  - `uboot_a` on eMMC = v1 image (hash checked).
  - pstore `console-ramoops-0` holds the **previous** good Android A boot (ends with our
    `reboot,shell`). **No patched-slot-A attempt reached the kernel's pstore init** (~0.05 s).
- Conclusions:
  - SPL accepted the patched copy 0 (U-Boot drew the logo, and SPL has no display code).
  - The reset happens in U-Boot after the logo, or at the very start of the kernel.
  - **The A/B fallback works:** about 7 failed tries → SPL/U-Boot switch to slot B by themselves. ✅
- Suspects:
  1. `usb start` leaves the xHCI/EHCI controllers running into `boot_android` → the kernel crashes
     immediately (DMA into kernel memory). The stock path never runs `usb start` before Android.
  2. A watchdog/timer that the extra ~7 s exceed. A `dw-wdt` node is enabled in U-Boot's DT, but
     no `wdt` command or start message was found.
  3. `usb start` itself crashing or resetting.
- Whether Ctrl+C from the laptop keyboard works is still unknown (no prompt seen; it may have
  been reset away).

### v2 (sha256 `1ef8e622…`): `usb stop;` before `boot_fit;boot_android`: boot loop too
`uboot-patch/uboot_a-w600d-v2.img`. Same behaviour as v1: ZTE boot counter 0x49 → 0x51 (8 boots),
slot-change counter 1 → 2, back on slot B, no slot-A kernel log in pstore.
→ **Suspect 1 (USB left running into the kernel) alone is ruled out.**

### Control (stock `uboot_a`, `2375420f…`, + `bootctl set-active-boot-slot 0`): boots first time ✅
Exactly the same procedure as v1/v2, only with the stock image:
- booted once, straight into slot A Android (user's own launcher setup back)
- `misc`: slot A `0f 00 01 00` (prio 15, successful, marked by Android), slot B `0e 00 01 00`
- ZTE counter 0x51 → 0x52 (one boot), no slot change
→ **`set-active-boot-slot`, the A/B tries and ZTE's retry logic are not the cause.** The reset
is caused by something in the **patched environment**. Remaining suspects:
  - **2. timing**: `bootdelay=3` and/or `sleep 3`, and a watchdog (`dw-wdt @fe600000`,
    enabled in U-Boot's DT; armed by SPL/ATF?) that the stock path, which reaches the kernel in
    ~1–2 s, never hits.
  - **3. `usb start` itself** resetting the board (crash, power draw of the USB devices: keyboard,
    camera, 5G module…).
  - 4. something else in the changed env (`boot_targets`, empty `bootcmd_pxe/dhcp`). Unlikely:
    nothing references them before the reset.

### Next variants (one change each, same test procedure, fallback to B is proven)
| Variant | Environment change vs stock | Loops → | Boots → |
|---|---|---|---|
| v3 | `bootdelay=3` only | timing/watchdog | bootdelay is fine |
| v4 | `bootcmd=usb start;usb stop;` + stock bootcmd | `usb start` | USB init is fine |
| v5 | `bootcmd=sleep 3;` + stock bootcmd | timing inside bootcmd | sleep is fine |

**Results (2026-11-06, run with `tools/uboot-test.sh flash <img>` / `check`):**

| Variant | Image sha256 | Result |
|---|---|---|
| v3 `bootdelay=3` | `f52c86f7…` | ✅ boots first time (counter 0x52→0x53) |
| v4 `usb start;usb stop;` + stock bootcmd (+ `bootcmd_pxe=` for room) | `3ea7c96a…` | ✅ (0x53→0x54) |
| v5 `sleep 3;` + stock bootcmd (+ `bootcmd_pxe=`) | `910eaa7d…` | ✅ (0x54→0x55) |

→ **bootdelay, sleep, `usb start`/`usb stop` are all fine.** Not a watchdog or timing problem.
What v1/v2 have and v3–v5 don't:
  - `run distro_bootcmd` **before** `boot_android`, with `boot_targets=usb0 mmc0`
    (stock runs distro only after Android fails, so this path never ran on this board).
    `bootcmd_usb0` → `usb dev 0` fails without a stick. `bootcmd_mmc0` → `mmc dev 0`, `part list
    mmc 0 -bootable`, then probing eMMC **partition 1 (`security`)** for extlinux/boot.scr. Prime suspect.
  - `boot_fit;boot_android` inside hush `if … then … fi`
  - `echo`, empty `bootcmd_dhcp`

Next: v6 = `run bootcmd_usb0;` + stock, v7 = `run bootcmd_mmc0;` + stock,
v8 = `if sleep 1;then boot_fit;boot_android ${devtype} ${devnum};fi;run distro_bootcmd;`.

Build e.g. v3: `python3 -I tools/patch-uboot-env.py w600d-backup/uboot_a.img uboot-patch/v3.img bootdelay=3`
(with arguments, only those variables change).

A **serial adapter (UART2, 1500000 baud)** would show the reset reason in one boot and replace
this bisecting: `debrick.md` §1.

### Lessons
- The A/B fallback is a real safety net for U-Boot experiments: a looping slot A costs ~7–8 resets,
  then slot B (stock uboot_b + Android B) boots by itself. Restore = `dd` stock `uboot_a` +
  `bootctl set-active-boot-slot 0`.
- Each failed run switches Android to slot B (different build, 2024-07). `/data` is shared and
  survives, but per-build state (e.g. a removed system launcher) looks "reverted" until slot A is back.
- Keep slot B **stock**: it is the rescue path.

To test any variant while running slot B:
```sh
# write uboot_a (as §6 steps 3–5), then make A active again with fresh tries:
adb -s $S shell "su 0 bootctl set-active-boot-slot 0"
adb -s $S reboot
# failure → ~7 resets → slot B again by itself
```

### v9-diag (`4ee5b9d8…`): show U-Boot output on the laptop screen
Why no U-Boot text appears on screen today: `stdout=serial,vidconsole` is applied at console init,
but the Rockchip display (and with it `vidconsole0`) only comes up later, when the logo is drawn.
Setting `stdout` again from `bootcmd` re-attaches the console. U-Boot also has
`rockchip_show_bmp <name>` (draws a BMP from the boot partition's resource), used here as
progress markers in case the text still doesn't show.

```
bootdelay=3
bootcmd=setenv stdout serial,vidconsole;setenv stderr serial,vidconsole;
  rockchip_show_bmp battery_0.bmp;echo [1] usb start;usb start;usb tree;sleep 2;
  rockchip_show_bmp battery_1.bmp;echo [2] scan usb0;run bootcmd_usb0;sleep 2;
  rockchip_show_bmp battery_2.bmp;echo [3] scan mmc0;run bootcmd_mmc0;sleep 2;
  rockchip_show_bmp battery_3.bmp;echo [4] usb stop;usb stop;sleep 2;
  rockchip_show_bmp battery_4.bmp;echo [5] boot_android;boot_fit;boot_android ${devtype} ${devnum};
  rockchip_show_bmp battery_fail.bmp;echo [6] android failed
(bootcmd_pxe, bootcmd_dhcp, partitions emptied for space; `partitions` is only used by `gpt write`)
```
Read the result from the screen: the last `[n]` text, or which battery picture
(0 = empty … 4 = 80 %, fail = red) was shown before the reset.

**v9 result (2026-11-06): ✅ booted first time** (slot A, counter 0x55→0x56).
It ran usb start → usb tree → `bootcmd_usb0` → `bootcmd_mmc0` → usb stop → boot_android as a flat
list. v2 ran the same steps **inside `if sleep 3;then … fi`** and via `distro_bootcmd`'s `for` loop,
and looped. → The scans and USB are innocent. **Prime suspect: the hush `if … fi` block** (with
`boot_android` / `for` inside it). Next: v8 (`if sleep 1;then boot_fit;boot_android …;fi`).
The user saw only battery_0 and battery_4 (the rest go by too fast) and **no text**:
re-setting `stdout` to `vidconsole` from `bootcmd` doesn't put text on the screen.
(`lcdputs` / `setcurs` exist in this U-Boot and haven't been tried yet.)

### v8 (`1c45633e…`): minimal `if`: boot loop
`bootcmd=if sleep 1;then boot_fit;boot_android ${devtype} ${devnum};fi;run distro_bootcmd;`
(+ `bootcmd_pxe=`). Loops: counter 0x56→0x5e, slot change 2→3, back on slot B.
→ No USB, no distro scan, only `boot_android` inside an `if`, and it loops.

### v11 (`492c1057…`): `if` with a literal device: boot loop
`bootcmd=usb start;if sleep 3;then run bootcmd_usb0;usb stop;boot_fit;boot_android mmc 0;fi;`
(+ `bootdelay=3 bootcmd_pxe=`). Tests the theory that `${devtype}`/`${devnum}` are expanded
when the whole `if` block is parsed (before `boot_fit` sets them) and come out empty.
Loops: counter 0x5e→0x66, slot change 3→4. → **Theory disproved.**

### Root cause (by bisection, 2026-11-06)
| `boot_android` runs … | Tests | Result |
|---|---|---|
| as a plain command in the `;` list | stock, v3, v4, v5, v9 | ✅ boots |
| inside `if … then … fi` | v1, v2, v8, v11 | ❌ resets before the kernel |

**Rule: never run `boot_android` inside a hush `if` (or `for`) block.** Probable mechanism (not
proven): `boot_android` runs U-Boot commands itself (`run_command`) while loading Android, and
U-Boot's hush parser isn't re-entrant while a compound command is still open. Anything else
(`sleep`, `usb`, `setenv`, the scans) is fine inside or outside blocks.

### v12 (`635e5a30…`): flat `boot_android`, Ctrl+C sets a variable
```
bootdelay=3
bootcmd=usb start;if sleep 3;then setenv bdev mmc;else setenv bdev none;fi;
  run bootcmd_usb0;usb stop;boot_fit;boot_android ${bdev} 0;
(bootcmd_pxe, bootcmd_dhcp emptied for space)
```
- The `if` only contains `setenv`. `boot_android` is a plain command, as in v9.
- No key: `bdev=mmc` → `bootcmd_usb0` (a USB stick with extlinux/boot.scr boots) → Android.
- Ctrl+C on the laptop keyboard during the 3 s: `bdev=none` → `boot_android none 0` fails →
  `bootcmd` ends → `=>` prompt. (`bootcmd_usb0` still runs first: Ctrl+C skips Android, not the stick.)
- Open question: how `boot_android` handles an invalid device. Only matters for the Ctrl+C path.

**v12 result: ❌ boot loop** (back on slot B by itself). So the rule is broader:
**no `if` written directly in `bootcmd` at all.** `if`/`for` inside scripts called with `run`
(`bootcmd_usb0` → `usb_boot` → `scan_dev_for_boot_part`) are fine: v9 ran them and booted.
Giving up the keyboard Ctrl+C window. `bootdelay=3` still gives a serial-only prompt.

### v13 (`b94f333f…`): USB first, flat (user's design)
`boot_fit` won't find Linux on a stick: it loads a FIT from the boot device's (eMMC) boot partition.
Stock never reaches `run distro_bootcmd`, because `boot_android` succeeds first. So USB has to come first:
```
bootdelay=3
bootcmd=run bootcmd_usb0;run bootcmd_mmc0;usb stop;boot_fit;boot_android ${devtype} ${devnum};run distro_bootcmd;
(bootcmd_pxe emptied for space)
```
- Same commands as v9 without the diagnostics (v9 booted).
- `bootcmd_usb0`: stick with `extlinux.conf`/`boot.scr` → boots Linux.
- `bootcmd_mmc0`: same for eMMC (for later), and resets `devtype=mmc devnum=0`, so a non-Linux
  stick still falls through to Android.
- Unknown: the stick's kernel is started (`sysboot`/`booti`) from inside the `for`/`if` of
  `scan_dev_for_boot_part`. That is fine on mainline; with this hush it's untested until there's a Linux stick.

**v13 result (2026-11-06): ✅ boots first time** (slot A successful, counter 0x6e→0x6f).
**v13 is the current `uboot_a`.** USB-stick boot: first test with `usb-demo/` (boot.scr + bare-metal demo) didn't run (2026-11-06): the stick was on the OTG port `fcc00000`, which U-Boot doesn't use as a host. Only `fd000000` (the keyboard's controller) is a host. See the `usb-demo/README.md` test log.

Why the A/B fallback rescued every loop: the vendor U-Boot decrements the tries during init,
before `bootcmd`. SPL only does it when both FIT copies fail. Details: `ab-tries.md`.

### v14-diag (`8de8c9f8…`): why doesn't the USB stick boot? Results → kernel cmdline
The usb-demo stick never ran (runs 1 and 2, OTG and right-side EHCI port; see `usb-demo/README.md`).
v14 is v13 plus checks. Each is `cmd && setenv x …` (no `if`), and the results are appended to
`bootargs` as one token, which Android shows in `/proc/cmdline` (root):
```
usb start && setenv a us;  usb dev 0 && setenv b d0;  usb dev 1 && setenv c d1;
fstype usb 0:1 f0;  fstype usb 1:1 f1;
test -e usb 0:1 /boot.scr && setenv e s0;  test -e usb 1:1 /boot.scr && setenv g s1;
part list usb 0 -bootable bp;  run bootcmd_usb0;
setenv bootargs ${bootargs} w6dbg=${a}.${b}.${c}.${f0}.${f1}.${e}.${g}.${bp}.${devtype}${devnum};
run bootcmd_mmc0;usb stop;boot_fit;boot_android ${devtype} ${devnum};run distro_bootcmd;
(bootdelay=3, bootcmd_pxe/bootcmd_dhcp/partitions emptied)
```
Read: `adb shell su 0 cat /proc/cmdline | tr ' ' '\n' | grep w6dbg`.
Expected with a working stick: `w6dbg=us.d0..fat..s0...usb0` (`f0=fat`, `devtype usb` left by bootcmd_usb0).
No `w6dbg` at all → `boot_android` rebuilds `bootargs` and this channel doesn't work.

**Result (2026-11-06): boots ✅ (slot A, counter 0x74→0x75), cmdline token `w6dbg=us.d0..fat..s0...usb0`.**
- **The bootargs channel works:** `boot_android` keeps `${bootargs}` and appends the Android cmdline.
  This is the way to get U-Boot results without serial or on-screen text.
- Stick on the right-side port (EHCI `fd800000`): `usb start` OK, it is `usb 0`, partition 1 is
  FAT, and `/boot.scr` exists. After `bootcmd_usb0`, `devtype`=usb: the distro scan selected the stick.
- So the scan finds `boot.scr`, but no effect of the script was seen (no battery animation in
  run 2). Suspects: `source` rejects the legacy uImage, the script's hush parsing fails, or the
  commands run without visible effect. Next: a `boot.scr` that appends its own markers to `bootargs`.
