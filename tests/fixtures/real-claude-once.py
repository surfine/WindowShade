#!/usr/bin/env python3
"""Pass-through to the real Claude CLI that lets only the first user message reach the model.

For the one real conductor-page check (AARON-DECISIONS-2026-10-29 #37): the page probe sends a
second message and stops at once; that one is dropped here, so the run makes exactly one request.
REAL_CLAUDE_BIN picks the CLI (default ~/.local/bin/claude).
"""
import os
import subprocess
import sys
import threading

binary = os.environ.get("REAL_CLAUDE_BIN", os.path.expanduser("~/.local/bin/claude"))
child = subprocess.Popen([binary, *sys.argv[1:]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0)


def pump():
    for chunk in iter(lambda: child.stdout.readline(), b""):
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()


threading.Thread(target=pump, daemon=True).start()
sent = 0
for line in sys.stdin.buffer:
    if not line.strip():
        continue
    if b'"user"' in line:
        sent += 1
        if sent > 1:
            continue
    child.stdin.write(line)
    child.stdin.flush()
child.stdin.close()
sys.exit(child.wait())
