#!/usr/bin/env python3
"""Fake Claude Code stream-json CLI for the owned-session test. No network, no model."""
import json
import sys

SESSION = "fake-claude-1"
print(json.dumps({"type": "system", "subtype": "init", "model": "fake-claude",
                  "session_id": SESSION}), flush=True)
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        message = json.loads(line)
    except json.JSONDecodeError:
        continue
    content = message.get("message", {}).get("content", "")
    if isinstance(content, list):
        content = "".join(part.get("text", "") for part in content if isinstance(part, dict))
    reply = "收到：" + str(content)
    print(json.dumps({"type": "stream_event",
                      "event": {"type": "content_block_delta",
                                "delta": {"type": "text_delta", "text": reply}}}), flush=True)
    print(json.dumps({"type": "assistant",
                      "message": {"role": "assistant",
                                  "content": [{"type": "text", "text": reply}]},
                      "session_id": SESSION}), flush=True)
    print(json.dumps({"type": "result", "subtype": "success", "is_error": False,
                      "result": reply, "total_cost_usd": 0.0,
                      "session_id": SESSION}), flush=True)
