// 音效表：每一下都取自画面自己的常量，改了画面的时间，声音跟着走。
// public/music/future/score.py 读这张表（scripts 用 esbuild 导出成 JSON），混进配乐。
// 一个房间、一套材质：Kenney Interface Sounds（CC0）的录音 + sfx_palette 的合成低音；事件比拍子少得多。
import { HIT } from './beats';
import { CP_ASK, CP_ESC, CP_IN, CP_NEXT, CP_OK } from './CarPlay';
import { GLIDE_AT, LP_CLOSE, LP_OPEN } from './Desktop';
import { POCKET, TOTAL } from './time';

/**
 * 音乐停下来的地方：[开始收, 收完, 开始回, 回满]（帧）。曲子不暂停，回来时还在原来的拍上。
 * 冷开场等面容 ID 认出才进；读唇那段「不出声」真的没声；长按刘海憋一口气，低音进来时一起回；锁上之后只剩房间。
 */
export const HUSH: [number, number, number, number][] = [
  [-2, -1, HIT.faceOk - 4, HIT.faceOk],
  [POCKET.face.open[1], POCKET.face.open[1] + 14, POCKET.face.close[0], POCKET.face.close[0] + 12],
  [2236, 2244, HIT.drop, HIT.drop],
  [3186, 3196, TOTAL + 10, TOTAL + 10],
];

export type Sfx = { f: number; kind: string; gain: number; pan?: number; send?: number };

export const SFX: Sfx[] = [
  { f: HIT.faceOk, kind: 'confirm', gain: 0.55, send: 0.3 },
  { f: LP_OPEN - 2, kind: 'tap', gain: 0.85, send: 0.15 },
  { f: LP_OPEN + 4, kind: 'pour', gain: 0.45, send: 0.45 },
  { f: LP_CLOSE, kind: 'gather', gain: 0.5, send: 0.35 },
  { f: POCKET.face.open[0], kind: 'dive', gain: 0.45, send: 0.55 },
  { f: POCKET.face.close[1] - 6, kind: 'fold', gain: 0.45, send: 0.35 },
  { f: 1326, kind: 'read', gain: 0.55, send: 0.25 },
  { f: POCKET.ear.open[0], kind: 'dive', gain: 0.45, send: 0.55 },
  { f: POCKET.ear.close[1] - 6, kind: 'fold', gain: 0.45, send: 0.35 },
  { f: 1752, kind: 'confirm', gain: 0.5, send: 0.3 },
  { f: GLIDE_AT, kind: 'slide', gain: 0.55, pan: -0.35, send: 0.4 },
  { f: 2040, kind: 'cancel', gain: 0.45, send: 0.3 },
  { f: CP_IN, kind: 'press', gain: 0.5, send: 0.2 },
  { f: HIT.drop, kind: 'unfold', gain: 0.6, send: 0.5 },
  { f: HIT.drop, kind: 'sub', gain: 0.55, send: 0.3 },
  { f: CP_NEXT, kind: 'tap', gain: 0.8, pan: 0.3, send: 0.15 },
  { f: CP_ASK, kind: 'ask', gain: 0.5, pan: -0.25, send: 0.3 },
  { f: CP_OK, kind: 'confirm', gain: 0.55, pan: -0.25, send: 0.3 },
  { f: CP_ESC, kind: 'key', gain: 0.85, send: 0.12 },
  { f: HIT.esc, kind: 'gather', gain: 0.5, send: 0.35 },
  ...HIT.ticks.map((f) => ({ f, kind: 'tick', gain: 0.75, pan: -0.3, send: 0.2 })),
  { f: 3184, kind: 'lock', gain: 0.6, send: 0.3 },
  { f: 3184, kind: 'sub', gain: 0.45, send: 0.3 },
];
