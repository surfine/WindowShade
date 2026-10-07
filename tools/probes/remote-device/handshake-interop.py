#!/usr/bin/env python3
"""Independent cryptographic client, no sockets. Tests the actual receiver handshake owner."""
import argparse, hashlib, importlib.util, json, subprocess
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey

shared = Path(__file__).resolve().parent.parent / 'companion-pairing' / 'pair-setup-interop.py'
spec = importlib.util.spec_from_file_location('pair_reference', shared)
r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)

def raw_key(key):
    return key.public_bytes(r.serialization.Encoding.Raw, r.serialization.PublicFormat.Raw)

def frame(kind, fields):
    # All handshake envelopes here use only _pd and no permissive extensions.
    payload = b'\xe1\x43_pd' + r.opack_data(r.tlv(fields))
    return bytes([kind]) + len(payload).to_bytes(3, 'big') + payload

def read_frame(encoded, kind):
    packet = bytes.fromhex(encoded); assert packet[0] == kind
    return r.read_wire((b'\x04' + packet[1:]).hex())

def hkdf(key, salt, info):
    return r.HKDF(algorithm=r.hashes.SHA512(), length=32, salt=salt.encode(), info=info.encode()).derive(key)

class Bridge:
    def __init__(self, path):
        self.p = subprocess.Popen([str(path), '--wire-test-json'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    def send(self, **value):
        self.p.stdin.write(json.dumps(value)+'\n'); self.p.stdin.flush()
        line = self.p.stdout.readline(); assert line, self.p.stderr.read()
        return json.loads(line)
    def feed(self, packet):
        for part in (packet[:2], packet[2:7]):
            result = self.send(op='feed', bytes=part.hex())
            assert not result.get('rejected') and not result['frames']
        return self.send(op='feed', bytes=packet[7:].hex())
    def close(self):
        self.p.stdin.close(); self.p.wait(timeout=5)
        assert self.p.returncode == 0, self.p.stderr.read()

def initial_verify(b):
    client = X25519PrivateKey.generate()
    response = b.feed(frame(5, [(6,b'\x01'),(3,raw_key(client.public_key()))]))
    assert response['phase'] == 'pair-verify' and not response['closed']
    assert read_frame(response['frames'][0],6)[6] == b'\x02'

def enroll(b):
    response = b.feed(frame(3,[(6,b'\x01'),(0,b'\x00')]))
    assert response['phase'] == 'pair-setup' and not response['disconnected']
    assert response['generation'] == 2, 'old verifier close must not close replacement'
    m2 = read_frame(response['frames'][0],4)
    ctx = r.SRPContext('Pair-Setup','3939',prime=r.constants.PRIME_3072,generator=r.constants.PRIME_3072_GEN,hash_func=hashlib.sha512)
    client = r.SRPClientSession(ctx); client.process(m2[3].hex(),m2[2].hex())
    response = b.feed(frame(4,[(6,b'\x03'),(3,r.raw(client.public)),(4,r.raw(client.key_proof))]))
    assert not response['closed']
    m4 = read_frame(response['frames'][0],4); assert client.verify_proof(m4[4].hex().encode())
    key = r.raw(client.key); encryption = r.derive(key,'Encrypt')
    signing = r.Ed25519PrivateKey.generate(); pub = raw_key(signing.public_key()); identifier=b'wire-test-client'
    signature = signing.sign(r.derive(key,'Controller-Sign')+identifier+pub)
    plain = r.tlv([(1,identifier),(3,pub),(10,signature)])
    encrypted = r.ChaCha20Poly1305(encryption).encrypt(b'\0'*4+b'PS-Msg05',plain,b'')
    response = b.feed(frame(4,[(6,b'\x05'),(5,encrypted)]))
    assert response['phase']=='enrolled' and not response['closed'] and response['peers']==1 and response['delivered']==0
    m6 = read_frame(response['frames'][0],4)
    accessory = r.read_tlv(r.ChaCha20Poly1305(encryption).decrypt(b'\0'*4+b'PS-Msg06',m6[5],b''))
    r.Ed25519PublicKey.from_public_bytes(accessory[3]).verify(accessory[10],r.derive(key,'Accessory-Sign')+accessory[1]+accessory[3])
    return signing,identifier,accessory,encryption

def verify(b, signing, identifier, accessory, bad=False):
    private=X25519PrivateKey.generate(); public=raw_key(private.public_key())
    response=b.feed(frame(5,[(6,b'\x01'),(3,public)]))
    assert response['phase']=='pair-verify' and not response['closed'] and response['generation']==3
    m2=read_frame(response['frames'][0],6)
    secret=private.exchange(X25519PublicKey.from_public_bytes(m2[3]))
    proofkey=hkdf(secret,'Pair-Verify-Encrypt-Salt','Pair-Verify-Encrypt-Info')
    proof=r.read_tlv(r.ChaCha20Poly1305(proofkey).decrypt(b'\0'*4+b'PV-Msg02',m2[5],b''))
    assert proof[1]==accessory[1]
    r.Ed25519PublicKey.from_public_bytes(accessory[3]).verify(proof[10],m2[3]+proof[1]+public)
    signature=signing.sign(public+identifier+m2[3])
    if bad: signature=bytes([signature[0]^1])+signature[1:]
    encrypted=r.ChaCha20Poly1305(proofkey).encrypt(b'\0'*4+b'PV-Msg03',r.tlv([(1,identifier),(10,signature)]),b'')
    response=b.feed(frame(6,[(6,b'\x03'),(5,encrypted)]))
    if bad:
        assert response.get('rejected') and response['closed'] and response['delivered']==0
    else:
        assert response['phase']=='verified' and not response['closed']
        assert read_frame(response['frames'][0],6)[6]==b'\x04'
    return secret

def encrypted_frame(key, payload, counter=0):
    header=b'\x08'+(len(payload)+16).to_bytes(3,'big')
    return header+r.ChaCha20Poly1305(key).encrypt(counter.to_bytes(8,'little')+b'\0'*4,payload,header)

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--bridge',type=Path,required=True); args=ap.parse_args()
    results=[]
    for case in ('same-socket-success','verified-restart','invalid-verify-signature','setup-key-input','expired-admission','fallback-repeat'):
        b=Bridge(args.bridge)
        try:
            initial_verify(b)
            if case=='expired-admission':
                b.send(op='expire-admission')
                denied=b.feed(frame(3,[(6,b'\x01'),(0,b'\x00')]))
                assert denied.get('rejected') and denied['closed'] and denied['peers']==0
            else:
                signing,identifier,accessory,setupkey=enroll(b)
                if case=='setup-key-input':
                    denied=b.feed(encrypted_frame(setupkey,b'\xe3\x42_t\x09\x42_i\x45_hidC\x42_c\xe0'))
                    assert denied.get('rejected') and denied['closed'] and denied['delivered']==0
                elif case=='fallback-repeat':
                    ephemeral=X25519PrivateKey.generate()
                    first=b.feed(frame(5,[(6,b'\x01'),(3,raw_key(ephemeral.public_key()))])); assert not first['closed']
                    denied=b.feed(frame(3,[(6,b'\x01'),(0,b'\x00')]))
                    assert denied.get('rejected') and denied['closed']
                else:
                    secret=verify(b,signing,identifier,accessory,bad=case=='invalid-verify-signature')
                    if case in ('same-socket-success','verified-restart'):
                        # Real authenticated _systemInfo request; server must return an encrypted response.
                        payload=(b'\xf4\x42_t\x0a\x42_i\x4b_systemInfo\x42_c\xf2\x42id\x05'
                                 + bytes(range(16)) + b'\x44time\x06' + (0x0102030405060708).to_bytes(8,'little')
                                 + b'\x42_x\x09')
                        clientkey=hkdf(secret,'','ClientEncrypt-main')
                        response=b.feed(encrypted_frame(clientkey,payload))
                        assert not response['closed'] and response['delivered']==1 and len(response['frames'])==3
                        reply=bytes.fromhex(response['frames'][0]); assert reply[0]==8
                        serverkey=hkdf(secret,'','ServerEncrypt-main')
                        plaintext=r.ChaCha20Poly1305(serverkey).decrypt(b'\0'*12,reply[4:],reply[:4])
                        assert b'_systemInfo' in plaintext
                        restart = frame(3,[(6,b'\x01'),(0,b'\x00')]) if case=='same-socket-success' else frame(5,[(6,b'\x01'),(3,raw_key(X25519PrivateKey.generate().public_key()))])
                        denied=b.feed(restart)
                        assert denied.get('rejected') and denied['closed'] and denied['delivered']==1
            results.append({'case':case,'passed':True})
        finally: b.close()
    print(json.dumps({'cases':results,'networkListener':False,'realCryptography':True}))
if __name__=='__main__': main()
