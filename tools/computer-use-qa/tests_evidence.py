#!/usr/bin/env python3
"""evidence.py 与 qa.Run 的离线单元测试（仅标准库，全部使用 mock / 合成数据）。

这些测试不访问网络、SSH 或任何真实产品文件；PNG/事件/归档均为显式合成数据。

运行：
    python3 -m unittest discover -s tools/computer-use-qa -p tests_evidence.py
"""

import hashlib
import json
import pathlib
import shutil
import struct
import tempfile
import time
import unittest
from unittest import mock

import evidence
import qa


# ----------------------------------------------------------------------
# 合成数据构造工具
# ----------------------------------------------------------------------
def _png(width, height):
    """构造最小但签名字节正确的合成 PNG：8 字节签名 + IHDR + 宽高。"""
    ihdr = b"IHDR" + struct.pack(">II", width, height) + b"\x00" * 8
    length = struct.pack(">I", len(ihdr) - 4)  # 仅长度无关紧要，只要 12:16==IHDR
    sig = b"\x89PNG\r\n\x1a\n"
    return sig + length + ihdr + b"\x00" * 16


def _sha256(data):
    return hashlib.sha256(data).hexdigest()


def _write_bytes(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


class Archive:
    """在一个临时目录中组装符合 verify() 契约的合成证据归档。"""

    def __init__(self, root, created=None):
        self.root = pathlib.Path(root)
        self.root.mkdir(parents=True, exist_ok=True)
        (self.root / "events").mkdir(exist_ok=True)
        self.run_id = "run-synthetic-1"
        self.created = created if created is not None else time.time()
        self.target = {"pid": 4242, "window_id": 7}
        self.baseline = {
            "pid": 4242, "window_id": 7, "title": "QA-doc",
            "frame": {"x": 10, "y": 20, "w": 800, "h": 600},
            "text": "WindowShade isolated QA",
        }
        self.meta = {
            "schema": 1,
            "run_id": self.run_id,
            "created": self.created,
            "session": "qa-" + self.run_id,
            "build": {"source": "candidate", "binary_sha256": "0" * 64,
                      "source_commit": "deadbeef",
                      "mapping": "unverified"},
            "target": self.target,
            "baseline": self.baseline,
        }
        self._write_json(self.root / "run.json", self.meta)

    # -- 底层写入 ---------------------------------------------------
    def _write_json(self, path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2))

    # -- 事件 -------------------------------------------------------
    def event(self, label, kind, ok=True, start=None, end=None,
              files=None, target=None, extra=None):
        """写入一个事件目录并登记文件哈希。

        files 为 {stem: bytes}; 返回值是可直接放进 review 引用的 label。
        """
        d = self.root / "events" / label
        d.mkdir(parents=True, exist_ok=True)
        if files is None:
            files = {"response": b"{}"}
        registered = {}
        for stem, data in files.items():
            fp = d / (stem + ".bin")
            _write_bytes(fp, data)
            registered[stem] = {"path": str(fp.relative_to(self.root)),
                                "sha256": _sha256(data)}
        start = self.created + 1 if start is None else start
        end = start + 1 if end is None else end
        event = {
            "run_id": self.run_id,
            "label": label,
            "kind": kind,
            "start": start,
            "end": end,
            "ok": ok,
            "target": self.target if target is None else target,
            "files": registered,
        }
        if extra:
            event.update(extra)
        self._write_json(d / "event.json", event)
        return label

    def capture(self, label, capture_id=None, width=1280, height=800,
                start=None, end=None, ok=True, target=None, png=None,
                remote_png=None, run_id=None, desktop_payload_extra=None):
        """写入一个成功的 capture 事件，返回 label。"""
        remote = remote_png if remote_png else "/guest/" + label + ".png"
        payload = {
            "capture_id": capture_id if capture_id is not None else "cap-" + label,
            "screenshot_width": width,
            "screenshot_height": height,
            "screenshot_file_path": remote,
        }
        if desktop_payload_extra:
            payload.update(desktop_payload_extra)
        desktop = json.dumps({"ok": True, "payload": payload}).encode()
        png_bytes = png if png is not None else _png(width, height)
        ax = json.dumps({"ok": True, "payload": self._ax_payload()}).encode()
        label_out = self.event(
            label, "capture", ok=ok, start=start, end=end, target=target,
            files={"desktop": desktop, "png": png_bytes, "ax": ax},
            extra={"remote_png": remote})
        if run_id is not None:
            # 改写 run_id 以模拟 stale run。
            p = self.root / "events" / label / "event.json"
            e = json.loads(p.read_text())
            e["run_id"] = run_id
            self._write_json(p, e)
        return label_out

    def _ax_payload(self):
        return {
            "pid": self.baseline["pid"],
            "window_id": self.baseline["window_id"],
            "window_title": self.baseline["title"],
            "elements": [
                {"role": "AXWindow", "frame": self.baseline["frame"]},
                {"role": "AXTextArea", "value": self.baseline["text"]},
            ],
        }

    def dead_capture(self, label, start=None, end=None):
        """写入一个 ok=False 的 capture 事件。"""
        return self.event(label, "capture", ok=False, start=start, end=end)

    def refused(self, label, start=None, end=None):
        return self.event(label, "refused", ok=False, start=start, end=end)

    def cleanup(self, status="pass", name=None):
        name = name or ("cleanup-%d.json" % time.time_ns())
        self._write_json(self.root / name, {"status": status, "at": time.time()})
        return name

    # -- review 构造 -------------------------------------------------
    def attempt(self, scenario, status="pass", before=None, after=None,
                checks=None, reason="reviewed"):
        keys = evidence.SCENARIOS[scenario]
        if checks is None:
            checks = {k: {"status": "pass", "evidence": [before, after],
                          "reason": "ok"} for k in keys}
        return {
            "scenario": scenario, "status": status,
            "before": before or "", "after": after or "",
            "reason": reason, "checks": checks,
        }

    def review(self, attempts, reviewer="Alice Reviewer"):
        return {"reviewer": reviewer, "attempts": attempts}

    # -- 全量通过归档（用于 all_passed 门槛测试） --------------------
    def full_pass_archive(self, cleanup_status="pass"):
        """构造 8 个场景全部可判 pass、cleanup 可控的合成归档。

        返回可传给 verify() 的 review。失败/拒绝事件排在所有正常场景之后，
        因此不会触发普通场景的 “earlier session/observation failure”。
        """
        t = self.created
        cid = [0]

        def nxt():
            cid[0] += 1
            return "cap-%d" % cid[0]

        def distinct(label, gap=10):
            return self.capture(label, capture_id=nxt(), png=_png(1280, 800) + label.encode(),
                                start=t + gap, end=t + gap + 1)

        def plain(label, gap):
            return self.capture(label, capture_id=nxt(), start=t + gap,
                                end=t + gap + 1)

        attempts = []
        cursor = 1

        def add(scenario, before, after):
            keys = evidence.SCENARIOS[scenario]
            checks = {k: {"status": "pass", "evidence": [before], "reason": "ok"}
                      for k in keys}
            attempts.append({"scenario": scenario, "status": "pass",
                             "before": before, "after": after, "reason": "ok", "measurements": {"counter_before": 1, "counter_after": 2},
                             "checks": checks})

        for scenario in ("fold-companion", "fold-solo", "peek-static",
                        "peek-cancel"):
            b = plain("%s-b" % scenario, cursor)
            a = plain("%s-a" % scenario, cursor + 3)
            cursor += 10
            add(scenario, b, a)

        lb = distinct("peek-live-b", cursor)
        la = distinct("peek-live-a", cursor + 3)
        cursor += 10
        add("peek-live", lb, la)

        tb = plain("target-change-b", cursor)
        ta = plain("target-change-a", cursor + 3)
        cursor += 10
        add("target-change", tb, ta)

        # restore：after 需携带与 baseline 完全一致的 ax。
        rb = plain("restore-b", cursor)
        ra = self._restore_after_event("restore-a", cursor + 3)
        cursor += 10
        add("restore", rb, ra)

        # observation-failure：放在最后，含真实失败与拒绝记录。
        ob = plain("obs-b", cursor)
        self.dead_capture("obs-dead", start=t + cursor + 3, end=t + cursor + 4)
        self.refused("obs-refused", start=t + cursor + 5, end=t + cursor + 6)
        oa = plain("obs-a", cursor + 7)
        add("observation-failure", ob, oa)

        self.cleanup(cleanup_status, name="cleanup-1.json")
        return self.review(attempts)

    def _restore_after_event(self, label, gap):
        """写入带 baseline ax 的 capture 事件。"""
        d = self.root / "events" / label
        d.mkdir(parents=True, exist_ok=True)
        ax_bytes = json.dumps({"ok": True, "payload": self._ax_payload()}).encode()
        png_bytes = _png(1280, 800) + label.encode()
        desktop = json.dumps({"ok": True, "payload": {
            "capture_id": "cap-" + label, "screenshot_width": 1280,
            "screenshot_height": 800,
            "screenshot_file_path": "/guest/%s.png" % label}}).encode()
        registered = {}
        for stem, data in (("ax", ax_bytes), ("png", png_bytes),
                           ("desktop", desktop)):
            fp = d / (stem + ".bin")
            _write_bytes(fp, data)
            registered[stem] = {"path": str(fp.relative_to(self.root)),
                                "sha256": _sha256(data)}
        event = {"run_id": self.run_id, "label": label, "kind": "capture",
                 "start": self.created + gap, "end": self.created + gap + 1,
                 "ok": True, "target": self.target, "files": registered,
                 "remote_png": "/guest/%s.png" % label}
        self._write_json(d / "event.json", event)
        return label


