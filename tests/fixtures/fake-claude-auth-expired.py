#!/usr/bin/env python3
"""Fake Claude Code CLI whose login has expired. No network, no model.
Every user message gets the same assistant/result error the real CLI printed on 2026-10-31."""
import json
import sys

SESSION = "fake-claude-auth-1"
TEXT = "Failed to authenticate. API Error: 401 OAuth session expired and could not be refreshed"
print(json.dumps({"type": "system", "subtype": "init", "model": "fake-claude",
                  "session_id": SESSION}), flush=True)
for line in sys.stdin:
    if not line.strip():
        continue
    print(json.dumps({"type": "assistant", "error": "authentication_failed",
                      "message": {"role": "assistant", "content": [{"type": "text", "text": TEXT}]},
                      "session_id": SESSION}), flush=True)
    print(json.dumps({"type": "result", "subtype": "success", "is_error": True,
                      "api_error_status": 401, "result": TEXT, "total_cost_usd": 0.0,
                      "session_id": SESSION}), flush=True)
