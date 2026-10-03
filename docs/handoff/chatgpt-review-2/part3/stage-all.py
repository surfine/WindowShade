#!/usr/bin/env python3
import subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
command=[sys.executable,str(root/'part3/tools/stage-all.py'),'--part1',str(root/'part1'),'--part2',str(root/'part2'),'--part3',str(root/'part3')]+sys.argv[1:]
result=subprocess.run(command)
if result.returncode==0: print('PASS STAGED_ALL')
sys.exit(result.returncode)
