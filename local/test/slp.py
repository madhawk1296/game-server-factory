# Minecraft Server List Ping. The handshake carries the hostname the client
# typed, which is exactly what mc-router keys on -- so this tests routing, not
# just reachability.
import socket, struct, json, sys

def varint(n):
    out = b''
    while True:
        x = n & 0x7F
        n >>= 7
        out += bytes([x | 0x80]) if n else bytes([x])
        if not n:
            return out

def read_varint(sock):
    n = shift = 0
    while True:
        b = sock.recv(1)
        if not b:
            raise EOFError("connection closed")
        n |= (b[0] & 0x7F) << shift
        if not (b[0] & 0x80):
            return n
        shift += 7

def ping(host, port, vhost):
    s = socket.create_connection((host, port), timeout=15)
    addr = vhost.encode()
    pkt = b'\x00' + varint(770) + varint(len(addr)) + addr + struct.pack('>H', port) + varint(1)
    s.sendall(varint(len(pkt)) + pkt)
    s.sendall(varint(1) + b'\x00')
    read_varint(s); read_varint(s)
    n = read_varint(s)
    buf = b''
    while len(buf) < n:
        c = s.recv(n - len(buf))
        if not c:
            break
        buf += c
    s.close()
    return json.loads(buf.decode('utf-8'))

if __name__ == "__main__":
    for label, host, port, vhost in [
        ("direct  ", "127.0.0.1", 25566, "localhost"),
        ("router  ", "127.0.0.1", 25565, "smp.mc.localhost"),
        ("router  ", "127.0.0.1", 25565, "nope.mc.localhost"),
    ]:
        try:
            r = ping(host, port, vhost)
            d = r.get('description')
            motd = d.get('text') if isinstance(d, dict) else d
            print(f"{label} {vhost:22} OK  version={r['version']['name']:12} "
                  f"players={r['players']['online']}/{r['players']['max']}  motd={motd!r}")
        except Exception as e:
            print(f"{label} {vhost:22} FAIL  {type(e).__name__}: {e}")