def _by_scenario(result):
    return {r["scenario"]: r for r in result["results"]}


class EvidenceTestBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.root = pathlib.Path(self.tmp) / "run-1"
        self.root.mkdir(parents=True, exist_ok=True)
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def verify(self, review):
        return evidence.verify(self.root, review)


# ----------------------------------------------------------------------
# 基础契约
# ----------------------------------------------------------------------
class DigestAndFileTests(EvidenceTestBase):
    def test_digest_matches_sha256(self):
        p = self.root / "f.bin"
        _write_bytes(p, b"hello")
        self.assertEqual(evidence.digest(p), hashlib.sha256(b"hello").hexdigest())

    def test_write_is_exclusive(self):
        p = self.root / "x.json"
        evidence.write(p, {"a": 1})
        with self.assertRaises(FileExistsError):
            evidence.write(p, {"a": 2})

    def test_checked_file_rejects_missing(self):
        with self.assertRaises(ValueError):
            evidence.checked_file(self.root, {"path": "nope", "sha256": "0"})

    def test_checked_file_rejects_tampered_hash(self):
        p = self.root / "f.bin"
        _write_bytes(p, b"hello")
        with self.assertRaises(ValueError):
            evidence.checked_file(self.root, {"path": "f.bin", "sha256": "0" * 64})

    def test_checked_file_rejects_escape(self):
        with self.assertRaises(ValueError):
            evidence.checked_file(self.root, {"path": "../escape", "sha256": "0"})


