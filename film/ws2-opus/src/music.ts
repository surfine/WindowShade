// 配乐的拍点表：Kevin MacLeod《Voxel Revolution》（incompetech.com，CC BY 4.0），见 public/music/README.md。
// 拍子事先量好写成常数（librosa beat_track + 固定拍距拟合：122.00 BPM，第 0 拍在曲中 0.056 秒，平均偏差 3.8 毫秒）。
// 渲染时不分析音频，每一帧只看帧号。
import { FPS } from './motion/site';

export const MUSIC_FILE = 'music/voxel-revolution.mp3';
/** 片子实际放的一轨：scripts/score.py 把配乐（UNDER 两段退到后面、在音效下让开，从不静音）和音效混好、做到 −16 LUFS 的成品。 */
export const MIX_FILE = 'music/ws2-opus-mix.flac';
export const BPM = 122;
const BEAT_SEC = 60 / BPM;
const FIRST_BEAT_SEC = 0.056;
/** 小节线：第 2、6、10……拍（k ≡ 2 mod 4），和 audiomap 的乐句起点、能量跳变一致。 */
export const isDownbeat = (k: number) => k % 4 === 2;

/** 成片第 0 帧放曲子的第几秒：让第 2 拍（第一个小节线）正好落在终端被吸进刘海的那一帧（成片第 31 帧）。 */
export const AUDIO_OFFSET_SEC = FIRST_BEAT_SEC + 2 * BEAT_SEC - 31 / FPS;

/** 曲子第 k 拍在成片里的帧号（四舍五入到整帧）。 */
export const beatFrame = (k: number) => Math.round((FIRST_BEAT_SEC + k * BEAT_SEC - AUDIO_OFFSET_SEC) * FPS);

/** 离 out 最近的拍：拍号和差几帧（正数＝在拍之后）。 */
export function nearestBeat(out: number) {
  const k = Math.round((out / FPS + AUDIO_OFFSET_SEC - FIRST_BEAT_SEC) / BEAT_SEC);
  return { k, off: out - beatFrame(k) };
}

/** 曲子的段落（拍号）：62.0 秒第一次推高，77.8 秒全曲最大的一次推高，87.6 秒能量落下去。 */
export const SECTIONS = { surge: 126, peak: 158, lastHit: 174, fall: 178 } as const;
