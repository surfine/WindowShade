#!/usr/bin/env python3
"""未来版的声音：配乐 + 音效，一次混好，写成 ws2-future-mix.wav（48 kHz / 24 bit）。

    /tmp/wsaudio/bin/python public/music/future/score.py      # 在 film/ws2-opus 下跑

- 配乐：Kevin MacLeod《Floating Cities》（incompetech.com，CC BY 4.0），120.00 BPM。
  从曲子 110.536 秒（第 55 小节强拍）取 60 秒：曲子 148.536 秒低音进来的那一下落在片子 38 秒 = 第 2280 帧（刘海展开）。
- 音效：src/future/sfx.ts 只有 tick 和 settle。短、干、大调，没有低鸣、气流、疑问音。
  同一个小房间（sfx_palette.impulse），送进去的很少，尾巴不挂着。
- 音乐在每个音效下面让一下（最多 6 dB），母带 −16 LUFS、真峰值 ≤ −4.0 dBTP。
依赖：numpy、scipy、soundfile、librosa；sfx_palette 在 ~/.claude/skills/onetake/scripts。
"""
import json, os, subprocess, sys, urllib.request
import numpy as np, soundfile as sf, librosa
from scipy import signal
from scipy.ndimage import minimum_filter1d

HERE = os.path.dirname(os.path.abspath(__file__))
FILM = os.path.abspath(os.path.join(HERE, '../../..'))
sys.path.insert(0, os.path.expanduser('~/.claude/skills/onetake/scripts'))
from sfx_palette import SR, impulse, hp  # noqa: E402

FPS, DUR = 60, 60.0
MUSIC_URL = 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Floating%20Cities.mp3'
MUSIC_CACHE = '/tmp/wsmusic/Floating Cities.mp3'
OFFSET = 110.536
TARGET_LUFS, CEIL_DBTP = -16.0, -4.0

def tone(freq, dur, decay, gain, attack=0.004):
    """一段乾的正弦。大調、往上，沒有不和的拖尾。"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    env = np.exp(-t * decay) * (1 - np.exp(-t / max(attack, 1e-4)))
    return np.sin(2 * np.pi * freq * t) * env * gain


def events():
    js = r"""
const esbuild = require('esbuild');
const r = esbuild.buildSync({ entryPoints: ['src/future/sfx.ts'], bundle: true, write: false, format: 'cjs', platform: 'node',
  jsx: 'automatic', loader: { '.jpg': 'empty', '.png': 'empty' }, external: ['remotion', 'react', 'react/jsx-runtime'] });
