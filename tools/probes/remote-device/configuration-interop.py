#!/usr/bin/env python3
"""Check one explicit probe configuration without opening a network listener."""
import hashlib, importlib.util, json, subprocess, sys
from pathlib import Path

here = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("handshake", here / "handshake-interop.py")
h = importlib.util.module_from_spec(spec); spec.loader.exec_module(h)

def read_small_value(payload, offset):
    tag = payload[offset]; offset += 1
    if 0x70 <= tag <= 0x90:
        n = tag - 0x70
    else:
        width = 1 << (tag - 0x91)
        n = int.from_bytes(payload[offset:offset + width], "little"); offset += width
    return payload[offset:offset + n], offset + n

def read_pairing_response(encoded, kind):
    packet = bytes.fromhex(encoded)
    assert packet[0] == kind and int.from_bytes(packet[1:4], "big") == len(packet) - 4
    payload = packet[4:]
    count = payload[0] - 0xe0
    assert 1 <= count <= 2
    offset = 1; fields = {}
    for _ in range(count):
        key_tag = payload[offset]; assert 0x40 <= key_tag <= 0x5f
        key_len = key_tag - 0x40
        key = payload[offset + 1:offset + 1 + key_len].decode(); offset += 1 + key_len
        if key == "_pd": value, offset = read_small_value(payload, offset)
        elif key == "_pwTy": assert payload[offset] == 0x09; value = 1; offset += 1
        else: raise AssertionError(key)
        fields[key] = value
    assert offset == len(payload)
    return fields

class Bridge:
    def __init__(self, path):
        self.process = subprocess.Popen([str(path), "--wire-test-json", "--reply-policy", "upstream-reference",
            "--pairing-envelope", "type1", "--identifier-form", "hyphenated", "--m6-metadata", "probe-label"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    def send(self, value=None, **kwargs):
        value = value if value is not None else kwargs
        self.process.stdin.write(json.dumps(value) + "\n"); self.process.stdin.flush()
        line = self.process.stdout.readline(); assert line, self.process.stderr.read()
        return json.loads(line)
    def feed(self, packet):
        for part in (packet[:2], packet[2:7]):
            result = self.send({"op": "feed", "bytes": part.hex()}); assert not result["frames"]
        return self.send({"op": "feed", "bytes": packet[7:].hex()})
    def close(self):
        self.process.stdin.close(); self.process.wait(timeout=5)
        assert self.process.returncode == 0, self.process.stderr.read()

def main():
    path = Path(sys.argv[1]); bridge = Bridge(path)
    try:
        first = bridge.feed(h.frame(3, [(6, b"\x01"), (0, b"\x00")]))
        fields = read_pairing_response(first["frames"][0], 4)
        assert fields.get("_pwTy") == 1 and first["configuration"]["pairingEnvelope"] == "type1"
        m2 = h.r.read_tlv(fields["_pd"])
        ctx = h.r.SRPContext("Pair-Setup", "3939", prime=h.r.constants.PRIME_3072,
            generator=h.r.constants.PRIME_3072_GEN, hash_func=hashlib.sha512)
        client = h.r.SRPClientSession(ctx); client.process(m2[3].hex(), m2[2].hex())
        second = bridge.feed(h.frame(4, [(6, b"\x03"), (3, h.r.raw(client.public)), (4, h.r.raw(client.key_proof))]))
        m4 = h.r.read_tlv(second["frames"][0] and read_pairing_response(second["frames"][0], 4)["_pd"]); assert client.verify_proof(m4[4].hex().encode())
        key = h.r.raw(client.key); encryption = h.r.derive(key, "Encrypt")
        signing = h.r.Ed25519PrivateKey.generate(); public = signing.public_key().public_bytes(h.r.serialization.Encoding.Raw, h.r.serialization.PublicFormat.Raw)
        identifier = b"configured-controller"; signature = signing.sign(h.r.derive(key, "Controller-Sign") + identifier + public)
        plain = h.r.tlv([(1, identifier), (3, public), (10, signature)])
        encrypted = h.r.ChaCha20Poly1305(encryption).encrypt(b"\0" * 4 + b"PS-Msg05", plain, b"")
        third = bridge.feed(h.frame(4, [(6, b"\x05"), (5, encrypted)]))
        fields = read_pairing_response(third["frames"][0], 4)
        assert "_pwTy" not in fields
        m6tlv = h.r.read_tlv(fields["_pd"])
        m6 = h.r.read_tlv(h.r.ChaCha20Poly1305(encryption).decrypt(b"\0" * 4 + b"PS-Msg06", m6tlv[5], b""))
        codec_spec = importlib.util.spec_from_file_location("opack", here / "wire-opack.py")
        codec = importlib.util.module_from_spec(codec_spec); codec_spec.loader.exec_module(codec)
        assert codec.unpack(m6[17]) == {"name":"WindowShade Remote Probe", "model":"AppleTV6,2"}
        assert b"-" in m6[1] and len(m6[1]) == 36
        h.r.Ed25519PublicKey.from_public_bytes(m6[3]).verify(m6[10], h.r.derive(key, "Accessory-Sign") + m6[1] + m6[3])
        assert third["configuration"]["identifierRepresentation"] == "hyphenated"
        h.verify(bridge, signing, identifier, m6, expected_generation=2)
        print(json.dumps({"case": "configured-metadata-and-reply-policy", "passed": True,
            "m2PairingType": 1, "m6Metadata": "probe-label", "identifierRepresentation": "hyphenated",
            "networkListener": False, "privateMaterialInReport": False}))
    finally:
        bridge.close()

if __name__ == "__main__": main()
