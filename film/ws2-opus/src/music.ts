// 配乐的拍点表：Kevin MacLeod《Voxel Revolution》（incompetech.com，CC BY 4.0），见 public/music/README.md。
// 拍子事先量好写成常数（librosa beat_track + 固定拍距拟合：122.00 BPM，曲子第 0 拍在 0.056 秒，平均偏差 3.8 毫秒）。
// 渲染时不分析音频，每一帧只看帧号。
import { FPS } from './motion/site';

export const MUSIC_FILE = 'music/voxel-revolution.mp3';
/** 片子实际放的一轨：scripts/score.py 把配乐（从头到尾不断，UNDER 段退到后面，在音效下让开 ≤6 dB）和音效混好、做到 −16 LUFS 的成品。 */
export const MIX_FILE = 'music/ws2-opus-mix.flac';
export const BPM = 122;
const BEAT_SEC = 60 / BPM;
const FIRST_BEAT_SEC = 0.056;
/**
 * 成片第 0 帧 = 曲子第 70 拍（一个小节线，曲中 34.5 秒）。这样曲子的几处起伏落在片子该落的地方：
 * 第 94 拍的抬升 → 片子第 24 拍（拖到刘海那段开始）；第 126 拍的推高 → 第 56 拍（读口型之前）；
 * 第 158 拍全曲最大的推高 → 第 88 拍（面容 ID 打勾）；第 174 拍最后一个重拍 → 第 104 拍（片名）；第 178 拍能量落下 → 第 108 拍（片尾）。
 */
const SONG_BEAT_AT_0 = 70;
export const AUDIO_OFFSET_SEC = FIRST_BEAT_SEC + SONG_BEAT_AT_0 * BEAT_SEC;

/** 片子第 b 拍在成片里的帧号（四舍五入到整帧）。 */
export const beatFrame = (b: number) => Math.round(b * BEAT_SEC * FPS);
/** 小节线：片子第 0、4、8……拍。 */
export const isDownbeat = (b: number) => b % 4 === 0;

/** 离 out 最近的拍：拍号和差几帧（正数＝在拍之后）。 */
export function nearestBeat(out: number) {
  const k = Math.round(out / FPS / BEAT_SEC);
  return { k, off: out - beatFrame(k) };
}

/** 曲子的起伏落在片子的第几拍。 */
export const SECTIONS = { lift: 24, surge: 56, peak: 88, lastHit: 104, fall: 108 } as const;
