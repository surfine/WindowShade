"""两版配乐 + 同一组音效，母带 −14 LUFS、真峰 ≤ −2 dBTP（AAC 之后仍在 −1 以内）。

用法（在 film/ws2-next 下）：
  ffmpeg -ss 25.218 -t 48.5 -i <tonight-hiphop.mp3> -ar 48000 -ac 2 audio/tonight-cut.wav
  ~/.venvs/mg-styles/bin/python scripts/score.py
输出 audio/mix-a-tonight.wav、audio/mix-b-original.wav。曲目与授权见 AUDIO.md。
时间点与 src/plan.ts 的 T 对齐（改了时间线要同步改这里）。
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / '.claude/skills/mg-styles-15/lib/audio'))
import numpy as np
import soundfile as sf
import mgaudio as mg
from mgaudio import sfx, recipes
from mgaudio.core import Sound

HERE = Path(__file__).resolve().parent.parent
DUR = 48.0
COVER = 0.567  # 窗口被刘海吞进的那一刻（plan.ts COVER.t）
APP_STARTS = [7.65 + 0.12 + 0.62 * (1 - (1 - i / 8) ** 1.7) for i in range(8)]


def add_sfx(m):
    m.sfx(sfx.whoosh(dur=0.8, kind='air', direction=1), at=COVER - 0.05, gain=-5)
    m.sfx(sfx.impact(kind='soft', size=0.35), at=COVER, gain=-6)
    m.sfx(sfx.click('soft'), at=5.4, gain=-9)
    m.sfx(sfx.whoosh(dur=0.6, kind='soft', direction=-1), at=5.75, gain=-9)
    m.sfx(sfx.click('soft'), at=7.6, gain=-9)
    for i, t in enumerate(APP_STARTS):
        m.sfx(sfx.blip(76 + (i % 4) * 2, kind='sine'), at=t + 0.05, gain=-12 - i * 0.8)
    m.sfx(sfx.whoosh(dur=0.5, kind='soft', direction=1), at=11.4, gain=-11)
    m.sfx(sfx.click('soft'), at=12.0, gain=-10)
    m.sfx(sfx.click('soft'), at=13.45, gain=-9)
    m.sfx(sfx.whoosh(dur=0.5, kind='swish', direction=1), at=13.65, gain=-11)
    m.sfx(sfx.ui('notify'), at=15.9, gain=-8)
    for t in (19.8, 20.4, 21.0):
        m.sfx(sfx.tick('wood'), at=t, gain=-11)
    m.sfx(sfx.click('switch'), at=21.4, gain=-6)
    m.sfx(sfx.blip(84, kind='sine'), at=24.6, gain=-10)
    m.sfx(sfx.blip(88, kind='sine'), at=25.2, gain=-10)
    m.sfx(sfx.shimmer_hit(note='E6'), at=26.0, gain=-6)
    m.sfx(sfx.ui('confirm'), at=33.55, gain=-8)
    m.sfx(sfx.whoosh(dur=0.6, kind='soft', direction=-1), at=33.85, gain=-10)
    m.sfx(sfx.whoosh(dur=1.8, kind='air', direction=1), at=41.2, gain=-9)
    m.sfx(sfx.riser(dur=1.8, kind='tonal'), at=44.0, gain=-10)
    m.sfx(sfx.impact(kind='soft', size=0.5), at=44.0, gain=-7)


def finish(m, name):
    g = m.group('music')
    g.automate('gain', [(0, 0), (28.2, 0), (28.8, -2), (32.9, -2), (33.5, 0), (46.2, 0), (47.9, -40)])
    res = m.export(str(HERE / 'audio' / name), lufs=-14, tp=-3.3)
    print(name, {k: res[k] for k in res if k in ('lufs', 'tp', 'peak', 'warnings')} if isinstance(res, dict) else res)


ONLY = sys.argv[1] if len(sys.argv) > 1 else 'ab'

# A：Mixkit「Tonight」（Michael Ramir C.），105 BPM；曲中 51.218 秒的抬升对上片子 26.0 秒的解开。
if 'a' in ONLY:
    x, sr = sf.read(str(HERE / 'audio' / 'tonight-cut.wav'), dtype='float32', always_2d=True)
    assert sr == 48000
    a = mg.Mix(duration=DUR, bpm=105)
    bed = a.track('bed', level=-20, group='music')
    bed.add(Sound(x.T[:, : int(DUR * sr)]), at=0)
    add_sfx(a)
    finish(a, 'mix-a-tonight.wav')

# B：本机原创（mgaudio ambient·glass，MIT 代码，纯合成），100 BPM，抬升（drop）放在 26.0 秒。
# 注：ambient·product 要用的钢琴采样在本机安装里缺文件，改用不依赖钢琴的 glass。
if 'b' in ONLY:
    b = recipes.ambient(duration=DUR, bpm=100, flavor='glass', drop=26.0, outro=44.0)
    add_sfx(b)
    finish(b, 'mix-b-original.wav')
