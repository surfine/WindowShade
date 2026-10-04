#!/usr/bin/env python3
"""《它没有 Face ID》配乐：本机从零合成，无采样、无第三方素材。

120 BPM，4/4，30 小节 = 60 秒。片子 60 fps，一拍正好 30 帧，一小节 120 帧。
和弦 Bm7 – Gmaj7 – D – A（D 大调 vi–IV–I–V），每小节一个。

段落（小节从 0 数）：
  0–3   开场：垫音 + 心跳底鼓，1.5 秒处一声提示音（面容 ID 认出）
  4–8   第一段：四拍底鼓、反拍镲、八分贝斯（启动台）
  9–16  第二段：加拍手、十六分拨弦（读唇、点头）
  17–18 拉升：军鼓滚奏、噪声上扫，最后半拍留空
  19–23 高潮：全编制（刘海展开成 CarPlay）
  24    落下：Esc 收回刘海，只剩垫音
  25–28 尾声：倒数滴答，53 秒落锁
  29    最后一个强拍：全和弦重击，余音到 60 秒

用法：/tmp/wsaudio/bin/python compose.py  → ws2-future.wav
"""
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import fftconvolve, lfilter

SR = 44100
BPM = 120
BEAT = 60 / BPM
BAR = BEAT * 4
BARS = 30
N = int(SR * BAR * BARS)
rng = np.random.default_rng(20261004)

L = np.zeros(N)
R = np.zeros(N)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def at(t):
    return int(round(t * SR))


def add(sig, t, gain=1.0, pan=0.0):
    i = at(t)
    if i >= N:
        return
    sig = sig[: N - i]
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    L[i : i + len(sig)] += sig * gain * l * 1.414
    R[i : i + len(sig)] += sig * gain * r * 1.414


def onepole_lp(x, fc):
    fc = np.broadcast_to(np.asarray(fc, dtype=float), x.shape)
    a = np.exp(-2 * np.pi * fc / SR)
    if np.all(a == a.flat[0]):
        return lfilter([1 - a.flat[0]], [1, -a.flat[0]], x)
    y = np.empty_like(x)
    s = 0.0
    for i in range(len(x)):
        s = (1 - a[i]) * x[i] + a[i] * s
        y[i] = s
    return y


def hp(x, fc):
    return x - onepole_lp(x, fc)


def saw(f, n, phase=0.0):
    t = np.arange(n) / SR
    return 2 * ((t * f + phase) % 1) - 1


def env_adsr(n, a, d, s, r_len):
    e = np.ones(n) * s
    na, nd = int(a * SR), int(d * SR)
    e[:na] = np.linspace(0, 1, na, endpoint=False) if na else e[:na]
    e[na : na + nd] = np.linspace(1, s, nd, endpoint=False)[: max(0, min(nd, n - na))]
    nr = int(r_len * SR)
    if nr:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


# ---- 鼓 ----
def kick(level=1.0):
    n = int(0.42 * SR)
    t = np.arange(n) / SR
    f = 46 + 110 * np.exp(-t * 32)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t * 7.5)
    click = rng.standard_normal(n) * np.exp(-t * 400) * 0.25
    return np.tanh((body + click) * 1.6) * level


def clap():
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    noise = hp(rng.standard_normal(n), 900)
    e = np.zeros(n)
    for k, dt in enumerate([0, 0.011, 0.022]):
        i = int(dt * SR)
        e[i:] += np.exp(-(t[: n - i]) * (60 if k < 2 else 16))
    return onepole_lp(noise * e, 6500) * 0.5


def hat(open_=False):
    n = int((0.22 if open_ else 0.06) * SR)
    t = np.arange(n) / SR
    x = hp(hp(rng.standard_normal(n), 7000), 7000)
    return x * np.exp(-t * (14 if open_ else 70)) * 0.32


def snare():
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30) * 0.5
    x = hp(rng.standard_normal(n), 1500) * np.exp(-t * 22) * 0.6
    return tone + x


# ---- 音色 ----
def pad(notes, dur, cutoff=1800, attack=0.6):
    n = int(dur * SR)
    x = np.zeros(n)
    for m in notes:
        for d in (-0.11, 0.0, 0.09):
            x += saw(midi(m + d), n, phase=rng.random())
    x /= len(notes) * 3
    x = onepole_lp(onepole_lp(x, cutoff), cutoff)
    return x * env_adsr(n, attack, 0.4, 0.85, min(0.8, dur * 0.3))