# ----------------------------------------------------------------------
# verify(): pass 的必要条件
# ----------------------------------------------------------------------
class VerifyPassTests(EvidenceTestBase):
    def _passing_archive(self):
        a = Archive(self.root)
        a.capture("peek-static-before", capture_id="c1",
                  start=a.created + 1, end=a.created + 2)
        a.capture("peek-static-after", capture_id="c2",
                  start=a.created + 10, end=a.created + 11)
        a.cleanup("pass")
        return a

    def test_valid_pass_requires_reviewer_checks_and_ordered_events(self):
        a = self._passing_archive()
        review = a.review([a.attempt("peek-static", "pass",
                                     before="peek-static-before",
                                     after="peek-static-after")])
        result = self.verify(review)
        row = _by_scenario(result)["peek-static"]
        self.assertEqual(row["status"], "pass", row["issues"])
        # 未提交其他场景时，all_passed 必须为 False（not_run 仍计入）。
        self.assertFalse(result["all_passed"])

    def test_full_pass_archive_sets_all_passed(self):
        a = Archive(self.root)
        review = a.full_pass_archive(cleanup_status="pass")
        result = self.verify(review)
        self.assertEqual(result["evidence_errors"], [])
        bad = [r for r in result["results"] if r["status"] != "pass"]
        self.assertEqual(bad, [], bad)
        self.assertTrue(result["all_passed"])

    def test_missing_reviewer_cannot_pass(self):
        a = self._passing_archive()
        review = a.review([a.attempt("peek-static", "pass",
                                     before="peek-static-before",
                                     after="peek-static-after")],
                          reviewer="   ")
        result = self.verify(review)
        row = _by_scenario(result)["peek-static"]
        self.assertEqual(row["status"], "inconclusive")
        self.assertIn("missing visual reviewer", row["issues"])
        self.assertFalse(result["all_passed"])

    def test_missing_required_check_cannot_pass(self):
        a = self._passing_archive()
        checks = {"content_matches": {"status": "pass",
                                      "evidence": ["peek-static-before"],
                                      "reason": "ok"}}
        review = a.review([a.attempt("peek-static", "pass",
                                     before="peek-static-before",
                                     after="peek-static-after",
                                     checks=checks)])
        result = self.verify(review)
        row = _by_scenario(result)["peek-static"]
        self.assertEqual(row["status"], "inconclusive")
        self.assertTrue(any("snapshot_label" in i for i in row["issues"]))

    def test_check_without_evidence_cannot_pass(self):
        a = self._passing_archive()
        checks = {k: {"status": "pass", "evidence": [], "reason": "ok"}
                  for k in evidence.SCENARIOS["peek-static"]}
        review = a.review([a.attempt("peek-static", "pass",
                                     before="peek-static-before",
                                     after="peek-static-after",
                                     checks=checks)])
        result = self.verify(review)
        self.assertEqual(_by_scenario(result)["peek-static"]["status"],
                         "inconclusive")

    def test_unknown_evidence_reference_cannot_pass(self):
        a = self._passing_archive()
        checks = {k: {"status": "pass", "evidence": ["ghost-event"],
                      "reason": "ok"}
                  for k in evidence.SCENARIOS["peek-static"]}
        review = a.review([a.attempt("peek-static", "pass",
                                     before="peek-static-before",
                                     after="peek-static-after",
                                     checks=checks)])
        result = self.verify(review)
        row = _by_scenario(result)["peek-static"]
        self.assertEqual(row["status"], "inconclusive")
        self.assertTrue(any("unknown evidence reference" in i
                            for i in row["issues"]))

    def test_not_run_omission_is_retained(self):
        a = self._passing_archive()
        review = a.review([a.attempt("peek-static", "pass",
                                     before="peek-static-before",
                                     after="peek-static-after")])
        result = self.verify(review)
        missing = [r for r in result["results"]
                   if r["scenario"] == "restore"]
        self.assertEqual(len(missing), 1)
        self.assertEqual(missing[0]["status"], "not_run")
        self.assertFalse(result["all_passed"])

    def test_missing_file_cannot_pass(self):
        a = self._passing_archive()
        # 删除被引用文件，但保留事件与 review。
        (self.root / "events" / "peek-static-before" / "png.bin").unlink()
        review = a.review([a.attempt("peek-static", "pass",
                                     before="peek-static-before",
                                     after="peek-static-after")])
        result = self.verify(review)
        self.assertTrue(result["evidence_errors"])
        self.assertEqual(_by_scenario(result)["peek-static"]["status"],
                         "inconclusive")
        self.assertFalse(result["all_passed"])

    def test_hash_tamper_cannot_pass(self):
        a = self._passing_archive()
        # 篡改字节但不更新记录的哈希。
        (self.root / "events" / "peek-static-after" / "png.bin").write_bytes(
            _png(1280, 800) + b"tampered")
        review = a.review([a.attempt("peek-static", "pass",
                                     before="peek-static-before",
                                     after="peek-static-after")])
        result = self.verify(review)
        self.assertTrue(result["evidence_errors"])
        self.assertFalse(result["all_passed"])

    def test_stale_run_cannot_pass(self):
        a = Archive(self.root)
        a.capture("good", capture_id="c1", start=a.created + 1, end=a.created + 2)
        a.capture("stale", capture_id="c2", start=a.created + 5, end=a.created + 6,
                  run_id="different-run")
        a.cleanup("pass")
        review = a.review([a.attempt("peek-static", "pass",
                                     before="good", after="stale")])
        result = self.verify(review)
        self.assertTrue(result["evidence_errors"])
        self.assertEqual(_by_scenario(result)["peek-static"]["status"],
                         "inconclusive")

    def test_reused_capture_id_cannot_pass(self):
        a = Archive(self.root)
        a.capture("b1", capture_id="SAME", start=a.created + 1, end=a.created + 2)
        a.capture("b2", capture_id="SAME", start=a.created + 5, end=a.created + 6)
        a.cleanup("pass")
        review = a.review([a.attempt("peek-static", "pass",
                                     before="b1", after="b2")])
        result = self.verify(review)
        self.assertTrue(any("reused capture" in e or "capture identity" in e
                            for e in result["evidence_errors"]),
                        result["evidence_errors"])
        self.assertFalse(result["all_passed"])

    def test_dimensions_mismatch_cannot_pass(self):
        a = Archive(self.root)
        # desktop 声明 1280x800，但 PNG 实际 640x480
        a.capture("b1", capture_id="c1", width=1280, height=800,
                  png=_png(640, 480), start=a.created + 1, end=a.created + 2)
        a.capture("b2", capture_id="c2", start=a.created + 5, end=a.created + 6)
        a.cleanup("pass")
        review = a.review([a.attempt("peek-static", "pass",
                                     before="b1", after="b2")])
        result = self.verify(review)
        self.assertTrue(result["evidence_errors"])
        self.assertFalse(result["all_passed"])

    def test_capture_source_disagreement_cannot_pass(self):
        a = Archive(self.root)
        a.capture("b1", capture_id="c1", remote_png="/guest/b1.png",
                  desktop_payload_extra={"screenshot_file_path": "/other.png"},
                  start=a.created + 1, end=a.created + 2)
        a.capture("b2", capture_id="c2", start=a.created + 5, end=a.created + 6)
        a.cleanup("pass")
        review = a.review([a.attempt("peek-static", "pass",
                                     before="b1", after="b2")])
        result = self.verify(review)
        self.assertTrue(result["evidence_errors"])

    def test_unordered_before_after_cannot_pass(self):
        a = Archive(self.root)
        # after 的 start 早于 before 的 end
        a.capture("b1", capture_id="c1", start=a.created + 10, end=a.created + 11)
        a.capture("b2", capture_id="c2", start=a.created + 1, end=a.created + 2)
        a.cleanup("pass")
        review = a.review([a.attempt("peek-static", "pass",
                                     before="b1", after="b2")])
        result = self.verify(review)
        row = _by_scenario(result)["peek-static"]
        self.assertEqual(row["status"], "inconclusive")
        self.assertIn("missing or unordered before/after observations",
                      row["issues"])

    def test_missing_observation_cannot_pass(self):
        a = Archive(self.root)
        a.capture("b1", capture_id="c1", start=a.created + 1, end=a.created + 2)
        a.cleanup("pass")
        review = a.review([a.attempt("peek-static", "pass",
                                     before="b1", after="nonexistent")])
        result = self.verify(review)
        self.assertEqual(_by_scenario(result)["peek-static"]["status"],
                         "inconclusive")

    def test_target_mismatch_cannot_pass(self):
        a = Archive(self.root)
        a.capture("b1", capture_id="c1", start=a.created + 1, end=a.created + 2,
                  target={"pid": 9999, "window_id": 7})
        a.capture("b2", capture_id="c2", start=a.created + 5, end=a.created + 6)
        a.cleanup("pass")
        review = a.review([a.attempt("peek-static", "pass",
                                     before="b1", after="b2")])
        result = self.verify(review)
        row = _by_scenario(result)["peek-static"]
        self.assertEqual(row["status"], "inconclusive")
        self.assertIn("target identity mismatch", row["issues"])

    def test_failed_check_with_attempted_pass_cannot_pass(self):
        a = self._passing_archive()
        checks = {k: {"status": "pass", "evidence": ["peek-static-before"],
                      "reason": "ok"} for k in evidence.SCENARIOS["peek-static"]}
        checks["content_matches"]["status"] = "fail"
        review = a.review([a.attempt("peek-static", "pass",
                                     before="peek-static-before",
                                     after="peek-static-after",
                                     checks=checks)])
        result = self.verify(review)
        row = _by_scenario(result)["peek-static"]
        self.assertEqual(row["status"], "inconclusive")
        self.assertTrue(any("content_matches" in i for i in row["issues"]))

    def test_pass_without_reason_cannot_pass(self):
        a = self._passing_archive()
        att = a.attempt("peek-static", "pass",
                        before="peek-static-before",
                        after="peek-static-after")
        att["reason"] = "   "
        review = a.review([att])
        result = self.verify(review)
        row = _by_scenario(result)["peek-static"]
        self.assertIn("missing explanation", row["issues"])

    def test_unknown_scenario_or_status_rejected(self):
        a = self._passing_archive()
        bad = a.attempt("peek-static", "pass",
                        before="peek-static-before",
                        after="peek-static-after")
        bad["scenario"] = "made-up"
        bad["status"] = "totally_fine"
        review = a.review([bad])
        result = self.verify(review)
        row = [r for r in result["results"] if r["scenario"] == "made-up"][0]
        self.assertIn("unknown scenario or status", row["issues"])


