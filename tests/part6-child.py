#!/usr/bin/env python3
"""Synthetic local subprocess. Never starts an assistant or accesses a user's home."""
import os, sys, time
mode=sys.argv[1]
if mode=='tail':
    for _ in range(128): os.write(2,b'x'*8192)
    os.write(2,b'\x1b[31mEND\n')
    os.write(1,b'{"complete":true}\n')
elif mode=='exit7':
    os.write(1,b'{"last":1}\n'); sys.exit(7)
elif mode=='inherited':
    pid=os.fork()
    if pid==0:
        time.sleep(0.8)
        try: os.write(1,b'{"late":1}\n')
        except BrokenPipeError: pass
        os._exit(0)
    os.write(1,b'{"parent":1}\n'); os._exit(0)
elif mode=='truncated':
    os.write(1,b'{"partial":')
elif mode=='many':
    for i in range(4000): os.write(1,('{"n":%d}\n'%i).encode())
elif mode=='hold':
    os.write(1,b'{"ready":1}\n'); time.sleep(3)
elif mode=='echo':
    os.write(1,b'{"ready":1}\n')
    for line in sys.stdin.buffer:
        os.write(1,line)
        break
