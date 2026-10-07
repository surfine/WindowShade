#!/usr/bin/env python3
"""Independent wire client: srptools + cryptography, no private material in output/report."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

import cryptography
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from srptools import SRPContext, SRPClientSession, constants
import srptools
import six

assert srptools.VERSION == (1, 0, 1)
assert six.__version__ == '1.17.0'
assert cryptography.__version__ == '50.0.1'


def tlv(fields):
    out = bytearray()
    for tag, data in fields:
        for i in range(0, len(data), 255):
            part = data[i:i+255]
            out.extend(bytes((tag, len(part))) + part)
    return bytes(out)


def read_tlv(data):
    result = {}; offset = 0
    while offset < len(data):
        assert offset + 2 <= len(data)
        tag, n = data[offset:offset+2]; offset += 2
        assert offset + n <= len(data)
        result[tag] = result.get(tag, b'') + data[offset:offset+n]; offset += n
    return result


def opack_data(data):
    if len(data) <= 32: return bytes((0x70 + len(data),)) + data
    width = 1 if len(data) <= 255 else 2
    return bytes((0x90 + width,)) + len(data).to_bytes(width, 'little') + data


def wire(kind, data):
    payload = b'\xe2\x43_pd' + opack_data(data) + b'\x45_pwTy\x09'
    return bytes((kind,)) + len(payload).to_bytes(3, 'big') + payload


def read_wire(encoded):
    data = bytes.fromhex(encoded)
    assert data[0] == 4 and int.from_bytes(data[1:4], 'big') == len(data) - 4
    payload = data[4:]
    assert payload[:5] == b'\xe1\x43_pd'
    tag = payload[5]; offset = 6
    if tag <= 0x90: n = tag - 0x70
    else:
        width = 1 << (tag - 0x91)
        n = int.from_bytes(payload[offset:offset+width], 'little'); offset += width
    assert len(payload) == offset + n
    return read_tlv(payload[offset:])


def raw(value):
    return bytes.fromhex(value.decode() if isinstance(value, bytes) else value)


def derive(key, label):
    return HKDF(algorithm=hashes.SHA512(), length=32,
                salt=f'Pair-Setup-{label}-Salt'.encode(), info=f'Pair-Setup-{label}-Info'.encode()).derive(key)


class Bridge:
    def __init__(self, path):
        self.p = subprocess.Popen([str(path), '--test-json', '--m2', 'srptools-minimal'],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    def send(self, **message):
        self.p.stdin.write(json.dumps(message) + '\n'); self.p.stdin.flush()
        line = self.p.stdout.readline()
        assert line, 'bridge ended unexpectedly'
        return json.loads(line)
    def frame(self, kind, data):
        packet = wire(kind, data)
        # Exercise incremental production frame decoding across header and payload boundaries.
        for part in (packet[:2], packet[2:7]):
            result = self.send(op='feed', bytes=part.hex())
            assert result['frames'] == [] and not result.get('rejected', False)
        return self.send(op='feed', bytes=packet[7:].hex())
    def close(self):
        self.p.stdin.close(); self.p.wait(timeout=5)
        assert self.p.returncode == 0, 'bridge failed'
        self.p.stdout.close(); self.p.stderr.close()


def no_enrollment(reply):
    assert reply['peers'] == reply['persistedPeers'] == 0
    assert not reply['enrolled'] and reply['closed'] and reply['disconnected']
    assert reply['frames'] == []


def scenario(path, name, private=None):
    bridge = Bridge(path)
    try:
        m2reply = bridge.frame(3, tlv([(6,b'\x01'),(0,b'\x00')]))
        assert m2reply['peers'] == m2reply['persistedPeers'] == 0
        m2 = read_wire(m2reply['frames'][0]); assert m2[6] == b'\x02'
        ctx = SRPContext('Pair-Setup', '0000' if name == 'wrong-pin' else '3939',
                         prime=constants.PRIME_3072, generator=constants.PRIME_3072_GEN, hash_func=hashlib.sha512)
        client = SRPClientSession(ctx, private)
        client.process(m2[3].hex(), m2[2].hex())
        m3 = tlv([(6,b'\x03'),(3,raw(client.public)),(4,raw(client.key_proof))])
        m4reply = bridge.frame(4, m3)
        if name == 'wrong-pin':
            assert m4reply.get('rejected'); no_enrollment(m4reply)
            return {'case':name,'rejected':True,'persisted_peers':0}
        m4 = read_wire(m4reply['frames'][0]); assert m4[6] == b'\x04'
        assert client.verify_proof(m4[4].hex().encode())
        assert m4reply['peers'] == m4reply['persistedPeers'] == 0
        key = raw(client.key); encryption = derive(key, 'Encrypt')
        signing = Ed25519PrivateKey.generate()
        pub = signing.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        identifier = b'isolated-controller'
        signature = signing.sign(derive(key,'Controller-Sign') + identifier + pub)
        if name == 'invalid-signature': signature = bytes([signature[0] ^ 1]) + signature[1:]
        plain = tlv([(1,identifier),(3,pub),(10,signature)])
        encrypted = ChaCha20Poly1305(encryption).encrypt(b'\0'*4 + b'PS-Msg05', plain, b'')
        if name == 'tampered-m5': encrypted = encrypted[:-1] + bytes([encrypted[-1] ^ 1])
        if name == 'cancel-before-m5':
            no_enrollment(bridge.send(op='cancel'))
        m5 = tlv([(6,b'\x05'),(5,encrypted)])
        m6reply = bridge.frame(4, m5)
        if name in ('tampered-m5','invalid-signature','cancel-before-m5'):
            assert m6reply.get('rejected'); no_enrollment(m6reply)
            # A corrected M5 cannot resurrect a consumed/cancelled session.
            retry = bridge.send(op='feed', bytes=wire(4,m5).hex())
            assert retry.get('rejected'); no_enrollment(retry)
            return {'case':name,'rejected':True,'persisted_peers':0,'retry_rejected':True}
        assert m6reply['enrolled'] and m6reply['peers'] == m6reply['persistedPeers'] == 1
        assert m6reply['awaitingVerification']
        assert bridge.send(op='check-peer',identifier=identifier.hex(),publicKey=pub.hex())['peerMatches']
        m6 = read_wire(m6reply['frames'][0]); assert m6[6] == b'\x06'
        result = read_tlv(ChaCha20Poly1305(encryption).decrypt(b'\0'*4+b'PS-Msg06',m6[5],b''))
        assert result[1] == b'isolated-accessory'
        Ed25519PublicKey.from_public_bytes(result[3]).verify(result[10],derive(key,'Accessory-Sign')+result[1]+result[3])
        # Attempt a real AEAD type-8 record under the setup key before any Pair-Verify.
        command = b'\xe3\x42_t\x09\x42_i\x45_hidC\x42_c\xe0'
        header = b'\x08' + (len(command)+16).to_bytes(3,'big')
        record = header + ChaCha20Poly1305(encryption).encrypt(b'\0'*12,command,header)
        denied = bridge.send(op='input-check',bytes=record.hex())
        assert denied['inputRejected'] and denied['inputChannelClosed'] and denied['delivered'] == 0
        # Pair-Setup channel itself also cannot consume application input after enrollment.
        same = bridge.send(op='feed',bytes=record.hex())
        assert same.get('rejected') and same['closed'] and same['peers'] == same['persistedPeers'] == 1
        return {'case':name,'m1_m6_verified':True,'public_A_bytes':len(raw(client.public)),
                'm6_aead_and_ed25519_verified':True,'persisted_peers':1,'awaiting_pair_verify':True,'persisted_identity_and_key_match':True,
                'setup_channel_input_rejected':True,'fresh_input_channel_rejected':True,'delivered_inputs':0}
    finally: bridge.close()


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--bridge',type=Path,required=True); parser.add_argument('--report',type=Path,required=True)
    args = parser.parse_args()
    cases = [scenario(args.bridge,'success-leading-zero','01'),scenario(args.bridge,'success-random')]
    cases += [scenario(args.bridge,n) for n in ('wrong-pin','tampered-m5','invalid-signature','cancel-before-m5')]
    report = {'srptools':'1.0.1','six':'1.17.0','cryptography':cryptography.__version__,'proof_convention':'srptools-minimal',
              'transport':'stdin/stdout fragmented Companion frames','storage':'ephemeral memory; reloaded through production repository',
              'private_material_in_report':False,'hardware':False,'network_listener':False,'production_integration':False,'cases':cases}
    args.report.parent.mkdir(parents=True,exist_ok=True); args.report.write_text(json.dumps(report,indent=2)+'\n')
    print('M1-M6: 2 independent-client success cases + 4 failure/cancel cases PASS; input delivery remains 0')

if __name__ == '__main__': main()
