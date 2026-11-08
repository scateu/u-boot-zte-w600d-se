#!/usr/bin/env python3
"""Build a patched W600D `logo` partition image (p17).

Layout found in the stock dump: two identical BMPs (1920x1080x24, bottom-up,
6220854 bytes), at offset 0 (U-Boot logo) and 0x5eee00 (kernel logo), rest zero.
We keep the BMP header byte-identical and only change pixels.
Quirk: the header says bottom-up (+1080) but the pixel rows are really stored
top-down (ZTE's U-Boot draws row 0 at the top). Opened on a PC it looks upside down.

usage: make-logo.py <stock logo.img> <out.img> [TEXT]
"""
import sys

W, H, ROW = 1920, 1080, 1920 * 3
HDR, BMP_SIZE, SECOND = 54, 6220854, 0x5eee00

# 5x7 font, just the glyphs we need
FONT = {
    'W': ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
    '6': ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
    '0': ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    'D': ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    'L': ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    'I': ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    'N': ["10001", "11001", "10101", "10101", "10011", "10001", "10001"],
    'U': ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    'X': ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    ' ': ["00000"] * 7,
}


def draw_text(px, text, top, scale, bgr):
    width = len(text) * 6 * scale - scale
    left = (W - width) // 2
    for n, ch in enumerate(text):
        for gy, line in enumerate(FONT[ch]):
            for gx, bit in enumerate(line):
                if bit != '1':
                    continue
                for dy in range(scale):
                    y = top + gy * scale + dy          # y from the top of the screen
                    row = y * ROW                      # rows stored top-down (see above)
                    for dx in range(scale):
                        x = left + (n * 6 + gx) * scale + dx
                        px[row + x * 3:row + x * 3 + 3] = bgr


def main():
    src, out = sys.argv[1], sys.argv[2]
    text = sys.argv[3].upper() if len(sys.argv) > 3 else "W600D LINUX"
    part = open(src, 'rb').read()
    bmp = part[:BMP_SIZE]
    assert bmp[:2] == b'BM' and part[SECOND:SECOND + BMP_SIZE] == bmp, "unexpected stock layout"

    px = bytearray(bmp[HDR:])
    draw_text(px, text, top=820, scale=10, bgr=bytes((0x00, 0xa5, 0xff)))  # orange
    new = bmp[:HDR] + bytes(px)

    img = bytearray(len(part))
    img[0:BMP_SIZE] = new
    img[SECOND:SECOND + BMP_SIZE] = new
    open(out, 'wb').write(img)
    open(out + '.bmp', 'wb').write(new)   # for previewing on the Mac


if __name__ == '__main__':
    main()
