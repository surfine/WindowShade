#!/usr/bin/env python3
"""Exercise the actual shell script with MOCKED compiler/SDK commands. Not a Mac build."""
import argparse, json, os, pathlib, shutil, subprocess, sys, tempfile, unittest
p=argparse.ArgumentParser();p.add_argument('--candidate',required=True,type=pathlib.Path);p.add_argument('--baseline',type=pathlib.Path);a=p.parse_args()
P=pathlib.Path(__file__).resolve().parent.parent
SCRIPT=(a.candidate/'prototype/build.sh').read_bytes()
MOCK='''#!PYTHON
import os,sys,pathlib,json
name=pathlib.Path(sys.argv[0]).name;args=sys.argv[1:]
with open(os.environ['MOCK_LOG'],'a') as f:f.write(json.dumps([name,args])+'\\n')
if name=='xcrun' and '--show-sdk-path' in args: print(os.environ['MOCK_SDK']);sys.exit(0)
kind=('swift-guard' if any('UpdateGuard-check' in x for x in args) else 'swift-main') if name=='swiftc' else next((x for x in ['clang','metal','metallib'] if x in args),name)
if kind==os.environ.get('MOCK_FAIL'):sys.exit(43)
if name not in ['swiftc','xcrun']:sys.exit(91)
if '-o' in args:
 p=pathlib.Path(args[args.index('-o')+1]);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b'MOCK-NOT-A-BINARY')
'''.replace('PYTHON',sys.executable+' -S')
class Test(unittest.TestCase):
 def setUp(self):
  self.t=tempfile.TemporaryDirectory(prefix='ws2-mock-');self.root=pathlib.Path(self.t.name);self.r=self.root/'repo';self.d=self.r/'prototype';self.d.mkdir(parents=True);(self.d/'build.sh').write_bytes(SCRIPT)
  for file in ['main.swift','Watchdog/main.swift','Watchdog/GuardIcon.swift','Core/UpdateVersion.swift','Core/UpdateModels.swift','Core/UpdateDecisions.swift','App/UpdaterSystem.swift','App/UpdaterCopy.swift','Effects/Duo.metal','Native/WS2Child.c','Native/WS2Child.h','Native/module.modulemap']:
   f=self.d/file;f.parent.mkdir(parents=True,exist_ok=True);f.write_text('// MOCK source, not built\n')
  self.bin=self.root/'bin';self.bin.mkdir();self.log=self.root/'calls.ndjson';self.sdk=self.root/'sdk';self.sdk.mkdir()
  for name in ['swiftc','xcrun','codesign','security','pgrep','killall','open','ditto','lipo']:
   f=self.bin/name;f.write_text(MOCK);f.chmod(0o700)
  self.env={**os.environ,'PATH':str(self.bin)+os.pathsep+os.environ['PATH'],'MOCK_LOG':str(self.log),'MOCK_SDK':str(self.sdk),'WINDOWSHADE_ARCH':'arm64'}
  self.env.pop('WINDOWSHADE_CODESIGN_IDENTITY',None);self.env.pop('MOCK_FAIL',None)
 def tearDown(self):self.t.cleanup()
 def run_check(self):return subprocess.run(['bash',str(self.d/'build.sh'),'--check'],env=self.env,capture_output=True,text=True,timeout=20)
 def calls(self):return [json.loads(x) for x in self.log.read_text().splitlines()] if self.log.exists() else []
 def test_01_check_does_not_source_signing(self):
  (self.d/'local-codesign.env').write_text('echo EXECUTED > "$PWD/forbidden"; exit 97\n');v=self.run_check();self.assertEqual(v.returncode,0,v.stderr);self.assertFalse((self.d/'forbidden').exists())
 def test_02_main_and_guard_strict(self):
  v=self.run_check();self.assertEqual(v.returncode,0,v.stderr);calls=[args for cmd,args in self.calls() if cmd=='swiftc'];self.assertEqual(len(calls),2)
  for args in calls:self.assertEqual(args[args.index('-swift-version')+1],'6');self.assertIn('-strict-concurrency=complete',args);self.assertIn('-warnings-as-errors',args)
 def test_03_both_normal_invocations_use_same_flags(self):
  text=SCRIPT.decode();self.assertEqual(text.count('swiftc "${SWIFT_LANGUAGE_FLAGS[@]}"'),4);self.assertNotIn('swiftc -module-cache-path',text)
 def test_04_no_sign_or_launch_or_bundle(self):
  self.assertEqual(self.run_check().returncode,0);self.assertFalse((self.d/'WindowShade.app').exists());self.assertTrue(all(cmd in ('xcrun','swiftc') for cmd,args in self.calls()))
 def test_05_c_failure_propagates(self):
  self.env['MOCK_FAIL']='clang';v=self.run_check();self.assertEqual(v.returncode,43);self.assertNotIn('编译验证通过',v.stdout);self.assertFalse(any(x[0]=='swiftc' for x in self.calls()))
 def test_06_metal_failure_propagates(self):
  self.env['MOCK_FAIL']='metal';self.assertEqual(self.run_check().returncode,43);self.assertFalse(any(x[0]=='swiftc' for x in self.calls()))
 def test_07_metallib_failure_propagates(self):
  self.env['MOCK_FAIL']='metallib';self.assertEqual(self.run_check().returncode,43)
 def test_08_main_failure_skips_guard(self):
  self.env['MOCK_FAIL']='swift-main';v=self.run_check();self.assertEqual(v.returncode,43);self.assertEqual(len([x for x in self.calls() if x[0]=='swiftc']),1)
 def test_09_guard_failure_no_success_message(self):
  self.env['MOCK_FAIL']='swift-guard';v=self.run_check();self.assertEqual(v.returncode,43);self.assertNotIn('编译验证通过',v.stdout)
 def test_10_native_and_main_same_target(self):
  self.assertEqual(self.run_check().returncode,0)
  for cmd,args in self.calls():
   if cmd=='swiftc' or 'clang' in args:self.assertEqual(args[args.index('-target')+1],'arm64-apple-macosx14.0')
 def test_11_temporary_sources_cleaned(self):
  self.run_check();self.assertEqual(list((self.r/'.build').glob('duo-build.*')),[])
 def test_12_glass_checks_header_not_version(self):
  f=self.sdk/'System/Library/Frameworks/AppKit.framework/Headers/NSGlassEffectView.h';f.parent.mkdir(parents=True);f.write_text('// test only');self.assertEqual(self.run_check().returncode,0)
  main=next(args for cmd,args in self.calls() if cmd=='swiftc');self.assertIn('-DWINDOWSHADE_SDK_HAS_GLASS',main)
