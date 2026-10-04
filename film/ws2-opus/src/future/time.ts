// 《它没有 Face ID》：60 秒，60 fps，跟着 120 BPM 的配乐剪。每一帧只看帧号。
import { bezier, clamp01, mix } from '../motion/site';

export const FPS = 60;
export const TOTAL = 3600;

/** 镜头表。desk 是同一张桌子、同一台 MacBook；face / ear 是实拍板。切点都在拍上（见 beats.ts）。 */
export const SHOT = {
  unlock: [0, 420],
  launch: [420, 1080],
  lips: [1080, 1320],
  read: [1320, 1560],
  ear: [1560, 1800],
  nod: [1800, 2160],
  carplay: [2160, 3000],
  leave: [3000, TOTAL],
} as const;
export type ShotName = keyof typeof SHOT;

export function shotAt(f: number): ShotName {
  for (const k of Object.keys(SHOT) as ShotName[]) if (f >= SHOT[k][0] && f < SHOT[k][1]) return k;
  return 'leave';
}

/** 屏外一句：≤ 12 字，一屏一句。每句从拍上进来。 */
export const LINES: { from: number; to: number; text: string }[] = [
  { from: 0, to: 150, text: '它没有 Face ID' },
  { from: 180, to: 410, text: '看一眼，就解开' },
  { from: 480, to: 1050, text: '点一下刘海，打开启动台' },
  { from: 1110, to: 1530, text: '不出声，动动嘴就行' },
  { from: 1590, to: 2130, text: '点头确认，摇头取消' },
  { from: 2160, to: 2370, text: '长按刘海，换个视野' },
  { from: 2400, to: 2850, text: 'iPhone 的 CarPlay，在 Mac 上' },
  { from: 3000, to: 3330, text: '人走开，它就锁上' },
  { from: 3360, to: TOTAL + 1, text: '刘海，比你想的多' },
];

export const seg = (t: number, a: number, b: number) => (b <= a ? (t >= b ? 1 : 0) : clamp01((t - a) / (b - a)));
export const inOut = bezier(0.65, 0, 0.35, 1);
export const out = bezier(0.23, 1, 0.32, 1);
export const smooth = bezier(0.32, 0, 0.67, 1);
export { clamp01, mix };

/** 欠阻尼 / 临界阻尼弹簧，从 0 到 1；ζ、response 与 SwiftUI 同义。 */
export function spring(frame: number, start: number, z: number, response: number, v0 = 0) {
  const t = (frame - start) / FPS;
  if (t <= 0) return 0;
  const w = (2 * Math.PI) / response;
  if (z < 1) {
    const wd = w * Math.sqrt(1 - z * z);
    return 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + ((z * w - v0) / wd) * Math.sin(wd * t));
  }
  return 1 - (1 + (w - v0) * t) * Math.exp(-w * t);
}

/** 带种子的伪随机（mulberry32）。 */
export function rng(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const R = rng(20261004);
const WAVES = Array.from({ length: 3 }, () => ({ wx: 0.6 + R() * 1.2, wy: 0.5 + R() * 1.1, wr: 0.3 + R() * 0.7, px: R() * 6.28, py: R() * 6.28, pr: R() * 6.28 }));
/** 手持：几条慢正弦叠起来，单位是像素 / 度。 */
export function handheld(f: number, amp = 1) {
  const t = f / FPS;
  let x = 0, y = 0, r = 0;
  WAVES.forEach((w, i) => {
    const k = 1 / (i + 1);
    x += Math.sin(t * w.wx + w.px) * k;
    y += Math.sin(t * w.wy + w.py) * k;
    r += Math.sin(t * w.wr + w.pr) * k;
  });
  return { x: x * 1.6 * amp, y: y * 1.2 * amp, r: r * 0.035 * amp };
}

/** 进出淡：入 0.18 秒，出 0.10 秒（motion-direction 的 fade）。 */
export function fade(f: number, from: number, to: number, inF = 11, outF = 6) {
  return Math.min(seg(f, from, from + inF), 1 - seg(f, to - outF, to));
}
