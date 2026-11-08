#!/usr/bin/env bash
# Build the USB stick files into ../stick/: boot.scr + w600d-demo.bin
set -euo pipefail
cd "$(dirname "$0")"
LOGO=../../logo/logo_w600d.img          # the p17 image flashed on the device (logo on screen)
OUT=../stick

python3 -I mksig.py "$LOGO" sig.h
clang --target=aarch64-none-elf -mcpu=cortex-a55 -O2 -ffreestanding -fno-builtin -nostdlib \
      -fno-pic -fno-stack-protector -fno-asynchronous-unwind-tables -mgeneral-regs-only \
      -Wall -Wextra -Wno-unused-parameter -c demo.c -o demo.o
python3 -I link.py demo.o "$OUT/w600d-demo.bin"
python3 -I mkscr.py boot.cmd "$OUT/boot.scr"
( cd "$OUT" && shasum -a 256 boot.scr w600d-demo.bin > SHA256SUMS && cat SHA256SUMS )