# ----------------------------------------------------------------------
# 场景专属证据规则
# ----------------------------------------------------------------------
class RestoreScenarioTests(EvidenceTestBase):
    def _restore(self, ax_payload=None, png_data=None):
        a = Archive(self.root)
        ax = ax_payload if ax_payload is not None else a._ax_payload()
        a.capture("restore-before", capture_id="c-before",
                  start=a.created + 1, end=a.created + 2)
        # after 需要包含 ax 文件用于投影比对。
        d = self.root / "events" / "restore-after"
        d.mkdir(parents=True, exist_ok=True)
        ax_bytes = json.dumps({"ok": True, "payload": ax}).encode()
        png_bytes = png_data if png_data is not None else _png(1280, 800)
        desktop = json.dumps({"ok": True, "payload": {
            "capture_id": "c-after", "screenshot_width": 1280,
            "screenshot_height": 800,
            "screenshot_file_path": "/guest/restore-after.png"}}).encode()
        files = {"ax": ax_bytes, "png": png_bytes, "desktop": desktop}
        registered = {}
        for stem, data in files.items():
            fp = d / (stem + ".bin")
            _write_bytes(fp, data)
            registered[stem] = {"path": str(fp.relative_to(self.root)),
                                "sha256": _sha256(data)}
        event = {"run_id": a.run_id, "label": "restore-after", "kind": "capture",
                 "start": a.created + 5, "end": a.created + 6, "ok": True,
                 "target": a.target, "files": registered,
                 "remote_png": "/guest/restore-after.png"}
        a._write_json(d / "event.json", event)
        return a

    def _review(self, before="restore-before", after="restore-after"):
        keys = evidence.SCENARIOS["restore"]
        checks = {k: {"status": "pass", "evidence": [before], "reason": "ok"}
                  for k in keys}
        return {"reviewer": "R",
                "attempts": [{"scenario": "restore", "status": "pass",
                              "before": before, "after": after,
                              "reason": "ok", "checks": checks}]}

    def test_restore_matching_baseline_passes(self):
        a = self._restore()
        a.cleanup("pass")
        result = self.verify(self._review())
        self.assertEqual(_by_scenario(result)["restore"]["status"], "pass")

    def test_restore_geometry_mismatch_cannot_pass(self):
        a = Archive(self.root)
        ax = a._ax_payload()
        ax["elements"][0]["frame"] = {"x": 999, "y": 999, "w": 1, "h": 1}
        a = self._restore_with_root(a, ax)
        a.cleanup("pass")
        result = self.verify(self._review())
        self.assertEqual(_by_scenario(result)["restore"]["status"],
                         "inconclusive")

    def test_restore_text_mismatch_cannot_pass(self):
        a = Archive(self.root)
        ax = a._ax_payload()
        ax["elements"][1]["value"] = "different text"
        a = self._restore_with_root(a, ax)
        a.cleanup("pass")
        result = self.verify(self._review())
        row = _by_scenario(result)["restore"]
        self.assertEqual(row["status"], "inconclusive")
        self.assertIn("AX geometry/content/identity differs from baseline",
                      " ".join(row["issues"]))

    def _restore_with_root(self, a, ax_payload):
        a.capture("restore-before", capture_id="c-before",
                  start=a.created + 1, end=a.created + 2)
        d = self.root / "events" / "restore-after"
        d.mkdir(parents=True, exist_ok=True)
        ax_bytes = json.dumps({"ok": True, "payload": ax_payload}).encode()
        png_bytes = _png(1280, 800)
        desktop = json.dumps({"ok": True, "payload": {
            "capture_id": "c-after", "screenshot_width": 1280,
            "screenshot_height": 800,
            "screenshot_file_path": "/guest/restore-after.png"}}).encode()
        files = {"ax": ax_bytes, "png": png_bytes, "desktop": desktop}
        registered = {}
        for stem, data in files.items():
            fp = d / (stem + ".bin")
            _write_bytes(fp, data)
            registered[stem] = {"path": str(fp.relative_to(self.root)),
                                "sha256": _sha256(data)}
        event = {"run_id": a.run_id, "label": "restore-after", "kind": "capture",
                 "start": a.created + 5, "end": a.created + 6, "ok": True,
                 "target": a.target, "files": registered,
                 "remote_png": "/guest/restore-after.png"}
        a._write_json(d / "event.json", event)
        return a


