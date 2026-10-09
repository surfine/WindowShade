#!/usr/bin/env python3
"""WindowShade isolated Computer Use QA. Python >= 3.9; stdlib only."""
import argparse
import base64
import plistlib
import contextlib
import fcntl
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import uuid
from evidence import SCENARIOS, visible_window, ax_projection, digest, png_size, read, template, verify, write
from transport import Transport

NAME = re.compile(r'[a-zA-Z0-9_-]{1,80}\Z')
OBSERVE = {'list_windows', 'get_window_state', 'health_report'}
ACTIONS = {'click', 'move_cursor', 'press_key', 'type_text', 'bring_to_front', 'set_window_frame', 'invoke_menu'}
CONFIG_KEYS = {'ssh_host','ssh_control','driver_path','timeout_seconds','vm_name','vm_nvram',
               'lume_path','lume_storage','guest_root','app_path','evidence_root','source_root','build_source','close_menu','finder_close_menu'}


def local(argv):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=30)
        return {'returncode': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr}
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {'returncode': None, 'stdout': '', 'stderr': str(exc)}


def config(path):
    c = read(path)
    if set(c) - CONFIG_KEYS:
        raise ValueError('unknown config keys (do not store credentials): ' + str(set(c)-CONFIG_KEYS))
    for k in ('guest_root','app_path','evidence_root','source_root','vm_nvram','lume_path'):
        if not isinstance(c.get(k), str) or not c[k].startswith('/'):
            raise ValueError(k + ' must be absolute')
    if not NAME.fullmatch(c.get('vm_name','')):
        raise ValueError('invalid vm name')
    if c.get('build_source') not in ('historical','candidate'):
        raise ValueError('build_source must be historical or candidate')
    Transport(c)
    return c


def runmeta(root):
    m = read(root / 'run.json')
    if (root / 'target.json').exists():
        m.update(read(root / 'target.json'))
    return m


@contextlib.contextmanager
def lock(root):
    with open(root / '.lock', 'a') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


