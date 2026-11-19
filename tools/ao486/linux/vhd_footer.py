#!/usr/bin/env python3
"""Append a fixed-disk VHD footer to a raw disk image (Microsoft VHD format 1.0).

    vhd_footer.py <raw image> <out.vhd>

The geometry is the one the VHD specification derives from the size (the
MiSTer computes its own from the size and ignores the footer).
"""
import struct, sys, time, uuid

raw, out = sys.argv[1], sys.argv[2]
data = open(raw, "rb").read()
size = len(data)
sectors = size // 512

# geometry as in the VHD specification, appendix
if sectors > 65535 * 16 * 255:
    sectors = 65535 * 16 * 255
if sectors >= 65535 * 16 * 63:
    spt, heads = 255, 16
    cth = sectors // spt
else:
    spt = 17
    cth = sectors // spt
    heads = (cth + 1023) // 1024
    if heads < 4:
        heads = 4
    if cth >= heads * 1024 or heads > 16:
        spt, heads = 31, 16
        cth = sectors // spt
    if cth >= heads * 1024:
        spt, heads = 63, 16
        cth = sectors // spt
cyl = cth // heads

f = bytearray(512)
f[0:8] = b"conectix"
struct.pack_into(">I", f, 8, 2)                      # features: reserved bit
struct.pack_into(">I", f, 12, 0x00010000)            # version 1.0
struct.pack_into(">Q", f, 16, 0xFFFFFFFFFFFFFFFF)    # data offset: fixed disk
struct.pack_into(">I", f, 24, int(time.time()) - 946684800)
f[28:32] = b"npl "                                   # creator application
struct.pack_into(">I", f, 32, 0x00010000)
f[36:40] = b"Wi2k"
struct.pack_into(">Q", f, 40, size)                  # original size
struct.pack_into(">Q", f, 48, size)                  # current size
struct.pack_into(">HBB", f, 56, cyl, heads, spt)
struct.pack_into(">I", f, 60, 2)                     # disk type: fixed
f[68:84] = uuid.uuid4().bytes
checksum = (~sum(f)) & 0xFFFFFFFF
struct.pack_into(">I", f, 64, checksum)

with open(out, "wb") as o:
    o.write(data)
    o.write(f)
