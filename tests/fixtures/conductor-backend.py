#!/usr/bin/env python3
"""Synthetic stdio app-server. No network, accounts, tools, or real assistant requests."""
import json
import pathlib
import sys
import time

if sys.argv[1:] == ["--version"]:
    print("codex-cli 0.153.0", flush=True)
    raise SystemExit(0)
if sys.argv[1:] != ["app-server"]:
    raise SystemExit(64)
root = pathlib.Path.cwd()
log = root / "protocol.jsonl"
counter = root / "thread-counter.txt"
thread = None
turn = None
serial = 0

def emit(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)

def reply(request, value):
    emit({"id": request, "result": value})

def completed(status):
    emit({"method": "turn/completed", "params": {"threadId": thread, "turn": {"id": turn, "status": status}}})

for line in sys.stdin:
    message = json.loads(line)
    with log.open("a") as output:
        output.write(json.dumps(message) + "\n")
    method = message.get("method")
    request = message.get("id")
    params = message.get("params", {})
    if method == "initialize":
        reply(request, {"userAgent": "SYNTHETIC / NO NETWORK"})
    elif method == "initialized":
        pass
    elif method == "model/list":
        reply(request, {"data": [{"model": model, "supportedReasoningEfforts": [{"reasoningEffort": effort} for effort in ["medium", "high"]]} for model in ["fixture-a", "fixture-b"]], "nextCursor": None})
    elif method == "config/read":
        reply(request, {"config": {"sandbox_mode": "read-only", "approval_policy": "on-request", "approvals_reviewer": "user", "model_provider": "openai", "web_search": "disabled", "features": {"shell_tool": False, "unified_exec": False, "shell_snapshot": False}, "mcp_servers": {}, "plugins": {}, "hooks": {}}, "layers": [], "origins": {}})
    elif method == "account/read":
        reply(request, {"account": {"type": "chatgpt"}, "requiresOpenaiAuth": True})
    elif method == "thread/start":
        count = int(counter.read_text()) + 1 if counter.exists() else 1
        counter.write_text(str(count))
        thread = "fixture-thread-" + str(count)
        reply(request, {"thread": {"id": thread}})
    elif method == "thread/resume":
        old = thread
        thread = params["threadId"]
        time.sleep(0.1)
        reply(request, {"thread": {"id": thread}})
        # A late notification for the old target must not update the selected session.
        if old:
            emit({"method": "turn/completed", "params": {"threadId": old, "turn": {"id": "foreign", "status": "interrupted"}}})
    elif method == "turn/start":
        serial += 1
        turn = thread + "-turn-" + str(serial)
        text = params["input"][0]["text"]
        time.sleep(0.12)
        reply(request, {"turn": {"id": turn, "status": "inProgress"}})
        emit({"method": "turn/started", "params": {"threadId": thread, "turn": {"id": turn}}})
        if not text.startswith("hold"):
            time.sleep(0.05)
            completed("completed")
            turn = None
    elif method == "turn/steer":
        assert params["threadId"] == thread and params["expectedTurnId"] == turn
        time.sleep(0.12)
        if params["input"][0]["text"] == "reject":
            emit({"id": request, "error": {"code": -32000, "message": "synthetic refusal"}})
        elif params["input"][0]["text"] == "wrong-turn":
            reply(request, {"turnId": "not-the-current-turn"})
        else:
            reply(request, {"turnId": turn})
    elif method == "turn/interrupt":
        assert params["threadId"] == thread and params["turnId"] == turn
        reply(request, {})
        time.sleep(0.2)
        completed("interrupted")
        turn = None
    else:
        emit({"id": request, "error": {"code": -32601, "message": "unsupported fixture method"}})
