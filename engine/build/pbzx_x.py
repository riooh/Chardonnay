import struct, sys, lzma

path, out_path = sys.argv[1], sys.argv[2]
data = open(path, "rb").read()
assert data[:4] == b"pbzx", "not a pbzx file"

i = 12  # pbzx magic + 8 header bytes
out = bytearray()
n = 0
while i + 16 <= len(data):
    dec, comp = struct.unpack(">QQ", data[i:i+16])
    i += 16
    if comp == 0 or i + comp > len(data):
        break
    chunk = data[i:i+comp]
    i += comp
    out += lzma.decompress(chunk)
    n += 1
print("chunks: %d, decompressed %d bytes" % (n, len(out)))
open(out_path, "wb").write(bytes(out))