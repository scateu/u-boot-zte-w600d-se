# HOWTO: boot Linux from a USB stick, via the vendor U-Boot (no kernel build)

A second USB-stick flow, independent of the [mainline-U-Boot stick](README.md):

```
BootROM → SPL → vendor U-Boot 2017.09 (uboot_a, USB-first — same patch as the other stick)
  → USB stick: boot.scr → booti vmlinuz + uInitrd + rk3568-w600d-linux.dtb
  → Linux 5.10.160 (prebuilt ophub rk35xx kernel), rootfs = the rest of the same stick
```

Nothing is written to the eMMC. Unplug the stick and the laptop boots Android as before, same
as the other stick (`README.md`). This is a **first cut, not yet boot-tested on the hardware** —
see Status below.

## Why this kernel, why this base devicetree

[`research/docs/ref-z96a-comparison.md`](../research/docs/ref-z96a-comparison.md) already worked
out the right kernel line by comparing against a sibling RK3568 laptop (Sunniwell Z96A) that's
fully working under Linux: **Rockchip BSP 5.10.160** (`unifreq/linux-5.10.y-rk35xx`), not
mainline — mainline is missing the RK3568 VOP2 display driver and (until 5.11) `mt7663s`.

Rather than build that kernel, this uses **ophub's prebuilt binary package** of the same tree
(`ophub/kernel`, tag `kernel_rk35xx`, `5.10.160-rk35xx-flippy-2412a.tar.gz`) — vmlinuz, a matching
`uInitrd`, and a full Rockchip `dtb-rockchip` set with modules, already built and depmod'd.

For the devicetree, instead of writing one from scratch: `rk3568-evb1-ddr4-v10-linux.dtb` from
that same package (the Rockchip EVB reference board) decompiled almost directly into a working
base — because ZTE's own W600D board turns out to be built on that same reference design:

