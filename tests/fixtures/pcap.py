"""pcap.py HOST LINKTYPE: a capture with one TLS ClientHello for HOST, stamped now."""
import struct, sys, time

host, link = sys.argv[1].encode(), int(sys.argv[2])
sni = struct.pack("!BH", 0, len(host)) + host
ext = struct.pack("!HHH", 0, len(sni) + 2, len(sni)) + sni
body = (b"\x03\x03" + b"\x00" * 32 + b"\x00" + b"\x00\x02\x00\x2f" + b"\x01\x00"
        + struct.pack("!H", len(ext)) + ext)
handshake = b"\x01" + len(body).to_bytes(3, "big") + body
tls = b"\x16\x03\x01" + struct.pack("!H", len(handshake)) + handshake
tcp = struct.pack("!HHIIBBHHH", 40000, 443, 1, 0, 5 << 4, 0x18, 65535, 0, 0)
ip = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(tcp) + len(tls), 1, 0, 64, 6, 0,
                 bytes([10, 0, 0, 2]), bytes([1, 2, 3, 4]))
packet = ip + tcp + tls
now = int(time.time())
sys.stdout.buffer.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, link)
                        + struct.pack("<IIII", now, 0, len(packet), len(packet)) + packet)
