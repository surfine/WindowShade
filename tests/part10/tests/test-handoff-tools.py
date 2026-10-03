#!/usr/bin/env python3
"""Handoff/reference and evidence-path tests. Not application feature certification."""
import argparse,hashlib,importlib.util,json,os,pathlib,tempfile,unittest
p=argparse.ArgumentParser();p.add_argument('--candidate',type=pathlib.Path,required=True);a=p.parse_args();P=pathlib.Path(__file__).resolve().parent.parent
s=importlib.util.spec_from_file_location('runner',P/'tools/run-final.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class Tests(unittest.TestCase):
 def setUp(self):
  self.t=tempfile.TemporaryDirectory(prefix='ws2-tool-');self.root=pathlib.Path(self.t.name);self.source=self.root/'source';self.source.mkdir()
 def tearDown(self):self.t.cleanup()
 def test_01_fresh_report_private(self):
  out=m.external_report(self.root/'out',[self.source]);self.assertTrue(out.is_dir());self.assertEqual(out.stat().st_mode&0o777,0o700)
 def test_02_existing_report_not_overwritten(self):
  out=self.root/'out';out.mkdir();(out/'keep').write_text('old')
  with self.assertRaises(ValueError):m.external_report(out,[self.source])
  self.assertEqual((out/'keep').read_text(),'old')
 def test_03_nested_report_rejected(self):
  with self.assertRaises(ValueError):m.external_report(self.source/'out',[self.source])
 def test_04_ancestor_report_rejected(self):
  with self.assertRaises(ValueError):m.external_report(self.root,[self.source])
 def test_05_symlink_parent_rejected(self):
  link=self.root/'link';link.symlink_to(self.root,target_is_directory=True)
  with self.assertRaises(ValueError):m.external_report(link/'out',[self.source])
 def test_06_missing_parent_rejected(self):
  with self.assertRaises(ValueError):m.external_report(self.root/'missing'/'out',[self.source])
 def test_07_file_output_rejected(self):
  f=self.root/'out';f.write_text('keep')
  with self.assertRaises(ValueError):m.external_report(f,[self.source])
  self.assertEqual(f.read_text(),'keep')
 def test_08_inventory_sees_content_change(self):
  f=self.source/'a';f.write_text('one');before=m.inventory(self.source);f.write_text('two');self.assertNotEqual(before,m.inventory(self.source))
 def test_09_inventory_does_not_dereference_link(self):
  (self.source/'outside').symlink_to(self.root/'missing');self.assertTrue(m.inventory(self.source)['outside'].startswith('SYMLINK:'))
 def test_10_all_original_axes_present(self):
  plan=json.loads((P/'execution-plan.json').read_text());self.assertEqual(plan['original_axes'],['窗口','实时活动','电量','CarPlay','指挥模式','刷脸解锁','隐私'])
 def test_11_dependencies_acyclic_and_valid(self):
  tasks=json.loads((P/'execution-plan.json').read_text())['tasks'];by={t['id']:t for t in tasks};self.assertEqual(len(by),12);visited=set();active=set()
  def walk(key):
   self.assertIn(key,by);self.assertNotIn(key,active)
   if key in visited:return
   active.add(key)
   for dep in by[key]['dependencies']:walk(dep)
   active.remove(key);visited.add(key)
  for key in by:walk(key)
  self.assertEqual(len(visited),12)
 def test_12_all_workorders_and_actual_paths_exist(self):
  tasks=json.loads((P/'execution-plan.json').read_text())['tasks']
  drift=json.loads((P/'drift.json').read_text());absent=set(drift['intentionally_absent']);remap=drift['code_map_remap']
  for t in tasks:
   self.assertTrue((P/t['workorder']).is_file())
   for path in t['source_paths']:
    if path in absent:
     # 本仓库明确不建第二套岛管理器：这个文件必须不存在，而不是「忘了建」。
     self.assertFalse((a.candidate/path).exists(),path);continue
    self.assertTrue((a.candidate/remap.get(path,path)).is_file(),path)
 def test_13_no_original_work_package_lost(self):
  tasks=json.loads((P/'execution-plan.json').read_text())['tasks'];codes={v for t in tasks for v in t['original_packages']}
  expected={'M1','S1','T1','T2','T3','T4','L1','L2','L3','L4','L5','A1','A2a','A2b','A3','A4','A5','D1','D2','D3','D4','D5a','D5b','D5c','D6','I1a','I1b','I1c','I1d','I1e','I1f','I2','I3','I4','I5a','I5b','I6','I7','I8','I9'}
  self.assertTrue(expected.issubset(codes),str(expected-codes));self.assertIn('FACE-F1',codes);self.assertIn('FILM-F1',codes)
 def test_14_code_map_hashes_and_lines(self):
  rows=json.loads((P/'sources/code-map.json').read_text())['files'];self.assertEqual(len(rows),len({x['path'] for x in rows}))
  # 本仓库比第十份钉的 v9 快照更新（第九份 + 第十份 + Mac 实测补丁）。允许清单见 drift.json /
  # DRIFT.md；清单外的任何漂移仍然失败，而且清单必须与实际情况完全一致。
  drift=json.loads((P/'drift.json').read_text());allowed=set(drift['code_map_drift']);remap=drift['code_map_remap'];seen=set()
  for x in rows:
   f=a.candidate/remap.get(x['path'],x['path'])
   if not f.is_file():
    self.assertIn(x['path'],allowed,'unlisted missing source: '+x['path']);seen.add(x['path']);continue
   if hashlib.sha256(f.read_bytes()).hexdigest()!=x['sha256'] or len(f.read_text().splitlines())!=x['line_count']:
    self.assertIn(x['path'],allowed,'unlisted drift: '+x['path']);seen.add(x['path'])
   for symbol in x['symbols']:self.assertGreater(symbol['line'],0);self.assertLessEqual(symbol['line'],x['line_count'])
  self.assertEqual(seen,allowed,'drift list must match the actual repository')
 def test_15_candidate_final_entry_is_real(self):
  self.assertIn('FINAL-HANDOFF.md',(a.candidate/'AGENTS.md').read_text());self.assertIn('W11',(a.candidate/'docs/handoff/FINAL-HANDOFF.md').read_text())
 def test_16_carplay_not_artificially_blocked_by_companion(self):
  tasks=json.loads((P/'execution-plan.json').read_text())['tasks'];self.assertEqual(next(t for t in tasks if t['id']=='W08')['dependencies'],['W00'])
class Recorded(unittest.TextTestResult):
 def __init__(self,*args,**kw):super().__init__(*args,**kw);self.rows=[]
 def addSuccess(self,t):super().addSuccess(t);self.rows.append({'name':t.id(),'status':'PASSED'})
 def addFailure(self,t,e):super().addFailure(t,e);self.rows.append({'name':t.id(),'status':'FAILED'})
 def addError(self,t,e):super().addError(t,e);self.rows.append({'name':t.id(),'status':'ERROR'})
r=unittest.TextTestRunner(verbosity=2,resultclass=Recorded).run(unittest.defaultTestLoader.loadTestsFromTestCase(Tests));(P/'validation/handoff-tool-tests.json').write_text(json.dumps({'kind':'DOCUMENT_AND_TOOL_TESTS','tests':r.testsRun,'failures':len(r.failures),'errors':len(r.errors),'cases':r.rows},indent=2)+'\n');raise SystemExit(0 if r.wasSuccessful() else 1)
