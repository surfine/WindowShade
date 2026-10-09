#!/usr/bin/env python3
"""F04 synthetic local subprocess. Never starts an assistant or accesses a user's home."""
import os, sys, time, signal
mode = sys.argv[1]
if mode == 'exit7':
    os.write(1, b'{"last":1}\n'); sys.exit(7)
elif mode == 'selfkill':
    os.write(1, b'{"ready":1}\n'); time.sleep(0.05); os.kill(os.getpid(), signal.SIGKILL)
elif mode == 'idle':
    os.write(1, b'{"ready":1}\n'); time.sleep(3)
elif mode == 'grandchild':
    # 孙进程继承管道并留在同一进程组：直接子进程先退出，宽限期后整组被清掉。
    if os.fork() == 0:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        time.sleep(30); os._exit(0)
    os.write(1, b'{"parent":1}\n'); os._exit(0)