- Its RK809 PMIC + all DCDC/LDO regulator µV values are **byte-for-byte identical** to the EVB's.
- Its `chosen/bootargs` already has `earlycon=uart8250,mmio32,0xfe660000 console=ttyFIQ0` and a
  `fiq-debugger` node — **the exact same UART2 debug console the vendor bootloader already uses**
  (confirmed against `memory.md`'s "UART2 @ 0xfe660000, 115200").
- `vcc5v0_host`/`vcc5v0_otg` fixed regulators already exist, just wired to the EVB's own GPIOs.

So the patch (`linux-build-dir/patch-dts.py`, run against a `dtc -I dtb -O dts` decompile of the
EVB dtb) is small and all textual:
1. rename `model`/`compatible`.
2. add `bq25700@6b` (`ti,bq25703`, matches `bq25700_charger.ko` as-is) and a `sbs,sbs-battery`
   node (matches `sbs-battery.ko`; the vendor's own compatible, `zte,smart_battery`, has no
   mainline/BSP driver, so this uses the generic SBS one instead and should read the same
   SBS-protocol fuel gauge) on **i2c0**, next to the PMIC — same bus as the vendor DT.
3. add a `hid-over-i2c` touchpad node on **i2c4** (mainline-standard binding, already matched by
   `CONFIG_I2C_HID=y`).
4. enable **sdmmc1** (the MT7663 SDIO slot; was `disabled` on the EVB) with the vendor's bus
   config and the SoC's stock `sdmmc1_bus4`/`clk`/`cmd` pins.
5. fix `vcc5v0_host`/`vcc5v0_otg`'s GPIOs to this board's real ones (**GPIO3_A0** / **GPIO0_C4**).
6. add a `gpio-hog` on GPIO3_A3 so the internal USB keyboard has power — the Linux-side twin of
   the `gpio-hog` already used in `patches/u-boot/0005-...` for the chain-loaded mainline U-Boot.

Every GPIO/I2C-address value above was cross-checked two ways: against
`research/backups/w600d-backup/device_slot_b.dts` (the vendor Android kernel's own DT dump) and
independently against the GPIO table in `ref-z96a-comparison.md`. Script:
[`linux-build-dir/patch-dts.py`](../linux-build-dir/patch-dts.py); compiled with `dtc` (no kernel
source tree needed, just the devicetree compiler).

## What's deliberately left out of this first cut

- **The eDP panel.** The vendor's own kernel DT (and U-Boot's resource-partition DT) have no
  `display-timings` block for the `guoxian-30NK` panel — the vendor driver looks it up in a
  built-in table keyed by the `edp_name=guoxian-30NK` boot parameter, which isn't anywhere in our
  dumps as plain data. Without a known-good timing block, `edp`/`edp_panel`/backlight are left
  disabled rather than guessed. **This build is serial-console-only.**
- **SC2021 (USB-PD)**: no mainline/BSP driver exists for it (same conclusion as
  `ref-z96a-comparison.md`); not declared.
- Camera, accelerometer, audio machine driver: not wired up; not needed for a first boot.
- MT7663 Wi-Fi/BT and the BQ25703 charger/SBS battery *are* wired up (drivers exist:
  `mt7663s.ko`, `btmtksdio.ko`, `bq25700_charger.ko`, `sbs-battery.ko`, all present in the ophub
  package) but **are untested** — see Status.

## What's staged in `linux-build-dir/`

```
dl/5.10.160-rk35xx-flippy-2412a.tar.gz   ophub prebuilt kernel package (sha256 in kernel-pkg/.../sha256sums)
dl/ubuntu-base-22.04.5-base-arm64.tar.gz  minimal arm64 rootfs seed (Ubuntu's own bootstrap tarball)
kernel-pkg/.../                          the package, unpacked (vmlinuz, uInitrd, dtb set, modules, config)
dts/rk3568-w600d-linux.dts(.dtb)          the patched board devicetree (see above)
patch-dts.py                              the patch script that makes it, from the decompiled EVB base
firmware/mt7663-from-device/              WIFI_RAM_CODE_MT7663.bin, mt7663_patch_e2_hdr.bin, EEPROM_MT7663.bin
                                           -- pulled live from this unit's /vendor/etc/firmware over adb
firmware/mediatek/                        the same 2 files, copied under the names mt7663s.ko's
                                           modinfo expects (mt7663pr2h[_rebb].bin, mt7663_n9_v3/_rebb.bin)
                                           -- which exact pair it wants is untested, both are staged
rootfs/                                   the populated ext4 tree (Ubuntu base + modules + firmware, /boot empty -- a mountpoint now)
fat.img                                    the FAT32 boot partition (mtools: mformat + mcopy), no mount/root needed
boot.cmd / boot.scr                        the U-Boot script (built with the other stick's chain/mkscr.py)
rootfs.ext4                                 the ext4 filesystem built from rootfs/ (mke2fs -d)
make-img2.py                                wraps fat.img (p1) + rootfs.ext4 (p2) as a 2-partition MBR disk image
w600d-linux.img(.gz)                        the final image -- see "Writing it to a USB stick" below
```

## Status: image built

`linux-build-dir/w600d-linux.img` (661 MiB) / `w600d-linux.img.gz` (~80 MB compressed) — a
2-partition MBR disk image, not yet boot-tested successfully on the hardware (see the two
failed-attempt writeups below). Layout:

- **Partition 1** (sector 2048, type `0x0c`, **FAT32**, 160 MiB): `boot.scr`,
  `vmlinuz-5.10.160-rk35xx-flippy-2412a`, `uInitrd-5.10.160-rk35xx-flippy-2412a`,
  `rk3568-w600d-linux.dtb`. The only thing the vendor U-Boot ever reads.
- **Partition 2** (1 MiB-aligned right after p1, type `0x83`, **ext4**, 500 MiB, ~42% used): the
  Linux rootfs — Ubuntu 22.04 base, the kernel's full module tree + `modules.dep` (already
  depmod'd by ophub), `/lib/firmware/mediatek/` (MT7663 blobs pulled from this unit's Android),
  `/boot` as an empty mountpoint for partition 1 (`/etc/fstab`: `/dev/sda1 /boot vfat`).