def pluck(m, dur=0.35, bright=4200):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = saw(midi(m), n) * 0.6 + np.sin(2 * np.pi * midi(m) * t) * 0.4
    x = onepole_lp(x, bright)
    return x * np.exp(-t * 9)


def bass(m, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = saw(midi(m), n) * 0.5 + np.sin(2 * np.pi * midi(m) * t) * 0.8
    x = onepole_lp(x, 420)
    return np.tanh(x * 1.4) * env_adsr(n, 0.004, 0.12, 0.7, 0.03)


def bell(m, dur=1.6):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = midi(m)
    x = sum(a * np.sin(2 * np.pi * f * k * t) * np.exp(-t * dcy) for k, a, dcy in [(1, 1, 3), (2.01, 0.4, 5), (3.0, 0.25, 7), (4.2, 0.12, 10)])
    return x * 0.35


def riser(dur):
    n = int(dur * SR)
    p = np.linspace(0, 1, n)
    x = rng.standard_normal(n)
    x = onepole_lp(x, 400 + 9000 * p**2) - onepole_lp(x, 200 + 3000 * p**2)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * np.cumsum(220 * 2 ** (p * 2)) / SR) * 0.15
    return (x * 0.5 + tone) * p**2.2


def boom(dur=2.4):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 34 + 60 * np.exp(-t * 6)
    return np.tanh(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 1.6) * 1.8) * 0.9


def tick():
    n = int(0.05 * SR)
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * 2400 * t) * np.exp(-t * 160) * 0.5


def downlift(dur):
    return riser(dur)[::-1] * 0.7


# ---- 和弦 ----
CHORDS = [
    (47, [59, 62, 66, 69]),  # Bm7
    (43, [55, 59, 62, 66]),  # Gmaj7
    (38, [57, 62, 66, 69]),  # D
    (45, [57, 61, 64, 69]),  # A
]
ARP = [0, 1, 2, 3, 2, 1, 3, 2]


def bar_t(b, beat=0.0):
    return b * BAR + beat * BEAT


# 侧链：每拍底鼓把垫音和贝斯压下去。
duck = np.ones(N)


def sidechain(b0, b1, depth):
    for b in range(b0, b1):
        for k in range(4):
            i = at(bar_t(b, k))
            n = int(0.32 * SR)
            seg = 1 - depth * np.exp(-np.arange(n) / SR * 11)
            j = min(N, i + n)
            duck[i:j] = np.minimum(duck[i:j], seg[: j - i])


sidechain(4, 19, 0.35)
sidechain(19, 24, 0.6)

padL = np.zeros(N)
padR = np.zeros(N)

for b in range(BARS):
    root, notes = CHORDS[b % 4]
    t0 = bar_t(b)

    # 垫音：开场闷、拉升打开、高潮最亮、尾声收回。
    if b < 4:
        cut = 1150 + b * 220
    elif b < 17:
        cut = 1300 + (b - 4) * 40
    elif b < 19:
        cut = 1800 + (b - 17) * 1400
    elif b < 24:
        cut = 4200
    else:
        cut = 1500
    if b == 29:
        continue
    dur = BAR + 0.25
    if b == 18:
        dur = BAR - BEAT * 0.5  # 落拍前留半拍空
    p = pad(notes, dur, cutoff=cut, attack=0.9 if b < 4 else 0.08)
    i = at(t0)
    j = min(N, i + len(p))
    padL[i:j] += p[: j - i] * 0.95
    padR[i:j] += np.roll(p, 220)[: j - i] * 0.95

    # 底鼓
    if b < 4:
        add(kick(0.75), t0)
        add(kick(0.45), bar_t(b, 0.75))
    elif b < 17 or 19 <= b < 24:
        for k in range(4):
            add(kick(1.0 if b >= 19 else 0.85), bar_t(b, k))
    elif b == 17:
        for k in range(8):
            add(kick(0.7), bar_t(b, k * 0.5))

    # 镲
    if 1 <= b < 4:
        for k in range(8):
            add(hat(), bar_t(b, k * 0.5), 0.55 if k % 2 else 0.3, 0.2)
    if 4 <= b < 17 or 19 <= b < 24:
        step = 0.25 if (b >= 19 or b >= 9) else 0.5
        k = 0.0
        while k < 4:
            off = abs(k % 1 - 0.5) < 1e-6
            add(hat(open_=off and b >= 19), bar_t(b, k), 0.75 if off else 0.4, 0.25 if int(k * 4) % 2 else -0.2)
            k += step

    # 拍手
    if 9 <= b < 17 or 19 <= b < 24:
        for k in (1, 3):
            add(clap(), bar_t(b, k), 1.0 if b >= 19 else 0.8)

    # 军鼓滚奏
    if b == 18:
        for k in range(14):
            add(snare(), bar_t(b, k * 0.25), 0.25 + k / 14 * 0.7, (k % 2 - 0.5) * 0.3)

    # 贝斯
    if 4 <= b < 19 or 19 <= b < 24:
        if b == 18:
            add(bass(root, BAR - BEAT * 0.5), t0, 0.5)
        else:
            for k in range(8):
                m = root + (12 if k % 4 == 3 and b >= 19 else 0)
                add(bass(m, BEAT * 0.48), bar_t(b, k * 0.5), 0.55)

    # 拨弦琶音
    if 4 <= b < 9:
        for k in range(8):
            add(pluck(notes[ARP[k]] + 12, 0.4, 3000), bar_t(b, k * 0.5), 0.16, (k % 2 - 0.5) * 0.6)
    if 9 <= b < 17:
        for k in range(16):
            add(pluck(notes[ARP[k % 8]] + 12, 0.3, 3800), bar_t(b, k * 0.25), 0.13, (k % 2 - 0.5) * 0.7)
    if 19 <= b < 24:
        for k in range(16):
            add(pluck(notes[ARP[(k * 3) % 8]] + 24, 0.25, 6000), bar_t(b, k * 0.25), 0.12, (k % 2 - 0.5) * 0.8)
            if k % 4 == 0:
                add(pluck(notes[ARP[k % 8]] + 12, 0.6, 5000), bar_t(b, k * 0.25), 0.14, 0)
    if 25 <= b < 29:
        for k in range(4):
            add(pluck(notes[ARP[k]] + 12, 0.9, 2600), bar_t(b, k), 0.2, (k % 2 - 0.5) * 0.5)

