#!/usr/bin/env python3
"""Actual compact payload/slots and production percentage font-layout consumer."""
import json,hashlib,sys
from pathlib import Path
root=Path(__file__).resolve().parents[2];out=Path(sys.argv[1]).resolve()
try:
    frames=json.loads((out/'frames.json').read_text())
    expected={'plug-zero':('0%','red','bolt.fill'),'plug-five':('5%','red','bolt.fill'),'plug-twenty':('20%','red','bolt.fill'),'plug-twenty-one':('21%','green','bolt.fill'),'plug-eighty-two':('82%','green','bolt.fill'),'plug-hundred':('100%','green','bolt.fill'),'full':('100%','green','battery.100'),'low-power':('82%','yellow','battery.25')}
    assert len(frames)==16
    for parent in ['light','dark']:
        subset=[f for f in frames if f['image'].startswith(parent+'-')]
        assert len(subset)==8 and {f['state'] for f in subset}==set(expected)
        for f in subset:
            assert f['synthetic'] and not f['realBatterySource'] and not f['powerFlashAPIOrAXUsed']
            assert f['alpha']==0 and not f['activeApplication'] and not f['intersectsScreen']
            assert (f['trailing'],f['tone'],f['symbol'])==expected[f['state']]
            assert f['compactWidth']==253 and f['compactHeight']==33.5
            assert f['leadingSlot']==[0,0,34,33.5] and f['trailingSlot']==[219,0,34,33.5]
            assert f['wholeRangeFontFits']==101 and f['fontPointSize']==10 and f['textWidth']<=f['availableTextWidth']==30
            assert (out/f['image']).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    sources=json.loads((out/'sources.json').read_text())
    for name,digest in sources.items():assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest,name
    pairs={s:hashlib.sha256((out/f'light-{s}.png').read_bytes()).digest()==hashlib.sha256((out/f'dark-{s}.png').read_bytes()).digest() for s in expected}
    assert all(pairs.values()),pairs
    print(json.dumps({'passed':True,'frames':16,'current_inputs':len(sources),'parent_pairs_identical':8,'whole_valid_percentage_range_font_fits':101,'hardware_source_announcements_real_timer_arbitration':'not_run'}))
except (AssertionError,KeyError,OSError,ValueError) as e:
    print('Power ears FAILED: '+str(e),file=sys.stderr);sys.exit(1)
