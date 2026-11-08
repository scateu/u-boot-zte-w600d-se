# wrap a raw aarch64 binary into a minimal ELF64 with one executable PT_LOAD/.text at BASE
import struct, sys
src, dst, base = sys.argv[1], sys.argv[2], int(sys.argv[3], 0)
code = open(src, 'rb').read()
shstr = b'\0.text\0.shstrtab\0'
ehsz, phsz, shsz = 64, 56, 64
code_off = 0x1000
shstr_off = code_off + len(code)
sh_off = (shstr_off + len(shstr) + 7) & ~7
eh = struct.pack('<16sHHIQQQIHHHHHH', b'\x7fELF\x02\x01\x01' + b'\0' * 9, 2, 183, 1, base,
                 ehsz, sh_off, 0, ehsz, phsz, 1, shsz, 3, 2)
ph = struct.pack('<IIQQQQQQ', 1, 5, code_off, base, base, len(code), len(code), 0x1000)
sh = b'\0' * shsz
sh += struct.pack('<IIQQQQIIQQ', 1, 1, 6, base, code_off, len(code), 0, 0, 4, 0)
sh += struct.pack('<IIQQQQIIQQ', 7, 3, 0, 0, shstr_off, len(shstr), 0, 0, 1, 0)
out = bytearray(eh + ph)
out += b'\0' * (code_off - len(out)) + code + shstr
out += b'\0' * (sh_off - len(out)) + sh
open(dst, 'wb').write(out)
