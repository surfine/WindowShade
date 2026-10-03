#!/usr/bin/env python3
"""Synthetic validator tests, not evidence that an application feature works."""
import copy
import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / "tools/readiness.py"
spec = importlib.util.spec_from_file_location("readiness", MODULE)
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)

class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "test.txt").write_text("SYNTHETIC TEST EVIDENCE ONLY\n")
        self.digest = hashlib.sha256((self.root / "test.txt").read_bytes()).hexdigest()
        record = {"status":"passed", "candidateRevision":"r", "environment":"fixture",
                  "command":"synthetic fixture", "exitCode":0, "logPath":"test.txt", "logSHA256":self.digest,
                  "recordedAt":"2026-10-03T00:00:00Z"}
        item = {"id":"synthetic-only", "expectedEnvironment":dict.fromkeys(r.STAGES,"fixture"),
                "reviewer":{"name":"fixture reviewer", "decision":"accepted"}}
        item.update({k:copy.deepcopy(record) for k in r.STAGES})
        self.doc = {"schemaVersion":1,"candidateRevision":"r","capabilities":[item]}
        self.item = self.doc["capabilities"][0]
    def tearDown(self): self.tmp.cleanup()
    def result(self): return r.evaluate(self.doc,self.root,"r")["status"]
    def test_complete_fixture(self): self.assertEqual(self.result(),"EVIDENCE_COMPLETE")
    def test_wrong_global_revision(self):
        self.doc["candidateRevision"]="old"; self.assertEqual(self.result(),"BLOCKED")
    def test_wrong_stage_revision(self):
        self.item["runtime"]["candidateRevision"]="old"; self.assertEqual(self.result(),"BLOCKED")
    def test_missing_log(self):
        self.item["build"]["logPath"]="absent"; self.assertEqual(self.result(),"BLOCKED")
    def test_hash_mismatch(self):
        self.item["build"]["logSHA256"]="0"*64; self.assertEqual(self.result(),"BLOCKED")
    def test_path_escape(self):
        self.item["build"]["logPath"]="../test.txt"; self.assertEqual(self.result(),"BLOCKED")
    def test_absolute(self):
        self.item["build"]["logPath"]=str(self.root/"test.txt"); self.assertEqual(self.result(),"BLOCKED")
    def test_symlink(self):
        (self.root/"link").symlink_to(self.root/"test.txt")
        self.item["build"]["logPath"]="link"; self.assertEqual(self.result(),"BLOCKED")
    def test_environment(self):
        self.item["runtime"]["environment"]="not-a-mac"; self.assertEqual(self.result(),"BLOCKED")
    def test_nonzero(self):
        self.item["build"]["exitCode"]=1; self.assertEqual(self.result(),"BLOCKED")
    def test_boolean_exitcode(self):
        self.item["build"]["exitCode"]=False; self.assertEqual(self.result(),"BLOCKED")
    def test_unexecuted(self):
        self.item["runtime"]["status"]="not-run"; self.assertEqual(self.result(),"BLOCKED")
    def test_failed(self):
        self.item["runtime"]["status"]="failed"; self.assertEqual(self.result(),"BLOCKED")
    def test_missing_reviewer(self):
        self.item.pop("reviewer"); self.assertEqual(self.result(),"BLOCKED")
    def test_duplicates(self):
        self.doc["capabilities"].append(copy.deepcopy(self.item)); self.assertEqual(self.result(),"BLOCKED")
    def test_empty(self):
        self.doc["capabilities"]=[]; self.assertEqual(self.result(),"BLOCKED")
    def test_missing_stage(self):
        self.item.pop("source"); self.assertEqual(self.result(),"BLOCKED")
    def test_tree_revision(self):
        before=r.tree_revision(self.root)
        (self.root/"test.txt").write_text("changed")
        self.assertNotEqual(before,r.tree_revision(self.root))

if __name__ == "__main__": unittest.main(verbosity=2)
