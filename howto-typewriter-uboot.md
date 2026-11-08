# HOWTO: the `typewriter` editor in U-Boot on the ZTE W600D SE

`typewriter` is a full-screen, Nano-style text editor for the U-Boot shell, with
a built-in Wubi 86 (五笔) Chinese input method. It draws on the framebuffer and
reads and writes UTF-8 files on FAT or ext4.
Upstream: <https://github.com/scateu/u-boot-typewriter> (written for the RK3399
gru/kevin Chromebook, U-Boot 2026.07). `typewriter/` here is that source plus the
small changes below, so it builds on the W600D (RK3568, U-Boot 2027.01-rc1).
They are also in `patches/typewriter/w600d-changes.patch`, made against the
upstream files.

## Use it
At the `=>` prompt on the laptop:
```
=> typewriter                       # opens usb 0:1 a.txt (the boot stick), created on first save
=> typewriter usb 0:1 notes.txt     # any file; [fat|ext4] [ro] may follow
=> typewriter -h                    # keys
```
Keys: `^S` save, `^X` exit, `^R` open another file, `^Space` Wubi/English,
`^V` run a U-Boot command and insert its output. `typewriter -h` lists the rest.

- **Save to the USB stick.** `mmc 0` (the eMMC, which holds Android) is always
  opened read-only. That lock comes from upstream; it is kept on purpose.
- Filenames must be ASCII. Chinese text *inside* files is fine.
- U-Boot only numbers USB **storage** devices, so the boot stick is `usb 0`
  when it's the only stick (the internal keyboard doesn't count).

## What was changed for the W600D

### 1. RK3399-only code moved behind a new option, `TW_RK3399_POWERSAVE`
Upstream guards its power-saving code with `#if defined(CONFIG_ARM64) && defined(__aarch64__)`.
At startup, that code:
- drops the CPU to 408 MHz through the regulator `ppvar_litcpu_pwm`,
- drops DDR to 400 MHz through a Rockchip bl31 SIP call,
- writes the **RK3399** CRU at `0xff760150` and `0xff760318` to gate clocks,

and its WFI idle path and the `twwfi` command use the RK3399 GIC (`0xfee00000`,
`0xfef10000`) and GPIO0 (`0xff720000`).
On the RK3568 these addresses belong to other blocks, so this code must not run there.

- New `config TW_RK3399_POWERSAVE` (`depends on ARM64 && ROCKCHIP_RK3399`,
  `default y`). The two `#if` lines in `cmd_tw.c` now test it.
  RK3399 builds (gru/kevin) behave exactly as before.
- `TW_WFI_IDLE` now depends on `TW_RK3399_POWERSAVE`.
- `cmd_twwfi.o` is only built with `TW_RK3399_POWERSAVE`.
- The non-RK3399 `tw_idle_nap()` stub used to be `udelay(ms * 1000)`, a 2 s busy
  wait in which no keys are read. It now does the same thing as upstream's
  `!TW_WFI_IDLE` path: `schedule(); udelay(TW_IDLE_POLL_MS * 1000);` (200 ms).
  The USB keyboard is polled through `tstc()`, so this keeps typing responsive.

### 2. The no-EC stub for `tw_poweroff_event_pending()` was commented out
`tw_read_key()` calls `tw_poweroff_event_pending()` to check for a power-button
or lid event. The real version needs `CONFIG_CROS_EC`. The `#else` stub
(`return 0`) was commented out, so **any board without a ChromeOS EC failed to
link** (`undefined reference to tw_poweroff_event_pending`). Gru/kevin never
noticed because it has CROS_EC. The stub is restored.

The W600D has **no ChromeOS EC** (power, lid and battery go through the RK809
PMIC, the BQ25703 charger and the SBS battery). So the defconfig sets
`# CONFIG_CROS_EC is not set` to override the Kconfig's `imply CROS_EC`. As a result:
- `^T` (battery/AC/current) reports that no EC is present,
- inside the editor, the power button and the lid do nothing (no auto power-off),
- `# CONFIG_REGULATOR_PWM is not set`: the W600D rails aren't PWM regulators.