class PeekLiveTests(EvidenceTestBase):
    def _archive(self, same_bytes):
        a = Archive(self.root)
        png = _png(1280, 800)
        after_png = png if same_bytes else _png(1280, 800) + b"\x01"
        a.capture("live-before", capture_id="c1", png=png,
                  start=a.created + 1, end=a.created + 2)
        a.capture("live-after", capture_id="c2", png=after_png,
                  start=a.created + 5, end=a.created + 6)
        a.cleanup("pass")
        return a

    def test_identical_image_bytes_cannot_prove_live(self):
        a = self._archive(same_bytes=True)
        keys = evidence.SCENARIOS["peek-live"]
        checks = {k: {"status": "pass", "evidence": ["live-before"], "reason": "ok"}
                  for k in keys}
        review = {"reviewer": "R", "attempts": [{
            "scenario": "peek-live", "status": "pass", "measurements": {"counter_before": 1, "counter_after": 2}, "before": "live-before",
            "after": "live-after", "reason": "ok", "checks": checks}]}
        result = self.verify(review)
        row = _by_scenario(result)["peek-live"]
        self.assertEqual(row["status"], "inconclusive")
        self.assertIn("same image cannot establish live preview",
                      " ".join(row["issues"]))

    def test_distinct_image_bytes_can_pass(self):
        a = self._archive(same_bytes=False)
        keys = evidence.SCENARIOS["peek-live"]
        checks = {k: {"status": "pass", "evidence": ["live-before"], "reason": "ok"}
                  for k in keys}
        review = {"reviewer": "R", "attempts": [{
            "scenario": "peek-live", "status": "pass", "measurements": {"counter_before": 1, "counter_after": 2}, "before": "live-before",
            "after": "live-after", "reason": "ok", "checks": checks}]}
        result = self.verify(review)
        self.assertEqual(_by_scenario(result)["peek-live"]["status"], "pass")


