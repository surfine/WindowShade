#!/usr/bin/env python3
"""Synthetic pinned-shape backend. No network, account access, or shell execution.
Tests copy this under an isolated name to select fault fixtures; never install as Codex.
"""
import json, os, pathlib, signal, sys, time
mode = pathlib.Path(__file__).stem.replace('fake-codex-', '')
if sys.argv[1:] == ['--version']:
    if mode == 'version-hang':
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        while True: time.sleep(0.1)
    print('codex-cli 9.9.9' if mode == 'version' else 'codex-cli 0.153.0', flush=True)
    sys.exit(0)
if sys.argv[1:] != ['app-server']:
    sys.exit(64)
log = pathlib.Path(__file__).with_suffix('.messages.ndjson')
logged = mode not in ['login', 'url', 'login-wrong-id', 'login-cancel']
thread = 'thread-real-fixture'
turn = None
count = 0
pending_approval = False

def emit(value):
    print(json.dumps(value, ensure_ascii=False, separators=(',', ':')), flush=True)

def result(id, value): emit({'id': id, 'result': value})
def notify(method, params): emit({'method': method, 'params': params})
def complete(status='completed'):
    notify('turn/completed', {'threadId': thread, 'turn': {'id': turn, 'status': status, 'items': [], 'error': None}})

for line in sys.stdin:
    message = json.loads(line)
    with log.open('a') as f: f.write(json.dumps(message) + '\n')
    method, id, p = message.get('method'), message.get('id'), message.get('params', {})
    if method == 'initialize':
        if mode == 'duplicate':
            print('{"id":1,"\\u0069d":2,"result":{}}', flush=True)
        else:
            result(id, {'userAgent': 'FAKE / NO NETWORK'})
    elif method == 'initialized': pass
    elif method == 'model/list':
        rows = [{'id':'fixture-a','model':'fixture-a','displayName':'Fixture A', 'description':'Synthetic only',
                 'hidden':False,'isDefault':True,'defaultReasoningEffort':'medium',
                 'supportedReasoningEfforts':[{'reasoningEffort':'medium','description':'M'}, {'reasoningEffort':'high','description':'H'}]}]
        result(id, {'data': rows, 'nextCursor': None})
    elif method == 'config/read':
        config = {'sandbox_mode':'danger-full-access' if mode == 'config' else 'read-only',
                  'approval_policy':'on-request','approvals_reviewer':'user','model_provider':'openai',
                  'web_search':'disabled','features':{'shell_tool':False,'unified_exec':False,'shell_snapshot':False},
                  'mcp_servers':{},'plugins':{},'hooks':{}}
        result(id, {'config':config, 'layers':[], 'origins':{}})
    elif method == 'account/read':
        result(id, {'account':{'type':'chatgpt','email':None,'planType':'unknown'} if logged else None,
                    'requiresOpenaiAuth':True})
    elif method == 'account/login/start':
        result(id, {'type':'chatgpt','loginId':'login-fixture',
                    'authUrl':'file:///tmp/not-a-browser-login' if mode == 'url' else 'https://auth.openai.com/authorize?state=fixture'})
        if mode not in ['url','login-cancel']:
            logged = True
            notify('account/login/completed',{'loginId':'WRONG' if mode == 'login-wrong-id' else 'login-fixture','success':True,'error':None})
    elif method == 'account/login/cancel': result(id, {'status':'canceled'})
    elif method == 'account/logout':
        logged = False
        result(id,{})
        notify('account/updated',{'authMode':None,'planType':None})
    elif method in ['thread/start','thread/resume']:
        if method == 'thread/resume': thread = p['threadId']
        result(id,{'thread':{'id':thread}})
    elif method == 'turn/start':
        count += 1
        turn = 'turn-' + str(count)
        result(id,{'turn':{'id':turn, 'status':'inProgress'}})
        notify('turn/started',{'threadId':thread,'turn':{'id':turn,'status':'inProgress'}})
        notify('item/agentMessage/delta',{'threadId':'FOREIGN','turnId':turn,'itemId':'f','delta':'WRONG-TARGET'})
        notify('item/agentMessage/delta',{'threadId':thread,'turnId':turn,'itemId':'a','delta':'来自受控后端的真实管道回复。'})
        if mode == 'approval':
            pending_approval = True
            emit({'id':'approval-fixture','method':'item/commandExecution/requestApproval','params':{
                'threadId':thread,'turnId':turn,'itemId':'command-1','command':'printf harmless', 'cwd':os.getcwd()}})
        elif mode not in ['hold','lock','directory','diagnostics']:
            complete('failed' if mode == 'failed' else 'completed')
        if mode == 'diagnostics': print('fixture stderr, NO USER SECRETS', file=sys.stderr, flush=True)
    elif method == 'turn/interrupt':
        result(id,{})
        time.sleep(0.15)
        complete('interrupted')
    elif pending_approval and id == 'approval-fixture':
        assert message['result']['decision'] == 'decline', 'Unexpected allow!'
        pending_approval = False
        complete()