### 3. U-Boot's USB keyboard driver: Ctrl chords (fix in `common/usb_kbd.c`)
With Ctrl held, U-Boot's `usb_kbd` sent **every** key as `scancode - 3`. That is
right for letters (`a` = 0x04 → `^A` = 0x01) but garbage for everything else:
Ctrl-Space came out as `)` (0x2c − 3), so **the IME never toggled**. `^\` came
out as `.`, `^]` as `-`, `^-` as `*`, and Ctrl+Enter or Ctrl+arrow as letters.
It now follows terminal convention:

| Keys | Sends |
|---|---|
| Ctrl + letter | 0x01–0x1a (as before) |
| Ctrl + Space, Ctrl + 2, Ctrl + @ | 0x00 (NUL) → typewriter `KEY_CTRL_SPACE` (Wubi/English) |
| Ctrl + `[` `\` `]` | 0x1b 0x1c 0x1d (`^\` two-column view, `^]` brighter) |
| Ctrl + 6 / `^` | 0x1e |
| Ctrl + `-` `_` `/` | 0x1f (`^-` dimmer) |
| Ctrl + anything else | the key unchanged |

Tested on the W600D: Ctrl-Space toggles Wubi/English. The fix is
`patches/u-boot/0001-usb-kbd-…patch`, a plain bug fix that applies to any board
using a USB keyboard.

### 4. The default file is configurable
A bare `typewriter` used to open `mmc 1:1 a.txt` (the Chromebook's microSD). The
W600D has no SD slot. New strings: `TW_DEFAULT_IFTYPE`, `TW_DEFAULT_DEVPART`, `TW_DEFAULT_FILE`.
Their defaults are `mmc`, `1:1` and `a.txt` (as upstream); the W600D defconfig sets `usb` and `0:1`.
The help text is built from them.

### 5. Built as `cmd/typewriter/`
The sources live in their own directory with their own `Makefile`, instead of
being copied loose into `cmd/`. U-Boot needs two lines for this:
`obj-$(CONFIG_CMD_TYPEWRITER) += typewriter/` in `cmd/Makefile`, and
`source "cmd/typewriter/Kconfig"` before the closing `endif` (of `if CMDLINE`)
in `cmd/Kconfig`. Both are in `patches/u-boot/0004-cmd-hook-up-…patch`.

Nothing else in the editor was changed: `cmd_tw_fs.c`, `cmd_tw_video.c`,
`cmd_tw.h`, `ime_table.*`, `font_data.*` and `wubi_embed.*` are byte-identical to upstream.

## Config (from `zte-w600d-chain-rk3568_defconfig`)
```
CONFIG_CMD_TYPEWRITER=y
CONFIG_TW_DEFAULT_IFTYPE="usb"
CONFIG_TW_DEFAULT_DEVPART="0:1"
# CONFIG_CROS_EC is not set
# CONFIG_REGULATOR_PWM is not set
CONFIG_CONSOLE_RECORD=y        # ^V inserts command output
CONFIG_CMD_BOOTFLOW=y          # ^Q "boot the OS" (bootflow scan -lb)
CONFIG_FS_FAT=y
CONFIG_FAT_WRITE=y
CONFIG_FS_EXT4=y
CONFIG_EXT4_WRITE=y
```

## Size and memory
- `u-boot.bin` grows from 0.96 MB to **1.8 MB** (the Wubi table plus a Unifont
  subset, about 0.8 MB). The vendor U-Boot loads it to `0x00800000`, and its own
  `boot.scr` sits at `0x00c00000`, so the image must stay **under 4 MiB**.
  `build.sh` checks this. If you embed the full dictionary, raise `CONFIG_TEXT_BASE`
  (for example to `0x02000000`) and rebuild the shim with `-DTARGET=0x02000000`.
- The 4 MB line buffer (`g_tw`) is BSS. It is only used after relocation, so it
  lands near the top of RAM, below the hidden vendor logo memory (`SYS_MEM_TOP_HIDE`).
- The file I/O buffers come from the 32 MiB malloc heap (`SYS_MALLOC_LEN=0x2000000`).

## Not available on the W600D
| Feature | Why |
|---|---|
| `^T` battery % | needs a ChromeOS EC. The W600D battery is SBS on I2C behind the charger; no U-Boot driver |
| power button / lid → power off | same: EC host events |
| `^-` / `^]` backlight | the takeover video driver doesn't expose a backlight (the vendor U-Boot keeps the panel lit) |
| `^Q` → power off | PSCI `SYSTEM_OFF` is passed to the vendor TF-A. Untested on this board; if it hangs, hold the power button |
| CPU/DDR down-clocking, WFI idle | RK3399-only (`TW_RK3399_POWERSAVE`) |

## Regenerating the embedded data
`font_data.c` and `wubi_embed.c` are generated (`typewriter/gen.sh`, `gen_font.py`)
from GNU Unifont (`unifont.hex`) and a `wubi.tab` built in the upstream author's
`wubi-fep` project. The generated files are included, so a normal build doesn't need either input.
See `typewriter/README-upstream.md`.
