#!/usr/bin/env python3
"""transport.py 的离线单元测试（仅标准库，全部使用 mock）。

运行：
    python3 -m unittest discover -s tools/computer-use-qa -p tests_transport.py
"""

import json
import os
import shlex
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

import transport

shlex_join = shlex.join


def _cfg(**overrides):
    base = {
        "ssh_host": "user@192.0.2.10",
        "ssh_control": "/tmp/wsqa-control",
        "driver_path": "/opt/cua/CuaDriver",
        "timeout_seconds": 45,
    }
    base.update(overrides)
    return base


def _completed(returncode=0, stdout="", stderr=""):
    return subprocess.CompletedProcess(
        args=["ssh"], returncode=returncode, stdout=stdout, stderr=stderr)


class ConfigTests(unittest.TestCase):
    def test_accepts_valid_config(self):
        t = transport.Transport(_cfg())
        self.assertEqual(t.ssh_host, "user@192.0.2.10")
        self.assertEqual(t.driver_path, "/opt/cua/CuaDriver")

    def test_default_timeout_is_45(self):
        cfg = _cfg()
        del cfg["timeout_seconds"]
        self.assertEqual(transport.Transport(cfg).timeout_seconds, 45)

    def test_rejects_host_starting_with_dash(self):
        with self.assertRaises(transport.TransportError):
            transport.Transport(_cfg(ssh_host="-oProxyCommand=evil"))

    def test_rejects_host_with_whitespace(self):
        with self.assertRaises(transport.TransportError):
            transport.Transport(_cfg(ssh_host="host name"))
        with self.assertRaises(transport.TransportError):
            transport.Transport(_cfg(ssh_host="host\ttab"))

    def test_rejects_relative_driver_path(self):
        with self.assertRaises(transport.TransportError):
            transport.Transport(_cfg(driver_path="bin/driver"))

    def test_rejects_non_dict_config(self):
        with self.assertRaises(transport.TransportError):
            transport.Transport(["not", "a", "dict"])

    def test_rejects_bad_timeout(self):
        with self.assertRaises(transport.TransportError):
            transport.Transport(_cfg(timeout_seconds=0))
        with self.assertRaises(transport.TransportError):
            transport.Transport(_cfg(timeout_seconds="45"))


class RemoteTests(unittest.TestCase):
    def test_uses_native_ssh_with_baseline_flags(self):
        t = transport.Transport(_cfg())
        with mock.patch.object(subprocess, "run",
                               return_value=_completed()) as run:
            t.remote(["echo", "hi"])
        argv = run.call_args[0][0]
        self.assertEqual(argv[0], "ssh")
        self.assertIn("BatchMode=yes", argv)
        self.assertIn("ConnectTimeout=10", argv)
        # "--" 是 ssh 选项终止符，必须位于 host 之前；host 之后仅有一个远端命令元素，
        # 由 ssh 远端解释，不经本地 shell。
        self.assertEqual(argv[argv.index("--") + 1], "user@192.0.2.10")
        self.assertEqual(argv[-2], "user@192.0.2.10")
        self.assertLess(argv.index("--"), argv.index("user@192.0.2.10"))
        self.assertEqual(argv[-1], "echo hi")
        kwargs = run.call_args[1]
        self.assertNotIn("shell", kwargs)
        self.assertTrue(kwargs.get("text"))

    def test_control_socket_included_when_set(self):
        t = transport.Transport(_cfg(ssh_control="/tmp/sock"))
        with mock.patch.object(subprocess, "run",
                               return_value=_completed()) as run:
            t.remote(["true"])
        argv = run.call_args[0][0]
        self.assertIn("-S", argv)
        self.assertEqual(argv[argv.index("-S") + 1], "/tmp/sock")

    def test_control_socket_omitted_when_absent(self):
        t = transport.Transport(_cfg(ssh_control=None))
        with mock.patch.object(subprocess, "run",
                               return_value=_completed()) as run:
            t.remote(["true"])
        self.assertNotIn("-S", run.call_args[0][0])

    def test_quoting_of_remote_args(self):
        t = transport.Transport(_cfg())
        with mock.patch.object(subprocess, "run",
                               return_value=_completed()) as run:
            t.remote(["cat", "file with space", "it's"])
        remote_cmd = run.call_args[0][0][-1]
        self.assertEqual(remote_cmd, shlex_join(["cat", "file with space",
                                                 "it's"]))
        self.assertNotIn("file with space", remote_cmd.split(" "))

    def test_remote_rejects_empty_and_non_str(self):
        t = transport.Transport(_cfg())
        with self.assertRaises(transport.TransportError):
            t.remote([])
        with self.assertRaises(transport.TransportError):
            t.remote(["ok", 5])

    def test_returns_structured_result(self):
        t = transport.Transport(_cfg())
        with mock.patch.object(subprocess, "run",
                               return_value=_completed(1, "out", "err")):
            res = t.remote(["true"])
        self.assertEqual(res["returncode"], 1)
        self.assertEqual(res["stdout"], "out")
        self.assertEqual(res["stderr"], "err")
        self.assertIsNone(res["error"])

    def test_timeout_returns_none_returncode(self):
        t = transport.Transport(_cfg(timeout_seconds=7))
        exc = subprocess.TimeoutExpired(cmd=["ssh"], timeout=7,
                                        output="partial", stderr="boom")
        with mock.patch.object(subprocess, "run", side_effect=exc):
            res = t.remote(["sleep", "99"])
        self.assertIsNone(res["returncode"])
        self.assertEqual(res["stdout"], "partial")
        self.assertEqual(res["stderr"], "boom")
        self.assertIn("timeout", res["error"])
        self.assertIn("7", res["error"])


