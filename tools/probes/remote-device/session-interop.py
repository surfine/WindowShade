#!/usr/bin/env python3
"""Complete independent multi-packet client for the actual socket/wire shared dispatcher."""
import argparse, importlib.util, json, uuid, hashlib, datetime
from pathlib import Path
from cryptography.exceptions import InvalidTag

here=Path(__file__).resolve().parent

def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
h=module('handshake_reference',here/'handshake-interop.py')
o=module('wire_opack',here/'wire-opack.py')

class Client:
    def __init__(self,path,alias=False):
        self.bridge=h.Bridge(path);self.alias=alias;self.tx=0;self.rx=0;self.xid=0;self.nonce_negative_checked=False
        h.initial_verify(self.bridge)
        signing,identity,accessory,_=h.enroll(self.bridge)
        secret=h.verify(self.bridge,signing,identity,accessory)
        self.sendkey=h.hkdf(secret,'','ClientEncrypt-main');self.recvkey=h.hkdf(secret,'','ServerEncrypt-main')
    def close(self):self.bridge.close()
    def exchange(self,envelope):
        packet=h.encrypted_frame(self.sendkey,o.pack(envelope),self.tx);self.tx+=1
        result=self.bridge.feed(packet); messages=[]
        for encoded in result['frames']:
            wire=bytes.fromhex(encoded)
            assert wire[0]==8 and int.from_bytes(wire[1:4],'big')==len(wire)-4
            nonce=self.rx.to_bytes(8,'little')+b'\0'*4
            if self.rx==1:
                try:h.r.ChaCha20Poly1305(self.recvkey).decrypt(b'\0'*4+self.rx.to_bytes(8,'little'),wire[4:],wire[:4])
                except InvalidTag:self.nonce_negative_checked=True
                else:raise AssertionError('HAP nonce unexpectedly accepted at nonzero counter')
            plaintext=h.r.ChaCha20Poly1305(self.recvkey).decrypt(nonce,wire[4:],wire[:4]);self.rx+=1
            messages.append(o.unpack(plaintext))
        return result,messages,packet
    def request(self,method,content=None,omit_content=False,extra=None):
        self.xid+=1
        envelope={'model' if self.alias else '_i':method,'_x':self.xid}
        if not self.alias:envelope['_t']=2
        if not omit_content:envelope['_c']={} if content is None else content
        if extra:envelope.update(extra)
        result,messages,packet=self.exchange(envelope)
        return result,messages,self.xid
    def event(self,method,content,with_xid=False):
        envelope={'model' if self.alias else '_i':method,'_c':content}
        if not self.alias or with_xid:envelope['_t']=1
        if with_xid:self.xid+=1;envelope['_x']=self.xid
        result,messages,_=self.exchange(envelope)
        return result,messages,self.xid if with_xid else None

def reply(method,xid,content=None,result=0):
    return {'_i':method,'_t':3,'_x':xid,'_rT':result,'_c':{} if content is None else content}
def event(method,content=None,xid=None):
    out={'_i':method,'_t':1,'_c':{} if content is None else content}
    if xid is not None:out['_x']=xid
    return out

def expect(result,messages,expected):
    assert not result['closed'],result
    assert messages==expected,(messages,expected)

states={'SystemStatus':{'state':3},'TVSystemStatus':{'state':3},'MediaControlStatus':{'MediaControlFlags':0},'_iMC':{'_mcF':0},'NowPlayingInfo':{}}

