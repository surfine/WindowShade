#!/usr/bin/env python3
"""把配乐和音效混成片子放的那一轨：public/music/ws2-opus-mix.flac。

  npx esbuild scripts/score-events.ts --bundle --platform=node --log-level=warning | node > /tmp/score-events.json
  ~/.venvs/onetake/bin/python scripts/score.py /tmp/score-events.json

照 onetake §7 的做法（方法照搬，代码是这里自己写的）：
- 一个房间：所有音效送进同一个合成混响（T60 0.9 s），远近只改送多少；
- 一组材质：气流、玻璃、木头、低音四种，13 声，比 178 拍少得多；不给每个动作配一声；
- 配乐在 QUIET 段真停（画面里「不出声」和锁屏），在每一声音效下让开约 5 dB；
- 母带 −16 LUFS、真峰值 −4 dBTP（AAC 320k 编码后仍低于 −3 dBFS）。
全部确定：噪声用固定种子，同样的事件表混出逐字节相同的文件。
"""
import json, os, subprocess, sys, tempfile, wave
import numpy as np
from scipy import signal

SR = 48000
HERE = os.path.dirname(os.path.abspath(__file__))
PUBLIC = os.path.join(HERE, "..", "public")
OUT = os.path.join(PUBLIC, "music", "ws2-opus-mix.flac")
rng = np.random.default_rng(20261004)


def t_(n): return np.arange(n) / SR
def lowpass(x, f, o=2): b, a = signal.butter(o, f / (SR / 2)); return signal.lfilter(b, a, x)
def highpass(x, f, o=2): b, a = signal.butter(o, f / (SR / 2), "high"); return signal.lfilter(b, a, x)
def band(x, f, q): b, a = signal.iirpeak(min(f, SR / 2 - 200) / (SR / 2), q); return signal.lfilter(b, a, x)


# ---- 材质 ----
def air(dur, f0, f1, peak=0.5):
    """气流：噪声过一个中心频率从 f0 滑到 f1 的带通，包络在 peak 处最高。"""
    n = int(SR * dur); x = rng.standard_normal(n); out = np.zeros(n); blocks = 32; L = n // blocks + 1
    for i in range(blocks):
        a, b = i * L, min(n, (i + 1) * L); f = f0 * (f1 / f0) ** (i / (blocks - 1))
        out[a:b] = band(x[max(0, a - 512):b], f, 1.3)[-(b - a):]
    u = t_(n) / dur; env = np.where(u < peak, u / peak, (1 - u) / (1 - peak)) ** 1.6
    out = lowpass(out * env, 6000); return out / (np.abs(out).max() + 1e-9)

def glass(f, dur=1.0, bright=1.0):
    """玻璃：基频加两个不成倍数的泛音，各自衰减，前面一点高频噪声当敲击。"""
    n = int(SR * dur); t = t_(n)
    s = np.sin(2 * np.pi * f * t) * np.exp(-t * 5) + bright * (0.3 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 13) + 0.12 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * 22))
    hit = highpass(rng.standard_normal(n), 2500) * np.exp(-t * 260) * 0.4
    s = s + hit; return s / np.abs(s).max()

def wood(f=200, dur=0.12):
    """木头：短促的低音身子，音高往下掉一点，加一声 3 kHz 左右的脆响。"""
    n = int(SR * dur); t = t_(n)
    body = np.sin(2 * np.pi * f * t * (1 + 0.25 * np.exp(-t * 80))) * np.exp(-t * 55)
    snap = band(rng.standard_normal(n), 3000, 2.0) * np.exp(-t * 400)
    s = body + 0.45 * snap; return s / np.abs(s).max()

def low(f=60, dur=0.8):
    """低音：音高下滑的正弦，轻轻饱和，像东西落定。"""
    n = int(SR * dur); t = t_(n); ph = np.cumsum(2 * np.pi * (f + 1.8 * f * np.exp(-t * 26)) / SR)
    s = np.tanh(1.6 * np.sin(ph) * np.exp(-t * 5)); s = s + lowpass(rng.standard_normal(n), 400) * np.exp(-t * 80) * 0.3
    return s / np.abs(s).max()


