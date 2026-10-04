// 一张提示表：画面、镜头、声音都读这里（promo/ 的 timeline.ts 同一个做法）。
// 60 fps，120 BPM：一拍 30 帧，一小节 120 帧。全片 30 小节，每段长度按小节记。
// 两台机器轮流出场：Neo（没有刘海）↔ 15 英寸 Air（有刘海）；交接时岛长满画面，从另一台的岛里退出来。
import type { MachineId } from './machines';

export const FPS = 60;
export const TOTAL = 3600;
export const BEAT = 30, BAR = 120;

export type Seg = { id: string; m: MachineId | 'both'; from: number; to: number };
export const SEGS: Seg[] = [
  { id: 'wake', m: 'neo', from: 0, to: 600 }, // 0–5 小节：醒来、刷脸
  { id: 'home', m: 'air', from: 600, to: 1080 }, // 5–9：点刘海回到主屏幕
  { id: 'lips', m: 'neo', from: 1080, to: 1800 }, // 9–15：读唇、点头
  { id: 'live', m: 'air', from: 1800, to: 2280 }, // 15–19：iPhone 的实时活动
  { id: 'pomo', m: 'neo', from: 2280, to: 2880 }, // 19–24：番茄钟（低音进来）
  { id: 'away', m: 'air', from: 2880, to: 3240 }, // 24–27：走开就锁
  { id: 'end', m: 'both', from: 3240, to: TOTAL }, // 27–30：两台一起
];

/** 交接：岛在前 GROW 帧里长满画面，后 SHRINK 帧里缩进下一台的岛。 */
export const HANDS = [600, 1080, 1800, 2280, 2880];
export const GROW = 20, SHRINK = 28;

export const segAt = (f: number) => SEGS.find((s) => f >= s.from && f < s.to) ?? SEGS[SEGS.length - 1];

// ---- 每段里的时刻 ----
export const T = {
  // Neo 醒来
  still: 90, wake: 100, faceOn: 380, faceOk: 470, unlock: 490,
  // Air 主屏幕
  curIn: 640, curNotch: 704, tap: 720, lpOpen: 724, lpClose: 960, closeTap: 956, listenPre: 1040,
  // Neo 读唇、点头
  lipsT0: 1110, charAt: 1130, charGap: 36, ghost: 1300, ask: 1440, nodA: 1500, nodB: 1556, ok: 1560, glide: 1572, rest: 1660, ride: 1740,
  // Air 实时活动
  rideOpen: 1890, rideClose: 1990, foodOpen: 2070, foodClose: 2170, livePre: 2240,
  // Neo 番茄钟
  pomoHover: 2280, pomoTap: 2340, ffA: 2400, ffB: 2560, restAlert: 2580, away: 2640, back: 2760, pomoPre: 2840,
  // Air 走开
  search: 2880, ticks: [3000, 3060, 3120], lock: 3180,
  // 片尾
  endCap: 3330, mark: 3420, endStill: 3480,
} as const;

export const LIP_TEXT = '放到左半屏';

/** 字幕：打字出来，后面一个游标（每 4 帧一个字）。 */
export const LINES: { from: number; to: number; text: string }[] = [
  { from: 150, to: 340, text: '它没有 Face ID' },
  { from: 400, to: 580, text: '看一眼，就解锁' },
  { from: 640, to: 1040, text: '点一下刘海，回到主屏幕' },
  { from: 1130, to: 1420, text: '不出声，它看口型就懂' },
  { from: 1460, to: 1700, text: '点一下头，就照做' },
  { from: 1840, to: 2230, text: 'iPhone 上的实时活动，这里也看得到' },
  { from: 2300, to: 2600, text: '专注时，聊天收起来' },
  { from: 2650, to: 2840, text: '休息时，桌面收起来' },
  { from: 2930, to: 3220, text: '人走开，就锁上' },
  { from: 3330, to: TOTAL, text: '有刘海、没刘海，都一样' },
];
export const CHAR_RATE = 4;

/** 音乐低音整段进来（Floating Cities 148.536 秒）：第 19 小节 = 番茄钟那一下。 */
export const DROP = 2280;
