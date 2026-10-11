#!/usr/bin/env python3
"""Real TCP M5+record pipelining and pre-PS record rejection; no phone or discovery."""
import hashlib
import importlib.util
import json
import queue
import subprocess
import sys
import threading
from pathlib import Path

spec = importlib.util.spec_from_file_location('native_socket_reference', Path(__file__).with_name('socket-interop.py'))
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)
h, r, o = s.h, s.r, s.o

class Server:
    def __init__(self, binary):
        self.p = subprocess.Popen([str(binary.resolve()), '--loopback-test'], stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True)
        self.messages = queue.Queue()
        def read():
            for line in self.p.stdout:
                self.messages.put(json.loads(line))
        self.reader = threading.Thread(target=read, daemon=True)
        self.reader.start()
        ready = self.messages.get(timeout=8)
        assert ready.get('event') == 'loopback-ready'
        self.client = s.Client(ready['port'])
    def finish(self):
        self.client.socket.close()
        self.p.wait(timeout=5)
        assert self.p.returncode == 0
        self.reader.join(timeout=1)
        logs = []
        while not self.messages.empty(): logs.append(self.messages.get_nowait())
        self.logs = logs
        closes = [x for x in logs if x.get('event') == 'connection-closed']
        assert len(closes) == 1
        finished = [x for x in logs if x.get('event') == 'finished']
        assert len(finished) == 1 and finished[0]['applicationActions'] == 0
        return closes[0]
    def cleanup(self):
        self.client.socket.close()
        if self.p.poll() is None:
            self.p.terminate()
            try: self.p.wait(timeout=3)
            except subprocess.TimeoutExpired: self.p.kill(); self.p.wait(timeout=3)
        self.p.stdout.close(); self.p.stderr.close()

def prepared_m5(c):
    m2 = c.handshake(3, [(6,b'\x01'),(0,b'\x00')], 4)
    context = r.SRPContext('Pair-Setup','3939',prime=r.constants.PRIME_3072,
        generator=r.constants.PRIME_3072_GEN,hash_func=hashlib.sha512)
    srp = r.SRPClientSession(context)
    srp.process(m2[3].hex(),m2[2].hex())
    m4 = c.handshake(4,[(6,b'\x03'),(3,r.raw(srp.public)),(4,r.raw(srp.key_proof))],4)
    assert m4[6] == b'\x04' and srp.verify_proof(m4[4].hex().encode())
    key = r.raw(srp.key)
    encryption = r.derive(key,'Encrypt')
    signing = r.Ed25519PrivateKey.generate()
    identity = b'pipelined-loopback-client'
    public = h.raw_key(signing.public_key())
    signature = signing.sign(r.derive(key,'Controller-Sign')+identity+public)
    plain = r.tlv([(1,identity),(3,public),(10,signature)])
    encrypted = r.ChaCha20Poly1305(encryption).encrypt(b'\0'*4+b'PS-Msg05',plain,b'')
    return h.frame(4,[(6,b'\x05'),(5,encrypted)]), key, encryption

def cause(close):
    return close['closeCause']

def pipeline(binary):
    server = Server(binary)
    try:
        c = server.client
        secret = c.initial_verify()
        m5, key, encryption = prepared_m5(c)
        c.keys(secret)
        request = {'_i':'_systemInfo','_t':2,'_x':1,'_c':{}}
        record = h.encrypted_frame(c.sendkey,o.pack(request),0)
        c.socket.sendall(m5 + record)
        m6 = h.read_frame(c.read().hex(),4)
        assert m6[6] == b'\x06'
        accessory = r.read_tlv(r.ChaCha20Poly1305(encryption).decrypt(b'\0'*4+b'PS-Msg06',m6[5],b''))
        r.Ed25519PublicKey.from_public_bytes(accessory[3]).verify(accessory[10],r.derive(key,'Accessory-Sign')+accessory[1]+accessory[3])
        actual = []
        for counter in range(3):
            packet = c.read()
            assert packet[0] == 8
            plain = r.ChaCha20Poly1305(c.recvkey).decrypt(counter.to_bytes(8,'little')+b'\0'*4,packet[4:],packet[:4])
            actual.append(o.unpack(plain))
        expected = [{'_i':'_systemInfo','_t':3,'_rT':0,'_x':1,'_c':{}}]
        expected += [{'_i':name,'_t':1,'_c':{'state':3}} for name in ('SystemStatus','TVSystemStatus')]
        assert actual == expected
        c.socket.shutdown(s.socket.SHUT_WR)
        close = server.finish()
        assert close['compatibilityMessageCount'] == 1 and close['authenticatedMessageCount'] == 0
        assert close['compatibilityInputCount'] == close['authenticatedInputCount'] == 0
        assert cause(close) == 'remote-eof', 'unexpected successful-flow close cause'
        return {'case':'m5-plus-rx0-one-sendall','passed':True,'outputs':4,'compatibilityMessages':1,'authenticatedMessages':0,'closeCause':cause(close)}
    finally: server.cleanup()

def premature(binary):
    server = Server(binary)
    try:
        c = server.client
        secret = c.initial_verify()
        m2 = c.handshake(3,[(6,b'\x01'),(0,b'\x00')],4)
        assert m2[6] == b'\x02'
        c.keys(secret)
        c.socket.sendall(h.encrypted_frame(c.sendkey,o.pack({'_i':'_systemInfo','_t':2,'_x':1,'_c':{}}),0))
        # Peer must close, without any response byte; a timeout also fails.
        assert c.socket.recv(1) == b''
        close = server.finish()
        assert close['compatibilityMessageCount'] == close['authenticatedMessageCount'] == 0
        assert close['compatibilityInputCount'] == close['authenticatedInputCount'] == 0
        assert cause(close) == 'protocol-reject'
        return {'case':'record-before-ps-completion','passed':True,'outputs':0,'closeCause':cause(close)}
    finally: server.cleanup()

def wrong_key(binary):
    server = Server(binary)
    try:
        c = server.client
        c.initial_verify()
        c.enroll()
        packet = h.encrypted_frame(b'\x7f'*32,o.pack({'_i':'_systemInfo','_t':2,'_x':1,'_c':{}}),0)
        c.socket.sendall(packet)
        assert c.socket.recv(1) == b''
        close = server.finish()
        assert close['compatibilityMessageCount'] == close['authenticatedMessageCount'] == 0
        assert close['compatibilityInputCount'] == close['authenticatedInputCount'] == 0
        assert cause(close) == 'protocol-reject'
        diagnostics = [item for item in server.logs if item.get('event') == 'candidate-aead']
        assert len(diagnostics) == 1
        observed = diagnostics[0]
        assert observed['classification'] == 'aead-failed'
        assert observed['identityBound'] is False and observed['connectionIndex'] == 1
        return {'case':'enrolled-wrong-record-key','passed':True,'outputs':0,
                'closeCause':cause(close),'candidateClassification':observed['classification']}
    finally: server.cleanup()

if __name__ == '__main__':
    binary = Path(sys.argv[1])
    print(json.dumps({'cases':[pipeline(binary),premature(binary),wrong_key(binary)],'network':'127.0.0.1','phoneTest':False}))
