// 一条 60fps 时间线，7560 帧。横版、竖版共用；只有版面不同。
import { BEAT } from './motion/direction';
import { ALERT_HOLD, HOVER_DELAY, TUCK_FRAMES, type IslandMode } from './motion/site';

export const TOTAL = 7560;

export type Segment = { id: string; from: number; to: number; line: string; concept?: [number, number] };

// 每段一句，照 docs/copy-guide.md：说用户遇到的事，一屏一句，不超过 12 个字。
export const SEGMENTS: Segment[] = [
  { id: 'lid', from: 0, to: 840, line: '合上盖子，桌面还在' },
  { id: 'live', from: 840, to: 1800, line: '正在发生的事，在刘海里' },
  { id: 'tuck', from: 1800, to: 2880, line: '窗口收进刘海，再放回' },
  { id: 'home', from: 2880, to: 3720, line: '点一下刘海，回到主屏幕' },
  { id: 'side', from: 3720, to: 4320, line: '甩出去，点回来' },
  { id: 'draw', from: 4320, to: 5400, line: '画一笔，说一句', concept: [4320, 5400] },
  { id: 'hold', from: 5400, to: 6120, line: '长按刘海，换一种用法', concept: [5400, 6120] },
  { id: 'away', from: 6120, to: 7140, line: '专注时安静，走开就锁', concept: [6340, 7140] },
  { id: 'end', from: 7140, to: TOTAL, line: 'WindowShade 2' },
];

/** 每句出现的帧（含起、不含止）。 */
export const CAPTIONS: { text: string; from: number; to: number }[] = [
  { text: SEGMENTS[0].line, from: 120, to: 660 },
  { text: SEGMENTS[1].line, from: 990, to: 1740 },
  { text: SEGMENTS[2].line, from: 2000, to: 2800 },
  { text: SEGMENTS[3].line, from: 3080, to: 3660 },
  { text: SEGMENTS[4].line, from: 3800, to: 4260 },
  { text: SEGMENTS[5].line, from: 4640, to: 5340 },
  { text: SEGMENTS[6].line, from: 5620, to: 6060 },
  { text: SEGMENTS[7].line, from: 6300, to: 7080 },
];
export const WORDMARK_AT = 7200;
export const FADE_TO_BLACK = [7500, TOTAL] as const;

// ---- 第 1 段：开盖 ----
export const LID_PLAYS = [90, 420];
export const DOLLY_AT = 680;

// ---- 刘海：每一次换样子 ----
export type Content =
  | 'none' | 'music' | 'headphones' | 'mouse' | 'window' | 'windowChanged' | 'card' | 'build'
  | 'stroke' | 'session' | 'road' | 'focus' | 'countdown';

/** at：起因确定的那一帧，旧内容从这里开始淡出；形状 exit.gap 之后换目标；新内容在形状走到 40% 时进场。 */
export type IslandEvent = { at: number; mode: IslandMode; content: Content; inAt?: number };

// 起因 → 先等一拍 → 开口。
export const MUSIC_PLAY = 940, CAUSE_PODS = 1160, CAUSE_MOUSE = 1480;
const CAUSE_MUSIC = MUSIC_PLAY;
export const PODS_END = CAUSE_PODS + BEAT + ALERT_HOLD;
export const MOUSE_END = CAUSE_MOUSE + BEAT + ALERT_HOLD;
export const TUCK_A = 1899; // 终端窗口飞进刘海
export const HOVER_A = 2120; // 指针停到刘海上
export const LEAVE_A = 2300;
export const ALERT_A = 2460;
export const HOVER_B = 2710;
export const CLICK_CARD = 2806; // 点一下格子，放回
export const UNTUCK_A = CLICK_CARD + 2;
export const LIFT_DRAW = 4541; // 画完一笔抬手
export const PRESS_LONG_A = 5520, PRESS_LONG_B = 5900;
export const LONG_PRESS = 30; // 长按门槛：片子取 0.5 秒，产品值待定
export const FOCUS_START = 6180;
export const TUCK_B = FOCUS_START + BEAT;
export const PHONE_GONE = 6440;
export const GRACE = 90; // 离开就锁：手机断开后 1.5 秒宽限（docs/dynamic-lock.md 的方案值）
export const COUNTDOWN = 600; // 刘海倒数 10 秒
export const LOCK_AT = PHONE_GONE + GRACE + COUNTDOWN;

export const ISLAND_EVENTS: IslandEvent[] = [
  { at: CAUSE_MUSIC + BEAT, mode: 'compact', content: 'music' },
  { at: CAUSE_PODS + BEAT, mode: 'alert', content: 'headphones' },
  { at: CAUSE_PODS + BEAT + ALERT_HOLD, mode: 'compact', content: 'music' },
  { at: CAUSE_MOUSE + BEAT, mode: 'alert', content: 'mouse' },
  { at: CAUSE_MOUSE + BEAT + ALERT_HOLD, mode: 'compact', content: 'music' },
  // 窗口落进刘海那一帧，两边换成窗口和个数。
  { at: TUCK_A, mode: 'compact', content: 'window', inAt: TUCK_A + Math.ceil(TUCK_FRAMES) + 1 },
  { at: HOVER_A + HOVER_DELAY, mode: 'shelf', content: 'card' },
  { at: LEAVE_A, mode: 'compact', content: 'window' },
  { at: ALERT_A, mode: 'alert', content: 'build' },
  { at: ALERT_A + ALERT_HOLD, mode: 'compact', content: 'windowChanged' },
  { at: HOVER_B + HOVER_DELAY, mode: 'shelf', content: 'card' },
  { at: CLICK_CARD, mode: 'rest', content: 'none' },
  { at: LIFT_DRAW + BEAT, mode: 'shelf', content: 'stroke' },
  { at: 5000, mode: 'compact', content: 'session' },
  { at: PRESS_LONG_A + LONG_PRESS, mode: 'full', content: 'road' },
  { at: PRESS_LONG_B + LONG_PRESS, mode: 'compact', content: 'session' },
  { at: FOCUS_START, mode: 'compact', content: 'focus' },
  { at: PHONE_GONE + GRACE, mode: 'alert', content: 'countdown' },
  { at: LOCK_AT, mode: 'rest', content: 'none' },
];

/** 落进刘海那一下的速度（帧）。 */
export const KICKS = [TUCK_A + Math.ceil(TUCK_FRAMES) + 1, TUCK_B + Math.ceil(TUCK_FRAMES) + 1];

export const LAND_A = KICKS[0];
export const LAND_B = KICKS[1];