def full_flow(path,alias):
    c=Client(path,alias)
    try:
        # Source-supported independent initialization: TVRC first, before systemInfo or SID.
        r,m,x=c.request('TVRCSessionStart')
        expect(r,m,[reply('TVRCSessionStart',x,{'ProtocolVersionKey':'1.2'}),event('MediaControlStatus',states['MediaControlStatus'],x),event('_iMC',states['_iMC'],x)])
        metadata={'id':uuid.UUID('00112233-4455-6677-8899-aabbccddeeff'),'time':o.RawTime(0x0102030405060708)}
        for name in ('_systemInfo','SystemInfo'):
            r,m,x=c.request(name,metadata)
            expect(r,m,[reply(name,x),event('SystemStatus',states['SystemStatus']),event('TVSystemStatus',states['TVSystemStatus'])])
        names=['SystemStatus','TVSystemStatus','MediaControlStatus','_iMC','NowPlayingInfo']
        r,m,x=c.event('_interest',{'_regEvents':names},with_xid=True)
        expect(r,m,[event(name,states[name],x) for name in names])
        r,m,_=c.event('_interest',{'_regEvents':names});expect(r,m,[])
        r,m,_=c.event('_interest',{'_deregEvents':['NowPlayingInfo']});expect(r,m,[])
        r,m,_=c.event('_interest',{'_regEvents':['NowPlayingInfo']});expect(r,m,[event('NowPlayingInfo')])
        # A missing _t with _x is a request; 17 acknowledged subscriptions must not leak 16 pending slots.
        for _ in range(17):
            c.xid+=1;x=c.xid
            r,m,_=c.exchange({'model' if alias else '_i':'_interest','_x':x,'_c':{'_regEvents':names}})
            expect(r,m,[reply('_interest',x)])
        c.xid+=1;x=c.xid
        r,m,_=c.exchange({'_i':'_touchStart','model':'ignored-device-metadata','future':{'bounded':True},'_x':x})
        expect(r,m,[reply('_touchStart',x,{'_i':1})])
        r,m,x=c.request('_touchStart');expect(r,m,[reply('_touchStart',x,{'_i':1})])
        r,m,x=c.request('_sessionStart',{'sid' if alias else '_sid':7})
        assert not r['closed'] and len(m)==1
        server_sid=m[0]['_c']['_sid'];assert type(server_sid)==int and 0<server_sid<2**32
        expect(r,m,[reply('_sessionStart',x,{'_sid':server_sid})]);combined=(server_sid<<32)|7
        for method,content,result in [('FetchMediaControlStatus',{'MediaControlFlags':0},0),('FetchAttentionState',{'state':3},0),
            ('FetchSiriRemoteInfo',{},0),('FetchCurrentNowPlayingInfoEvent',{},0),('FetchLaunchableApplicationsEvent',{},2),('_tiStart',{'_tiE':False},0)]:
            r,m,x=c.request(method,omit_content=alias);expect(r,m,[reply(method,x,content,result)])
        for method in ('_tiStop','_touchMove','_touchStop'):
            r,m,x=c.request(method);expect(r,m,[reply(method,x)])
        for state in (1,2):
            r,m,x=c.request('_hidC',{'_hidC':6,'_hBtS':state});expect(r,m,[reply('_hidC',x)])
        for phase in (1,4):
            r,m,_=c.event('_hidT',{'_tPh':phase,'_cx':500,'_cy':500});expect(r,m,[])
        r,m,x=c.request('_hidT',{'_tPh':3,'_cx':501,'_cy':500});expect(r,m,[reply('_hidT',x)])
        r,m,_=c.event('_hidC',{'_hidC':6,'_hBtS':2});expect(r,m,[])
        for method,content,expected in [('_mcc',{'_mcc':5},{'_vol':0.5}),('MediaControlCommand',{'MediaControlCommand':6,'_vol':0.75},{}),
            ('_mcc',{'_mcc':5},{'_vol':0.75}),('_mcc',{'_mcc':12},{'_cse':False})]:
            r,m,x=c.request(method,content);expect(r,m,[reply(method,x,expected)])
        r,m,x=c.request('_sessionStop',{'_sid':combined,'_srvT':'com.apple.tvremoteservices'});expect(r,m,[reply('_sessionStop',x)])
        assert not r['active'] and r['subscriptions']==[]
        r,m,x=c.request('_touchStart');expect(r,m,[reply('_touchStart',x,{'_i':1})])
        r,m,x=c.request('_hidC',{'_hidC':6,'_hBtS':2});expect(r,m,[reply('_hidC',x)])
        r,m,x=c.request('_sessionStop');expect(r,m,[reply('_sessionStop',x)])
        before=r['counts'].get('_hidC',0)
        r,m,_=c.request('_hidC',{'_hidC':6,'_hBtS':2})
        assert r['closed'] and not m and r['counts'].get('_hidC',0)==before
        assert c.tx>40 and c.rx>40 and c.nonce_negative_checked
        return {'case':'full-alias-defaults' if alias else 'full-canonical','clientRecords':c.tx,'serverRecordsVerified':c.rx,'passed':True}
    finally:c.close()