Built with `linux-build-dir/patch-dts.py` (devicetree), `make-img2.py` (MBR wrapper),
`boot.cmd`/`mkscr.py` (boot script, from the other stick's `chain/`), `mtools` (the FAT32
partition) and `mke2fs -d <dir>` (Homebrew `e2fsprogs`, the ext4 partition) — all without `sudo`
(see caveat below) and without touching any physical disk; macOS has no native ext4 writer, so
both filesystems are built directly from a directory/file tree rather than by mounting.

**Login**: `root` / `w600d` on the serial console — **change it**, this is a bring-up default.

**Known caveat**: built without root, so every file in the image is owned by the build host's
uid instead of `0:0` (visible with `debugfs -R 'ls -l /boot' w600d-linux.img`, or after boot with
`ls -la /boot`). This is cosmetic, not a security hole here: the booted kernel's root (uid 0) can
read/write any file regardless of its recorded owner (`CAP_DAC_OVERRIDE`). Fix later if it ever
matters: `sudo chown -R 0:0 /` from a shell on the booted system, or rebuild this image with
`sudo` once sudo is available non-interactively.

## Writing it to a USB stick

The image is 601 MiB; the destination can be any USB stick ≥ 1 GiB (the rest of a bigger stick is
left unpartitioned — grow the ext4 partition into it later with `growpart`/`resize2fs` if wanted).

```sh
gunzip -k w600d-linux.img.gz        # or write the .img directly, both are the same disk image
diskutil list                       # find the stick, e.g. /dev/disk5 -- CHECK THE SIZE
diskutil unmountDisk /dev/diskN
sudo dd if=w600d-linux.img of=/dev/rdiskN bs=4m          # rdiskN (raw) is much faster than diskN
diskutil eject /dev/diskN
```
(`balenaEtcher` or Raspberry Pi Imager also accept `w600d-linux.img.gz` directly, decompressing
on the fly, if you'd rather not use `dd`.) Use the **right-side USB-A port** on the laptop (EHCI;
the other port is OTG and untested for this — see `README.md`).

## Status / what's left

Verified offline so far:
- Kernel package downloaded, checksummed, unpacked; `CONFIG_USB_STORAGE=y`, `CONFIG_EXT4_FS=y`,
  `CONFIG_VFAT_FS=y`, `CONFIG_SCSI=y` confirmed in the kernel `.config`.
- Custom `rk3568-w600d-linux.dtb` compiles clean (`dtc`, no errors beyond the stock EVB dtb's own
  cosmetic warnings).
- The built ext4 filesystem passes `e2fsck -fn` clean; `/boot.scr` built and the three `/boot/*`
  files it loads are present at the right paths (checked with `debugfs`, not by booting).
- MT7663 firmware pulled live from this unit's Android and staged under the names `mt7663s.ko`
  expects.

**Not done: booting it.** This has not run on the real hardware yet. First boot needs the UART2
debug serial (1500000 8N1, same wiring as `debrick.md`) since this first cut has no display.
Expect to iterate — see Troubleshooting below.

### First real-hardware attempt: no `w6*` markers at all → modern ext4 features

First boot: stock Android, no change. Added `w6start=1`/`w6kernel=`/`w6fdt=`/`w6initrd=`/
`w6bootifail=1` markers to `boot.scr` (same technique as the other stick's bring-up — readable
from Android afterwards with `adb shell su 0 cat /proc/cmdline`). Re-tested: **still nothing**,
not even `w6start=1`, which is set unconditionally as the very first line, before any file is
loaded. That rules out every failure *inside* the script (wrong path, wrong partition number,
`booti` rejecting the kernel, ...) — `source` never executed a single line of it. So either
`boot.scr` was never found, or it was found but rejected before being interpreted.