# ---- 落点 ----
add(bell(86), 1.5, 0.55)                     # 90 帧：面容 ID 认出
add(bell(81, 1.0), bar_t(4, 0.25), 0.2)      # 510 帧：点刘海
add(riser(BAR * 2 - BEAT * 0.5), bar_t(17), 0.6)
add(boom(), bar_t(19), 1.0)                  # 2280 帧：落拍，刘海展开
add(hat(open_=True), bar_t(19), 1.2)
add(downlift(BAR * 0.9), bar_t(23, 0.4), 0.4)
add(boom(1.8), bar_t(24), 0.6)               # 2880 帧：Esc 收回
for k in range(3):                           # 3000 / 3060 / 3120 帧：三、二、一
    add(tick(), bar_t(25, k * 2), 0.5)
add(kick(0.6), bar_t(26, 2))               # 3180 帧：落锁
add(boom(4.0), bar_t(29), 1.0)               # 3480 帧：最后一个强拍
root, notes = CHORDS[2]
fin = pad([n + 0 for n in notes] + [root + 12], BAR, cutoff=3000, attack=0.01)
padL[at(bar_t(29)) : at(bar_t(29)) + len(fin)] += fin[: N - at(bar_t(29))] * 1.1
padR[at(bar_t(29)) : at(bar_t(29)) + len(fin)] += np.roll(fin, 220)[: N - at(bar_t(29))] * 1.1
add(bell(74, 2.0), bar_t(29), 0.35)

L += padL * duck * 0.55
R += padR * duck * 0.55

# ---- 混响 ----
irn = int(1.8 * SR)
ir_t = np.arange(irn) / SR
irL = rng.standard_normal(irn) * np.exp(-ir_t * 3.2)
irR = rng.standard_normal(irn) * np.exp(-ir_t * 3.2)
irL[:200] = 0
irR[:200] = 0
wetL = fftconvolve(L, irL)[:N] * 0.018
wetR = fftconvolve(R, irR)[:N] * 0.018
L = L + wetL
R = R + wetR

# 尾巴：最后半小节淡出。
fade = np.ones(N)
fn = int(1.2 * SR)
fade[-fn:] = np.linspace(1, 0, fn) ** 1.5
fade[: int(0.01 * SR)] = np.linspace(0, 1, int(0.01 * SR))

mix = np.stack([L * fade, R * fade], axis=1)
mix = np.tanh(mix / np.max(np.abs(mix)) * 1.25) * 0.89
out = Path(__file__).with_name("ws2-future.wav")
sf.write(out, mix.astype(np.float32), SR)
print(out, len(mix) / SR, "s")
