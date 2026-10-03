#!/usr/bin/env python3
"""Local synthetic child only. Never connects to Codex, Claude, a user profile, or a network."""
import json, os, sys, time
mode = sys.argv[1]
if mode == 'duplex':
    os.write(1, b'{"event":'); time.sleep(.01); os.write(1, b'"approval"}\n')
    message = sys.stdin.buffer.readline()
    os.write(1, json.dumps({'read': message.decode().rstrip('\n')}).encode() + b'\n')
    # A large stderr burst would deadlock an undrained stderr pipe. Production discards it.
    os.write(2, b'x' * (1024 * 1024))
elif mode == 'blocked':
    os.write(1, b'{"ready":true}\n'); time.sleep(10)
elif mode == 'partial':
    os.write(1, b'{"unfinished":')
elif mode == 'broken':
    os.close(0); os.write(1, b'{"ready":true}\n'); time.sleep(10)
elif mode == 'oversized':
    os.write(1, b'x' * (1048576 + 1)); time.sleep(10)
elif mode == 'multi':
    os.write(1, b'{"a":1}\n{"b":2}\n{"c":3}\n')
