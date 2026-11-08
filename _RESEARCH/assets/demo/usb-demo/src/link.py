#!/usr/bin/env python3
"""Minimal linker: AArch64 relocatable ELF (.o) -> flat position-independent binary.
macOS has clang for aarch64-none-elf but no ELF linker. Lays out .text (entry `_start` must be at
offset 0) and the read-only data sections, then resolves the PC-relative relocations clang emits.
Anything needing an absolute address or writable data is refused.

usage: link.py <in.o> <out.bin>
"""
import struct, sys

R = {   # AArch64 relocation types we can resolve in a position-independent image
    257: 'ABS64?', 261: 'PREL32', 274: 'ADR_PREL_LO21', 275: 'ADR_PREL_PG_HI21',
    277: 'ADD_ABS_LO12_NC', 278: 'LDST8_ABS_LO12_NC', 279: 'TSTBR14', 280: 'CONDBR19',
    282: 'JUMP26', 283: 'CALL26', 284: 'LDST16_ABS_LO12_NC', 285: 'LDST32_ABS_LO12_NC',
    286: 'LDST64_ABS_LO12_NC', 299: 'LDST128_ABS_LO12_NC',
}


def main():
    d = open(sys.argv[1], 'rb').read()
    assert d[:4] == b'\x7fELF' and d[4] == 2 and struct.unpack('<H', d[18:20])[0] == 183, 'not aarch64 ELF64'
    shoff, = struct.unpack('<Q', d[40:48])
    shentsize, shnum, shstrndx = struct.unpack('<HHH', d[58:64])
    sh = [struct.unpack('<IIQQQQIIQQ', d[shoff + i * shentsize:shoff + (i + 1) * shentsize]) for i in range(shnum)]
    strtab = lambda off, i: d[off + i:d.index(b'\0', off + i)].decode()
    name = lambda i: strtab(sh[shstrndx][4], sh[i][0])

    # layout: .text first, then other allocated sections (4 KiB page alignment keeps ADRP simple)
    alloc = [i for i in range(shnum) if sh[i][2] & 2 and sh[i][5]]
    alloc.sort(key=lambda i: (name(i) != '.text', i))
    base, img = {}, bytearray()
    for i in alloc:
        typ, flags, size, align = sh[i][1], sh[i][2], sh[i][5], max(sh[i][8], 1)
        assert not flags & 1 or name(i).startswith('.text'), 'writable section %s not supported' % name(i)
        assert typ != 8, 'NOBITS section %s (.bss) not supported' % name(i)
        img += b'\0' * (-len(img) % max(align, 16))
        base[i] = len(img)
        img += d[sh[i][4]:sh[i][4] + size]

    symtab = next(i for i in range(shnum) if sh[i][1] == 2)
    stroff = sh[sh[symtab][6]][4]
    syms = []
    for k in range(sh[symtab][5] // 24):
        o = sh[symtab][4] + k * 24
        st_name, info, other, shndx, value, size = struct.unpack('<IBBHQQ', d[o:o + 24])
        syms.append((strtab(stroff, st_name), shndx, value))

    start = [s for s in syms if s[0] == '_start']
    assert start and base.get(start[0][1]) == 0 and start[0][2] == 0, '_start must be at offset 0'

    for i in range(shnum):
        if sh[i][1] != 4 or sh[i][7] not in base:      # SHT_RELA for an allocated section
            continue
        tgt = base[sh[i][7]]
        for k in range(sh[i][5] // 24):
            off, info, add = struct.unpack('<QQq', d[sh[i][4] + k * 24:sh[i][4] + k * 24 + 24])
            typ, si = info & 0xffffffff, info >> 32
            sname, shndx, value = syms[si]
            assert shndx in base, 'undefined/unsupported symbol %r (reloc %d)' % (sname, typ)
            P, S = tgt + off, base[shndx] + value
            v = S + add
            ins, = struct.unpack('<I', img[P:P + 4])
            if typ == 283 or typ == 282:                  # CALL26 / JUMP26
                ins = (ins & 0xfc000000) | (((v - P) >> 2) & 0x3ffffff)
            elif typ == 280:                              # CONDBR19
                ins = (ins & 0xff00001f) | ((((v - P) >> 2) & 0x7ffff) << 5)
            elif typ == 279:                              # TSTBR14
                ins = (ins & 0xfff8001f) | ((((v - P) >> 2) & 0x3fff) << 5)
            elif typ == 275:                              # ADRP: page delta (image placed 4 KiB aligned)
                pd = ((v & ~0xfff) - (P & ~0xfff)) >> 12
                ins = (ins & 0x9f00001f) | ((pd & 3) << 29) | (((pd >> 2) & 0x7ffff) << 5)
            elif typ == 274:                              # ADR
                pd = v - P
                ins = (ins & 0x9f00001f) | ((pd & 3) << 29) | (((pd >> 2) & 0x7ffff) << 5)
            elif typ == 277:                              # ADD :lo12:
                ins = (ins & 0xffc003ff) | ((v & 0xfff) << 10)
            elif typ in (278, 284, 285, 286, 299):         # LDST :lo12: scaled by access size
                sc = {278: 0, 284: 1, 285: 2, 286: 3, 299: 4}[typ]
                assert v & ((1 << sc) - 1) == 0, 'misaligned LDST reloc'
                ins = (ins & 0xffc003ff) | (((v & 0xfff) >> sc) << 10)
            elif typ == 261:                              # PREL32 (data)
                struct.pack_into('<i', img, P, v - P)
                continue
            else:
                raise SystemExit('unsupported relocation %d (%s) at %#x -> %s' % (typ, R.get(typ, '?'), P, sname))
            struct.pack_into('<I', img, P, ins)

    open(sys.argv[2], 'wb').write(img)
    print('%s: %d bytes, sections %s' % (sys.argv[2], len(img), ' '.join('%s@%#x' % (name(i), base[i]) for i in alloc)))


if __name__ == '__main__':
    main()