const m = { exports: {} }; new Function('module', 'exports', 'require', r.outputFiles[0].text)(m, m.exports, require);
process.stdout.write(JSON.stringify({ sfx: m.exports.SFX, dips: m.exports.DIPS, bed: m.exports.BED }));
"""
    return json.loads(subprocess.check_output(['node', '-e', js], cwd=FILM))


def bed_gain(dips, bed, n):
    """音乐床：一条不断。头尾淡入淡出。中間若有讓位，最深 −6 dB，不到靜音。"""
    f = np.arange(n) / SR * FPS
    g = np.minimum(1, f / bed['fadeIn'])
    tail = np.clip((bed['total'] - f) / bed['fadeOut'], 0, 1)
    g = g * (0.5 - 0.5 * np.cos(np.pi * tail))
    for a, b, c, d, db in dips:
        down = np.clip((f - a) / max(b - a, 1e-6), 0, 1); up = np.clip((f - c) / max(d - c, 1e-6), 0, 1)
        k = np.minimum(down, 1 - up)
        g = g * (1 - k * (1 - 10 ** (max(db, -6) / 20)))
    return g


def voice(kind):
    """輕點一下，或輕輕落下。都在 200 毫秒以內，沒有低音、沒有掃頻。"""
    if kind == 'settle':
        # 大三度：E5 + G#5，軟，往上解決。
        a = tone(659.25, 0.16, 18, 0.55)
        b = tone(830.61, 0.14, 16, 0.32, 0.008)
        y = np.zeros(max(len(a), len(b)))
        y[:len(a)] += a
        y[:len(b)] += b
        return y
    # tick：一聲短的高音點，加上 3 毫秒的乾瞬態。
    y = tone(2349.32, 0.04, 90, 0.7, 0.0015)
    n = int(0.003 * SR)
    rng = np.random.default_rng(7)
    y[:n] += rng.standard_normal(n) * np.linspace(0.18, 0, n)
    return y


# ---- 响度（ITU-R BS.1770-4，48 kHz K 加权 + 门限）与真峰值（4 倍过采样） ----
def k_weight(x):
    b1, a1 = [1.53512485958697, -2.69169618940638, 1.19839281085285], [1.0, -1.69065929318241, 0.73248077421585]
    b2, a2 = [1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621]
    return signal.lfilter(b2, a2, signal.lfilter(b1, a1, x, axis=0), axis=0)


def lufs(x):
    y = k_weight(x); n, hop = int(0.4 * SR), int(0.1 * SR)
    z = np.array([np.sum(np.mean(y[i:i + n] ** 2, axis=0)) for i in range(0, len(y) - n, hop)])
    l = -0.691 + 10 * np.log10(z + 1e-12)
    z = z[l > -70]; rel = -0.691 + 10 * np.log10(z.mean()) - 10
    z = z[(-0.691 + 10 * np.log10(z)) > rel]
    return -0.691 + 10 * np.log10(z.mean())


def true_peak(x):
    return 20 * np.log10(np.abs(signal.resample_poly(x, 4, 1, axis=0)).max() + 1e-12)


def limit(x, ceil_db):
    """前视 5 毫秒、释放 80 毫秒的真峰值限幅。"""
    c = 10 ** (ceil_db / 20)
    up = np.abs(signal.resample_poly(x, 4, 1, axis=0)).max(1)
    pk = up[: len(up) // 4 * 4].reshape(-1, 4).max(1)
    pk = np.concatenate([pk, np.zeros(len(x) - len(pk))])
    need = np.minimum(1, c / np.maximum(pk, 1e-9))
    la = int(0.005 * SR)
    need = minimum_filter1d(need, size=la, origin=-(la // 2))
    g = np.empty_like(need); cur = 1.0; rel = np.exp(-1 / (0.08 * SR))
    for i, v in enumerate(need):
        cur = v if v < cur else v + (cur - v) * rel
        g[i] = cur
    return x * g[:, None]


def main():
    n = int(DUR * SR)
    if not os.path.exists(MUSIC_CACHE):
        os.makedirs(os.path.dirname(MUSIC_CACHE), exist_ok=True)
        urllib.request.urlretrieve(MUSIC_URL, MUSIC_CACHE)
    m, _ = librosa.load(MUSIC_CACHE, sr=SR, mono=False, offset=OFFSET, duration=DUR + 0.5)
    music = np.zeros((n, 2)); music[: min(n, m.shape[1])] = m.T[:n]
    t = np.arange(n) / SR
    data = events(); ev = data['sfx']
    music *= bed_gain(data['dips'], data['bed'], n)[:, None]
    dry = np.zeros((n + 3 * SR, 2)); wet = np.zeros_like(dry)
    duck = np.zeros(n)
    for e in ev:
        sig = voice(e['kind']); i0 = int(e['f'] / FPS * SR); k = len(sig)
        p = e.get('pan', 0.0); L, R = np.sqrt(0.5 * (1 - p)), np.sqrt(0.5 * (1 + p))
        g = e['gain']; s = e.get('send', 0.25)
        dry[i0:i0 + k, 0] += sig * g * L; dry[i0:i0 + k, 1] += sig * g * R
        wet[i0:i0 + k, 0] += sig * g * s * L; wet[i0:i0 + k, 1] += sig * g * s * R
        # 让一下：提前 30 毫秒压下去，声音长度（最多 0.35 秒）里保持，0.45 秒放回。
        # 线性增益的减量：0.35 ≈ -3.7 dB，0.45 ≈ -5.2 dB；上限 -6 dB。
        depth = 0.22 if e['kind'] == 'settle' else 0.16
        a, h, r = int(0.04 * SR), int(min(k / SR, 0.28) * SR), int(0.55 * SR)
        env = np.concatenate([np.linspace(0, 1, a), np.ones(h), np.linspace(1, 0, r)])
        j0 = max(0, i0 - a); seg = env[a - (i0 - j0):][: n - j0]
        duck[j0:j0 + len(seg)] = np.maximum(duck[j0:j0 + len(seg)], seg * depth)
    ir = impulse(0.9)
    rev = np.stack([signal.fftconvolve(wet[:, c], ir[:, c])[: len(dry)] for c in (0, 1)], 1)
    fx = np.stack([hp(dry[:, c] + rev[:, c] * 0.9, 38) for c in (0, 1)], 1)[:n]

    # 音乐压在 −20 LUFS 左右，音效在自己的窗口里要比让过之后的音乐响。
    music *= 10 ** ((-20.5 - lufs(music)) / 20)
    music *= (1 - duck)[:, None]
    win = [(int(e['f'] / FPS * SR), int(e['f'] / FPS * SR) + int(0.12 * SR)) for e in ev if e['kind'] not in ('sub',)]
    rms = lambda x: np.sqrt(np.mean(x ** 2) + 1e-12)
    fr = np.median([rms(fx[a:b]) for a, b in win]); mr = np.median([rms(music[a:b]) for a, b in win])
    fx *= (mr * 10 ** (4 / 20)) / fr

    mix = music + fx
    for _ in range(4):
        mix *= 10 ** ((TARGET_LUFS - lufs(mix)) / 20)
        mix = limit(mix, CEIL_DBTP - 0.1)
    out = os.path.join(HERE, 'ws2-future-mix.wav')
    sf.write(out, mix, SR, subtype='PCM_24')
    rel = [20 * np.log10(rms(fx[a:b]) / rms(music[a:b]) + 1e-12) for a, b in win if rms(music[a:b]) > 1e-4]
    blocks = np.array([np.sqrt(np.mean(mix[i:i + 4000] ** 2)) for i in range(0, n - 4000, 4000)])
    print('quiet (1/12 s blocks under -40 dBFS, verify_promo):', round(float((20 * np.log10(blocks + 1e-9) < -40).mean()), 3))
    print(json.dumps({
        'out': out, 'events': len(ev), 'beats': int(DUR * 2), 'lufs': round(lufs(mix), 2), 'dBTP': round(true_peak(mix), 2),
        'sfx_over_ducked_music_dB': {'min': round(min(rel), 1), 'median': round(float(np.median(rel)), 1), 'max': round(max(rel), 1)},
    }, ensure_ascii=False, indent=1))


if __name__ == '__main__':
    main()