# ---- 房间 ----
def room(T60=0.9):
    n = int(SR * T60 * 1.4); t = t_(n); ir = rng.standard_normal((n, 2)) * np.exp(-6.9 * t / T60)[:, None]
    ir = np.stack([lowpass(ir[:, 0], 4200), lowpass(ir[:, 1], 3800)], 1); ir[: int(SR * 0.014)] = 0
    for d, g in ((0.019, 0.45), (0.031, 0.3), (0.047, 0.2)): ir[int(d * SR)] += g
    return ir / np.abs(ir).sum(0).max() * 3.5


class Bus:
    def __init__(self, n): self.dry = np.zeros((n, 2)); self.wet = np.zeros((n, 2)); self.times = []
    def place(self, sig, t, gain, pan=0.0, send=0.3):
        i = int(round(t * SR)); sig = sig[: max(0, len(self.dry) - i)]; L, R = np.sqrt(0.5 * (1 - pan)), np.sqrt(0.5 * (1 + pan))
        for buf, g in ((self.dry, gain), (self.wet, gain * send)):
            buf[i : i + len(sig), 0] += sig * g * L; buf[i : i + len(sig), 1] += sig * g * R
        self.times.append(t)
    def render(self):
        ir = room(); rev = np.stack([signal.fftconvolve(self.wet[:, c], ir[:, c])[: len(self.dry)] for c in (0, 1)], 1)
        return self.dry + rev


# 每种事件用哪几样材质（t 是事件那一帧的秒数）。
def score_event(bus, kind, t, v):
    if kind == "tuck":   # 被吸进刘海：一口往上走的气，落定时一声很轻的低音
        bus.place(air(0.42, 260, 2400, 0.8), t - 0.36, 0.55 * v, 0.0, 0.35); bus.place(low(70, 0.6), t, 0.35 * v, 0.0, 0.2)
    elif kind == "chime":  # 刘海开口
        bus.place(glass(880, 1.0, 0.7), t, 0.32 * v, 0.05, 0.5); bus.place(glass(1320, 1.0, 0.5), t + 0.035, 0.22 * v, 0.05, 0.5)
    elif kind == "click":  # 触控板按下、抬起
        bus.place(wood(230, 0.09), t, 0.45 * v, 0.1, 0.12); bus.place(wood(190, 0.08), t + 0.06, 0.3 * v, 0.1, 0.12)
    elif kind == "lean":   # 镜头靠过去：一口低的气
        bus.place(air(0.6, 180, 900, 0.55), t - 0.33, 0.4 * v, 0.0, 0.45)
    elif kind == "open":   # 落点垂下来
        bus.place(air(0.3, 1800, 500, 0.3), t - 0.05, 0.3 * v, 0.0, 0.35); bus.place(glass(660, 0.7, 0.4), t + 0.08, 0.22 * v, 0.0, 0.4)
    elif kind == "land":   # 放进落点
        bus.place(low(90, 0.5), t, 0.4 * v, -0.1, 0.2); bus.place(wood(260, 0.08), t, 0.3 * v, -0.1, 0.15)
    elif kind == "nod":    # 点头：安静里唯一的一声，近、干
        bus.place(wood(210, 0.1), t, 0.35 * v, 0.0, 0.08)
    elif kind == "sleep":  # 屏幕一黑
        bus.place(low(52, 1.0), t, 0.55 * v, 0.0, 0.25)
    elif kind == "unlock":  # 对上了：一个五度
        bus.place(glass(1046, 1.4, 0.8), t, 0.3 * v, 0.0, 0.55); bus.place(glass(1568, 1.4, 0.6), t + 0.03, 0.22 * v, 0.0, 0.55); bus.place(low(65, 0.7), t, 0.35 * v, 0.0, 0.2)
    elif kind == "mark":   # 片名：压在音乐那一下重拍下面
        bus.place(low(58, 1.2), t, 0.5 * v, 0.0, 0.3)
    else:
        raise SystemExit(f"不认识的事件 {kind}")


