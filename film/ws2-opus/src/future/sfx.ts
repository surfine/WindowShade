// 音效表：每一下都取自画面自己的常量，改了画面的时间，声音跟着走。
// public/music/future/score.py 读这张表（scripts 用 esbuild 导出成 JSON），混进配乐。
// 一个房间、一套材质：Kenney Interface Sounds（CC0）的录音 + sfx_palette 的合成低音；事件比拍子少得多。
import { HIT } from './beats';
import { CP_ASK, CP_ESC, CP_IN, CP_NEXT, CP_OK } from './CarPlay';
import { GLIDE_AT, LP_CLOSE, LP_OPEN } from './Desktop';
import { POCKET, TOTAL } from './time';


/**
 * 音乐从头到尾一条不断。只在落拍前让一口气：[开始压, 压到底, 开始回, 回满, 压多少 dB]（帧）。
 * 压 10 dB、只有 0.2 秒，低音进来那一下回满——听起来是一下顿挫，不是断了。
 * （先前把冷开场、读唇、锁后都做成静音，听感是「时断时续」，已拿掉。）
 */
export const DIPS: [number, number, number, number, number][] = [
  [HIT.drop - 12, HIT.drop - 6, HIT.drop, HIT.drop, -10],
];
/** 开头 0.2 秒淡入，片尾最后 1.5 秒淡出。 */
export const BED = { fadeIn: 12, fadeOut: 90, total: TOTAL };

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