@contextlib.contextmanager
def vm_lock(c):
    root=pathlib.Path(c['evidence_root']);root.mkdir(parents=True,exist_ok=True)
    with open(root/('.vm-'+c['vm_name']+'.lock'),'a') as stream:
        fcntl.flock(stream,fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


class Run:
    def __init__(self, root):
        self.root = pathlib.Path(root).resolve()
        self.meta = runmeta(self.root)
        self.c = self.meta['config']
        self.t = Transport(self.c)

    def halted(self):
        return (self.root / 'HALTED.json').exists()

    def halt(self, reason):
        if not self.halted():
            write(self.root / 'HALTED.json', {'at': time.time(), 'reason': reason})

    def begin(self, label, kind):
        if not NAME.fullmatch(label):
            raise ValueError('invalid label')
        d = self.root / 'events' / label
        d.mkdir()  # never overwrite an earlier step
        return d, {'run_id': self.meta['run_id'], 'label': label, 'kind': kind,
                   'start': time.time(), 'target': self.meta.get('target'), 'files': {}}

    def finish(self, d, event, ok):
        event.update(end=time.time(), ok=ok)
        for p in d.iterdir():
            if p.is_file():
                event['files'][p.stem] = {'path': str(p.relative_to(self.root)), 'sha256': digest(p)}
        write(d / 'event.json', event)
        if not ok:
            self.halt(event['label'])
        return event

    def call(self, tool, args):
        if 'session' in args and args['session'] != self.meta['session']:
            raise ValueError('session override forbidden')
        return self.t.call(tool, dict(args, session=self.meta['session']))

    def capture(self, label, ax=True):
        d, e = self.begin(label, 'capture' if ax else 'recovery_view')
        remote = self.meta['guest_dir'] + '/' + label + '.png'
        e['remote_png'] = remote
        shot = self.call('get_desktop_state', {'screenshot_out_file': remote, 'max_image_dimension':1280})
        write(d / 'desktop.json', shot)
        ok = shot['ok'] and (shot.get('payload') or {}).get('screenshot_file_path') == remote
        if ok:
            fetched = self.t.fetch(remote, str(d / 'png.png'))
            write(d / 'fetch.json', fetched)
            ok = fetched['ok']
            if ok:
                try:
                    ok = png_size(d / 'png.png') == (shot['payload']['screenshot_width'],shot['payload']['screenshot_height'])
                    ok = ok and bool(shot['payload'].get('capture_id'))
                except (ValueError, KeyError):
                    ok = False
        if ax and self.meta.get('target'):
            state = self.call('get_window_state', dict(self.meta['target'], include_screenshot=False, timeout_ms=15000))
            write(d / 'ax.json', state)
            # Folded windows can have an empty AX tree. Identity must still be the requested window.
            payload = state.get('payload') or {}
            ok = ok and state['ok'] and not payload.get('degraded') and not payload.get('truncated') and all(payload.get(k) == v for k,v in self.meta['target'].items())
        return self.finish(d, e, bool(ok))

    def observe(self, label, tool, args):
        if tool not in OBSERVE:
            raise ValueError('not an observation tool')
        d,e = self.begin(label,'observe')
        result = self.call(tool,args)
        write(d / 'response.json',result)
        return self.finish(d,e,result['ok'])

    def act(self, label, tool, args, basis):
        d,e = self.begin(label,'action')
        e.update(tool=tool,args=args,basis=basis)
        try:
            if self.halted() or (self.root / 'CLOSED.json').exists():
                raise ValueError('run halted or closed; input refused')
            if tool not in ACTIONS:
                raise ValueError('action not allowed')
            b = read(self.root / 'events' / basis / 'event.json')
            if b['kind'] != 'capture' or not b['ok'] or time.time()-b['end'] > 50:
                raise ValueError('need a successful screenshot less than 50 seconds old')
            events = [read(p) for p in (self.root/'events').glob('*/event.json')]
            if any(x['start'] > b['end'] and x['kind'] == 'action' for x in events):
                raise ValueError('observation already consumed by an action')
            from evidence import checked_file
            for item in b['files'].values():
                checked_file(self.root,item)
            shot = read(self.root / b['files']['desktop']['path'])['payload']
            if tool in ('click','move_cursor') and ('x' in args or 'y' in args):
                if args.get('scope') != 'desktop':
                    raise ValueError('pixel actions must use scope desktop')
                if not (0 <= args['x'] < shot['screenshot_width'] and 0 <= args['y'] < shot['screenshot_height']):
                    raise ValueError('coordinates outside current screenshot')
                if tool == 'click':
                    args = dict(args, capture_id=shot['capture_id'])
            if 'target' in args:
                raise ValueError('use explicit pid/window_id or desktop scope; nested target overrides forbidden')
            if 'pid' in args and args['pid'] != self.meta['target']['pid']:
                raise ValueError('pid differs from controlled target')
            if 'window_id' in args and args['window_id'] != self.meta['target']['window_id']:
                raise ValueError('window differs from controlled target')
            if tool in ('press_key','type_text','invoke_menu','set_window_frame','bring_to_front') and (args.get('pid')!=self.meta['target']['pid'] or args.get('window_id')!=self.meta['target']['window_id']):
                raise ValueError('non-pixel input requires exact controlled pid and window_id')
            if 'element_token' in args:
                ax = read(self.root / b['files']['ax']['path'])['payload']
                if args['element_token'] not in [x.get('element_token') for x in ax.get('elements',[])]:
                    raise ValueError('element token is not from this observation')
        except (ValueError, KeyError, OSError) as exc:
            e.update(kind='refused',reason=str(exc))
            return self.finish(d,e,False)
        result = self.call(tool,args)
        write(d/'response.json',result)
        event = self.finish(d,e,result['ok'])
        if result['ok']:
            # Fresh observation immediately after every input; caller may capture again after settling.
            after = self.capture(label+'-after')
            if not after['ok']:
                return dict(event, ok=False, observation_failed=after['label'])
        return event


def doctor(c, session):
    t = Transport(c)
    health = t.call('health_report',{'session':session})
    screen=t.call('get_screen_size',{'session':session})
    processes = local(['ps','-axo','pid,command'])
    lines = [l for l in processes['stdout'].splitlines() if c['lume_path']+' run '+c['vm_name'] in l]
    nvram = local(['lsof','-Fpc',c['vm_nvram']])
    system = t.remote(['sw_vers'])
    lume = local([c['lume_path'],'get',c['vm_name'],'--storage',c['lume_storage'],'--format','json'])
    ok = screen['ok'] and health['ok'] and health['payload'].get('overall') == 'ok' and len(lines)==1 and nvram['returncode']==0 and bool(nvram['stdout'].strip()) and system['returncode']==0
    return {'status':'pass' if ok else 'blocked','health':health,'screen':screen,'vm_processes':lines,
            'nvram_owners':nvram,'lume':lume,'system':system,
            'note':'Screen capture and scale verified by prepare/capture; health alone does not prove capture readiness.'}


def prepare(c, companion, fixture='text'):
    rid = time.strftime('%Y%m%dT%H%M%S')+'-'+uuid.uuid4().hex[:8]
    root = pathlib.Path(c['evidence_root']) / rid
    root.mkdir(parents=True)
    active = root.parent / ('.active-'+c['vm_name']+'.json')
    if active.exists():
        old = pathlib.Path(read(active)['run'])
        if not (old/'CLOSED.json').exists():
            raise ValueError('another run owns this VM; finish cleanup: '+str(old))
        active.unlink()
    write(active, {'run':str(root)})
    (root/'events').mkdir()
    source = pathlib.Path(c['source_root'])
    commit = local(['git','-C',str(source),'rev-parse','HEAD'])
    diff = local(['git','-C',str(source),'diff','--binary','HEAD'])
    status = local(['git','-C',str(source),'status','--porcelain'])
    (root/'source.diff').write_text(diff['stdout'])
    (root/'source-status.txt').write_text(status['stdout'])
    # Record untracked source identity as well; never archive credentials or payloads here.
    files = local(['git','-C',str(source),'ls-files','--others','--exclude-standard'])
    untracked = {p:digest(source/p) for p in files['stdout'].splitlines() if (source/p).is_file()}
    write(root/'source-untracked.json',untracked)
    t=Transport(c)
    binary = c['app_path']+'/Contents/MacOS/WindowShade'
    sha = t.remote(['shasum','-a','256',binary])
    signature = t.remote(['codesign','-dv','--verbose=4',c['app_path']])
    running = t.remote(['pgrep','-x','WindowShade'])
    pids=running['stdout'].split()
    process=t.remote(['ps','-p',pids[0],'-o','comm=']) if len(pids)==1 else {'returncode':None,'stdout':'','stderr':'not exactly one WindowShade'}
    text = 'WindowShade isolated QA\nRun '+rid+'\nNo personal data.'
    meta = {'schema':1,'run_id':rid,'created':time.time(),'session':'qa-'+rid,
            'config':c,'guest_dir':c['guest_root']+'/'+rid,'document_text':text,
            'companion':companion,'fixture':fixture,'build':{'source':c['build_source'],
            'source_commit':commit['stdout'].strip(),'source_diff_sha256':digest(root/'source.diff'),
            'source_untracked_sha256':digest(root/'source-untracked.json'),
            'binary_sha256':sha['stdout'].split()[0] if sha['returncode']==0 else None,
            'signature':signature,'running_process':process,'mapping':'unverified: source snapshot is not a build provenance attestation'}}
    write(root/'run.json',meta)
    write(root/'review-template.json',template())
    run=Run(root)
    try:
        start=run.call('start_session',{})
        write(root/'session-start.json',start)
        if not start['ok']:
            raise ValueError('session start failed')
        health=doctor(c,meta['session']);write(root/'doctor.json',health)
        if health['status']!='pass' or not meta['build']['binary_sha256'] or process['stdout'].strip()!=binary:
            raise ValueError('environment or binary identity not ready')
        guest=meta['guest_dir']
        made=t.remote(['mkdir',guest]);write(root/'mkdir.json',made)
        if made['returncode']!=0:
            raise ValueError('guest run directory unavailable')
        # argv supplies text through stdin; remote shell only redirects to the unique owned path.
        doc=guest+'/QA-'+rid+'.txt'
        made=t.remote(['sh','-c','umask 077; cat > "$1"','qa-write',doc],input_text=text)
        write(root/'document-create.json',made)
        if made['returncode']!=0:
            raise ValueError('fixture creation failed')
        write(root/'owned.json',{'document':doc,'finder_folder':guest if companion else None})
        if companion:
            opened=t.remote(['open',guest]);write(root/'finder-open.json',opened)
        if fixture=='counter':
            source=pathlib.Path(__file__).with_name('CounterFixture.swift')
            exe=root/'CounterFixture'
            compiled=local(['swiftc','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors',
                            '-target','arm64-apple-macos14.0',str(source),'-o',str(exe)])
            write(root/'fixture-build.json',dict(compiled,source_sha256=digest(source)))
            if compiled['returncode']!=0:raise ValueError('counter fixture build failed')
            app=guest+'/CounterFixture.app'
            remote_exe=app+'/Contents/MacOS/CounterFixture'
            t.remote(['mkdir','-p',app+'/Contents/MacOS'])
            uploaded=t.remote(['sh','-c','base64 -D > "$1"','qa-upload',remote_exe],input_text=base64.b64encode(exe.read_bytes()).decode())
            info=plistlib.dumps({'CFBundleIdentifier':'com.windowshade.qa.counter','CFBundleName':'QA Counter',
                                'CFBundleExecutable':'CounterFixture','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'14.0'})
            t.remote(['sh','-c','base64 -D > "$1"','qa-upload',app+'/Contents/Info.plist'],input_text=base64.b64encode(info).decode())
            t.remote(['chmod','700',remote_exe])
            sha=t.remote(['shasum','-a','256',remote_exe])
            write(root/'fixture-upload.json',dict(sha,local_sha256=digest(exe)))
            if uploaded['returncode']!=0 or sha['stdout'].split()[0]!=digest(exe):raise ValueError('counter upload mismatch')
            opened=t.remote(['open','-n',app,'--args',pathlib.Path(doc).name])
        else:
            opened=t.remote(['open','-a','TextEdit',doc])
        write(root/'document-open.json',opened)
        if opened['returncode']!=0:
            raise ValueError('document open failed')
        deadline=time.monotonic()+30
        while True:
            listed=run.call('list_windows',{})
            write(root/('windows-'+str(time.time_ns())+'.json'),listed)
            payload=listed.get('payload') or {}
            windows=payload.get('windows',[])
            matches=[w for w in windows if pathlib.Path(doc).name in str(w.get('title',w.get('window_title','')))]
            if matches: break
            if not listed['ok'] or time.monotonic()>deadline:
                raise ValueError('fixture window not discovered')
            time.sleep(1)
        w=matches[0]
        target={'pid':w.get('pid',w.get('owner_pid')),'window_id':w.get('window_id',w.get('id'))}
        if not all(isinstance(v,int) and v>0 for v in target.values()):
            raise ValueError('window identity unavailable')
        if companion:
            finder = [x for x in windows if x.get('app_name')=='Finder' and x.get('title', x.get('window_title')) == rid]
            write(root/'finder-target.json', {'windows':finder})
        ax=run.call('get_window_state',dict(target,include_screenshot=False,timeout_ms=15000))
        write(root/'baseline-ax.json',ax)
        baseline=ax_projection(ax['payload'])
        if fixture=='text' and baseline['text']!=text:
            raise ValueError('fixture text not independently confirmed')
        write(root/'target.json',{'target':target,'baseline':baseline})
        run=Run(root)
        if not run.capture('baseline')['ok']:
            raise ValueError('baseline capture failed')
        print(json.dumps({'run':str(root),'status':'ready','target':target},ensure_ascii=False))
        return 0
    except Exception as exc:
        run.halt(str(exc))
        write(root/'prepare-failure.json',{'error':str(exc)})
        print(json.dumps({'run':str(root),'status':'blocked','reason':str(exc)},ensure_ascii=False))
        return 2


def close_owned_window(run, target, menu):
    front=run.call('bring_to_front',target)
    if not front['ok'] or not (front.get('payload') or {}).get('exact_window_effect',{}).get('verified'):
        return {'ok':False,'front':front,'reason':'exact focus not confirmed'}
    closed=run.call('invoke_menu',dict(target,path=menu))
    observations=[]
    deadline=time.monotonic()+8
    while True:
        check=run.call('list_windows',{});observations.append(check)
        matched=[w for w in (check.get('payload') or {}).get('windows',[]) if w.get('window_id',w.get('id'))==target['window_id']]
        gone=not matched
        if matched and all(w.get('is_on_screen') is False for w in matched):
            ax=run.call('get_window_state',dict(target,include_screenshot=False,timeout_ms=1000))
            observations.append({'closed_ax':ax})
            gone=ax['ok'] and (ax.get('payload') or {}).get('background_input',{}).get('exact_window',{}).get('status')=='ax_unresolved'
        if not check['ok'] or gone or time.monotonic()>=deadline:break
        time.sleep(0.25)
    return {'ok':closed['ok'] and check['ok'] and gone,'front':front,'close':closed,'observations':observations}


def recover_strip(run, basis, x, y):
    """Explicit recovery only: freshly observed original title strip, double-click to restore."""
    if not NAME.fullmatch(basis):raise ValueError('invalid recovery basis')
    from evidence import checked_file
    b=read(run.root/'events'/basis/'event.json')
    if b['kind'] not in ('capture','recovery_view') or not b['ok'] or time.time()-b['end']>50:
        raise ValueError('recovery needs a fresh successful screenshot')
    if b['target']!=run.meta['target']:raise ValueError('recovery target mismatch')
    for item in b['files'].values():checked_file(run.root,item)
    shot=read(run.root/b['files']['desktop']['path'])['payload']
    f=run.meta['baseline']['frame']
    # Screenshot pixels to screen points. Only the original title strip is admissible.
    px=x*shot['screen_width']/shot['screenshot_width']
    py=y*shot['screen_height']/shot['screenshot_height']
    if not (f['x']<=px<f['x']+f['w'] and f['y']<=py<f['y']+32):
        raise ValueError('recovery coordinates outside original title strip; manual recovery required')
    d,e=run.begin('recovery-'+str(time.time_ns()),'recovery')
    e.update(basis=basis,tool='click',args={'scope':'desktop','x':x,'y':y,'count':2})
    r=run.call('click',dict(e['args'],capture_id=shot['capture_id']))
    write(d/'response.json',r)
    if not r['ok']:run.finish(d,e,False)
    if not r['ok']:raise ValueError('recovery dispatch failed')
    deadline=time.monotonic()+8
    while True:
        state=run.call('get_window_state',dict(run.meta['target'],include_screenshot=False,timeout_ms=15000))
        write(d/('restore-'+str(time.time_ns())+'.json'),state)
        try:
            restored=state['ok'] and visible_window(state['payload']) and ax_projection(state['payload'])==run.meta['baseline']
        except (ValueError,KeyError):
            restored=False
        if restored:break
        if time.monotonic()>deadline:
            run.finish(d,e,False)
            raise ValueError('restore not confirmed within recovery deadline')
        time.sleep(0.25)
    run.finish(d,e,True)
    return run.capture('restored-'+str(time.time_ns()))


def cleanup(run, reviewfile=None):
    """Restore through WindowShade before cleanup. Close only exact owned windows."""
    result={'at':time.time(),'status':'blocked','resources':[]}
    owned=read(run.root/'owned.json') if (run.root/'owned.json').exists() else {}
    try:
        if (run.root/'CLOSED.json').exists():
            return {'status':'pass','reason':'already closed; no further input'}
        if run.meta.get('target') and not (run.root/'document-closed.json').exists():
            if reviewfile is None:raise ValueError('cleanup requires --review with a visually checked restore pass; AX visibility alone cannot distinguish live preview')
            reviewed=verify(run.root,read(reviewfile))
            if not any(r['scenario']=='restore' and r['status']=='pass' for r in reviewed['results']):raise ValueError('visual restoration not verified')
            result['review_sha256']=digest(reviewfile)
            target=run.meta['target']
            ax=run.call('get_window_state',dict(target,include_screenshot=False,timeout_ms=15000))
            result['restore_check']=ax
            previous=[]
            for p in sorted(run.root.glob('cleanup-*.json')):
                previous.extend(read(p).get('resources',[]))
            dispatched=any(r.get('close',{}).get('ok') and all(r.get('front',{}).get('payload',{}).get(k)==v for k,v in target.items()) for r in previous)
            if dispatched and ax['ok'] and ax['payload'].get('background_input',{}).get('exact_window',{}).get('status')=='ax_unresolved':
                listing=run.call('list_windows',{});result['close_reconcile']=listing
                remaining=[w for w in (listing.get('payload') or {}).get('windows',[]) if w.get('window_id')==target['window_id']]
                if listing['ok'] and all(w.get('is_on_screen') is False for w in remaining):
                    write(run.root/'document-closed.json',{'at':time.time(),'target':target,'observation':listing,'ax':ax,'reconciled_previous_close':True})
                else:raise ValueError('previous close remains unresolved')
            elif not ax['ok'] or not visible_window(ax['payload']) or ax_projection(ax['payload'])!=run.meta['baseline']:
                raise ValueError('restore not confirmed; preserve window and journal, restore through WindowShade first')
        elif owned and not (run.root/'document-closed.json').exists():
            raise ValueError('fixture identity unresolved; manual recovery required')
        if owned.get('document') and not (run.root/'document-closed.json').exists():
            closed=close_owned_window(run,run.meta['target'],run.c.get('close_menu',['File','Close']))
            result['resources'].append(closed)
            if not closed['ok']:raise ValueError('exact fixture close not confirmed; do not dismiss save prompts blindly')
            write(run.root/'document-closed.json',{'at':time.time(),'target':run.meta['target'],'observation':closed})
        if owned.get('finder_folder'):
            if not (run.root/'finder-target.json').exists():
                original=sorted(run.root.glob('windows-*.json'))
                candidates=read(original[-1])['payload'].get('windows',[]) if original else []
                found=[w for w in candidates if w.get('app_name')=='Finder' and w.get('title')==run.meta['run_id']]
                write(run.root/'finder-target.json',{'windows':found})
            matches=read(run.root/'finder-target.json')['windows']
            if len(matches)!=1:raise ValueError('Finder identity ambiguous')
            w=matches[0]; target={'pid':w.get('pid',w.get('owner_pid')),'window_id':w.get('window_id',w.get('id'))}
            check=run.call('list_windows',{})
            if not check['ok']:raise ValueError('cannot observe Finder')
            present=[x for x in check['payload'].get('windows',[]) if x.get('window_id',x.get('id'))==target['window_id']]
            if present:
                if present[0].get('title',present[0].get('window_title'))!=run.meta['run_id']:
                    raise ValueError('Finder target changed')
                closed=close_owned_window(run,target,run.c.get('finder_close_menu',['File','Close Window']))
                result['resources'].append(closed)
                if not closed['ok']:raise ValueError('Finder close not confirmed')
        ended=run.call('end_session',{});result['session_end']=ended
        if not ended['ok']:raise ValueError('session end failed')
        result['status']='pass'
        write(run.root/'CLOSED.json',{'at':time.time()})
    except (ValueError,KeyError,TypeError) as exc:
        result['reason']=str(exc)
    write(run.root/('cleanup-'+str(time.time_ns())+'.json'),result)
    return result


def report(run, reviewfile):
    review=read(reviewfile)
    result=verify(run.root,review)
    tag=str(time.time_ns())
    write(run.root/('review-'+tag+'.json'),review)
    write(run.root/('verification-'+tag+'.json'),result)
    lines=['# Computer Use 验收报告','',f"运行：{result['run_id']}",
           f"构建类别：{result['build']['source']}；二进制 SHA256：{result['build']['binary_sha256']}",
           '源码与二进制关联：'+result['build']['mapping'],'',
           '| 场景 | 结果 | 原因 | 证据 |','| --- | --- | --- | --- |']
    for r in result['results']:
        why=(r.get('reason','')+'；'+'；'.join(r.get('issues',[]))).replace('|','/').replace('\n',' ')
        links=[]
        for name in (r.get('before'),r.get('after')):
            if name and (run.root/'events'/name/'event.json').is_file():
                e=read(run.root/'events'/name/'event.json')
                ref=e.get('files',{}).get('png',{}).get('path','events/'+name+'/event.json')
                links.append('['+name+']('+ref+')')
        lines.append(f"| {r['scenario']} | {r['status']} | {why} | {' / '.join(links)} |")
    lines+=['', '清理：'+result['cleanup']['status'], '证据完整性：'+str(result['evidence_errors']),
            '', '视觉结论来自具名复核；哈希证明归档一致性，不自动证明画面语义。',
            '所有尝试保留；一次后续成功不能抹掉早先失败。']
    lines += ['', '清理历史：'] + [str(x) for x in result['cleanup_history']]
    path=run.root/('report-'+tag+'.md');path.write_text('\n'.join(lines)+'\n')
    result['report']=str(path)
    manifest={str(p.relative_to(run.root)):digest(p) for p in run.root.rglob('*') if p.is_file() and p.name!='.lock'}
    write(run.root/('manifest-'+tag+'.json'),manifest)
    return result


def main():
    os.umask(0o077)
    p=argparse.ArgumentParser(description=__doc__)
    sub=p.add_subparsers(dest='command',required=True)
    d=sub.add_parser('doctor');d.add_argument('--config',required=True);d.add_argument('--session',required=True)
    q=sub.add_parser('prepare');q.add_argument('--config',required=True);q.add_argument('--companion',action='store_true');q.add_argument('--fixture',choices=['text','counter'],default='text')
    for name in ('capture','observe','act','verify','report','cleanup'):
        a=sub.add_parser(name);a.add_argument('--run',required=True)
        if name in ('capture','observe','act'):a.add_argument('--label',required=True)
        if name=='capture':a.add_argument('--recovery-view',action='store_true',help='desktop only; eligible for explicit recovery, never normal input')
        if name in ('observe','act'):
            a.add_argument('--tool',required=True);a.add_argument('--args',default='{}')
        if name=='act':a.add_argument('--basis',required=True)
        if name=='cleanup':
            a.add_argument('--review');a.add_argument('--restore-basis');a.add_argument('--restore-x',type=float);a.add_argument('--restore-y',type=float)
        if name in ('verify','report'):a.add_argument('--review',required=True)
    a=p.parse_args()
    if a.command=='doctor':
        result=doctor(config(a.config),a.session)
    elif a.command=='prepare':
        c=config(a.config)
        with vm_lock(c):return prepare(c,a.companion,a.fixture)
    else:
        run=Run(a.run)
        with vm_lock(run.c), lock(run.root):
            if a.command=='capture':result=run.capture(a.label,ax=not a.recovery_view)
            elif a.command=='observe':result=run.observe(a.label,a.tool,json.loads(a.args))
            elif a.command=='act':result=run.act(a.label,a.tool,json.loads(a.args),a.basis)
            elif a.command=='cleanup':
                if any(v is not None for v in (a.restore_basis,a.restore_x,a.restore_y)):
                    if any(v is None for v in (a.restore_basis,a.restore_x,a.restore_y)):raise ValueError('all restore options are required together')
                    restored=recover_strip(run,a.restore_basis,a.restore_x,a.restore_y)
                    result={'status':'needs_visual_review','restored':restored,'reason':'Open the new image, write the restore review, then run cleanup --review. No windows closed.'}
                else:result=cleanup(run,a.review)
            elif a.command=='report':result=report(run,a.review)
            else:result=verify(run.root,read(a.review))
    print(json.dumps(result,ensure_ascii=False,indent=2))
    if a.command in ('verify','report'):return 0 if result['all_passed'] else 2
    return 0 if result.get('ok',result.get('status')=='pass') else 2


if __name__=='__main__':
    try:sys.exit(main())
    except (ValueError, OSError, KeyError, TypeError) as exc:
        print(json.dumps({'status':'blocked','error':str(exc)},ensure_ascii=False),file=sys.stderr)
        sys.exit(2)
