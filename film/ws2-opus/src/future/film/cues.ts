// 一张提示表：画面、镜头、声音都读这里（promo/ 的 timeline.ts 同一个做法）。
// 60 fps，120 BPM：一拍 30 帧，一小节 120 帧。全片 30 小节，每段长度按小节记。
// 两台机器轮流出场：Neo（没有刘海）↔ 15 英寸 Air（有刘海）；交接时岛长满画面，从另一台的岛里退出来。
import type { MachineId } from './machines';

export const FPS = 60;
export const TOTAL = 3600;
export const BEAT = 30, BAR = 120;

export type Seg = { id: string; m: MachineId | 'both'; from: number; to: number };
export const SEGS: Seg[] = [
  { id: 'wake', m: 'neo', from: 0, to: 720 }, // 0–6 小节：醒来、收窗、再说没刘海
  { id: 'home', m: 'air', from: 720, to: 1080 }, // 6–9：点刘海回到主屏幕
  { id: 'lips', m: 'neo', from: 1080, to: 1800 }, // 9–15：读唇、点头
  { id: 'live', m: 'air', from: 1800, to: 2280 }, // 15–19：iPhone 的实时活动
  { id: 'pomo', m: 'neo', from: 2280, to: 2880 }, // 19–24：番茄钟（低音进来）
  { id: 'away', m: 'air', from: 2880, to: 3300 }, // 24–27.5：走开就锁，锁屏停满
  { id: 'end', m: 'both', from: 3300, to: TOTAL }, // 27.5–30：硬切双机桌面
];

/** 交接：岛在前 GROW 帧里长满画面，后 SHRINK 帧里缩进下一台的岛。 */
export const HANDS = [720, 1080, 1800, 2280, 2880];
export const GROW = 20, SHRINK = 28;

export const segAt = (f: number) => SEGS.find((s) => f >= s.from && f < s.to) ?? SEGS[SEGS.length - 1];

// ---- 每段里的时刻 ----
export const T = {
  // Neo 醒来
  still: 90, wake: 100, faceOn: 400, faceOk: 445, phoneOk: 505, pwFill: 515, unlock: 555,
  // Air 主屏幕（Neo 多留一小节说「这台没有刘海」）
  curIn: 760, curNotch: 824, tap: 840, lpOpen: 844, lpClose: 960, closeTap: 956, listenPre: 1040,
  // Neo 读唇、点头：确认后很短一截再落位（审片 C11-02）
  lipsT0: 1110, charAt: 1130, charGap: 30, ghost: 1460, ask: 1380, nodA: 1420, nodB: 1476, ok: 1440, glide: 1488, rest: 1660, ride: 1760,
  // Air 实时活动。外卖稳态盖住 35–36 秒，弹簧先停稳再给字。
  rideOpen: 1860, rideClose: 1980, foodOpen: 2020, foodClose: 2200, livePre: 2240,
  // Neo 番茄钟
  pomoHover: 2280, pomoTap: 2340, ffA: 2400, ffB: 2560, restAlert: 2580, away: 2640, back: 2760, pomoPre: 2840,
  // Air 走开
  search: 2880, ticks: [3000, 3060, 3120], lock: 3180,
  // 片尾
  endCap: 3330, mark: 3420, endStill: 3480,
} as const;

export const LIP_TEXT = '放到左半屏';

/** 字幕：打字出来，后面一个游标（每 4 帧一个字）。英文在中文下面，不进岛。 */
export const LINES: { from: number; to: number; text: string; en?: string }[] = [
  // 先收窗进胶囊，再停在没开口的上边框（审片 C11-05）。
  // 一句一件事、有施事、有受事；一个东西从头到尾一个名字（看、窗口、刘海、Mac）。
  { from: 36, to: 500, text: '你一看，Mac 就解锁' },
  { from: 584, to: 646, text: '窗口收进刘海' },
  { from: 686, to: 718, text: '这台没有刘海，窗口也收得进' },
  { from: 780, to: 1040, text: '点一下刘海，回到主屏幕' },
  { from: 1130, to: 1370, text: '不用出声，读口型就行' },
  { from: 1380, to: 1620, text: '点一下头，就算确认' },
  { from: 1820, to: 2230, text: 'iPhone 上的提醒，Mac 上也看得到' },
  { from: 2300, to: 2580, text: '开始专注，窗口都收起来' },
  { from: 2620, to: 2754, text: '休息了，窗口也收起来' },
  { from: 2756, to: 2920, text: '点一下回来，休息不停表' },
  { from: 2960, to: 3280, text: '你走开，Mac 就锁上' },
  { from: 3330, to: TOTAL, text: '有没有刘海，窗口都收进顶部' },
];
export const CHAR_RATE = 4;

/** 音乐低音整段进来（Floating Cities 148.536 秒）：第 19 小节 = 番茄钟那一下。 */
export const DROP = 2280;
