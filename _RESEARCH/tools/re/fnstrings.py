# print strings referenced (adrp+add) inside the functions starting at the given addresses
import re, sys, bisect
lst, binf, base = sys.argv[1], sys.argv[2], int(sys.argv[3], 0)
data = open(binf, 'rb').read()
insn = []
for l in open(lst):
    m = re.match(r'\s*([0-9a-f]+):\s+(\w+)\s*(.*)', l)
    if m: insn.append((int(m[1], 16), m[2], m[3]))
addrs = [a for a, _, _ in insn]
def cstr(v):
    o = v - base
    if not 0 <= o < len(data): return None
    e = data.find(b'\0', o)
    s = data[o:e]
    return s.decode() if 3 <= len(s) < 120 and all(32 <= c < 127 or c in (9, 10) for c in s) else None
for f in sys.argv[4:]:
    f = int(f, 0); i = bisect.bisect_left(addrs, f); pages = {}; out = []
    while i < len(insn):
        a, op, ar = insn[i]
        if a != f and op == 'stp' and ar.startswith('x29, x30') and ar.endswith('!'): break
        if op == 'adrp':
            m = re.match(r'(\w+), (0x[0-9a-f]+)', ar); pages[m[1]] = int(m[2], 16)
        elif op == 'add':
            m = re.match(r'(\w+), (\w+), #(0x[0-9a-f]+|\d+)$', ar)
            if m and m[2] in pages:
                s = cstr(pages[m[2]] + int(m[3], 0))
                if s: out.append(repr(s)[:70])
        i += 1
    print('%#x:' % f, ' | '.join(dict.fromkeys(out)) or '-')
