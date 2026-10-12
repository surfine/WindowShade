#!/usr/bin/env python3
"""Consume actual production-native frames, colors, geometry and cleanup."""
from pathlib import Path
import hashlib,json,sys
root=Path(__file__).resolve().parents[2]
out=Path(sys.argv[1]).resolve()
try:
    media=json.loads((out/'media/frames.json').read_text())
    owned=json.loads((out/'owned/frames.json').read_text())
    assert len(media)==16 and len(owned)==10
    for group,frames,states in [('media',media,{'warm','cool','neutral','paused','removed','routes-eight','routes-last','no-artist'}),('owned',owned,{'signed-out','config-rejected','malformed-account','long-models','long-model-picker'})]:
        for parent in ['light','dark']:
            subset=[f for f in frames if f['image'].startswith(parent+'-')]
            assert {f['state'] for f in subset}==states and len(subset)==len(states)
        for f in frames:
            assert f['synthetic'] and f['panelAlpha']==0 and not f['intersectsScreen'] and not f['activeApplication']
            assert (out/group/f['image']).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
            if group=='media':
                assert f['decodedRGBABytes']==65536
                if f['artist']:
                    assert len(f['actualArtistRGB'])==3 and all(abs(a-b)<.0001 for a,b in zip(f['actualArtistRGB'],f['expectedTextRGB'])),f
                assert f['hasDecodedColor']==(f['state']!='neutral')
                routes=f['state'] in {'routes-eight','routes-last'}
                assert f['listOpen']==routes and f['routeReads']==int(routes) and f['routeCount']==(8 if routes else 0)
            else:
                if f['state']=='signed-out':assert not f['canSend'] and not f['canChooseModel'] and f['phase']=='signedOut'
                if f['state']=='config-rejected':assert f['status']=='助手设置与当前权限不符，已断开。' and not f['canSend'] and f['phase']=='stopped'
                if f['state']=='malformed-account':assert f['status']=='助手返回的信息不完整，已断开。' and f['notice']=='请重新启动助手。' and not f['canSend'] and f['phase']=='stopped'
                if f['state']=='long-models':
                    assert len(f['selectedModel'])==295 and f['phase']=='ready'
                    for b in f['buttons']:
                        assert b['width']>0,(f['image'],b,'collapsed action')
                        minimum={'medium':60,'选择模型…':24,'指挥模式':64}.get(b['title'],0)
                        assert b['width']>=minimum,(f['image'],b,'unreadable action')
                        assert b['x']>=-1 and b['x']+b['width']<=f['contentWidth']+1,(f['image'],b,'horizontal overflow')
    cleanup=json.loads((out/'owned/cleanup.json').read_text())
    assert cleanup['childReaped'] and cleanup['temporaryRemoved'] and cleanup['browserRequests']==0
    sources=json.loads((out/'sources.json').read_text())
    for name,digest in sources.items():
        p=(root/name).resolve();assert p.is_relative_to(root) and hashlib.sha256(p.read_bytes()).hexdigest()==digest,name
    pairs={s:hashlib.sha256((out/f'media/light-{s}.png').read_bytes()).digest()==hashlib.sha256((out/f'media/dark-{s}.png').read_bytes()).digest() for s in {f['state'] for f in media}}
    assert all(pairs.values()),pairs
    print(json.dumps({'passed':True,'media_frames':16,'owned_frames':10,'current_inputs':len(sources),'media_parent_pairs_identical':8,'real_hardware_media_login_focus_motion':'not_run'}))
except (AssertionError,OSError,ValueError,KeyError) as e:
    print('State preview FAILED: '+str(e),file=sys.stderr);sys.exit(1)
