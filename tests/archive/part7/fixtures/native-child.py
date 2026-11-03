import os, signal, sys, time
mode=sys.argv[1]
if mode=='stubborn':
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    print('{"ready":1}',flush=True)
    while True: time.sleep(.05)
elif mode=='grandchild':
    if os.fork()==0:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        time.sleep(.9)
        with open(sys.argv[2],'w') as f: f.write('late descendant survived')
        os._exit(0)
    time.sleep(.08)
    print('{"parent":1}',flush=True)
    os._exit(0)
elif mode=='fd':
    try: os.fstat(int(sys.argv[2])); seen=True
    except OSError: seen=False
    print('{"inherited":'+('true' if seen else 'false')+'}',flush=True)
elif mode=='echo':
    for line in sys.stdin: print(line.strip(),flush=True)
