"""Evidence contract; never infer visible behavior from a successful tool call."""
import hashlib
import json
import pathlib
import struct
import time

SCENARIOS = {
    'fold-companion': ['content_hidden', 'strip_visible', 'focus_handoff'],
    'fold-solo': ['only_target_window', 'content_hidden', 'strip_visible'],
    'peek-static': ['content_matches', 'snapshot_label', 'focus_unchanged'],
    'peek-live': ['counter_changes', 'not_snapshot', 'focus_unchanged'],
    'peek-cancel': ['preview_gone', 'strip_remains', 'window_still_folded'],
    'restore': ['content_matches', 'geometry_matches', 'window_visible'],
    'target-change': ['target_changed', 'no_unrelated_input'],
    'observation-failure': ['observation_failed', 'subsequent_input_refused'],
}
STATUSES = {'pass', 'fail', 'blocked', 'inconclusive', 'not_run'}


def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def read(path):
    return json.loads(pathlib.Path(path).read_text())


def write(path, data):
    # Evidence records are exclusive. Never rewrite a previous attempt.
    with open(path, 'x') as stream:
        json.dump(data, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


def checked_file(root, item):
    p = (root / item['path']).resolve()
    if not p.is_relative_to(root.resolve()) or not p.is_file():
        raise ValueError('missing or escaping evidence: ' + item['path'])
    if digest(p) != item['sha256']:
        raise ValueError('changed evidence: ' + item['path'])
    return p


def png_size(path):
    b = pathlib.Path(path).read_bytes()
    if len(b) < 24 or b[:8] != b'\x89PNG\r\n\x1a\n' or b[12:16] != b'IHDR':
        raise ValueError('invalid PNG')
    return struct.unpack('>II', b[16:24])


def ax_projection(payload):
    windows = [e for e in payload.get('elements', []) if e.get('role') == 'AXWindow']
    if len(windows) != 1 or payload.get('degraded_reason') or payload.get('truncated'):
        raise ValueError('AX window unresolved or incomplete')
    return {'pid': payload['pid'], 'window_id': payload['window_id'],
            'title': payload.get('window_title'), 'frame': windows[0].get('frame'),
            'text': '\n'.join(e.get('value', '') for e in payload['elements']
                              if e.get('role') == 'AXTextArea')}


def visible_window(payload):
    routes = payload.get('background_input', {}).get('routes', [])
    return any(r.get('route') == 'window_pointer' and r.get('status') == 'available' for r in routes)


def template():
    return {'reviewer': '', 'attempts': [
        {'scenario': s, 'status': 'not_run', 'before': '', 'after': '',
         'reason': '', 'checks': {k: {'status': 'not_run', 'evidence': [], 'reason': ''}
                                for k in keys}}
        for s, keys in SCENARIOS.items()]}


def verify(root, review):
    root = pathlib.Path(root)
    meta = read(root / 'run.json')
    if (root / 'target.json').exists():
        meta.update(read(root / 'target.json'))
    events, errors = {}, []
    seen_captures = set()
    for p in sorted((root / 'events').glob('*/event.json')):
        try:
            e = read(p)
            if e.get('label')!=p.parent.name:raise ValueError('event label disagrees with directory')
            if e['run_id'] != meta['run_id'] or e['start'] < meta['created'] or e['end'] < e['start']:
                raise ValueError('stale run or invalid time')
            for item in e['files'].values():
                checked_file(root, item)
            if e['kind'] == 'capture' and e['ok']:
                raw = read(checked_file(root, e['files']['desktop']))
                if not raw.get('ok'):
                    raise ValueError('desktop response reports failure')
                d = raw['payload']
                axraw=read(checked_file(root,e['files']['ax']))
                if not axraw.get('ok') or any(axraw.get('payload',{}).get(k)!=v for k,v in meta.get('target',{}).items()):
                    raise ValueError('AX evidence identity disagrees')
                if not d.get('capture_id') or d['capture_id'] in seen_captures:
                    raise ValueError('missing or reused capture identity')
                seen_captures.add(d['capture_id'])
                if png_size(checked_file(root, e['files']['png'])) != (d['screenshot_width'], d['screenshot_height']):
                    raise ValueError('screenshot dimensions disagree')
                if d['screenshot_file_path'] != e['remote_png']:
                    raise ValueError('capture source disagrees')
            events[e['label']] = e
        except (KeyError, ValueError, TypeError, OSError) as exc:
            errors.append(f'{p.parent.name}: {exc}')
    results = []
    review_sources=[read(p) for p in sorted(root.glob('review-*.json')) if p.name!='review-template.json']+[review]
    attempts=[];seen=set()
    for source in review_sources:
        for a in source.get('attempts',[]):
            key=json.dumps(a,sort_keys=True,ensure_ascii=False)
            if key not in seen:
                attempts.append((a,source.get('reviewer','')));seen.add(key)
    for attempt, reviewer in attempts:
        s, status = attempt.get('scenario'), attempt.get('status')
        issues = []
        if s not in SCENARIOS or status not in STATUSES:
            issues.append('unknown scenario or status')
        if status != 'not_run' and not attempt.get('reason', '').strip():
            issues.append('missing explanation')
        if status == 'pass':
            if not reviewer.strip():
                issues.append('missing visual reviewer')
            before, after = events.get(attempt.get('before')), events.get(attempt.get('after'))
            if not before or not after or before['end'] >= after['start']:
                issues.append('missing or unordered before/after observations')
            else:
                for e in (before, after):
                    if s == 'observation-failure' and e is after and e['kind'] == 'refused':
                        continue
                    if e['kind'] != 'capture' or not e['ok']:
                        issues.append('observation failed')
                    if s not in ('target-change', 'observation-failure') and e.get('target') != meta.get('target'):
                        issues.append('target identity mismatch')
                # No evidence after an observation fault can silently regain credibility.
                if s not in ('observation-failure','restore') and any(not e['ok'] and e['end'] <= after['end'] for e in events.values()):
                    issues.append('earlier session/observation failure; use a fresh run')
            for k in SCENARIOS.get(s, []):
                c = attempt.get('checks', {}).get(k, {})
                refs = c.get('evidence', [])
                if c.get('status') != 'pass' or not c.get('reason', '').strip() or not refs:
                    issues.append('missing/contradictory review: ' + k)
                elif any(r not in events for r in refs):
                    issues.append('unknown evidence reference: ' + k)
            if s == 'restore' and after and after.get('ok'):
                try:
                    ax = read(checked_file(root, after['files']['ax']))['payload']
                    if ax_projection(ax) != meta.get('baseline'):
                        issues.append('AX geometry/content/identity differs from baseline')
                except (ValueError, KeyError) as exc:
                    issues.append(str(exc))
            if s == 'peek-live' and before and after and before.get('files', {}).get('png', {}).get('sha256') == after.get('files', {}).get('png', {}).get('sha256'):
                issues.append('same image cannot establish live preview')
            if s == 'peek-live':
                m=attempt.get('measurements',{})
                values=[m.get('counter_before'),m.get('counter_after')]
                if any(type(v) is not int for v in values) or values[0]==values[1]:
                    issues.append('need distinct visually read counter_before/counter_after integers')
            if s == 'observation-failure':
                if not any(e['kind']=='capture' and not e['ok'] for e in events.values()) or not any(e['kind'] == 'refused' for e in events.values()):
                    issues.append('missing real failure and refusal records')
            if errors:
                issues.append('run evidence integrity failed')
        results.append({'scenario': s, 'requested': status,
                        'status': 'inconclusive' if issues else status,
                        'reason': attempt.get('reason', ''), 'issues': issues,
                        'before': attempt.get('before'), 'after': attempt.get('after')})
    for s in SCENARIOS:
        if not any(r['scenario'] == s for r in results):
            results.append({'scenario': s, 'status': 'not_run', 'reason': 'no attempt'})
    cleanups = sorted(root.glob('cleanup-*.json'))
    cleanup = read(cleanups[-1]) if cleanups else {'status': 'not_run'}
    return {'run_id': meta['run_id'], 'build': meta['build'], 'evidence_errors': errors,
            'results': results, 'cleanup': cleanup,
            'cleanup_history': [{'file':p.name,'status':read(p).get('status'),'reason':read(p).get('reason')} for p in cleanups],
            'all_passed': not errors and bool(results) and all(r['status'] == 'pass' for r in results)
                          and cleanup.get('status') == 'pass'}
