#!/usr/bin/env python3
"""Isolated full build --check only. Does not sign, launch, replace, or publish an app."""
from __future__ import annotations
import argparse, hashlib, json, pathlib, platform, plistlib, shutil, subprocess, sys, tempfile, time
from importlib.util import spec_from_file_location,module_from_spec
s=spec_from_file_location('final_runner',pathlib.Path(__file__).with_name('run-final.py'));m=module_from_spec(s);s.loader.exec_module(m)
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--candidate',required=True,type=pathlib.Path);p.add_argument('--report',required=True,type=pathlib.Path);p.add_argument('--sparkle',type=pathlib.Path);p.add_argument('--timeout',type=int,default=1800);n=p.parse_args();r=n.candidate.resolve()
    try:
        if not (r/'prototype/build.sh').is_file():raise ValueError('missing build.sh')
        if n.timeout<1 or n.timeout>14400:raise ValueError('invalid timeout')
        out=m.external_report(n.report,[r,pathlib.Path(__file__).resolve().parent.parent]);before=m.inventory(r)
    except (ValueError,OSError) as e:print('REFUSED:',e,file=sys.stderr);return 2
    state={'environment':platform.platform(),'sdk_build':'NOT_RUN','signing':'NOT_RUN','application_launch':'NOT_RUN','candidate_unchanged':True,'commands':[]}
    def finish(code,reason):
        state.update(exit_code=code,reason=reason,candidate_unchanged=m.inventory(r)==before)
        if not state['candidate_unchanged']:state.update(exit_code=2,reason='input changed');code=2
        (out/'result.json').write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n');print(json.dumps(state,ensure_ascii=False));return code
    if platform.system()!='Darwin':return finish(78,'NOT RUN: requires a real macOS SDK and host')
    fw=(n.sparkle.resolve() if n.sparkle else r/'prototype/Vendor/Sparkle.framework')
    info=fw/'Resources/Info.plist'
    try:
        if not info.is_file():info=fw/'Versions/B/Resources/Info.plist'
        ver=plistlib.loads(info.read_bytes()).get('CFBundleShortVersionString')
        if ver!='2.10.0':raise ValueError('Sparkle version must match pinned 2.10.0, not auto-upgraded')
        if not (fw/'Versions/B/Sparkle').is_file():raise ValueError('missing pinned framework binary')
    except (OSError,ValueError,plistlib.InvalidFileException) as e:return finish(2,'PREPARATION_FAILED: '+str(e))
    def command(argv,cwd=None):
        start=time.monotonic()
        try:
            q=subprocess.run(argv,cwd=cwd,capture_output=True,timeout=n.timeout);code=q.returncode;stdout=q.stdout;stderr=q.stderr
        except subprocess.TimeoutExpired as e:code=124;stdout=e.stdout or b'';stderr=e.stderr or b''
        except OSError as e:code=127;stdout=b'';stderr=str(e).encode()
        number=len(state['commands']);(out/f'{number:02d}-stdout.txt').write_bytes(stdout);(out/f'{number:02d}-stderr.txt').write_bytes(stderr)
        state['commands'].append({'argv':list(map(str,argv)),'cwd':str(cwd) if cwd else None,'exit_code':code,'elapsed_seconds':time.monotonic()-start,'stdout':f'{number:02d}-stdout.txt','stderr':f'{number:02d}-stderr.txt'})
        return code
    for c in [['sw_vers'],['xcodebuild','-version'],['xcrun','--sdk','macosx','--show-sdk-version'],['xcrun','--find','swiftc'],['swiftc','--version']]:
        ec=command(c)
        if ec:return finish(ec,'PREPARATION_FAILED: toolchain probe')
    # Whole trusted source snapshot; do not exclude *.app globally (Sparkle contains its own app).
    with tempfile.TemporaryDirectory(prefix='ws2-final-mac-') as t:
        copy=pathlib.Path(t)/'candidate'
        def ignore(directory,names):return [x for x in names if x in {'.git','.build','local-codesign.env','WindowShade.app','dist','__pycache__'}]
        shutil.copytree(r,copy,symlinks=True,ignore=ignore)
        target=copy/'prototype/Vendor/Sparkle.framework';target.parent.mkdir(parents=True,exist_ok=True)
        if target.exists():shutil.rmtree(target)
        shutil.copytree(fw,target,symlinks=True)
        state['framework_version']=ver;state['framework_binary_sha256']=hashlib.sha256((fw/'Versions/B/Sparkle').read_bytes()).hexdigest()
        ec=command(['bash','build.sh','--check'],copy/'prototype')
        state['sdk_build']='PASSED' if ec==0 else 'FAILED'
        return finish(ec,'SDK build result only; no runtime or release certification')
if __name__=='__main__':raise SystemExit(main())
