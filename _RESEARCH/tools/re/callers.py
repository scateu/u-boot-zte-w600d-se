# callers chain: for a function address, list call sites and their containing function (nearest preceding 'stp x29, x30')
import re, sys
lines = open(sys.argv[1]).read().splitlines()
insn = []
for l in lines:
    m = re.match(r'\s*([0-9a-f]+):\s+(\w+)\s*(.*)', l)
    if m: insn.append((int(m[1], 16), m[2], m[3]))
starts = [a for a, op, ar in insn if op == 'stp' and ar.startswith('x29, x30') and ar.endswith('!')]
import bisect
def func_of(a):
    i = bisect.bisect_right(starts, a) - 1
    return starts[i] if i >= 0 else None
def callers(f):
    return [(a, func_of(a)) for a, op, ar in insn if op in ('bl', 'b') and ar.startswith('0x%x ' % f)]
seen = set()
def walk(f, depth):
    for a, fn in callers(f):
        print('  ' * depth + '%#x called at %#x in fn %#x' % (f, a, fn or 0))
        if fn and fn not in seen and depth < int(sys.argv[3]):
            seen.add(fn); walk(fn, depth + 1)
walk(int(sys.argv[2], 0), 0)
