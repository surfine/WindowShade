#!/usr/bin/env python3
"""Independent expected wire dictionaries; no networking and no Swift expectation reuse."""
import json, pathlib, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parents[3]
with tempfile.TemporaryDirectory(prefix='ws2-profile-') as directory:
    binary = str(pathlib.Path(directory) / 'test')
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-warnings-as-errors', '-strict-concurrency=complete', '-parse-as-library', '-module-cache-path', directory + '/cache',
        'prototype/Core/WS2OPACK.swift', 'tools/probes/remote-device/ProbeConfiguration.swift',
        'tools/probes/remote-device/SessionProfile.swift', 'tools/probes/remote-device/ProfileValueTests.swift', '-o', binary], cwd=root, check=True)
    rows = json.loads(subprocess.check_output([binary]))
for row in rows:
    method, xid = row['method'], row['xid']
    reply = row['request'] if row['policy'] == 'current' else method != '_interest'
    if method == 'UnknownMethod': reply = xid is not None
    content = {'TVRCSessionStart': {'ProtocolVersionKey':'1.2'}, '_touchStart':{'_i':1}, '_tiStart':{'_tiE':False},
        'FetchMediaControlStatus':{'MediaControlFlags':0}, 'FetchAttentionState':{'state':3},
        'MediaControlCommand':{'_vol':0.5}, '_mcc':{'_vol':0.5}}.get(method, {})
    if method == '_sessionStart' and reply:
        sid = row['output'][0]['_c']['_sid']
        assert isinstance(sid,int) and 0 < sid <= 0xffffffff
        content = {'_sid':sid}
    expected = []
    if reply:
        expected.append({'_i':method,'_t':3,'_rT':2 if method=='FetchLaunchableApplicationsEvent' else 0,'_c':content})
        if xid is not None: expected[-1]['_x'] = xid
    events = []
    if method in ('_systemInfo','SystemInfo'): events = [('SystemStatus',{'state':3}),('TVSystemStatus',{'state':3})]
    if method == 'TVRCSessionStart': events = [('MediaControlStatus',{'MediaControlFlags':0}),('_iMC',{'_mcF':0})]
    if method == '_interest': events = [('MediaControlStatus',{'MediaControlFlags':0}),('SystemStatus',{'state':3})]
    for name, payload in events:
        expected.append({'_i':name,'_t':1,'_c':payload})
        if xid is not None and method not in ('_systemInfo','SystemInfo'): expected[-1]['_x']=xid
    assert row['output'] == expected, (row, expected)
print(f'PASS {len(rows)} full output/content/order cases; Swift SID, stop, malformed, input trajectory and reset checks passed')
