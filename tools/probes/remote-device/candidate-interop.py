#!/usr/bin/env python3
"""Independent post-PS record client. Synthetic evidence, never a phone-pass claim."""
import importlib.util, json, sys
from pathlib import Path
p = Path(__file__).with_name('session-interop.py')
spec = importlib.util.spec_from_file_location('session', p)
s = importlib.util.module_from_spec(spec); spec.loader.exec_module(s)
h, o = s.h, s.o

class CandidateClient:
    def __init__(self, binary, pause=None):
        self.bridge = h.Bridge(binary)
        self.secret = h.initial_verify(self.bridge)
        self.signing, self.identity, self.accessory, self.setupkey = h.enroll(self.bridge, pause_seconds=pause)
        self.sendkey = h.hkdf(self.secret, '', 'ClientEncrypt-main')
        self.recvkey = h.hkdf(self.secret, '', 'ServerEncrypt-main')
        self.tx = self.rx = 0
    def exchange(self, envelope, plaintext=None, key=None, counter=None, packet=None):
        packet = packet or h.encrypted_frame(key or self.sendkey,
            o.pack(envelope) if plaintext is None else plaintext, self.tx if counter is None else counter)
        self.tx += 1
        result = self.bridge.feed(packet)
        messages = []
        for raw in result['frames']:
            wire = bytes.fromhex(raw)
            assert wire[0] == 8 and int.from_bytes(wire[1:4], 'big') == len(wire)-4
            plain = h.r.ChaCha20Poly1305(self.recvkey).decrypt(self.rx.to_bytes(8,'little')+b'\0'*4, wire[4:], wire[:4])
            self.rx += 1; messages.append(o.unpack(plain))
        return result, messages, packet
    def request(self, name, content=None):
        xid = self.tx + 1
        result, messages, packet = self.exchange({'_i':name,'_t':2,'_x':xid,'_c':content or {}})
        return result, messages, xid
    def close(self): self.bridge.close()

results = []
def check(name, body):
    body(); results.append({'case': name, 'passed': True})
binary = Path(sys.argv[1])

def full_flow():
    c = CandidateClient(binary, pause=20)
    try:
        result, messages, xid = c.request('_systemInfo')
        assert messages == [s.reply('_systemInfo',xid),s.event('SystemStatus',{'state':3}),s.event('TVSystemStatus',{'state':3})]
        assert result['candidateAeadMatched'] and not result['identityBound']
        assert result['delivered'] == result['authenticatedInputCount'] == result['compatibilityInputCount'] == 0
        result, messages, xid = c.request('_touchStart')
        assert messages == [s.reply('_touchStart',xid,{'_i':1})]
        for phase in (1,2,4):
            result, messages, xid = c.request('_hidT', {'_tPh':phase,'_cx':0.5,'_cy':0.25})
            assert messages == [s.reply('_hidT',xid)]
        for state in (1,2):
            result, messages, xid = c.request('_hidC', {'_hidC':6,'_hBtS':state})
            assert messages == [s.reply('_hidC',xid)]
        assert result['compatibilityInputCount'] == 5 and result['authenticatedInputCount'] == 0
        for _ in range(260):
            result, messages, xid = c.request('FetchAttentionState')
            assert messages == [s.reply('FetchAttentionState',xid,{'state':3})]
        assert c.tx > 256 and c.rx > 256 and not result['closed']
        # Stop/reinitialize is a business transition, not a record-key reset.
        result, messages, xid = c.request('_sessionStop'); assert messages == [s.reply('_sessionStop',xid)]
        result, messages, xid = c.request('_touchStart'); assert messages == [s.reply('_touchStart',xid,{'_i':1})]
        assert result['compatibilityInputCount'] == 5
        # A fresh, fully verified key drops compatibility profile state and starts its own counters.
        secret = h.verify(c.bridge,c.signing,c.identity,c.accessory)
        c.sendkey = h.hkdf(secret,'','ClientEncrypt-main');c.recvkey = h.hkdf(secret,'','ServerEncrypt-main');c.tx=c.rx=0
        result, messages, xid = c.request('_hidC',{'_hidC':6,'_hBtS':1})
        assert messages == [s.reply('_hidC',xid)]
        assert result['identityBound'] and result['authenticatedInputCount'] == 1 and result['compatibilityInputCount'] == 5
    finally:c.close()
check('full-compatible-flow-260-records-then-fresh-PV', full_flow)

for case in ('wrong-key','setup-key','wrong-nonce','tamper','bad-opack','bad-envelope','replay','revoked','handoff-expired','owner-expired','send-failure','old-key-after-fresh-PV'):
    def negative(case=case):
        c = CandidateClient(binary)
        try:
            payload={'_i':'_systemInfo','_t':2,'_x':1,'_c':{}}
            if case == 'revoked': c.bridge.send(op='revoke')
            if case == 'handoff-expired': c.bridge.send(op='advance-clock',seconds=10)
            if case == 'owner-expired':
                c.request('_systemInfo');c.bridge.send(op='advance-clock',seconds=120)
            if case == 'send-failure': c.bridge.send(op='fail-send')
            if case == 'old-key-after-fresh-PV': h.verify(c.bridge,c.signing,c.identity,c.accessory)
            if case == 'wrong-key': result,_,_=c.exchange(payload,key=b'\x7f'*32)
            elif case == 'setup-key': result,_,_=c.exchange(payload,key=c.setupkey)
            elif case == 'bad-opack': result,_,_=c.exchange(payload,plaintext=b'\xc4')
            elif case == 'bad-envelope': result,_,_=c.exchange(payload,plaintext=o.pack({'_i':False}))
            elif case == 'wrong-nonce': result,_,_=c.exchange(payload,counter=1)
            elif case == 'tamper':
                packet=h.encrypted_frame(c.sendkey,o.pack(payload));packet=packet[:-1]+bytes([packet[-1]^1]);result=c.bridge.feed(packet)
            elif case == 'replay':
                _,_,packet=c.exchange(payload);result=c.bridge.feed(packet)
            else: result,_,_=c.exchange(payload)
            assert result['closed'] and result['authenticatedInputCount']==0, case
            assert not result['frames'], case
            if case == 'bad-opack': assert result['candidateAead']['classification']=='aead-matched-invalid-opack'
            after=c.bridge.send(op='feed',bytes=h.encrypted_frame(c.sendkey,o.pack(payload)).hex())
            assert after['closed'] and not after['frames']
        finally:c.close()
    check(case,negative)
print(json.dumps({'cases':results,'source':'independent-python-crypto','phoneTest':False}))
