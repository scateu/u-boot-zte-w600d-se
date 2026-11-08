# find adrp+add references to given string offsets in an llvm-objdump listing; print containing function start guesses
import re, sys
lst, binf = sys.argv[1], sys.argv[2]
data = open(binf, "rb").read(); BASE = int(__import__("os").environ.get("BASE","0"),0)
targets = {}
for s in sys.argv[3:]:
    i = data.find(s.encode())
    while i >= 0:
        targets[i + BASE] = s; i = data.find(s.encode(), i + 1)
for t, s in targets.items(): print('string %#x %s' % (t, s))
pages = {}
for line in open(lst):
    m = re.match(r'\s*([0-9a-f]+):\s+(\w+)\s+(.*)', line)
    if not m: continue
    a, op, args = int(m[1], 16), m[2], m[3]
    if op == 'adrp':
        r, v = re.match(r'(\w+), (0x[0-9a-f]+)', args).groups(); pages[r] = (int(v, 16), a)
    elif op == 'add':
        mm = re.match(r'(\w+), (\w+), #(0x[0-9a-f]+|\d+)', args)
        if mm and mm[2] in pages and a - pages[mm[2]][1] < 64:
            v = pages[mm[2]][0] + int(mm[3], 0)
            if v in targets: print('%#x -> %s' % (a, targets[v]))
    elif op == 'adr':
        mm = re.match(r'(\w+), (0x[0-9a-f]+)', args)
        if mm and int(mm[2], 16) in targets: print('%#x adr-> %s' % (a, targets[int(mm[2], 16)]))
