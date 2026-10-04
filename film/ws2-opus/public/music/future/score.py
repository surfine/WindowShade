#!/usr/bin/env python3
"""未来版的声音：配乐 + 音效，一次混好，写成 ws2-future-mix.wav（48 kHz / 24 bit）。

    /tmp/wsaudio/bin/python public/music/future/score.py      # 在 film/ws2-opus 下跑

- 配乐：Kevin MacLeod《Floating Cities》（incompetech.com，CC BY 4.0），120.00 BPM。
  从曲子 110.536 秒（第 55 小节强拍）取 60 秒：曲子 148.536 秒低音进来的那一下落在片子 38 秒 = 第 2280 帧（刘海展开）。
- 音效：src/future/sfx.ts 的表（esbuild 现导，不手抄帧号）。材质只有一套：Kenney Interface Sounds（CC0）的录音，
  加 onetake sfx_palette 的合成低音 / 气流；全部过同一个房间（sfx_palette.impulse）。
- 音乐在每个音效下面让一下（duck），母带 −16 LUFS 整合响度、真峰值 ≤ −4.0 dBTP（AAC 编完约 −3.6）。
依赖：numpy、scipy、soundfile、librosa；sfx_palette 在 ~/.claude/skills/onetake/scripts。
"""
import json, os, subprocess, sys, urllib.request
import numpy as np, soundfile as sf, librosa
from scipy import signal
from scipy.ndimage import minimum_filter1d

HERE = os.path.dirname(os.path.abspath(__file__))
FILM = os.path.abspath(os.path.join(HERE, '../../..'))
sys.path.insert(0, os.path.expanduser('~/.claude/skills/onetake/scripts'))
from sfx_palette import SR, air, impulse, sub, wood, hp  # noqa: E402

FPS, DUR = 60, 60.0
MUSIC_URL = 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Floating%20Cities.mp3'
MUSIC_CACHE = '/tmp/wsmusic/Floating Cities.mp3'
OFFSET = 110.536
TARGET_LUFS, CEIL_DBTP = -16.0, -4.0

SAMPLE = {
    'confirm': 'confirmation_002', 'tap': 'click_002', 'pour': 'maximize_004', 'gather': 'minimize_004',
    'dive': 'maximize_002', 'fold': 'minimize_002', 'read': 'select_002', 'cancel': 'back_002',
    'press': 'select_004', 'unfold': 'maximize_008', 'ask': 'question_001', 'key': 'click_005',
    'tick': 'tick_001', 'lock': 'close_004',
}


def events():
    js = r"""
const esbuild = require('esbuild');
const r = esbuild.buildSync({ entryPoints: ['src/future/sfx.ts'], bundle: true, write: false, format: 'cjs', platform: 'node',
  jsx: 'automatic', loader: { '.jpg': 'empty', '.png': 'empty' }, external: ['remotion', 'react', 'react/jsx-runtime'] });
const m = { exports: {} }; new Function('module', 'exports', 'require', r.outputFiles[0].text)(m, m.exports, require);
process.stdout.write(JSON.stringify({ sfx: m.exports.SFX, hush: m.exports.HUSH }));
"""
    return json.loads(subprocess.check_output(['node', '-e', js], cwd=FILM))


def hush_gain(hush, n):
    f = np.arange(n) / SR * FPS
    g = np.ones(n)
    for a, b, c, d in hush:
        down = np.clip((f - a) / max(b - a, 1e-6), 0, 1); up = np.clip((f - c) / max(d - c, 1e-6), 0, 1)
        g = np.minimum(g, 1 - np.minimum(down, 1 - up))
    return 0.5 - 0.5 * np.cos(np.pi * g)


def load(name):
    x, sr = sf.read(os.path.join(HERE, 'sfx', name + '.ogg'), always_2d=True)
    return librosa.resample(x.mean(1), orig_sr=sr, target_sr=SR)


def voice(kind):
    """一个事件的声音（单声道）。录音为主，合成只补低频和气流。"""
    if kind == 'sub':
        return sub(48, 1.2) * 0.9
    if kind == 'slide':
        return air(0.42, 240, 1900, 1.3, 0.5) * 0.6
    x = load(SAMPLE[kind])
    if kind in ('tap', 'key'):
        w = wood(210 if kind == 'tap' else 170, 0.09) * 0.5
        n = max(len(x), len(w)); y = np.zeros(n); y[:len(x)] += x; y[:len(w)] += w
        return y
    if kind == 'unfold':
        a = air(0.55, 180, 2600, 1.2, 0.35) * 0.55
        y = np.zeros(max(len(a), len(x) + int(0.05 * SR))); y[:len(a)] += a; y[int(0.05 * SR):int(0.05 * SR) + len(x)] += x
        return y
    return x


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
    music *= hush_gain(data['hush'], n)[:, None]
    dry = np.zeros((n + 3 * SR, 2)); wet = np.zeros_like(dry)
    duck = np.zeros(n)
    for e in ev:
        sig = voice(e['kind']); i0 = int(e['f'] / FPS * SR); k = len(sig)
        p = e.get('pan', 0.0); L, R = np.sqrt(0.5 * (1 - p)), np.sqrt(0.5 * (1 + p))
        g = e['gain']; s = e.get('send', 0.25)
        dry[i0:i0 + k, 0] += sig * g * L; dry[i0:i0 + k, 1] += sig * g * R
        wet[i0:i0 + k, 0] += sig * g * s * L; wet[i0:i0 + k, 1] += sig * g * s * R
        # 让一下：提前 30 毫秒压下去，声音长度（最多 0.35 秒）里保持，0.45 秒放回。
        depth = 0.55 if e['kind'] in ('unfold', 'sub', 'lock') else 0.4
        a, h, r = int(0.03 * SR), int(min(k / SR, 0.35) * SR), int(0.45 * SR)
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