**Root cause (found by inspection, not yet re-tested on hardware): the ext4 filesystem used
features too new for a 2017.09-era U-Boot.** `mke2fs` 1.47.4's defaults include `metadata_csum`,
`metadata_csum_seed` and `orphan_file` — none of which existed yet when this vendor U-Boot's ext4
driver was written. The FAT32 stick (the other, already-working one) never hit this because FAT
has no such versioning. U-Boot likely can't verify/read the partition at all with those features
on, and silently moves on to the next boot source — which looks exactly like "boot.scr never
ran," indistinguishable from a wrong port or a missing partition without `w6start` to rule those
out.

Fix: rebuilt the filesystem with `mke2fs -O ^64bit,^metadata_csum,^metadata_csum_seed,^orphan_file`,
leaving only features that have existed in ext4 since roughly 2010–2011 (`extent`, `flex_bg`,
`huge_file`, `dir_nlink`, `extra_isize`, ...). **Re-tested: still nothing, not even `w6start=1`.**
So the ext4-feature mismatch, while real and worth fixing, wasn't the (only) problem.

### Second attempt, same result → switched the boot partition to FAT32

Stepping back: **every prior confirmed-working USB boot on this exact vendor U-Boot fork — v13
through v15's own testing, and the other (mainline-U-Boot) stick — used a FAT32 partition 1.**
`research/docs/HOWTO-usb-drive.md` states the vendor's distro-scan supports ext2/3/4 as well as
FAT, but that line was inferred from generic U-Boot source reading, not actually exercised on
this fork before this session. Two tests in a row where `source` never ran a single line (not
even the unconditional first `setenv`) means `boot.scr` itself was never found *or* read — which
is consistent with "this fork's distro-boot-part scan plain doesn't find boot.scr on ext4", a
simpler explanation than two different ext4 quirks in a row.

**New layout**, matching the two-partition plan `HOWTO-usb-drive.md` §6 already sketched:
- **Partition 1: FAT32** (160 MiB, built with `mtools`/`mformat`+`mcopy`, no mount/root needed on
  macOS) — `boot.scr`, `vmlinuz-...`, `uInitrd-...`, `rk3568-w600d-linux.dtb`. This is the only
  thing the vendor U-Boot ever has to read, on the one filesystem type already proven to work.
- **Partition 2: ext4** (500 MiB, same `mke2fs` conservative-feature build as above) — the actual
  Linux rootfs, with `/boot` as a separate `vfat` fstab mount pointing at partition 1. The
  **Linux kernel's own ext4 driver** reads this, not the vendor U-Boot, so the feature-version
  question above doesn't matter here either way.
- `boot.cmd` now uses `fatload` instead of `ext4load`, and `root=/dev/sda2` instead of `/dev/sda1`.

Built with `make-img2.py` (2-partition MBR wrapper, p1 @ sector 2048, p2 1 MiB-aligned after it).
`w600d-linux.img`/`.img.gz` already have this. **Still needs re-flashing and re-testing.**

### Third attempt, same result → found it: `BPB_HiddSec`

Still nothing. At this point you ran the control test yourself: deleted partition 1's files and
copied the *other*, already-working stick's `boot.scr`/`u-boot-w600d.bin`/`w600d-chain.bin`
straight onto the FAT32 partition **our image** had created — still nothing. Then reformatted
the same USB stick from scratch with macOS Disk Utility (one plain FAT32 partition) and copied
the identical files — **it booted straight to the typewriter prompt.**

