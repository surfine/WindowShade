#!/usr/bin/env python3
"""File-tool tests use a tiny synthetic baseline, never the user's working tree."""
import contextlib,hashlib,importlib.util,json,pathlib,subprocess,tempfile,unittest
root=pathlib.Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('stage',root/'tools/stage.py');stage=importlib.util.module_from_spec(spec);spec.loader.exec_module(stage)
class Tests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix='ws2-stage-test-');self.root=pathlib.Path(self.temp.name).resolve();self.base=self.root/'base';self.base.mkdir();(self.base/'old').write_text('old')
  self.pkg=self.root/'package';(self.pkg/'overlay').mkdir(parents=True);(self.pkg/'sources').mkdir();(self.pkg/'overlay'/'old').write_text('new');(self.pkg/'overlay'/'addition').write_text('added')
  self.expected=stage.snapshot(self.base);(self.pkg/'sources/base-manifest.json').write_text(json.dumps(self.expected));self.man={'changes':[dict(path=x,baseSHA256=self.expected.get(x),sha256=stage.digest(self.pkg/'overlay'/x)) for x in ['old','addition']]};self.save();self.out=self.root/'out'
 def save(self):(self.pkg/'manifest.json').write_text(json.dumps(self.man))
 def tearDown(self):self.temp.cleanup()
 def test_exact_output(self):
  result=stage.stage(self.pkg,self.base,self.out);self.assertEqual(result['output_files'],2);self.assertTrue(result['original_preserved']);self.assertEqual((self.out/'old').read_text(),'new')
 def test_existing_output(self):
  self.out.mkdir();self.assertRaises(ValueError,stage.stage,self.pkg,self.base,self.out)
 def test_drift(self):
  (self.base/'old').write_text('user edit');self.assertRaises(ValueError,stage.stage,self.pkg,self.base,self.out);self.assertFalse(self.out.exists())
 def test_output_inside_base(self):self.assertRaises(ValueError,stage.stage,self.pkg,self.base,self.base/'out')
 def test_overlay_drift(self):
  (self.pkg/'overlay'/'old').write_text('wrong');self.assertRaises(ValueError,stage.stage,self.pkg,self.base,self.out)
 def test_baseline_symlink(self):
  (self.base/'linked').symlink_to(self.base/'old');self.assertRaises(ValueError,stage.stage,self.pkg,self.base,self.out)
 def test_overlay_symlink(self):
  (self.pkg/'overlay'/'linked').symlink_to(self.base/'old');self.assertRaises(ValueError,stage.stage,self.pkg,self.base,self.out)
 def test_traversal(self):
  self.man['changes'][0]['path']='../escape';self.save();self.assertRaises(ValueError,stage.stage,self.pkg,self.base,self.out)
 def test_missing_overlay_entry(self):
  self.man['changes'].pop();self.save();self.assertRaises(ValueError,stage.stage,self.pkg,self.base,self.out)
 def test_duplicate_manifest_path(self):
  self.man['changes'].append(self.man['changes'][0]);self.save();self.assertRaises(ValueError,stage.stage,self.pkg,self.base,self.out)
if __name__=='__main__':
 with (root/'validation/tools-tests.txt').open('w') as log:
  result=unittest.TextTestRunner(stream=log,verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Tests))
 report={'tests_run':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'scope':'synthetic file staging, not application runtime'}
 (root/'validation/tools-tests.json').write_text(json.dumps(report,indent=2));print((root/'validation/tools-tests.txt').read_text());raise SystemExit(not result.wasSuccessful())
