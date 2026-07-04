#!/usr/bin/env python3
# Build a 10.5-native .icns (classic is32/il32/ih32/it32 reps + 8-bit masks,
# plus ic08/ic09 PNG for 10.6+) from the square source art. Run on a Mac with PIL.
import struct, io, sys
from PIL import Image

SRC = "design/icon/degelato-icon-glossy.png"
OUT = "Resources/DeGelato.icns"

src = Image.open(SRC).convert("RGBA")
w, h = src.size
s = min(w, h)                      # center-crop to square
src = src.crop(((w - s)//2, (h - s)//2, (w - s)//2 + s, (h - s)//2 + s))

def icns_rle(data):
    out = bytearray(); i = 0; n = len(data)
    while i < n:
        j = i
        while j < n and data[j] == data[i] and (j - i) < 130: j += 1
        if j - i >= 3:
            out.append(0x80 + (j - i) - 3); out.append(data[i]); i = j
        else:
            lit = bytearray(); j = i
            while j < n and len(lit) < 128:
                k = j
                while k < n and data[k] == data[j] and (k - j) < 3: k += 1
                if k - j >= 3: break
                lit.append(data[j]); j += 1
            out.append(len(lit) - 1); out.extend(lit); i = j
    return bytes(out)

def rgb_rle(img):
    r, g, b, a = img.split()
    return icns_rle(r.tobytes()) + icns_rle(g.tobytes()) + icns_rle(b.tobytes())

def alpha(img):
    return img.split()[3].tobytes()

def png(img):
    bio = io.BytesIO(); img.save(bio, "PNG"); return bio.getvalue()

def rz(px):
    return src.resize((px, px), Image.LANCZOS)

i16, i32, i48, i128 = rz(16), rz(32), rz(48), rz(128)
members = [
    (b'is32', rgb_rle(i16)),  (b's8mk', alpha(i16)),
    (b'il32', rgb_rle(i32)),  (b'l8mk', alpha(i32)),
    (b'ih32', rgb_rle(i48)),  (b'h8mk', alpha(i48)),
    (b'it32', b'\x00\x00\x00\x00' + rgb_rle(i128)), (b't8mk', alpha(i128)),
    (b'ic08', png(rz(256))),  (b'ic09', png(rz(512))),
]
body = b''.join(t + struct.pack('>I', len(d) + 8) + d for t, d in members)
data = b'icns' + struct.pack('>I', len(body) + 8) + body
open(OUT, "wb").write(data)
print("wrote %d bytes; types: %s" % (len(data), ", ".join(t.decode() for t, _ in members)))
