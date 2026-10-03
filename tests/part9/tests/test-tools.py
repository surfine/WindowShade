#!/usr/bin/env python3
"""Filesystem refusal tests on tiny fixtures; not product runtime tests."""
import importlib.util,json,pathlib,tempfile,unittest,hashlib,os
P=pathlib.Path(__file__).resolve().parent.parent
s=importlib.util.spec_from_file_location('stage',P/'tools/stage.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class Tests(unittest.TestCase):
 def setUp(self):
  self.t=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.t.name);self.p=self.root/'pack';self.b=self.root/'base';self.o=self.root/'out'
  (self.p/'sources').mkdir(parents=True);(self.p/'overlay').mkdir();self.b.mkdir();(self.b/'x').write_text('old');(self.p/'overlay/x').write_text('new');(self.p/'overlay/y').write_text('added')
  self.base={'x':m.digest(self.b/'x')};self.man={'changes':[dict(path='x',operation='replace',base_sha256=self.base['x'],sha256=m.digest(self.p/'overlay/x')),dict(path='y',operation='add',base_sha256=None,sha256=m.digest(self.p/'overlay/y'))],'result_file_count':2}
  (self.p/'sources/base-files.json').write_text(json.dumps(self.base));self.save()
 def tearDown(self):self.t.cleanup()
 def save(self):(self.p/'manifest.json').write_text(json.dumps(self.man))
 def apply(self):return m.apply(self.p,self.b,self.o)
 def refuses(self):
  with self.assertRaises((m.StageError,FileExistsError)):self.apply()
  self.assertFalse(self.o.exists())
 def test_success_and_original(self):
  r=self.apply();self.assertEqual(r['result_file_count'],2);self.assertEqual((self.o/'x').read_text(),'new');self.assertEqual((self.b/'x').read_text(),'old')
 def test_existing_directory(self):
  self.o.mkdir();(self.o/'keep').write_text('keep')
  with self.assertRaises(m.StageError):self.apply()
  self.assertEqual((self.o/'keep').read_text(),'keep')
 def test_existing_file(self):
  self.o.write_text('keep')
  with self.assertRaises(m.StageError):self.apply()
  self.assertEqual(self.o.read_text(),'keep')
 def test_wrong_base(self):(self.b/'x').write_text('changed');self.refuses()
 def test_missing_base(self):(self.b/'x').unlink();self.refuses()
 def test_extra_base(self):(self.b/'extra').write_text('new');self.refuses()
 def test_bad_overlay(self):(self.p/'overlay/y').write_text('corrupt');self.refuses()
 def test_missing_overlay(self):(self.p/'overlay/y').unlink();self.refuses()
 def test_extra_overlay(self):(self.p/'overlay/z').write_text('unlisted');self.refuses()
 def test_base_symlink(self):(self.b/'link').symlink_to(self.b/'x');self.refuses()
 def test_overlay_symlink(self):(self.p/'overlay/x').unlink();(self.p/'overlay/x').symlink_to(self.b/'x');self.refuses()
 def test_nested_output(self):
  self.o=self.b/'out';self.refuses()
 def test_package_output(self):
  self.o=self.p/'out';self.refuses()
 def test_traversal(self):self.man['changes'][0]['path']='../escape';self.save();self.refuses()
 def test_duplicate_manifest_path(self):self.man['changes'].append(self.man['changes'][0]);self.save();self.refuses()
 def test_wrong_base_sha(self):self.man['changes'][0]['base_sha256']='0'*64;self.save();self.refuses()
 def test_wrong_count(self):self.man['result_file_count']=999;self.save();self.refuses()
 def test_symlink_parent(self):
  link=self.root/'link';link.symlink_to(self.root,target_is_directory=True);self.o=link/'nested';self.refuses()
class Recorded(unittest.TextTestResult):
 def __init__(self,*a,**kw):super().__init__(*a,**kw);self.records=[]
 def addSuccess(self,test):super().addSuccess(test);self.records.append({'name':test.id(),'result':'PASS'})
 def addFailure(self,test,err):super().addFailure(test,err);self.records.append({'name':test.id(),'result':'FAIL'})
 def addError(self,test,err):super().addError(test,err);self.records.append({'name':test.id(),'result':'ERROR'})
if __name__=='__main__':
 result=unittest.TextTestRunner(verbosity=2,resultclass=Recorded).run(unittest.defaultTestLoader.loadTestsFromTestCase(Tests))
 (P/'validation/tools-tests.json').write_text(json.dumps(dict(tests_run=result.testsRun,failures=len(result.failures),errors=len(result.errors),cases=result.records),indent=2)+'\n')
 raise SystemExit(0 if result.wasSuccessful() else 1)