def decode(path, start, dur):
    r = subprocess.run(["ffmpeg", "-v", "error", "-ss", f"{start:.6f}", "-t", f"{dur:.6f}", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
                       capture_output=True, check=True)
    x = np.frombuffer(r.stdout, np.float32).reshape(-1, 2).astype(float); n = int(round(dur * SR))
    return np.pad(x, ((0, max(0, n - len(x))), (0, 0)))[:n]


def ramp(n, a, b, up):
    """在 [a, b) 采样内从 0 到 1（up）或 1 到 0 的余弦过渡。"""
    g = np.ones(n) if not up else np.zeros(n); i = np.arange(n)
    u = np.clip((i - a) / max(1, b - a), 0, 1); c = 0.5 - 0.5 * np.cos(np.pi * u)
    return c if up else 1 - c


def main():
    ev = json.load(open(sys.argv[1])); fps = ev["fps"]; dur = ev["total"] / fps; n = int(round(dur * SR)); s = lambda f: int(round(f / fps * SR))
    music = decode(os.path.join(PUBLIC, ev["music"]), ev["offsetSec"], dur)
    music *= 10 ** (-20 / 20) / (np.sqrt((music ** 2).mean()) + 1e-9)      # 配乐垫在 −20 dBFS RMS，音效在上面

    g = np.ones(n)
    for a, b in ev["quiet"]:      # 停：剪接点上 8 ms 收掉；回：拍点上 5 ms 进来（保住那一下鼓）
        g *= np.maximum(ramp(n, s(a), s(a) + int(0.008 * SR), up=False), ramp(n, s(b) - int(0.005 * SR), s(b), up=True))
    a, b = ev["tail"]; g *= ramp(n, s(a), s(b), up=False)
    duck = np.zeros(n)
    for e in ev["events"]:        # 每一声前 30 ms 让开、400 ms 回来
        c = s(e["at"]); i = np.arange(max(0, c - int(0.03 * SR)), min(n, c + int(0.4 * SR)))
        d = np.where(i < c, (i - (c - 0.03 * SR)) / (0.03 * SR), 1 - (i - c) / (0.4 * SR)); duck[i] = np.maximum(duck[i], d)
    g *= 1 - 0.44 * duck          # −5 dB
    music *= g[:, None]

    bus = Bus(n)
    for e in ev["events"]: score_event(bus, e["kind"], e["at"] / fps, e["v"])
    sfx = bus.render() * 10 ** (-7 / 20)
    mix = music + sfx
    mix = np.stack([highpass(mix[:, c], 30) for c in (0, 1)], 1)
    mix[np.repeat((g < 1e-4)[:, None], 2, 1) & (np.abs(sfx) < 10 ** (-70 / 20))] = 0.0   # 安静段里没有音效的地方是真零

    tmp = tempfile.mkdtemp(); raw = os.path.join(tmp, "mix.wav")
    with wave.open(raw, "wb") as w:
        w.setnchannels(2); w.setsampwidth(3); w.setframerate(SR)
        q = np.clip(mix / max(1.0, np.abs(mix).max()), -1, 1); i24 = (q * (2 ** 23 - 1)).astype(np.int32)
        w.writeframes(np.ascontiguousarray(i24.astype("<i4")).view(np.uint8).reshape(-1, 4)[:, :3].tobytes())
    # 两遍 loudnorm（线性）：先量，再按量到的数做 −16 LUFS / −4 dBTP。
    first = subprocess.run(["ffmpeg", "-hide_banner", "-i", raw, "-af", "loudnorm=I=-16:TP=-4:LRA=20:print_format=json", "-f", "null", "-"], capture_output=True, text=True).stderr
    m = json.loads(first[first.rindex("{") : first.rindex("}") + 1])
    af = (f"loudnorm=I=-16:TP=-4:LRA=20:linear=true:measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}"
          f":measured_thresh={m['input_thresh']}:offset={m['target_offset']}:print_format=json")
    second = subprocess.run(["ffmpeg", "-hide_banner", "-y", "-i", raw, "-af", af, "-ar", str(SR), "-c:a", "flac", "-sample_fmt", "s16", OUT], capture_output=True, text=True).stderr
    m2 = json.loads(second[second.rindex("{") : second.rindex("}") + 1])
    print(json.dumps({"out": os.path.relpath(OUT), "events": len(bus.times), "beats": 178, "input_i": m["input_i"], "output_i": m2["output_i"],
                      "output_tp": m2["output_tp"], "normalization": m2["normalization_type"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