That's the whole answer: identical file *content*, on a FAT32 partition that's otherwise the same
(same type byte, same files), behaves differently only depending on which tool built the
filesystem. The difference is `BPB_HiddSec` — the FAT32 boot sector's "hidden sectors before this
partition" field. `mtools`/`mformat` builds `fat.img` as if it were its own whole disk (`HiddSec
= 0`), with no idea it will later be embedded at sector 2048 inside a bigger image. macOS's own
formatter writes the real partition in place, so it gets this right automatically. A FAT driver
that computes absolute LBAs from `HiddSec` (apparently this vendor U-Boot's does) silently can't
read the filesystem with the wrong value — not an error, just "nothing here," indistinguishable
from the stick not being found at all. Three attempts, same symptom, three unrelated-looking
causes ruled out first.

Fixed: `make-img2.py` now patches `BPB_HiddSec` (boot sector *and* the FAT32 backup boot sector
at sector 6) to the partition's real LBA start before writing it into the final image, instead of
leaving whatever `mformat` happened to write. `w600d-linux.img`/`.img.gz` have this baked in.
**Not yet re-tested on the hardware.**

### Fourth attempt: it ran — screen stuck at the boot logo, no serial available to confirm

With the `BPB_HiddSec` fix, this time the vendor's boot logo stayed on screen instead of handing
off to Android — a good sign: nothing *visibly* changes because this build has no display driver
(see above), so a kernel that boots fine on serial alone looks identical, on screen, to one that's
hung. Two more bugs found by inspection before assuming it's actually working:

- `rockchip,baudrate = <0x16e360>` (1 500 000, the EVB default) was still in the devicetree,
  while `boot.cmd` sets `console=ttyFIQ0,115200` and the vendor Android kernel's own
  fiq-debugger is 115200 (`debrick.md`). Fixed in `patch-dts.py` to `0x1c200` (115200), so a
  serial adapter at the same settings used for Android debugging would also work here.
- No serial adapter is available for now, so there's no way to watch the boot or get a login
  prompt. Added a no-serial-needed diagnostic instead: three `systemd` oneshot services
  (`bringup-log-{early,mid,late}.service`, tied to `sysinit`/`basic`/`multi-user.target`) that
  each `sync` a growing snapshot (`dmesg`, `systemctl --failed`, `lsmod`, `ip -brief a`,
  `journalctl -b`, and a grep for `mt76`/`bq2570`/`sbs`/`hid-over-i2c`/etc.) to
  **`/boot/boot-log.txt`** — on the FAT32 partition, so it's readable by just plugging the stick
  into any computer, no `mtools`/`debugfs`/root needed. Whichever of the three stages is the last
  one present in the log says how far the boot got before whatever happened next (hang, reboot,
  the stick being pulled).

**Next step**: flash this image, boot with the stick in, give it a couple of minutes, then power
off, pull the stick, and plug it into a computer — `boot-log.txt` sits right at the root of the
visible FAT32 volume.

### Fifth attempt: no serial available, no `boot-log.txt` either → the hang is earlier than systemd

No serial adapter to hand, so the above was the only check: plugged the stick back into the Mac
after a boot attempt, and `/boot/boot-log.txt` **didn't exist at all** — meaning none of the
three `systemd` units ever ran, which means the real root (`/dev/sda2`) was never reached, which
means the hang is inside the **initramfs**, before `switch_root`. (In hindsight, attempt 4's
"stuck at the boot logo" never actually proved systemd was reached either — it's equally
consistent with the initramfs itself hanging, since no display means the screen looks frozen
either way. Both attempts are probably the same failure.)

Pulled apart `initrd.img-5.10.160-rk35xx-flippy-2412a` (`xz -d`, `cpio -idm`): it's a normal
Debian `initramfs-tools` image (klibc utilities, not busybox) with `MODULES=most` — meaning it
leans on `udev` to autoload whatever driver matches the hotplugged device, rather than loading a
fixed list. `sd_mod.ko` (the one module actually needed — `usb-storage`, `scsi_mod` and `xhci`
are all built into the kernel, confirmed in `config-...`; `modules.dep` shows `sd_mod.ko` has no
dependencies of its own) is present in the image, but nothing forces it to load before the
root-wait loop times out (`scripts/local-top/` didn't even exist in this image — there was
nothing hooked in at that stage at all). If `udev`'s autoload races with (or never fires before)
that ~30 s wait in `scripts/local` (`local_device_setup`'s "`Timeout is max(30, rootdelay)`"),
it drops to a `panic()` shell on the console — which, with no serial attached, is indistinguishable
from a true hang.

**Fix**: added `scripts/local-top/w600d` (repackaged into a new `initrd-custom.img`, replacing
`uInitrd` so `mkimage`/`u-boot-tools` aren't needed — `boot.cmd` now loads it as a plain file and
passes `booti`'s ramdisk arg as `addr:${filesize}` instead of relying on a uImage header). It
unconditionally `modprobe sd_mod`s *before* the wait loop, so root's availability no longer
depends on `udev` timing — and, same trick as the `systemd` units, mounts `/dev/sda1` (this same
FAT32 partition) read-write and copies its own log there as `/initrd-log.txt`, with a `sync`
before unmounting, so this stage is now visible too, however it goes. `w600d-linux.img`/`.img.gz`
have this. **Not yet re-tested.**

### Sixth attempt: neither log file appeared → you were right, `boot.scr` itself was the bug

Not even `/initrd-log.txt` this time — so the hang moved *earlier* than the initramfs script,
right back to something in `boot.scr`/`booti` itself failing to reach the kernel at all. The
actual bug: swapping `uInitrd` for the repackaged initramfs also swapped how it was loaded —
the raw `initrd-custom.img` (plain `xz`-compressed cpio, no header) was passed to `booti` as
`0x0a200000:${filesize}`, the documented syntax for a raw ramdisk with an explicit size. The
*working* attempt (4) used `uInitrd`, which has a legacy `uImage` header, loaded as a plain
address with no `:size` — a different code path. This 2017.09 vendor fork is old enough that
there's a real chance its `booti`/`do_bootm_linux` doesn't handle the `addr:size` raw-ramdisk
form the way current upstream U-Boot does, and changing two things at once (initrd content *and*
how it's passed to `booti`) made it impossible to tell which one broke it.

Fix: stopped trying to avoid `mkimage` (installed via `brew install u-boot-tools`) and wrapped
the patched initramfs properly instead — `initrd-custom.uimg` (`mkimage -A arm64 -O linux -T
ramdisk -C gzip`, gzip to match the stock `uInitrd`'s own compression rather than changing that
too), loaded the exact same way the working attempt loaded `uInitrd`: a plain address, no `:size`,
letting `booti` read the size from the header like it did when that worked. Only one variable
changed from attempt 4 now — the initramfs content (the `sd_mod` fix) — not also the loading
mechanism. `w600d-linux.img`/`.img.gz` have this. **Not yet re-tested.**

## Troubleshooting (anticipated, not yet observed)

| What you see | Likely meaning |
|---|---|
| Nothing at all, Android boots | `boot.scr` didn't run — same causes as the other stick: wrong port, not FAT/ext partition 1, or a plain `mkimage` script (needs `mkscr.py`'s `0xFFFFFFFF` terminator, see `README.md` Notes) |
| Kernel prints to UART2, then stops before a login prompt | root= didn't resolve (check the stick shows up as `/dev/sda`, not `/dev/sdb`, if another USB device is plugged in) or `sd_mod`/`usb-storage` didn't load from `uInitrd` in time |
| Login prompt, but `wlan0`/`mmc1` missing | `sdmmc1` or `mt7663s` didn't probe — check `dmesg \| grep -i mt76` once a shell comes up |
| Battery/charger sysfs empty | `bq25700_charger`/`sbs-battery` didn't bind — check `i2cdetect -y 0` sees `0x6b`/`0x0b` |
