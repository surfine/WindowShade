#!/usr/bin/env python3
"""Independent Python reference. NOT execution of Swift/CryptoKit or native Remote interoperability."""
import json, struct, unittest
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import x25519, ed25519
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from cryptography.exceptions import InvalidTag, InvalidSignature
ROOT=Path(__file__).resolve().parents[1]
def raw(public): return public.public_bytes(serialization.Encoding.Raw,serialization.PublicFormat.Raw)
def hkdf(secret,salt,info): return HKDF(algorithm=hashes.SHA512(),length=32,salt=salt,info=info).derive(secret)
def counter(n):
    if not 0 <= n < (1<<64)-1: raise ValueError('counter exhausted')
    return struct.pack('<Q',n)+b'\0'*4
def header(n):
    if not 16<=n<=65536: raise ValueError('record length')
    return bytes([8])+n.to_bytes(3,'big')
ce=x25519.X25519PrivateKey.from_private_bytes(bytes(range(1,33)))
se=x25519.X25519PrivateKey.from_private_bytes(bytes(range(33,65)))
cs=ed25519.Ed25519PrivateKey.from_private_bytes(bytes(range(65,97)))
ss=ed25519.Ed25519PrivateKey.from_private_bytes(bytes(range(97,129)))
cid=b'client-fixture';sid=b'server-fixture';cp=raw(ce.public_key());sp=raw(se.public_key())
shared=ce.exchange(se.public_key()); proof=hkdf(shared,b'Pair-Verify-Encrypt-Salt',b'Pair-Verify-Encrypt-Info')
c2s=hkdf(shared,b'',b'ClientEncrypt-main');s2c=hkdf(shared,b'',b'ServerEncrypt-main')
server_signed=sp+sid+cp;client_signed=cp+cid+sp
ssig=ss.sign(server_signed);csig=cs.sign(client_signed)
message=b'WindowShade fixture only';aad=header(len(message)+16)
record=ChaCha20Poly1305(c2s).encrypt(counter(0),message,aad)
vector={k:v.hex() for k,v in dict(clientEphemeralPrivate=bytes(range(1,33)),serverEphemeralPrivate=bytes(range(33,65)),clientEphemeralPublic=cp,serverEphemeralPublic=sp,sharedSecret=shared,proofKey=proof,clientEncryptKey=c2s,serverEncryptKey=s2c,clientSigningSeed=bytes(range(65,97)),serverSigningSeed=bytes(range(97,129)),clientSigningPublic=raw(cs.public_key()),serverSigningPublic=raw(ss.public_key()),clientID=cid,serverID=sid,serverSignature=ssig,clientSignature=csig,nonce0=counter(0),nonce1=counter(1),noncePV02=b'\0'*4+b'PV-Msg02',recordHeader=aad,recordPlaintext=message,recordCiphertextAndTag=record).items()}
vector['status']='deterministic synthetic Python reference; not real device traffic; private keys are TEST ONLY'
(ROOT/'tests/fixtures/companion-crypto-vectors.json').write_text(json.dumps(vector,indent=2)+'\n')
class Tests(unittest.TestCase):
    def test_shared_secret_agrees(self): self.assertEqual(shared,se.exchange(ce.public_key()))
    def test_directions_are_distinct(self): self.assertNotEqual(c2s,s2c)
    def test_proof_and_transport_distinct(self): self.assertNotEqual(proof,c2s)
    def test_server_signature(self): ss.public_key().verify(ssig,server_signed)
    def test_client_signature(self): cs.public_key().verify(csig,client_signed)
    def test_wrong_identity_fails(self):
        with self.assertRaises(InvalidSignature): cs.public_key().verify(csig,cp+b'other-id'+sp)
    def test_reordered_signature_fails(self):
        with self.assertRaises(InvalidSignature): ss.public_key().verify(ssig,cp+sid+sp)
    def test_record_opens(self): self.assertEqual(ChaCha20Poly1305(c2s).decrypt(counter(0),record,aad),message)
    def test_wrong_direction_fails(self):
        with self.assertRaises(InvalidTag): ChaCha20Poly1305(s2c).decrypt(counter(0),record,aad)
    def test_tampered_header_fails(self):
        with self.assertRaises(InvalidTag): ChaCha20Poly1305(c2s).decrypt(counter(0),record,header(len(record)+1))
    def test_tampered_cipher_fails(self):
        with self.assertRaises(InvalidTag): ChaCha20Poly1305(c2s).decrypt(counter(0),bytes([record[0]^1])+record[1:],aad)
    def test_short_tag_fails(self):
        with self.assertRaises(InvalidTag): ChaCha20Poly1305(c2s).decrypt(counter(0),record[:10],aad)
    def test_expected_next_counter_rejects_replay(self):
        with self.assertRaises(InvalidTag): ChaCha20Poly1305(c2s).decrypt(counter(1),record,aad)
    def test_nonce_layout_is_not_hap_layout(self): self.assertNotEqual(counter(1),b'\0'*4+struct.pack('<Q',1))
    def test_nonce_exhaustion(self):
        with self.assertRaises(ValueError): counter((1<<64)-1)
    def test_length_cap(self):
        with self.assertRaises(ValueError): header(65537)
    def test_proof_nonce_is_distinct(self): self.assertNotEqual(counter(0),b'\0'*4+b'PV-Msg02')
    def test_fresh_ephemeral_changes_transport(self):
        other=x25519.X25519PrivateKey.from_private_bytes(b'\x99'*32)
        self.assertNotEqual(hkdf(other.exchange(se.public_key()),b'',b'ClientEncrypt-main'),c2s)
if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Tests))
    (ROOT/'.build/part4-core/crypto-reference.json').write_text(json.dumps({'runtime':'Python cryptography; not Swift','testsRun':result.testsRun,'failures':len(result.failures),'errors':len(result.errors)},indent=2)+'\n')
    raise SystemExit(not result.wasSuccessful())