class ObservationFailureTests(EvidenceTestBase):
    def _archive(self):
        a = Archive(self.root)
        a.capture("obs-before", capture_id="c1", start=a.created + 1,
                  end=a.created + 2)
        a.dead_capture("obs-bad", start=a.created + 3, end=a.created + 4)
        a.refused("obs-refused", start=a.created + 5, end=a.created + 6)
        a.capture("obs-after", capture_id="c2", start=a.created + 7,
                  end=a.created + 8)
        a.cleanup("pass")
        return a

    def _review(self):
        keys = evidence.SCENARIOS["observation-failure"]
        checks = {k: {"status": "pass", "evidence": ["obs-refused"],
                      "reason": "ok"} for k in keys}
        return {"reviewer": "R", "attempts": [{
            "scenario": "observation-failure", "status": "pass",
            "before": "obs-before", "after": "obs-after", "reason": "ok",
            "checks": checks}]}

    def test_observation_failure_with_real_failure_and_refusal_passes(self):
        a = self._archive()
        result = self.verify(self._review())
        self.assertEqual(_by_scenario(result)["observation-failure"]["status"],
                         "pass")

    def test_missing_failure_record_cannot_pass(self):
        a = Archive(self.root)
        a.capture("obs-before", capture_id="c1", start=a.created + 1,
                  end=a.created + 2)
        a.capture("obs-after", capture_id="c2", start=a.created + 7,
                  end=a.created + 8)
        a.cleanup("pass")
        result = self.verify(self._review())
        row = _by_scenario(result)["observation-failure"]
        self.assertEqual(row["status"], "inconclusive")
        self.assertIn("missing real failure and refusal records",
                      " ".join(row["issues"]))

    def test_missing_refusal_record_cannot_pass(self):
        a = Archive(self.root)
        a.capture("obs-before", capture_id="c1", start=a.created + 1,
                  end=a.created + 2)
        a.dead_capture("obs-bad", start=a.created + 3, end=a.created + 4)
        a.capture("obs-after", capture_id="c2", start=a.created + 7,
                  end=a.created + 8)
        a.cleanup("pass")
        result = self.verify(self._review())
        self.assertEqual(_by_scenario(result)["observation-failure"]["status"],
                         "inconclusive")

    def test_earlier_fault_cannot_pass_normal_scenario(self):
        a = Archive(self.root)
        # 正常场景：但会话中存在一次早先失败事件。
        a.capture("ps-before", capture_id="c1", start=a.created + 1,
                  end=a.created + 2)
        a.dead_capture("early-hiccup", start=a.created + 3, end=a.created + 4)
        a.capture("ps-after", capture_id="c2", start=a.created + 5,
                  end=a.created + 6)
        a.cleanup("pass")
        keys = evidence.SCENARIOS["peek-static"]
        checks = {k: {"status": "pass", "evidence": ["ps-before"], "reason": "ok"}
                  for k in keys}
        review = {"reviewer": "R", "attempts": [{
            "scenario": "peek-static", "status": "pass", "before": "ps-before",
            "after": "ps-after", "reason": "ok", "checks": checks}]}
        result = self.verify(review)
        row = _by_scenario(result)["peek-static"]
        self.assertEqual(row["status"], "inconclusive")
        self.assertIn("earlier session/observation failure; use a fresh run",
                      " ".join(row["issues"]))


