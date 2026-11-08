#!/usr/bin/env python3
"""List / extract partitions from an Android A/B OTA payload.bin (full OTAs only).

Pure Python, no protobuf module needed. Supports REPLACE, REPLACE_BZ, REPLACE_XZ, ZERO,
DISCARD, which is everything a full (non-incremental) OTA uses.

usage: payload-extract.py payload.bin                 # list partitions
       payload-extract.py payload.bin OUTDIR [names]  # extract (all, or the named ones)
"""
import bz2, hashlib, lzma, os, struct, sys

OPS = {0: 'REPLACE', 1: 'REPLACE_BZ', 4: 'SOURCE_COPY', 5: 'SOURCE_BSDIFF', 6: 'ZERO',
       7: 'DISCARD', 8: 'REPLACE_XZ', 9: 'PUFFDIFF', 10: 'BROTLI_BSDIFF'}


def varint(b, i):
    v = s = 0
    while True:
        c = b[i]; i += 1
        v |= (c & 0x7f) << s; s += 7
        if c < 0x80:
            return v, i


def fields(b):
    """Yield (field_number, value) for one protobuf message; nested messages stay bytes."""
    i = 0
    while i < len(b):
        key, i = varint(b, i)
        f, t = key >> 3, key & 7
        if t == 0:
            v, i = varint(b, i)
        elif t == 1:
            v = b[i:i + 8]; i += 8
        elif t == 2:
            n, i = varint(b, i); v = b[i:i + n]; i += n
        elif t == 5:
            v = b[i:i + 4]; i += 4
        else:
            raise ValueError('wire type %d' % t)
        yield f, v


def parse(path):
    with open(path, 'rb') as fh:
        hdr = fh.read(24)
        assert hdr[:4] == b'CrAU', 'not a payload.bin'
        ver, msize = struct.unpack('>QQ', hdr[4:20])
        sigsize = struct.unpack('>I', hdr[20:24])[0] if ver >= 2 else 0
        manifest = fh.read(msize)
    data_start = 24 + msize + sigsize
    block = 4096
    parts = []
    for f, v in fields(manifest):
        if f == 3:
            block = v
        elif f == 13:
            p = {'name': '', 'size': 0, 'hash': b'', 'ops': []}
            for pf, pv in fields(v):
                if pf == 1:
                    p['name'] = pv.decode()
                elif pf == 7:
                    for k, x in fields(pv):
                        if k == 1: p['size'] = x
                        if k == 2: p['hash'] = x
                elif pf == 8:
                    op = {'type': 0, 'off': 0, 'len': 0, 'dst': []}
                    for k, x in fields(pv):
                        if k == 1: op['type'] = x
                        elif k == 2: op['off'] = x
                        elif k == 3: op['len'] = x
                        elif k == 6:
                            e = dict(fields(x)); op['dst'].append((e.get(1, 0), e.get(2, 0)))
                    p['ops'].append(op)
            parts.append(p)
    return data_start, block, parts


def extract(path, outdir, want):
    data_start, block, parts = parse(path)
    os.makedirs(outdir, exist_ok=True)
    with open(path, 'rb') as fh:
        for p in parts:
            if want and p['name'] not in want:
                continue
            out = os.path.join(outdir, p['name'] + '.img')
            with open(out, 'wb') as o:
                o.truncate(p['size'])
                for op in p['ops']:
                    t = op['type']
                    if t in (6, 7):
                        continue                    # ZERO/DISCARD: already zero (sparse)
                    fh.seek(data_start + op['off'])
                    d = fh.read(op['len'])
                    if t == 1: d = bz2.decompress(d)
                    elif t == 8: d = lzma.decompress(d)
                    elif t != 0:
                        raise SystemExit('%s: op %s needs the source image (incremental OTA)'
                                         % (p['name'], OPS.get(t, t)))
                    pos = 0
                    for start, num in op['dst']:
                        n = num * block
                        o.seek(start * block); o.write(d[pos:pos + n]); pos += n
            h = hashlib.sha256()
            with open(out, 'rb') as r:
                for chunk in iter(lambda: r.read(1 << 20), b''):
                    h.update(chunk)
            ok = 'OK' if h.digest() == p['hash'] else 'HASH MISMATCH'
            print('%-16s %12d  %s' % (p['name'], p['size'], ok))


def main():
    if len(sys.argv) == 2:
        _, block, parts = parse(sys.argv[1])
        for p in parts:
            types = sorted({OPS.get(o['type'], o['type']) for o in p['ops']})
            print('%-16s %12d  %s' % (p['name'], p['size'], ','.join(map(str, types))))
    else:
        extract(sys.argv[1], sys.argv[2], set(sys.argv[3:]))


if __name__ == '__main__':
    main()
