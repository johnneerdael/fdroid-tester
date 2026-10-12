"""png.py W H: writes a W x H grey PNG to stdout (a fake screenshot)."""
import struct, sys, zlib

w, h = int(sys.argv[1]), int(sys.argv[2])


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


rows = b"".join(b"\x00" + b"\x80" * w for _ in range(h))
sys.stdout.buffer.write(b"\x89PNG\r\n\x1a\n"
                        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
                        + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