class FailRetentionTests(EvidenceTestBase):
    def test_fail_first_attempt_not_erased_by_later_pass(self):
        a = Archive(self.root)
        a.capture("ps-before", capture_id="c1", start=a.created + 1,
                  end=a.created + 2)
        a.capture("ps-after", capture_id="c2", start=a.created + 5,
                  end=a.created + 6)
        a.cleanup("pass")
        keys = evidence.SCENARIOS["peek-static"]
        checks = {k: {"status": "pass", "evidence": ["ps-before"], "reason": "ok"}
                  for k in keys}
        failing = {"scenario": "peek-static", "status": "fail",
                   "before": "ps-before", "after": "ps-after",
                   "reason": "first attempt failed", "checks": checks}
        passing = {"scenario": "peek-static", "status": "pass",
                   "before": "ps-before", "after": "ps-after",
                   "reason": "retried", "checks": checks}
        review = {"reviewer": "R", "attempts": [failing, passing]}
        result = self.verify(review)
        rows = [r for r in result["results"] if r["scenario"] == "peek-static"]
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["requested"], "fail")
        self.assertEqual(rows[0]["status"], "fail")
        self.assertEqual(rows[1]["status"], "pass")
        self.assertFalse(result["all_passed"])


class CleanupTests(EvidenceTestBase):
    def test_cleanup_absent_blocks_all_passed(self):
        a = Archive(self.root)
        review = a.full_pass_archive(cleanup_status="pass")
        # 删除 cleanup 记录以模拟“无清理证据”。
        for p in self.root.glob("cleanup-*.json"):
            p.unlink()
        result = self.verify(review)
        self.assertEqual(result["cleanup"]["status"], "not_run")
        self.assertFalse(result["all_passed"])

    def test_cleanup_fail_blocks_all_passed(self):
        a = Archive(self.root)
        review = a.full_pass_archive(cleanup_status="blocked")
        result = self.verify(review)
        self.assertEqual(result["cleanup"]["status"], "blocked")
        self.assertFalse(result["all_passed"])

    def test_cleanup_pass_with_full_pass_allows_all_passed(self):
        a = Archive(self.root)
        review = a.full_pass_archive(cleanup_status="pass")
        result = self.verify(review)
        self.assertEqual(result["cleanup"]["status"], "pass")
        self.assertTrue(result["all_passed"])

    def test_latest_cleanup_record_wins(self):
        a = Archive(self.root)
        review = a.full_pass_archive(cleanup_status="blocked")
        a.cleanup("pass", name="cleanup-2.json")
        result = self.verify(review)
        # sorted() 顺序：cleanup-1 在前，cleanup-2 在后 -> 取最后一个。
        self.assertEqual(result["cleanup"]["status"], "pass")
        self.assertTrue(result["all_passed"])


