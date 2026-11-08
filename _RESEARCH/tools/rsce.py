#!/usr/bin/env python3
"""List / extract a Rockchip RSCE resource image, or the one inside an Android boot image v0-2.

usage: rsce.py <resource.img | boot.img> [OUTDIR]
"""
import os, struct, sys


def find_rsce(d):
    if d[:8] == b'ANDROID!':
        ksz, _, rsz, _, ssz = struct.unpack('<5I', d[8:28])
        page = struct.unpack('<I', d[36:40])[0]
        up = lambda n: (n + page - 1) // page * page
        off = page + up(ksz) + up(rsz)
        return d[off:off + ssz]
    return d


def main():
    d = find_rsce(open(sys.argv[1], 'rb').read())
    assert d[:4] == b'RSCE', 'no RSCE resource found'
    # magic, u16 ver, u16 index ver, u8 header blocks, u8 table offset, u8 entry blocks, u32 count
    tbl, ent_blks, count = d[9], d[10], struct.unpack('<I', d[12:16])[0]
    out = sys.argv[2] if len(sys.argv) > 2 else None
    if out:
        os.makedirs(out, exist_ok=True)
    for i in range(count):
        e = d[(tbl + i * ent_blks) * 512:][:ent_blks * 512]
        name = e[4:260].split(b'\0')[0].decode()
        blk, size = struct.unpack('<II', e[260:268])
        print('%-40s %9d' % (name, size))
        if out:
            open(os.path.join(out, name.replace('#', '__')), 'wb').write(d[blk * 512:blk * 512 + size])


if __name__ == '__main__':
    main()
