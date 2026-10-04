// 音效表：每一下都取自提示表（film/cues.ts），改了画面的时间，声音跟着走。
// public/music/future/score.py 读这张表（esbuild 现导成 JSON），混进配乐。
// 一个房间、一套材质：Kenney Interface Sounds（CC0）的录音 + sfx_palette 的合成低音；事件比拍子（120 拍）少得多。
import { DROP, HANDS, T, TOTAL } from './film/cues';

/**
 * 音乐从头到尾一条不断。只在落拍前让一口气：[开始压, 压到底, 开始回, 回满, 压多少 dB]（帧）。
 * 压 10 dB、只有 0.2 秒，低音进来那一下回满——听起来是一下顿挫，不是断了。
 */
export const DIPS: [number, number, number, number, number][] = [[DROP - 12, DROP - 6, DROP, DROP, -10]];
/** 开头 0.2 秒淡入，片尾最后 1.5 秒淡出。 */
export const BED = { fadeIn: 12, fadeOut: 90, total: TOTAL };

export type Sfx = { f: number; kind: string; gain: number; pan?: number; send?: number };

export const SFX: Sfx[] = [
  { f: T.faceOk, kind: 'confirm', gain: 0.55, send: 0.3 },
  // 交接：钻进岛里那一下
  ...HANDS.map((h) => ({ f: h - 16, kind: 'dive', gain: 0.4, send: 0.55 })),
  { f: T.tap, kind: 'tap', gain: 0.85, send: 0.15 },
  { f: T.lpOpen + 4, kind: 'pour', gain: 0.45, send: 0.45 },
  { f: T.lpClose, kind: 'gather', gain: 0.5, send: 0.35 },
  { f: T.charAt, kind: 'read', gain: 0.5, send: 0.25 },
  { f: T.ask, kind: 'ask', gain: 0.5, send: 0.3 },
  { f: T.ok, kind: 'confirm', gain: 0.5, send: 0.3 },
  { f: T.glide, kind: 'slide', gain: 0.55, pan: -0.35, send: 0.4 },
  { f: T.rideOpen, kind: 'press', gain: 0.5, send: 0.2 },
  { f: T.foodOpen, kind: 'press', gain: 0.5, send: 0.2 },
  { f: DROP, kind: 'unfold', gain: 0.55, send: 0.5 },
  { f: DROP, kind: 'sub', gain: 0.55, send: 0.3 },
  { f: T.pomoTap, kind: 'tap', gain: 0.8, pan: 0.2, send: 0.15 },
  { f: T.pomoTap + 8, kind: 'gather', gain: 0.45, pan: 0.3, send: 0.35 },
  { f: T.restAlert, kind: 'confirm', gain: 0.5, send: 0.3 },
  { f: T.away, kind: 'gather', gain: 0.5, send: 0.4 },
  { f: T.back, kind: 'tap', gain: 0.8, send: 0.15 },
  { f: T.back + 6, kind: 'pour', gain: 0.4, send: 0.4 },
  ...T.ticks.map((f) => ({ f, kind: 'tick', gain: 0.75, pan: -0.2, send: 0.2 })),
  { f: T.lock, kind: 'lock', gain: 0.6, send: 0.3 },
  { f: T.lock, kind: 'sub', gain: 0.45, send: 0.3 },
];
