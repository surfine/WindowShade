// 音效表：每一下都取自提示表（film/cues.ts）。score.py 讀這張表，混進配樂。
// 只有兩種聲音，都短、都乾、都往上：輕點一下（tick）、輕輕落下（settle）。
// 沒有低鳴、氣流、疑問音、倒放、長尾巴。一個房間，送進去的很少。
// 事件比拍子少（60 秒、120 BPM 是 120 拍）。音樂不斷；讓位最多 6 dB，由 score.py 做。
import { T, TOTAL } from './film/cues';

/** 音樂不挖坑。頭尾的淡入淡出在 BED。 */
export const DIPS: [number, number, number, number, number][] = [];
/** 開頭 0.2 秒淡入，片尾最後 1.5 秒淡出。中間不靜音。 */
export const BED = { fadeIn: 12, fadeOut: 90, total: TOTAL };

export type Sfx = { f: number; kind: 'tick' | 'settle'; gain: number; pan?: number; send?: number };

const tick = (f: number, gain = 0.7, pan = 0): Sfx => ({ f, kind: 'tick', gain, pan, send: 0.05 });
const settle = (f: number, gain = 0.62, pan = 0): Sfx => ({ f, kind: 'settle', gain, pan, send: 0.08 });

export const SFX: Sfx[] = [
  settle(T.faceOk),
  tick(T.tap, 0.75),
  tick(T.lpOpen + 8, 0.6),
  settle(T.lpClose),
  tick(T.ask, 0.55),
  settle(T.ok),
  settle(T.glide + 18, 0.5, -0.2),
  tick(T.rideOpen, 0.6),
  tick(T.foodOpen, 0.6),
  tick(T.pomoTap, 0.75, 0.15),
  settle(T.restAlert),
  settle(T.away + 8, 0.55),
  tick(T.back, 0.7),
  ...T.ticks.map((f, i) => tick(f, 0.62 - i * 0.04, -0.1)),
  settle(T.lock, 0.6),
];
