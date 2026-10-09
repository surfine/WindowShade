#!/usr/bin/env python3
"""Computer Use QA 的受限 SSH 传输层（仅标准库）。

本模块只负责通过本机原生 ssh 复用已建立的 control master 连接，
不保存任何密码、不创建新的认证方式、不执行本地 shell。

设计约束：
  * ssh_host 必须以非 '-' 开头且不含空白字符；
  * driver_path 必须是绝对路径；
  * 所有远程参数使用 shlex.join 拼装并交给 ssh，不做本地 shell 解析；
  * call() 解析远程 driver 返回的 JSON 并判断应用层错误；
  * fetch() 用 ssh cat 抓取远端文件（不使用 scp），本地文件独占创建，
    并保证图片签名（PNG）与原字节一致，绝不修改内容。

本模块不打印任何输出，由上层 CLI 决定如何展示。
"""

import json
import math
import os
import shlex
import subprocess

DEFAULT_TIMEOUT = 45
SSH_CONNECT_TIMEOUT = 10
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

# 视为应用层错误的 payload 字段。
_ERROR_KEYS = ("error", "isError")
_SUCCESS_KEYS = ("success",)


class TransportError(ValueError):
    """配置非法时抛出。"""


class Transport:
    """受限 SSH 传输对象。

    config 支持的键：
      ssh_host         目标主机（必填，非 '-' 开头，无空白字符）
      ssh_control      control master 套接字路径（可选）
      driver_path      远端 driver 可执行文件绝对路径（必填）
      timeout_seconds  单次调用超时秒数，默认 45
    """

    def __init__(self, config):
        if not isinstance(config, dict):
            raise TransportError("config 必须是 dict")

        host = config.get("ssh_host")
        if not isinstance(host, str) or not host:
            raise TransportError("ssh_host 必须是非空字符串")
        if host.startswith("-"):
            raise TransportError("ssh_host 不能以 '-' 开头: %r" % (host,))
        if any(ch.isspace() for ch in host):
            raise TransportError("ssh_host 不能包含空白字符: %r" % (host,))

        driver = config.get("driver_path")
        if not isinstance(driver, str) or not driver:
            raise TransportError("driver_path 必须是非空字符串")
        if not os.path.isabs(driver):
            raise TransportError("driver_path 必须是绝对路径: %r" % (driver,))

        control = config.get("ssh_control")
        if control is not None and not isinstance(control, str):
            raise TransportError("ssh_control 必须是字符串")

        timeout = config.get("timeout_seconds", DEFAULT_TIMEOUT)
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)):
            raise TransportError("timeout_seconds 必须是数字")
        if not math.isfinite(timeout) or timeout <= 0 or timeout > 120:
            raise TransportError("timeout_seconds 必须为正数")

        self.ssh_host = host
        self.ssh_control = control
        self.driver_path = driver
        self.timeout_seconds = timeout

    # ------------------------------------------------------------------
    # 底层执行
    # ------------------------------------------------------------------
    def _ssh_prefix(self):
        """构造 ssh 前缀 argv（不含远端命令）。

        原生 ssh，BatchMode=yes 禁止交互认证，ConnectTimeout=10 限定连接。
        """
        argv = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]
        if self.ssh_control:
            argv += ["-S", self.ssh_control]
        argv += ["--", self.ssh_host]
        return argv

    def _run_ssh(self, remote_command, input_text=None, binary=False):
        """执行 ssh 命令，返回 {returncode, stdout, stderr, error}。

        超时时 returncode 为 None，stdout/stderr 保留已有输出并写 error。
        """
        argv = self._ssh_prefix() + [remote_command]

        run_kwargs = {
            "capture_output": True,
            "timeout": self.timeout_seconds,
        }
        if not binary:
            run_kwargs["text"] = True
        if input_text is not None:
            run_kwargs["input"] = input_text

        try:
            proc = subprocess.run(argv, **run_kwargs)
        except OSError as exc:
            return {"returncode": None, "stdout": b"" if binary else "", "stderr": b"" if binary else "", "error": str(exc)}
        except subprocess.TimeoutExpired as exc:
            stdout, stderr = exc.stdout, exc.stderr
            if not binary:
                stdout = _as_text(stdout)
                stderr = _as_text(stderr)
            else:
                stdout = stdout or b""
                stderr = stderr or b""
            return {
                "returncode": None,
                "stdout": stdout,
                "stderr": stderr,
                "error": "timeout after %ss" % (self.timeout_seconds,),
            }

        return {
            "returncode": proc.returncode,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "error": None,
        }

    # ------------------------------------------------------------------
    # 公开 API
    # ------------------------------------------------------------------
    def remote(self, argv, input_text=None):
        """执行远端命令 argv（list[str]），返回 {returncode, stdout, stderr, error}。"""
        if not isinstance(argv, (list, tuple)) or not argv:
            raise TransportError("remote argv 必须是非空 list")
        for item in argv:
            if not isinstance(item, str):
                raise TransportError("remote argv 每一项必须是字符串")

        remote_command = shlex.join(list(argv))
        return self._run_ssh(remote_command, input_text=input_text)

    def call(self, tool, args):
        """调用远端 driver 的某个 tool。

        构造 `<driver_path> call <tool> <json>`，解析远端 stdout 的 JSON。
        返回 {ok, raw, payload}；raw 为 remote() 结果，payload 解析失败为 None。
        ok 为 False 的情况：非零退出、超时、JSON 非法、payload 表示错误。
        """
        if not isinstance(tool, str) or not tool:
            raise TransportError("tool 必须是非空字符串")
        if not isinstance(args, dict):
            raise TransportError("args 必须是 dict")

        remote_argv = [
            self.driver_path,
            "call",
            tool,
            json.dumps(args, ensure_ascii=False),
        ]
        raw = self.remote(remote_argv)

        ok, payload = self._interpret(raw)
        return {"ok": ok, "raw": raw, "payload": payload}

    @staticmethod
    def _interpret(raw):
        """解析 remote() 结果，返回 (ok, payload)。"""
        if raw["returncode"] != 0 or raw["error"]:
            return False, None

        stdout = raw["stdout"]
        if not isinstance(stdout, str):
            stdout = _as_text(stdout)
        try:
            payload = json.loads(stdout)
        except (ValueError, TypeError):
            return False, None

        if _payload_is_error(payload):
            return False, payload
        return True, payload

    def fetch(self, remote_path, local_path):
        """用 ssh cat 把远端文件取到本地（独占创建，不覆盖已有文件）。

        返回 {ok, path, bytes, error}；不记录文件内容到日志。
        若远端为 PNG 截图，则校验本地文件签名与原字节一致。
        """
        if not isinstance(remote_path, str) or not remote_path:
            raise TransportError("remote_path 必须是非空字符串")
        if not isinstance(local_path, str) or not local_path:
            raise TransportError("local_path 必须是非空字符串")

        # 远端路径作为 cat 的单个字面参数，shlex.join 会安全引用。
        raw = self._run_ssh("cat -- " + shlex.quote(remote_path), binary=True)

        if raw["returncode"] != 0 or raw["error"]:
            return {
                "ok": False,
                "path": local_path,
                "bytes": None,
                "error": raw["error"] or "ssh cat 退出码 %s" % (raw["returncode"],),
            }

        data = raw["stdout"] or b""
        if isinstance(data, str):
            data = data.encode("utf-8", "surrogateescape")

        # 独占创建，绝不 clobber 已有文件。
        try:
            fd = os.open(local_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        except FileExistsError:
            return {
                "ok": False,
                "path": local_path,
                "bytes": None,
                "error": "本地文件已存在，拒绝覆盖: %s" % (local_path,),
            }
        except OSError as exc:
            return {
                "ok": False,
                "path": local_path,
                "bytes": None,
                "error": "无法创建本地文件: %s" % (exc,),
            }

        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(data)
        except OSError as exc:
            return {
                "ok": False,
                "path": local_path,
                "bytes": None,
                "error": "写入本地文件失败: %s" % (exc,),
            }

        # 截图调用方所需的 PNG 签名校验：若内容以 PNG 开头，则必须携带完整
        # 8 字节签名。这里只做只读校验，绝不修改任何字节。
        result = {"ok": True, "path": local_path, "bytes": len(data), "error": None}
        if data[:4] == PNG_SIGNATURE[:4] and not data.startswith(PNG_SIGNATURE):
            result["ok"] = False
            result["error"] = "PNG 签名不完整"
        return result


def _as_text(value):
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return value


def _payload_is_error(payload):
    """判断 payload 是否表示应用层错误。"""
    if not isinstance(payload, dict):
        return True

    if payload.get("effect") in ("failed", "refused", "denied") or payload.get("status") in ("error", "failed"):
        return True
    for key in _ERROR_KEYS:
        if key in payload and payload[key]:
            return True

    for key in _SUCCESS_KEYS:
        if key in payload and payload[key] is False:
            return True

    return False
