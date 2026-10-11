#!/usr/bin/env python3
"""Actual TCP loopback: independent SRP/PV/AEAD client. No wire-harness state simulation."""
import argparse
import hashlib
import importlib.util
import json
import queue
import socket
import subprocess
import threading
from pathlib import Path

here = Path(__file__).resolve().parent

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

h = module('socket_handshake_primitives', here / 'handshake-interop.py')
o = module('socket_opack', here / 'wire-opack.py')
r = h.r

class Client:
    def __init__(self, port):
        self.socket = socket.create_connection(('127.0.0.1', port), timeout=3)
        self.socket.settimeout(3)
        self.tx = self.rx = 0
    def read_exact(self, size):
        result = bytearray()
        while len(result) < size:
            part = self.socket.recv(size - len(result))
            if not part: raise AssertionError('unexpected socket EOF')
            result.extend(part)
        return bytes(result)
    def read(self):
        header = self.read_exact(4)
        size = int.from_bytes(header[1:], 'big')
        assert 0 < size <= 65536, 'frame length outside bound'
        return header + self.read_exact(size)
    def handshake(self, kind, fields, expected):
        packet = h.frame(kind, fields)
        # Exercise real stream fragmentation, not a simulated decoder feed.
        for part in (packet[:2], packet[2:7], packet[7:]):
            if part: self.socket.sendall(part)
        return h.read_frame(self.read().hex(), expected)
    def initial_verify(self):
        private = h.X25519PrivateKey.generate()
        response = self.handshake(5, [(6,b'\x01'),(3,h.raw_key(private.public_key()))], 6)
        assert response[6] == b'\x02'
        return private.exchange(h.X25519PublicKey.from_public_bytes(response[3]))
    def enroll(self):
        m2 = self.handshake(3, [(6,b'\x01'),(0,b'\x00')], 4)
        assert m2[6] == b'\x02'
        context = r.SRPContext('Pair-Setup','3939',prime=r.constants.PRIME_3072,
            generator=r.constants.PRIME_3072_GEN,hash_func=hashlib.sha512)
        srp = r.SRPClientSession(context)
        srp.process(m2[3].hex(),m2[2].hex())
        m4 = self.handshake(4, [(6,b'\x03'),(3,r.raw(srp.public)),(4,r.raw(srp.key_proof))], 4)
        assert m4[6] == b'\x04' and srp.verify_proof(m4[4].hex().encode())
        key = r.raw(srp.key)
        encryption = r.derive(key,'Encrypt')
        self.signing = r.Ed25519PrivateKey.generate()
        self.identity = b'loopback-test-client'
        public = h.raw_key(self.signing.public_key())
        signature = self.signing.sign(r.derive(key,'Controller-Sign') + self.identity + public)
        plaintext = r.tlv([(1,self.identity),(3,public),(10,signature)])
        encrypted = r.ChaCha20Poly1305(encryption).encrypt(b'\0'*4+b'PS-Msg05',plaintext,b'')
        m6 = self.handshake(4,[(6,b'\x05'),(5,encrypted)],4)
        assert m6[6] == b'\x06'
        self.accessory = r.read_tlv(r.ChaCha20Poly1305(encryption).decrypt(b'\0'*4+b'PS-Msg06',m6[5],b''))
        a = self.accessory
        r.Ed25519PublicKey.from_public_bytes(a[3]).verify(a[10],r.derive(key,'Accessory-Sign')+a[1]+a[3])
    def fresh_verify(self):
        private = h.X25519PrivateKey.generate()
        public = h.raw_key(private.public_key())
        m2 = self.handshake(5,[(6,b'\x01'),(3,public)],6)
        assert m2[6] == b'\x02'
        secret = private.exchange(h.X25519PublicKey.from_public_bytes(m2[3]))
        proofkey = h.hkdf(secret,'Pair-Verify-Encrypt-Salt','Pair-Verify-Encrypt-Info')
        proof = r.read_tlv(r.ChaCha20Poly1305(proofkey).decrypt(b'\0'*4+b'PV-Msg02',m2[5],b''))
        assert proof[1] == self.accessory[1]
        r.Ed25519PublicKey.from_public_bytes(self.accessory[3]).verify(proof[10],m2[3]+proof[1]+public)
        signature = self.signing.sign(public+self.identity+m2[3])
        encrypted = r.ChaCha20Poly1305(proofkey).encrypt(b'\0'*4+b'PV-Msg03',r.tlv([(1,self.identity),(10,signature)]),b'')
        m4 = self.handshake(6,[(6,b'\x03'),(5,encrypted)],6)
        assert m4[6] == b'\x04'
        self.keys(secret)
    def keys(self, secret):
        self.sendkey = h.hkdf(secret,'','ClientEncrypt-main')
        self.recvkey = h.hkdf(secret,'','ServerEncrypt-main')
        self.tx = self.rx = 0
    def request(self, method, content=None, extra_events=()):
        xid = self.tx + 1
        self.socket.sendall(h.encrypted_frame(self.sendkey,o.pack({'_i':method,'_t':2,'_x':xid,'_c':content or {}}),self.tx))
        self.tx += 1
        outputs = []
        for _ in range(1 + len(extra_events)):
            packet = self.read()
            assert packet[0] == 8
            plaintext = r.ChaCha20Poly1305(self.recvkey).decrypt(self.rx.to_bytes(8,'little')+b'\0'*4,packet[4:],packet[:4])
            self.rx += 1
            outputs.append(o.unpack(plaintext))
        payload = {'_touchStart':{'_i':1},'FetchAttentionState':{'state':3}}.get(method,{})
        expected = [{'_i':method,'_t':3,'_rT':0,'_x':xid,'_c':payload}] + list(extra_events)
        assert outputs == expected, 'full response/order mismatch for ' + method
    def inputs(self):
        self.request('_touchStart')
        for phase in (1,2,4): self.request('_hidT',{'_tPh':phase,'_cx':0.5,'_cy':0.25})
        for state in (1,2): self.request('_hidC',{'_hidC':6,'_hBtS':state})

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('binary',type=Path)
    parser.add_argument('--reply-policy',choices=['current','upstream-reference'],default='current')
    args = parser.parse_args()
    process = subprocess.Popen([str(args.binary.resolve()),'--loopback-test','--reply-policy',args.reply_policy],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    messages = queue.Queue()
    def read_output():
        for line in process.stdout:
            try: messages.put(json.loads(line))
            except json.JSONDecodeError: messages.put({'event':'invalid-json'})
        messages.put({'event':'process-eof'})
    reader = threading.Thread(target=read_output,daemon=True)
    reader.start()
    client = None
    try:
        ready = messages.get(timeout=8)
        assert ready.get('event') == 'loopback-ready', 'loopback did not become ready'
        client = Client(ready['port'])
        initial = client.initial_verify()
        client.enroll()
        client.keys(initial)
        events = [{'_i':name,'_t':1,'_c':{'state':3}} for name in ('SystemStatus','TVSystemStatus')]
        client.request('_systemInfo',extra_events=events)
        client.inputs()
        for _ in range(260): client.request('FetchAttentionState')
        assert client.tx > 256 and client.rx > 256
        compatibility_records = client.tx
        client.fresh_verify()
        client.request('_systemInfo',extra_events=events)
        client.inputs()
        client_records, server_records = client.tx, client.rx
        client.socket.shutdown(socket.SHUT_WR)
        client.socket.close()
        client = None
        process.wait(timeout=5)
        assert process.returncode == 0, 'loopback exited unsuccessfully'
        reader.join(timeout=1)
        logs = []
        while not messages.empty(): logs.append(messages.get_nowait())
        closes = [item for item in logs if item.get('event') == 'connection-closed']
        assert len(closes) == 1, 'missing actual transport close evidence'
        close = closes[0]
        assert close.get('compatibilityInputCount') == 5
        assert close.get('authenticatedInputCount') == 5
        assert close.get('identityBound') is True
        assert close.get('closeCause') == 'remote-eof'
        assert close.get('recordRX') == client_records and close.get('recordTX') == server_records
        finished = [item for item in logs if item.get('event') == 'finished']
        assert len(finished) == 1 and finished[0].get('applicationActions') == 0
        assert close.get('inputCategories',{}).get('valid') == 5
        print(json.dumps({'passed':True,'network':'127.0.0.1','compatibilityRecords':compatibility_records,
            'compatibilityValidInputs':5,'authenticatedValidInputs':5,'systemInfoOutputs':6,'phoneTest':False,
            'replyPolicy':args.reply_policy,'close':close,'finished':finished[0]}))
    finally:
        if client is not None: client.socket.close()
        if process.poll() is None:
            process.terminate()
            try: process.wait(timeout=3)
            except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=3)
        process.stdout.close()
        process.stderr.close()

if __name__ == '__main__': main()