# ----------------------------------------------------------------------
# Run.act：halted / closed 的输入拒绝
# ----------------------------------------------------------------------
class RunActTests(EvidenceTestBase):
    def _run_root(self):
        """构造一个 Run 可加载的最小 run 目录。"""
        root = pathlib.Path(self.tmp) / "run-act"
        root.mkdir(parents=True, exist_ok=True)
        (root / "events").mkdir(exist_ok=True)
        cfg = {
            "ssh_host": "user@192.0.2.10",
            "ssh_control": None,
            "driver_path": "/opt/cua/CuaDriver",
            "timeout_seconds": 45,
        }
        meta = {
            "schema": 1, "run_id": "run-act-1", "created": time.time(),
            "session": "s", "config": cfg,
            "target": {"pid": 1, "window_id": 2},
            "guest_dir": "/guest/run-act-1",
        }
        (root / "run.json").write_text(json.dumps(meta))
        return root

    def _patch_transport(self, run, call_mock):
        run.t = mock.Mock()
        run.t.call = call_mock
        run.t.fetch = mock.Mock()
        return run

    def test_act_halted_never_calls_transport(self):
        root = self._run_root()
        run = qa.Run(root)
        call = mock.Mock()
        self._patch_transport(run, call)
        run.halt("previous failure")
        # act 在 halted 时应拒绝且不调用 Transport.call。
        event = run.act("act-halted", "click", {"x": 1, "y": 2}, "none")
        self.assertFalse(event["ok"])
        self.assertEqual(event["kind"], "refused")
        call.assert_not_called()

    def test_act_closed_never_calls_transport(self):
        root = self._run_root()
        run = qa.Run(root)
        call = mock.Mock()
        self._patch_transport(run, call)
        (root / "CLOSED.json").write_text(json.dumps({"at": time.time()}))
        event = run.act("act-closed", "click", {"x": 1, "y": 2}, "none")
        self.assertFalse(event["ok"])
        self.assertEqual(event["kind"], "refused")
        call.assert_not_called()
        self.assertIn("halted or closed", event.get("reason", ""))

    def test_act_disallowed_tool_never_calls_transport(self):
        root = self._run_root()
        run = qa.Run(root)
        call = mock.Mock()
        self._patch_transport(run, call)
        event = run.act("act-bad-tool", "format_disk", {}, "none")
        self.assertFalse(event["ok"])
        self.assertEqual(event["kind"], "refused")
        call.assert_not_called()

    def test_act_with_valid_basis_calls_transport(self):
        root = self._run_root()
        run = qa.Run(root)
        # 构造一个成功的 capture 事件作为 basis。
        cap_dir = root / "events" / "basis"
        cap_dir.mkdir(parents=True)
        desktop = json.dumps({"ok": True, "payload": {
            "capture_id": "cap-basis", "screenshot_width": 1280,
            "screenshot_height": 800, "screenshot_file_path": "/g/b.png"}}).encode()
        (cap_dir / "desktop.bin").write_bytes(desktop)
        (cap_dir / "ax.bin").write_bytes(b"{}")
        (cap_dir / "png.bin").write_bytes(_png(1280, 800))
        reg = {}
        for stem in ("desktop", "ax", "png"):
            fp = cap_dir / (stem + ".bin")
            reg[stem] = {"path": str(fp.relative_to(root)),
                         "sha256": _sha256(fp.read_bytes())}
        now = time.time()
        (cap_dir / "event.json").write_text(json.dumps({
            "run_id": "run-act-1", "label": "basis", "kind": "capture",
            "start": now - 5, "end": now - 4, "ok": True,
            "target": {"pid": 1, "window_id": 2}, "files": reg,
            "remote_png": "/g/b.png"}))
        call = mock.Mock(return_value={"ok": True, "payload": {}, "raw": {}})
        self._patch_transport(run, call)
        with mock.patch.object(run, "capture", return_value={"ok": True}) as capture:
            event = run.act("act-ok", "click",
                            {"x": 10, "y": 20, "scope": "desktop"}, "basis")
        self.assertTrue(event["ok"])
        capture.assert_called_once_with("act-ok-after")
        call.assert_called()
        # 首次调用应是目标动作。
        self.assertEqual(call.call_args_list[0][0][0], "click")


if __name__ == "__main__":
    unittest.main()

