// 运动的基本件：弹簧（与 ws2-opus/src/motion/springs.ts 的 solve() 同式，换目标时保留位置和速度）、
// 刘海轮廓（本机 Mac17,4 实测 + DisplayShape.swift 的 ContinuousCorner）、缓动与小工具。
// 每个函数只看输入，不看时钟，不用随机数。

export const FPS = 30;
export const TOTAL = 48 * FPS;

export const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
export const clamp01 = (v: number) => clamp(v, 0, 1);
export const mix = (a: number, b: number, p: number) => a + (b - a) * p;
export const seg = (t: number, a: number, b: number) => (b <= a ? (t >= b ? 1 : 0) : clamp01((t - a) / (b - a)));
export const smooth = (x: number) => x * x * (3 - 2 * x);

/** 位移 d0、速度 v0，过 t 秒后的 [位移, 速度]。resp 是周期（秒），z 是阻尼比。 */
export function solve(d0: number, v0: number, resp: number, z: number, t: number): [number, number] {
  if (t <= 0) return [d0, v0];
  const w = (2 * Math.PI) / resp;
  if (z < 1) {
    const wd = w * Math.sqrt(1 - z * z);
    const e = Math.exp(-z * w * t);
    const c = Math.cos(wd * t);
    const n = Math.sin(wd * t);
    const B = (v0 + z * w * d0) / wd;
    const d = e * (d0 * c + B * n);
    return [d, -z * w * d + e * wd * (B * c - d0 * n)];
  }
  const e = Math.exp(-w * t);
  const C = v0 + w * d0;
  return [(d0 + C * t) * e, (C - w * (d0 + C * t)) * e];
}

/** 从 0 走向 1；v0 是每秒多少个全程。 */
export function approach(t: number, resp: number, z: number, v0 = 0) {
  if (t <= 0) return 0;
  return 1 + solve(-1, v0, resp, z, t)[0];
}

export function bezier(x1: number, y1: number, x2: number, y2: number) {
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  return (x: number) => {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    let t = x;
    for (let i = 0; i < 10; i++) {
      const X = ((ax * t + bx) * t + cx) * t - x;
      const d = (3 * ax * t + 2 * bx) * t + cx;
      if (Math.abs(X) < 1e-7 || !d) break;
      t -= X / d;
    }
    return ((ay * t + by) * t + cy) * t;
  };
}
/** 指针移动：teach.js 同一条曲线。 */
export const moveCurve = bezier(0.32, 0, 0.67, 1);

// ---------- 刘海 ----------
const E = 1.52866495;
const SEG: [number, number][][] = [
  [[0, 1.08849001], [0, 0.86840701], [0.0749114, 0.63149399]],
  [[0.16906001, 0.37282401], [0.37282401, 0.16906001], [0.63149399, 0.0749114]],
  [[0.86840701, 0], [1.08849001, 0], [1.52866495, 0]],
];
const UNIT: [number, number][] = (() => {
  const pts: [number, number][] = [[0, E]];
  let from: [number, number] = [0, E];
  for (const s of SEG) {
    for (let i = 1; i <= 10; i++) {
      const t = i / 10, u = 1 - t, a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
      pts.push([a * from[0] + b * s[0][0] + c * s[1][0] + d * s[2][0], a * from[1] + b * s[0][1] + c * s[1][1] + d * s[2][1]]);
    }
    from = s[2];
  }
  return pts;
})();
const REV = UNIT.slice().reverse();

/** 本机 Mac17,4（1710×1107 pt）：刘海 762.38–947.62，深 33.26，底角沿边 15.07，肩沿边 7.12。 */
export const HW = { cx: 855, w: 947.62 - 762.38, h: 33.26, rb: 15.07 / E, rs: 7.12 / E };
export type Shape = { w: number; h: number; rb: number };

export function notchPath(s: Shape, cx = HW.cx) {
  const L = cx - s.w / 2, R = cx + s.w / 2, h = s.h;
  const rb = Math.max(0, Math.min(s.rb, Math.min(s.w / 2, h) / E));
  const rs = HW.rs;
  const p: [number, number][] = [];
  for (const q of UNIT) p.push([L - q[1] * rs, q[0] * rs]);
  for (const q of UNIT) p.push([L + q[0] * rb, h - q[1] * rb]);
  for (const q of REV) p.push([R - q[0] * rb, h - q[1] * rb]);
  for (const q of REV) p.push([R + q[1] * rs, q[0] * rs]);
  p.push([R + rs * E, -4], [L - rs * E, -4]);
  return 'M' + p.map((a) => a[0].toFixed(2) + ' ' + a[1].toFixed(2)).join('L') + 'Z';
}

// ---------- 二次贝塞尔路径 ----------
export const quad = (a: number, c: number, b: number, p: number) => (1 - p) * (1 - p) * a + 2 * (1 - p) * p * c + p * p * b;
