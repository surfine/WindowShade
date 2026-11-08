#!/usr/bin/env python3
"""Run an existing, selected suite in a disposable copy; never overwrite historical evidence."""
from __future__ import annotations
import argparse, hashlib, json, os, pathlib, platform, shutil, subprocess, sys, tempfile, time
P = pathlib.Path(__file__).resolve().parent.parent
SUITES = {'window-core','frame','duo','input','flow','native','foundation','legacy-foundation','legacy-process','mac-build'}
def inventory(root: pathlib.Path) -> dict[str,str]:
    result={}
    for f in sorted(root.rglob('*')):
        if f.is_symlink():
            result[f.relative_to(root).as_posix()]='SYMLINK:'+os.readlink(f)
        elif f.is_file(): result[f.relative_to(root).as_posix()]=hashlib.sha256(f.read_bytes()).hexdigest()
    return result

def external_report(report: pathlib.Path, roots: list[pathlib.Path]) -> pathlib.Path:
    report=report.absolute()
    # macOS 的 /var、/tmp、/etc 是 Apple 自己的根级符号链接（Linux 上是真目录）；先按系统事实
    # 规范化这三个前缀，否则文档推荐的 `mktemp -d /tmp/...` 报告目录会被自己拒掉。其余任何一段是
    # 符号链接仍然拒绝。
    folded=str(report)
    for link,target in (('/var','/private/var'),('/tmp','/private/tmp'),('/etc','/private/etc')):
        if folded==link or folded.startswith(link+'/'):
            folded=target+folded[len(link):];break
    report=pathlib.Path(folded)
    for parent in [report,*report.parents]:
        if parent.is_symlink(): raise ValueError('report path must not contain symlinks')
    for root in roots:
        root=root.resolve()
        if report==root or root in report.parents or report in root.parents:
            raise ValueError('report must not overlap inputs')
    if report.exists(): raise ValueError('report already exists')
    if not report.parent.is_dir(): raise ValueError('report parent must already exist')
    report.mkdir(mode=0o700)
    return report

def main() -> int:
    a=argparse.ArgumentParser(description=__doc__)
    a.add_argument('--candidate',type=pathlib.Path,required=True)
    a.add_argument('--handoff',type=pathlib.Path,required=True)
    a.add_argument('--report',type=pathlib.Path,required=True)
    a.add_argument('--suite',choices=sorted(SUITES),required=True)
    a.add_argument('--sparkle',type=pathlib.Path)
    a.add_argument('--timeout',type=int,default=1800,help='hard command timeout, not a completion-time estimate')
    n=a.parse_args(); r=n.candidate.resolve(); h=n.handoff.resolve()
    try:
        if not (r/'prototype/build.sh').is_file() or not (h/'part9/tests/run.py').is_file(): raise ValueError('candidate or historical test entry missing')
        if n.timeout<1 or n.timeout>14400: raise ValueError('invalid timeout')
        out=external_report(n.report,[r,h,P]); before=inventory(r)
    except (ValueError,OSError) as e: print('REFUSED:',e,file=sys.stderr); return 2
    meta={'suite':n.suite,'environment':platform.platform(),'candidate_sha256':hashlib.sha256(json.dumps(before,sort_keys=True).encode()).hexdigest(),'source_file_count':len(before),'real_cli':False,'real_devices':False,'raw_logs_may_contain_local_paths':True}
    if n.suite=='mac-build':
        cmd=[sys.executable,'-B',str(P/'tools/run-mac-check.py'),'--candidate',str(r),'--report',str(out/'mac'),'--timeout',str(n.timeout)]
        if n.sparkle: cmd += ['--sparkle',str(n.sparkle)]
        return execute(cmd,out,meta,r,before,n.timeout+60)
    with tempfile.TemporaryDirectory(prefix='ws2-final-suite-') as temp:
        work=pathlib.Path(temp)/'part9';shutil.copytree(h/'part9',work)
        shutil.rmtree(work/'validation',ignore_errors=True);(work/'validation').mkdir()
        # legacy 两批由 part9 的 run-previous 转发给「与本仓库适配过的」part7 回归脚本；
        # 那个脚本按临时目录的兄弟路径找 part7，所以这里把它一并复制过去。
        if n.suite.startswith('legacy-') and (h/'part7').is_dir():
            shutil.copytree(h/'part7',pathlib.Path(temp)/'part7')
        prefix=[sys.executable,'-B']
        if n.suite in ('window-core','frame'):
            cmd=prefix+[str(work/'tests/run.py'),'--repo',str(r),'--suite','regression' if n.suite=='window-core' else 'frame']
        elif n.suite=='foundation':cmd=prefix+[str(work/'tests/check-build.py'),'--repo',str(r)]
        else:
            name={'duo':'duo','input':'part8-input','flow':'part7-flow','native':'part7-native','legacy-foundation':'legacy-foundation','legacy-process':'legacy-process'}[n.suite]
            # 本仓库把 part1..part6 的原始测试留在归档 docs/handoff/chatgpt-review-2/ 里，
            # part7/part8/part9 的 runner 在 tests/；legacy 两套要用归档当 history。
            history=h
            if name.startswith('legacy-'):
                archive=r/'docs/handoff/chatgpt-review-2'
                if (archive/'part6/tests').is_dir():history=archive
            cmd=prefix+[str(work/'tests/run-previous.py'),'--repo',str(r),'--history',str(history),'--suite',name]
        code=execute(cmd,out,meta,r,before,n.timeout)
        shutil.copytree(work/'validation',out/'raw-suite-evidence')
        return code

def execute(cmd,out,meta,root,before,timeout):
    t=time.monotonic();meta['argv']=cmd
    try:
        v=subprocess.run(cmd,capture_output=True,timeout=timeout)
        code=v.returncode;stdout=v.stdout;stderr=v.stderr
        meta['status']='PASSED' if code==0 else ('NOT_RUN' if code==78 else 'FAILED')
    except subprocess.TimeoutExpired as e:
        code=124; stdout=e.stdout or b'';stderr=e.stderr or b'';meta['status']='TIMED_OUT'
    except OSError as e:
        code=127;stdout=b'';stderr=str(e).encode();meta['status']='FAILED'
    meta.update(exit_code=code,elapsed_seconds=time.monotonic()-t,candidate_unchanged=inventory(root)==before)
    if not meta['candidate_unchanged']:meta['status']='FAILED_INPUT_CHANGED';code=2;meta['exit_code']=code
    (out/'stdout.txt').write_bytes(stdout);(out/'stderr.txt').write_bytes(stderr)
    meta['logs_sha256']={p:hashlib.sha256((out/p).read_bytes()).hexdigest() for p in ('stdout.txt','stderr.txt')}
    (out/'result.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'suite':meta['suite'],'status':meta['status'],'exit_code':code,'report':str(out)},ensure_ascii=False))
    return code
if __name__=='__main__': raise SystemExit(main())
