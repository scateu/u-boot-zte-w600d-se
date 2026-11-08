#!/usr/bin/env python3
"""Patch the default environment of the stock W600D uboot_a.img (Rockchip U-Boot 2017.09 FIT).

uboot_a holds two identical FIT copies (0x0 and 0x200000). SPL tries them in order and checks
the sha256 of each image. Only copy 0 is patched: if it is rejected, SPL loads the untouched copy 1.

Only the `uboot` image hash in the FIT header is updated. The RSA signature becomes stale, but
SPL has no public key, so it isn't checked (see HOWTO-patch-uboot.md).

usage: patch-uboot-env.py <stock uboot_a.img> <out.img> [VAR=VALUE ...]
       (no VAR=VALUE: apply the default W600D patch below)
"""
import hashlib, struct, sys

COPY = 0x200000

# v15 (2026-11-06) = v13 with bootdelay left at the stock 0 (3 only gave a serial-only
# countdown). v13 (boots): USB stick first (extlinux.conf / boot.scr), then eMMC extlinux, then
# Android exactly as stock. Flat list: an `if` written directly in bootcmd resets the board
# (v1, v2, v8, v11, v12); `if` inside scripts started with `run` is fine. See HOWTO-patch-uboot.md §8.
DEFAULT = {
    'bootcmd': 'run bootcmd_usb0;run bootcmd_mmc0;usb stop;boot_fit;boot_android ${devtype} ${devnum};'
               'run distro_bootcmd;',
    # no network in U-Boot here: free bytes for the longer bootcmd
    'bootcmd_pxe': '',
}


def fdt_prop(blob, path, prop):
    """Return (offset, length) of a property value in an FDT. path like 'images/uboot/hash'."""
    off_struct, off_strings = struct.unpack('>II', blob[8:16])
    want = path.split('/')
    stack, i = [], off_struct
    while True:
        tag = struct.unpack('>I', blob[i:i + 4])[0]; i += 4
        if tag == 1:                                        # BEGIN_NODE
            end = blob.index(b'\0', i)
            stack.append(blob[i:end].decode()); i = (end + 4) & ~3
        elif tag == 2:                                      # END_NODE
            stack.pop()
        elif tag == 3:                                      # PROP
            ln, nameoff = struct.unpack('>II', blob[i:i + 8]); i += 8
            name = blob[off_strings + nameoff:blob.index(b'\0', off_strings + nameoff)].decode()
            if stack[1:] == want and name == prop:
                return i, ln
            i = (i + ln + 3) & ~3
        elif tag == 4:                                      # NOP
            pass
        elif tag == 9:                                      # END
            raise KeyError(path + ':' + prop)


def u32(blob, path, prop):
    o, _ = fdt_prop(blob, path, prop)
    return struct.unpack('>I', blob[o:o + 4])[0]


def main():
    src, out = sys.argv[1], sys.argv[2]
    changes = dict(a.split('=', 1) for a in sys.argv[3:]) or DEFAULT
    img = bytearray(open(src, 'rb').read())
    assert img[:COPY] == img[COPY:2 * COPY], 'expected two identical FIT copies'

    pos, size = u32(img, 'images/uboot', 'data-position'), u32(img, 'images/uboot', 'data-size')
    hoff, hlen = fdt_prop(img, 'images/uboot/hash', 'value')
    assert hashlib.sha256(img[pos:pos + size]).digest() == bytes(img[hoff:hoff + hlen]), 'stock hash mismatch'

    # default environment: NUL-separated "var=value" strings ending in an empty string
    start = img.index(b'bootcmd=', pos, pos + size)
    end = img.index(b'\0\0', start) + 1                 # include the last NUL
    env = [kv for kv in bytes(img[start:end]).split(b'\0') if kv]
    names = [kv.split(b'=', 1)[0].decode() for kv in env]
    for k in changes:
        assert k in names, 'unknown variable %s (only existing ones can be changed)' % k
    new = b''.join((k + '=' + changes[k]).encode() + b'\0' if k in changes else kv + b'\0'
                   for k, kv in zip(names, env))
    room = end - start
    assert len(new) <= room, 'new environment is %d bytes too long' % (len(new) - room)
    img[start:end] = new + b'\0' * (room - len(new))   # pad: extra NULs end the list early

    img[hoff:hoff + hlen] = hashlib.sha256(img[pos:pos + size]).digest()
    open(out, 'wb').write(img)

    for k in changes:
        print('%s=%s' % (k, changes[k]))
    print('env: %d of %d bytes used; copy 0 patched, copy 1 (0x200000) untouched' % (len(new), room))


if __name__ == '__main__':
    main()
