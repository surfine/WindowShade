#!/usr/bin/env python3
"""Compare the explicit current and upstream-reference reply policies."""
import importlib.util, json, sys
from pathlib import Path

here = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("session", here / "session-interop.py")
s = importlib.util.module_from_spec(spec); spec.loader.exec_module(s)

def run(path, extra_args, expected_interest_reply, expected_hid_reply):
    c = s.Client(path, extra_args=extra_args)
    try:
        result, messages, xid = c.request("_touchStart")
        assert messages == [s.reply("_touchStart", xid, {"_i": 1})]
        result, messages, xid = c.request("_interest", {"_regEvents": ["SystemStatus"]})
        expected = ([s.reply("_interest", xid)] if expected_interest_reply else [])
        expected += [s.event("SystemStatus", {"state": 3}, xid)]
        assert messages == expected, (messages, expected)
        result, messages, xid = c.request("_hidC", {"_hidC": 6, "_hBtS": 2})
        expected = [s.reply("_hidC", xid)] if expected_hid_reply else []
        assert messages == expected, (messages, expected)
        return {"replyPolicy": "upstream-reference" if extra_args else "current",
                "interestReply": expected_interest_reply, "hidRequestReply": expected_hid_reply}
    finally:
        c.close()

def main():
    path = Path(sys.argv[1])
    results = [run(path, [], True, True), run(path, ["--reply-policy", "upstream-reference"], False, True)]
    print(json.dumps({"case": "reply-policy-matrix", "passed": True, "results": results,
                      "networkListener": False, "systemActions": 0}))

if __name__ == "__main__": main()
