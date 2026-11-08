# Who decrements the A/B tries? (SPL vs U-Boot disassembly, 2026-11-06)

The question: if `uboot_a` holds something other than the vendor U-Boot (mainline U-Boot,
a foreign image…), does the automatic fallback to slot B still work?
**Answer: only if the image is unloadable. A loadable non-vendor U-Boot means no fallback.**

## Result

| Stage | Decrements slot tries? | When |
|---|---|---|
| SPL (2017.09, in idbloader @ LBA 64) | **only on failure** | both FIT copies of `uboot_<slot>` fail (bad magic, IO error, hash) |
| vendor U-Boot (`uboot_a` / `uboot_b`) | **every boot, during init** | late init, **before** `bootdelay`/`bootcmd`, if the slot isn't marked successful |
| Android | marks the slot successful | after a good boot (`0f 00 01 00`) |

Consequences:
- All our looping `bootcmd` tests (v1, v2, v8, v11, v12) fell back to slot B because the
  **vendor U-Boot had already decremented** before `bootcmd` ran. Where the reset happened didn't matter.
- **Corrupt `uboot_a`** (both copies bad): SPL decrements on each attempt → after the tries run out,
  slot B. Safe (each attempt probably needs a power cycle).
- **Valid but foreign `uboot_a`** (e.g. the mainline EVB `u-boot.itb`): SPL loads it, nobody
  decrements, slot A is chosen forever. If it hangs or can't boot Android, the only recoveries are
  that image itself (if it reaches a prompt or runs a self-repairing `bootcmd`) or MaskROM (`debrick.md`).
  **Don't flash foreign U-Boot images into `uboot_a`.**

## Evidence

### SPL
`idbloader` header `RKNS` (unencrypted). Entry 1 at sector 4, 0x6c sectors = DDR init (TPL);
entry 2 at sector 0x70, 0x1d8 sectors = SPL, linked at 0x0.

- `0x42cc` = `spl_ab_decrease_tries`: gets the current slot (`0x4110`, prints
  `SPL: A/B-slot: %s, successful: %d, tries-remain: %d`), compares `_a`/`_b`, reads `misc`
  (`0x3fcc`), then `if (!slot.successful && slot.tries) slot.tries--;` (`0x4354–0x4374`).
  If anything changed, it fixes the crc (`0x3ea8`) and writes `misc` (`0x3f08`).
- **Only caller: `0x324c`** in the FIT loader (`0x3194`, `Trying fit image at 0x%lx sector`).
  The loader loops over 2 copies (`+0x200000 / blksz`). Every failure (`IO error`, `Not fit magic`,
  load/hash errors at `0x3370`, `0x338c`, `0x344c`, `0x3510`, `0x3664`) counts one attempt.
  Only after **both** fail does it call `0x42cc` and return the error. A successful load returns
  without touching `misc`.

### Vendor U-Boot (`uboot_a` FIT `images/uboot`, load 0xa00000)
- `0xa249c0` = decrease tries (strings `Can not load metadata`, `Can not save metadata`):
  same `!successful && tries → tries--` (`0xa24a80–0xa24a94`), save (`0xa9045c`).
- Called from `0xa03d80` (strings `Hotkey: ctrl+%c`, `Enter bootrom download...`,
  `Decrease ab tries count fail!`) = Rockchip `board_late_init`-style init. That runs
  unconditionally, before autoboot (`Hit key to stop autoboot('CTRL+C')` is in `0xa160bc`, later).
- `boot_android` (`0xa2767c`) only reads the current slot (`0xa2492c`). It doesn't decrement.

## Tools (`tools/re/`)
```sh
python3 -I tools/re/raw2elf.py spl.bin spl.elf 0x0          # raw binary -> ELF so llvm-objdump can read it
objdump -d --no-show-raw-insn spl.elf > spl.S
python3 -I tools/re/xref.py spl.S spl.bin "SPL: A/B-slot"   # adrp+add string refs (BASE=0xa00000 for U-Boot)
python3 -I tools/re/callers.py uboot.S 0xa90944 5           # call chain upwards
python3 -I tools/re/fnstrings.py uboot.S uboot.bin 0xa00000 0xa03d80   # strings used by a function
```
SPL = `w600d-backup/emmc_first16MiB.bin[64*512:]`, entry 2 of the RKNS header.
U-Boot = `w600d-backup/uboot_a.img[0xe00:0xe00+0xf2f48]`.

## Safe way to run mainline / custom U-Boot: chain-load from USB
Leave the vendor U-Boot (v13) in `uboot_a`. It decrements the tries at init and then runs
`bootcmd_usb0`, which executes `boot.scr` from a USB stick. A `boot.scr` that loads a mainline
`u-boot.bin` (e.g. one with the `typewriter` command, built for RK3568) and jumps to it runs
the foreign U-Boot **without touching eMMC**:
- unplug the stick → Android
- if it hangs → power-cycle; the tries keep counting down, and slot B takes over after ~7 boots.
Untested so far.

The RK3128 (Pomera DM250) U-Boot and the RK3399 coreboot/libreboot ROM in `typerwriter/` are for
other SoCs (32-bit Cortex-A7 / RK3399-only DRAM init and coreboot) and can't run on RK3568 at all.