def reject_flow(path,case):
    c=Client(path)
    try:
        if case=='invalid-primary-method-type':r,m,_=c.request('TVRCSessionStart',extra={'_i':17,'model':'TVRCSessionStart'})
        elif case=='conflicting-sid':r,m,_=c.request('_sessionStart',{'_sid':7,'sid':8})
        elif case=='wrong-service':r,m,_=c.request('_sessionStart',{'_srvT':'wrong'})
        elif case=='subscription-budget':r,m,_=c.event('_interest',{'_regEvents':['SystemStatus']*17})
        elif case=='wrong-stop-target':
            r,m,x=c.request('_sessionStart',{'_sid':7});assert not r['closed']
            old_sid=(m[0]['_c']['_sid']<<32)|7
            r,m,x=c.request('_sessionStart',{'_sid':8});assert not r['closed']
            r,m,_=c.request('_sessionStop',{'_sid':old_sid})
        elif case=='replay':
            r,m,packet=c.exchange({'_i':'_touchStart','_t':2,'_x':1,'_c':{}});assert not r['closed']
            r=c.bridge.feed(packet);m=r['frames']
        elif case=='wrong-nonce-layout':
            r,m,_=c.request('_touchStart');assert not r['closed']
            plain=o.pack({'_i':'_touchStop','_t':2,'_x':2,'_c':{}})
            header=b'\x08'+(len(plain)+16).to_bytes(3,'big')
            packet=header+h.r.ChaCha20Poly1305(c.sendkey).encrypt(b'\0'*4+(1).to_bytes(8,'little'),plain,header)
            r=c.bridge.feed(packet);m=r['frames']
        else:raise AssertionError(case)
        assert r['closed'] and not m,(case,r,m)
        return {'case':case,'passed':True}
    finally:c.close()


def fallback_flow(path):
    c=Client(path,True)
    try:
        r,m,x=c.request('_touchStart');expect(r,m,[reply('_touchStart',x,{'_i':1})])
        before=r['delivered'];counts=dict(r['counts'])
        r,m,x=c.request('_launchApp',{'_bundleID':'private-test'})
        expect(r,m,[reply('_launchApp',x)])
        assert r['unhandledMethods']==1 and r['delivered']==before and r['counts']==counts and r['systemActions']==0
        r,m,_=c.event('UnsupportedClientEvent',{'ignored':'private-test'},with_xid=True)
        expect(r,m,[])
        assert r['unhandledMethods']==2 and r['delivered']==before and r['counts']==counts and r['systemActions']==0
        r,m,x=c.request('_hidC',{'_hidC':6,'_hBtS':2});expect(r,m,[reply('_hidC',x)])
        assert r['unhandledMethods']==2 and r['delivered']==before+1 and r['counts']['_hidC']==1 and r['systemActions']==0
        stopped=c.bridge.send(op='cancel')
        assert stopped['closed'] and stopped['unhandledMethods']==2 and stopped['systemActions']==0
        return {'case':'unknown-request-event-fallback-no-delivery','passed':True,'unhandledMethods':2,'systemActions':0,'subsequentKnownInput':True,'countRetainedAfterClose':True}
    finally:c.close()

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--bridge',type=Path,required=True);ap.add_argument('--report',type=Path);args=ap.parse_args()
    results=[full_flow(args.bridge,False),full_flow(args.bridge,True),fallback_flow(args.bridge)]
    results += [reject_flow(args.bridge,name) for name in ('invalid-primary-method-type','conflicting-sid','wrong-service','subscription-budget','wrong-stop-target','replay','wrong-nonce-layout')]
    result={'cases':results,'networkListener':False,'systemActions':0,'nonce':'LE64-counter + zero4; independent send/receive counters','simulatedMediaState':True}
    if args.report:
        root=here.parents[2]
        paths=[args.bridge,root/'prototype/Support/WS2CompanionChannel.swift',root/'prototype/Core/WS2OPACK.swift']+list(sorted(here.glob('*.swift')))+list(sorted(here.glob('*.py')))
        result['sha256']={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
        result['recorded_at']=datetime.datetime.now(datetime.timezone.utc).isoformat()
        args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({key:value for key,value in result.items() if key!='sha256'}))
if __name__=='__main__':main()