class CallTests(unittest.TestCase):
    def test_success_parses_payload(self):
        t = transport.Transport(_cfg())
        payload = {"active": True, "session": "s1"}
        with mock.patch.object(subprocess, "run",
                               return_value=_completed(0, json.dumps(payload))):
            res = t.call("start_session", {"session": "s1"})
        self.assertTrue(res["ok"])
        self.assertEqual(res["payload"], payload)
        self.assertEqual(res["raw"]["returncode"], 0)

    def test_driver_call_command_shape(self):
        t = transport.Transport(_cfg())
        with mock.patch.object(subprocess, "run",
                               return_value=_completed(0, "{}")) as run:
            t.call("click", {"x": 1, "y": 2})
        remote_cmd = run.call_args[0][0][-1]
        self.assertEqual(
            remote_cmd,
            shlex_join(["/opt/cua/CuaDriver", "call", "click",
                        json.dumps({"x": 1, "y": 2}, ensure_ascii=False)]))

    def test_nonzero_exit_is_not_ok(self):
        t = transport.Transport(_cfg())
        with mock.patch.object(subprocess, "run",
                               return_value=_completed(1, "{}", "fail")):
            res = t.call("click", {})
        self.assertFalse(res["ok"])
        self.assertIsNone(res["payload"])
        self.assertEqual(res["raw"]["stderr"], "fail")

    def test_timeout_is_not_ok(self):
        t = transport.Transport(_cfg())
        exc = subprocess.TimeoutExpired(cmd=["ssh"], timeout=45)
        with mock.patch.object(subprocess, "run", side_effect=exc):
            res = t.call("click", {})
        self.assertFalse(res["ok"])
        self.assertIsNone(res["raw"]["returncode"])

    def test_malformed_json_is_not_ok(self):
        t = transport.Transport(_cfg())
        with mock.patch.object(subprocess, "run",
                               return_value=_completed(0, "not json {")):
            res = t.call("click", {})
        self.assertFalse(res["ok"])
        self.assertIsNone(res["payload"])

    def test_error_payload_despite_exit_zero(self):
        t = transport.Transport(_cfg())
        for payload in ({"error": "boom"},
                        {"isError": True},
                        {"success": False}):
            with self.subTest(payload=payload):
                with mock.patch.object(
                        subprocess, "run",
                        return_value=_completed(0, json.dumps(payload))):
                    res = t.call("click", {})
                self.assertFalse(res["ok"])
                self.assertEqual(res["payload"], payload)

    def test_non_object_json_is_not_ok(self):
        t = transport.Transport(_cfg())
        with mock.patch.object(subprocess, "run",
                               return_value=_completed(0, "[1, 2, 3]")):
            res = t.call("click", {})
        self.assertFalse(res["ok"])

    def test_rejects_bad_arguments(self):
        t = transport.Transport(_cfg())
        with self.assertRaises(transport.TransportError):
            t.call("", {})
        with self.assertRaises(transport.TransportError):
            t.call("click", ["not", "dict"])


class FetchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _local(self, name="out.bin"):
        return os.path.join(self.tmp, name)

    def test_fetch_uses_ssh_cat_not_scp(self):
        t = transport.Transport(_cfg())
        data = b"\x89PNG\r\n\x1a\nrest"
        with mock.patch.object(subprocess, "run",
                               return_value=_completed(0, data, b"")) as run:
            res = t.fetch("/remote/shot.png", self._local("shot.png"))
        argv = run.call_args[0][0]
        self.assertEqual(argv[0], "ssh")
        self.assertNotIn("scp", argv[0])
        self.assertTrue(argv[-1].startswith("cat -- "))
        self.assertTrue(res["ok"])
        self.assertEqual(res["bytes"], len(data))

    def test_remote_path_is_shlex_quoted(self):
        t = transport.Transport(_cfg())
        with mock.patch.object(subprocess, "run",
                               return_value=_completed(0, b"x", b"")) as run:
            t.fetch("/remote/a b'c.png", self._local())
        remote_cmd = run.call_args[0][0][-1]
        self.assertEqual(remote_cmd, "cat -- " + shlex_join(["/remote/a b'c.png"]))

    def test_writes_binary_bytes_unchanged(self):
        t = transport.Transport(_cfg())
        data = b"\x89PNG\r\n\x1a\n\x00\x01\x02\xff"
        with mock.patch.object(subprocess, "run",
                               return_value=_completed(0, data, b"")):
            res = t.fetch("/r.png", self._local("r.png"))
        with open(res["path"], "rb") as fh:
            self.assertEqual(fh.read(), data)

    def test_exclusive_create_no_clobber(self):
        t = transport.Transport(_cfg())
        local = self._local("keep.bin")
        with open(local, "wb") as fh:
            fh.write(b"original")
        with mock.patch.object(subprocess, "run",
                               return_value=_completed(0, b"new", b"")):
            res = t.fetch("/r.bin", local)
        self.assertFalse(res["ok"])
        self.assertIn("已存在", res["error"])
        with open(local, "rb") as fh:
            self.assertEqual(fh.read(), b"original")

    def test_nonzero_exit_reports_error_without_file(self):
        t = transport.Transport(_cfg())
        local = self._local("missing.png")
        with mock.patch.object(subprocess, "run",
                               return_value=_completed(1, b"", b"no such file")):
            res = t.fetch("/missing.png", local)
        self.assertFalse(res["ok"])
        self.assertFalse(os.path.exists(local))

    def test_timeout_reports_error(self):
        t = transport.Transport(_cfg())
        local = self._local("slow.png")
        exc = subprocess.TimeoutExpired(cmd=["ssh"], timeout=45)
        with mock.patch.object(subprocess, "run", side_effect=exc):
            res = t.fetch("/slow.png", local)
        self.assertFalse(res["ok"])
        self.assertFalse(os.path.exists(local))

    def test_metadata_excludes_bytes(self):
        t = transport.Transport(_cfg())
        data = b"\x89PNG\r\n\x1a\nsecretbytes"
        with mock.patch.object(subprocess, "run",
                               return_value=_completed(0, data, b"")):
            res = t.fetch("/r.png", self._local("r.png"))
        self.assertEqual(set(res.keys()), {"ok", "path", "bytes", "error"})
        self.assertNotIn(data, res.values())

    def test_full_png_signature_preserved(self):
        t = transport.Transport(_cfg())
        data = b"\x89PNG\r\n\x1a\n" + b"\x00" * 16
        with mock.patch.object(subprocess, "run",
                               return_value=_completed(0, data, b"")):
            res = t.fetch("/r.png", self._local("r.png"))
        self.assertTrue(res["ok"])
        with open(res["path"], "rb") as fh:
            self.assertTrue(fh.read().startswith(b"\x89PNG\r\n\x1a\n"))

    def test_truncated_png_signature_flagged(self):
        t = transport.Transport(_cfg())
        data = b"\x89PNG" + b"\x00" * 8  # 只有前 4 字节签名
        with mock.patch.object(subprocess, "run",
                               return_value=_completed(0, data, b"")):
            res = t.fetch("/r.png", self._local("r.png"))
        self.assertFalse(res["ok"])
        self.assertIn("PNG", res["error"])


if __name__ == "__main__":
    unittest.main()
