#!/usr/bin/env python3
"""Inspect and compare netplay recordings (.npr) — the replay determinism test (SPEC.md T5).

  npr.py info rec.npr          frame count, CRC count, ROM MD5
  npr.py diff a.npr b.npr      first frame where input or CRC differs

Format (little endian): "NPR2", rom_md5[16], u8 delay, u32 frames, joy[frames],
u32 crcs, crc[crcs] (u32 each). NES.
SNES: "NPR3", rom_md5[16], u8 delay, u8 system (1), u32 frames, u16 joy[frames],
u32 crcs, crc[crcs].
"""
import struct
import sys


def load(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] not in (b"NPR2", b"NPR3"):
        sys.exit(f"{path}: not an NPR2/NPR3 file")
    wide = data[:4] == b"NPR3"
    md5 = data[4:20].hex()
    delay = data[20]
    off = 22 if wide else 21               # NPR3: one system byte after the delay
    (n,) = struct.unpack_from("<I", data, off)
    off += 4
    if wide:
        joy = list(struct.unpack_from(f"<{n}H", data, off))
        off += 2 * n
    else:
        joy = list(data[off:off + n])
        off += n
    (m,) = struct.unpack_from("<I", data, off)
    crc = list(struct.unpack_from(f"<{m}I", data, off + 4))
    return md5, joy, crc, delay


def main(argv):
    if len(argv) == 3 and argv[1] == "info":
        md5, joy, crc, delay = load(argv[2])
        changes = sum(1 for i in range(1, len(joy)) if joy[i] != joy[i - 1])
        print(f"rom md5 {md5}\ndelay   {delay}\nframes  {len(joy)} ({len(joy) / 60.0988:.1f} s NTSC)\ncrcs    {len(crc)}\npad changes {changes}")
        return 0
    if len(argv) == 4 and argv[1] == "diff":
        a, b = load(argv[2]), load(argv[3])
        if a[0] != b[0]:
            print(f"different ROMs: {a[0]} vs {b[0]}")
            return 1
        for name, x, y in (("input", a[1], b[1]), ("crc", a[2], b[2])):
            n = min(len(x), len(y))
            first = next((i for i in range(n) if x[i] != y[i]), None)
            if first is not None:
                print(f"{name} differs first at frame {first}: {x[first]:#x} vs {y[first]:#x}")
                return 1
            print(f"{name}: {n} frames identical")
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
