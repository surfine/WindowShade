#!/usr/bin/env python3
import hashlib, json, sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'reference'))
import srp_reference as s
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.exceptions import InvalidTag, InvalidSignature

def derive(key, suffix):
    return HKDF(algorithm=hashes.SHA512(),length=32,salt=('Pair-Setup-'+suffix+'-Salt').encode(),info=('Pair-Setup-'+suffix+'-Info').encode()).derive(key)
def tlv(parts):
    result = bytearray()
    for kind,value in parts:
        for offset in range(0,len(value),255):
            chunk=value[offset:offset+255];result.extend(bytes([kind,len(chunk)])+chunk)
    return bytes(result)

class CryptoReference(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.salt=bytes(range(16));cls.a=0x123456789abcdef123456789abcdef123456789abcdef123456789abcdef12345
        cls.A=pow(s.G,cls.a,s.N)
        cls.B,cls.M,cls.K,cls.HAMK=s.server(cls.salt,cls.A)
    def test_01_rfc5054_group(self): self.assertEqual((s.N.bit_length(),s.G,len(s.minimal(s.N))),(3072,5,384))
    def test_02_rfc5054_sha1_k_x(self):
        n=int('EEAF0AB9ADB38DD69C33F80AFA8FC5E86072618775FF3C0B9EA2314C9C256576D674DF7496EA81D3383B4813D692C6E0E0D5D8E250B98BE48E495C1D6089DAD15DC7D7B46154D6B6CE8EF4AD69B15D4982559B297BCF1885C529F566660E57EC68EDBC3C05726CC02FD4CBF4976EAA9AFD5138FE8376435B9FC61D2FC0EB06E3',16)
        k=hashlib.sha1(n.to_bytes(128,'big')+(2).to_bytes(128,'big')).hexdigest()
        x=hashlib.sha1(bytes.fromhex('BEB25379D1A8581EB5A727673A2441EE')+hashlib.sha1(b'alice:password123').digest()).hexdigest()
        self.assertEqual(k,'7556aa045aef2cdd07abaf0f665c3e818913186f')
        self.assertEqual(x,'94b7555aabe9127cc58ccf4993db6cf84d16c124')
    def test_03_client_server_match(self):
        A,M,K=s.client(self.salt,self.B,private=self.a)
        self.assertEqual((A,M,K),(self.A,self.M,self.K))
    def test_04_leading_zero_public_encoding(self):
        A=5;B,M,K,_=s.server(self.salt,A);a,m,k=s.client(self.salt,B,private=1)
        self.assertEqual((a,m,k),(A,M,K));self.assertEqual(len(s.minimal(A)),1)
    def test_05_wrong_pin(self): self.assertNotEqual(s.client(self.salt,self.B,pin='9999',private=self.a)[1],self.M)
    def test_06_zero_public(self):
        with self.assertRaises(ValueError): s.server(self.salt,0)
        with self.assertRaises(ValueError): s.client(self.salt,0)
    def test_07_noncanonical_public(self):
        with self.assertRaises(ValueError): s.server(self.salt,s.N+1)
    def test_08_padding_is_not_cosmetic(self):
        self.assertNotEqual(s.h(s.minimal(5)),s.h(s.padded(5)))
        self.assertNotEqual(s.h(s.minimal(1)),s.h(s.padded(1)))
    def test_09_raw_key_not_hex_text(self):
        with self.assertRaises(ValueError): s.proof(self.salt,self.A,self.B,self.K.hex().encode())
    def test_10_direction_salts_differ(self): self.assertNotEqual(derive(self.K,'Controller-Sign'),derive(self.K,'Accessory-Sign'))
    def test_11_aead_tamper_rejected(self):
        c=ChaCha20Poly1305(derive(self.K,'Encrypt'));n=b'\0'*4+b'PS-Msg05';message=c.encrypt(n,b'test',b'')
        with self.assertRaises(InvalidTag): c.decrypt(n,message[:-1]+bytes([message[-1]^1]),b'')
    def test_12_nonce_direction_rejected(self):
        c=ChaCha20Poly1305(derive(self.K,'Encrypt'));message=c.encrypt(b'\0'*4+b'PS-Msg05',b'test',b'')
        with self.assertRaises(InvalidTag): c.decrypt(b'\0'*4+b'PS-Msg06',message,b'')
    def test_13_identity_signature_binding(self):
        private=Ed25519PrivateKey.from_private_bytes(bytes(range(32)));public=private.public_key()
        pk=public.public_bytes(serialization.Encoding.Raw,serialization.PublicFormat.Raw)
        body=derive(self.K,'Controller-Sign')+b'phone'+pk;signature=private.sign(body)
        public.verify(signature,body)
        with self.assertRaises(InvalidSignature): public.verify(signature,derive(self.K,'Controller-Sign')+b'other'+pk)
    def test_14_server_confirmation(self): self.assertEqual(self.HAMK,s.h(s.minimal(self.A),self.M,self.K))

def fixtures():
    # A synthetic K isolates M5/M6 AEAD/signature interoperability from the SRP backend.
    key=bytes(range(64));cs=bytes(range(32));ss=bytes(range(32,64));cid=b'ws2-test-phone';sid=b'ws2-test-mac'
    c=Ed25519PrivateKey.from_private_bytes(cs);a=Ed25519PrivateKey.from_private_bytes(ss)
    cp=c.public_key().public_bytes(serialization.Encoding.Raw,serialization.PublicFormat.Raw)
    ap=a.public_key().public_bytes(serialization.Encoding.Raw,serialization.PublicFormat.Raw)
    signature=c.sign(derive(key,'Controller-Sign')+cid+cp)
    plain=tlv([(1,cid),(3,cp),(10,signature)])
    cipher=ChaCha20Poly1305(derive(key,'Encrypt'))
    m5=cipher.encrypt(b'\0'*4+b'PS-Msg05',plain,b'')
    m6plain=tlv([(1,sid),(3,ap),(10,a.sign(derive(key,'Accessory-Sign')+sid+ap))])
    m6=cipher.encrypt(b'\0'*4+b'PS-Msg06',m6plain,b'')
    badsig=bytes([signature[0]^1])+signature[1:]
    badm5=cipher.encrypt(b'\0'*4+b'PS-Msg05',tlv([(1,cid),(3,cp),(10,badsig)]),b'')
    values={'key':key,'clientSeed':cs,'serverSeed':ss,'clientID':cid,'serverID':sid,'clientPublic':cp,'serverPublic':ap,'m5':m5,'m6':m6,'m5BadSignature':badm5}
    return {'warning':'ARTIFICIAL TEST VALUES ONLY. NOT PAIRING CREDENTIALS.',**{k:v.hex() for k,v in values.items()}}
if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(CryptoReference))
    (ROOT/'reference/pair-setup-vectors.json').write_text(json.dumps(fixtures(),indent=2)+'\n')
    (ROOT/'validation/crypto-reference.json').write_text(json.dumps({'tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'nativeInterop':False,'swiftCryptoExecuted':False},indent=2)+'\n')
    sys.exit(not result.wasSuccessful())
