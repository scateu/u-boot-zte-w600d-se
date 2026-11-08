#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0+
"""Wrap a text U-Boot script into a legacy uImage (type script) = boot.scr, like
`mkimage -A arm64 -T script -C none -d boot.cmd boot.scr`, with one difference: the vendor U-Boot's
`source` (0xa07f4c in uboot_a) skips the image-length table until a word == 0xFFFFFFFF, not 0 as in
mainline/mkimage. A mkimage script makes it run garbage (2026-11-06, usb-demo runs 1-4), so the
table is terminated with 0xFFFFFFFF here. Such a boot.scr only works on this vendor U-Boot.

usage: mkscr.py <boot.cmd> <boot.scr>
"""
import struct, sys, time, zlib

IH_MAGIC, IH_OS_LINUX, IH_ARCH_ARM64, IH_TYPE_SCRIPT, IH_COMP_NONE = 0x27051956, 5, 22, 6, 0


def main():
    text = open(sys.argv[1], 'rb').read()
    # script payload: table of image lengths (one), terminator 0xFFFFFFFF (vendor quirk), then the data
    data = struct.pack('>II', len(text), 0xffffffff) + text
    hdr = struct.pack('>IIIIIIIBBBB32s', IH_MAGIC, 0, int(time.time()), len(data), 0, 0,
                      zlib.crc32(data) & 0xffffffff, IH_OS_LINUX, IH_ARCH_ARM64, IH_TYPE_SCRIPT,
                      IH_COMP_NONE, b'W600D USB demo')
    hdr = hdr[:4] + struct.pack('>I', zlib.crc32(hdr) & 0xffffffff) + hdr[8:]
    open(sys.argv[2], 'wb').write(hdr + data)
    print('%s: %d bytes' % (sys.argv[2], len(hdr) + len(data)))


if __name__ == '__main__':
    main()