class Recorded(unittest.TextTestResult):
 def __init__(self,*args,**kw):super().__init__(*args,**kw);self.rows=[]
 def addSuccess(self,t):super().addSuccess(t);self.rows.append({'test':t.id(),'status':'PASSED'})
 def addFailure(self,t,e):super().addFailure(t,e);self.rows.append({'test':t.id(),'status':'FAILED'})
 def addError(self,t,e):super().addError(t,e);self.rows.append({'test':t.id(),'status':'ERROR'})
result=unittest.TextTestRunner(verbosity=2,resultclass=Recorded).run(unittest.defaultTestLoader.loadTestsFromTestCase(Test))
report={'tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'kind':'ACTUAL_SHELL_MOCKED_SDK_COMPILER','mac_build':'NOT_RUN','cases':result.rows}
if a.baseline:
 t=Test();t.setUp()
 try:
  (t.d/'build.sh').write_bytes((a.baseline/'prototype/build.sh').read_bytes());(t.d/'local-codesign.env').write_text('echo EXECUTED > "$PWD/forbidden"; exit 97\n');q=t.run_check()
  report['baseline']={'exit_code':q.returncode,'signing_config_executed':(t.d/'forbidden').exists(),'stdout':q.stdout,'stderr':q.stderr,'explicit_language_flag_count':(a.baseline/'prototype/build.sh').read_text().count('-swift-version')}
 finally:t.tearDown()
(P/'validation/build-entry-tests.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
raise SystemExit(0 if result.wasSuccessful() else 1)
