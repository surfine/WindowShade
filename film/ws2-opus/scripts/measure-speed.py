#!/usr/bin/env python3
"""每一帧画面里最快的东西走了多远（按 1920 宽、30 fps 折算的 px/帧，onetake 曲线腿的口径）。

  ~/.venvs/onetake/bin/python scripts/measure-speed.py film-60fps.mp4 --cuts 120,474,... > speed.json

只在做片时跑一次，结果写成 src/shutter.ts 的常数表；渲染时不分析画面。剪接点前后一帧不算（那是切换，不是运动）。
"""
import argparse, json, subprocess, sys
import numpy as np, cv2

ap = argparse.ArgumentParser(); ap.add_argument("film"); ap.add_argument("--cuts", default=""); ap.add_argument("--width", type=int, default=480)
a = ap.parse_args()
cuts = {int(x) for x in a.cuts.split(",") if x}
probe = json.loads(subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "json", a.film],
                                  capture_output=True, text=True, check=True).stdout)["streams"][0]
W = a.width; H = round(probe["height"] * W / probe["width"] / 2) * 2
p = subprocess.Popen(["ffmpeg", "-v", "error", "-i", a.film, "-vf", f"scale={W}:{H}", "-f", "rawvideo", "-pix_fmt", "gray", "-"], stdout=subprocess.PIPE)
k = 1920 / W * 2          # 60 fps 的一帧位移 → 1920 宽、30 fps
prev, speeds, i = None, [], 0
while True:
    buf = p.stdout.read(W * H)
    if len(buf) < W * H: break
    f = np.frombuffer(buf, np.uint8).reshape(H, W)
    if prev is None or i in cuts:
        speeds.append(0.0)
    else:
        flow = cv2.calcOpticalFlowFarneback(prev, f, None, 0.5, 4, 21, 3, 5, 1.1, 0)
        m = np.hypot(flow[..., 0], flow[..., 1])
        moving = m[m > 0.25]
        speeds.append(round(float(np.percentile(moving, 99)) * k, 1) if moving.size > 200 else 0.0)
    prev = f; i += 1
    if i % 500 == 0: print(i, file=sys.stderr)
json.dump(speeds, sys.stdout)
