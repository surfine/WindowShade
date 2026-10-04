// 官网动画的数字，原样搬过来，改成只看帧号。每一段都注明出处；没有出处的数字不放在这里。
// dt 固定 1/60。

export const FPS = 60;
export const DT = 1 / FPS;

export const clamp01 = (v: number) => Math.max(0, Math.min(1, v));
export const mix = (a: number, b: number, p: number) => a + (b - a) * p;
export const seg = (t: number, a: number, b: number) => (b <= a ? (t >= b ? 1 : 0) : clamp01((t - a) / (b - a)));

// ---- cubic-bezier，site/island.js 与 site/teach.js 同一种解法 ----
export function bezier(x1: number, y1: number, x2: number, y2: number) {
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  const X = (t: number) => ((ax * t + bx) * t + cx) * t;
  const Y = (t: number) => ((ay * t + by) * t + cy) * t;
  const dX = (t: number) => (3 * ax * t + 2 * bx) * t + cx;
  return (x: number) => {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    let t = x;
    for (let i = 0; i < 8; i++) {
      const d = X(t) - x, s = dX(t);
      if (Math.abs(d) < 1e-6 || !s) break;
      t -= d / s;
    }
    return Y(clamp01(t));
  };
}

// ---- site/island.js：岛的宽、高、圆角各一根弹簧（单位 cqw，屏宽的百分之一） ----
export const NOTCH = { w: 14.5, h: 5.4, r: 1.5 };
export const ISLAND_SHAPES = {
  rest: NOTCH,
  compact: { w: NOTCH.w + 2 * 4.6, h: NOTCH.h, r: 1.6 },
  alert: { w: 38, h: NOTCH.h + 8.6, r: 3.6 },
  shelf: { w: 54, h: NOTCH.h + 21, r: 4.2 },
  // 片子新增的一个目标：长按后铺满整块屏。弹簧沿用展开的 0.96 / 0.38，不另配。
  full: { w: 100, h: 62.5, r: 0 },
} as const;
export type IslandMode = keyof typeof ISLAND_SHAPES;

/** 安静 / 收起：calm 0.34、ζ 1。一排：expand 0.40、ζ 0.92。提醒：bloom 0.42、ζ 0.84。 */
export const islandTuning = (mode: IslandMode) =>
  mode === 'alert' ? { damping: 0.84, response: 0.42 }
  : mode === 'shelf' || mode === 'full' ? { damping: 0.92, response: 0.4 }
  : { damping: 1, response: 0.34 };

/** 落进刘海那一下：calm 被踢。宽 +700 pt/s、高 +300 pt/s。100 cqw = 1710 pt。 */
export const TUCK_KICK = { w: 700 / 17.1, h: 300 / 17.1 };
/** 提醒停 2.6 秒；island.js 在 2620ms 时重新取目标。 */
export const ALERT_HOLD = Math.round(2.62 * FPS);
/** 指针停 120ms 才展开成一排。 */
export const HOVER_DELAY = Math.round(0.12 * FPS);

function solve(d0: number, v0: number, response: number, zeta: number, t: number): [number, number] {
  if (t <= 0) return [d0, v0];
  const w = (2 * Math.PI) / response;
  if (zeta < 1) {
    const wd = w * Math.sqrt(1 - zeta * zeta);
    const e = Math.exp(-zeta * w * t);
    const c = Math.cos(wd * t);
    const s = Math.sin(wd * t);
    const b = (v0 + zeta * w * d0) / wd;
    const d = e * (d0 * c + b * s);
    return [d, -zeta * w * d + e * wd * (b * c - d0 * s)];
  }
  const e = Math.exp(-w * t);
  const k = v0 + w * d0;
  const d = (d0 + k * t) * e;
  return [d, (k - w * (d0 + k * t)) * e];
}
function namedProgress(frame: number, start: number, response: number, zeta: number, v0 = 0) {
  const t = (frame - start) / FPS;
  if (t <= 0) return 0;
  const p = 1 + solve(-1, v0, response, zeta, t)[0];
  return p < 0 ? 0 : p;
}
function restFrames(response: number, zeta: number) {
  for (let f = 1; f < FPS * 2; f++) if (1 - namedProgress(f, 0, response, zeta) <= 0.004) return f;
  return Math.round(1.6 * FPS);
}
/** 窗口收进刘海：settle。帧数是残差落到 0.004 的那一帧，鼓一下跟在它后面。 */
export const TUCK_FRAMES = restFrames(0.38, 1);
export function tuckProgress(frame: number, start: number) {
  return Math.min(1, namedProgress(frame, start, 0.38, 1));
}
/** 放回是一根新的 flyOut，从收起的位置走向原位。 */
export function untuckProgress(frame: number, start: number) {
  if (frame <= start) return 1;
  return Math.max(0, 1 - namedProgress(frame, start, 0.38, 0.9));
}
export { solve };

// ---- site/app.js：开盖播放与合盖的折叠 ----
/** play()：铰链走 dolly（1.6 秒、ζ 1）。1.5 秒合到 0.9，停到 2.4 秒，再打开。0 是开着。页面折进去仍是 FoldSpring。 */
export const LID_PLAY_FRAMES = Math.round(3.6 * FPS);
export function lidPlay(frame: number, start: number) {
  const t = (frame - start) / FPS;
  if (t <= 0) return 0;
  const hinge = (u: number) => namedProgress(Math.round(u * FPS), 0, 1.6, 1);
  if (t < 1.5) return 0.9 * hinge(t);
  if (t < 2.4) return 0.9;
  if (t < 3.6) return 0.9 * (1 - hinge(t - 2.4));
  return 0;
}
/** .lid { transform: rotateX(calc(var(--lid) * -62deg)) } */
export const LID_DEGREES = -62;

/** FoldSpring：临界阻尼，频率 5.83/0.2；触发 0.18，满程 0.86。按帧积分，闭式解与 app.js 相同。 */
export function foldSeries(frames: number, lidAt: (f: number) => number) {
  const frequency = 5.83 / 0.2, trigger = 0.18, full = 0.86;
  const out = new Float64Array(frames);
  let e = 0, v = 0;
  for (let f = 0; f < frames; f++) {
    const goal = clamp01((lidAt(f) - trigger) / (full - trigger));
    const dt = f === 0 ? 0 : DT;
    const offset = e - goal, decay = Math.exp(-frequency * dt), slope = v + frequency * offset;
    e = goal + (offset + slope * dt) * decay;
    v = (slope - frequency * (offset + slope * dt)) * decay;
    out[f] = clamp01(e);
  }
  return out;
}

/** shade 预设的玻璃投影（focal 2.254、angle 0.45、defocus 0.12、dim 15、base 0.012），换成像素的 matrix3d。 */
export const SHADE = { focal: 2.254, defocus: 0.12, dim: 15, base: 0.012, angle: 0.45 };
export function shadeFold(amount: number, w: number, h: number) {
  const o = SHADE;
  const s = Math.sin(amount * o.angle), c = Math.cos(amount * o.angle), f = o.focal;
  const g = [f, 0.5 * s, -0.5 * s, 0, 0.5 * s + c * f, f - 0.5 * s - c * f, 0, s, f - s];
  const det = g[0] * (g[4] * g[8] - g[5] * g[7]) - g[1] * (g[3] * g[8] - g[5] * g[6]) + g[2] * (g[3] * g[7] - g[4] * g[6]);
  const m = [
    g[4] * g[8] - g[5] * g[7], g[2] * g[7] - g[1] * g[8], g[1] * g[5] - g[2] * g[4],
    g[5] * g[6] - g[3] * g[8], g[0] * g[8] - g[2] * g[6], g[2] * g[3] - g[0] * g[5],
    g[3] * g[7] - g[4] * g[6], g[1] * g[6] - g[0] * g[7], g[0] * g[4] - g[1] * g[3],
  ].map((x) => x / det);
  const n = (x: number) => +x.toFixed(6);
  const matrix = `matrix3d(${n(m[0])},${n((m[3] * h) / w)},0,${n(m[6] / w)},${n((m[1] * w) / h)},${n(m[4])},0,${n(m[7] / h)},0,0,1,0,${n(m[2] * w)},${n(m[5] * h)},0,${n(m[8])})`;
  const radius = (d: number) => o.defocus * (d * s + o.base * amount);
  return {
    matrix,
    blurTop: radius(1) * h * 0.6,
    shadeTop: Math.min(1, o.dim * radius(1)),
    shadeHinge: Math.min(1, o.dim * radius(0)),
  };
}

// ---- site/app.js 侧拉：glide 0.42 / 0.88，带着松手速度。残差落到 0.004 才停在终点。 ----
export const SLIDE_FRAMES = Math.round(1.6 * FPS);
export function slideSpring(frame: number, start: number, v0 = 0) {
  const t = (frame - start) / FPS;
  if (t <= 0) return 0;
  const p = namedProgress(frame, start, 0.42, 0.88, v0);
  if (Math.abs(1 - p) <= 0.004 || t >= 1.6) return 1;
  return p;
}

// ---- site/teach.js：一笔的节奏、移动曲线、窗口落定的弹簧 ----
export const TEACH = { appear: 400, settle: 200, press: 190, dwell: 500, move: 1000, lift: 220, hold: 1100, fade: 380, empty: 420, flick: 280, flickHold: 1300, flickLead: 140 };
export const ms = (v: number) => Math.round((v / 1000) * FPS);
export const moveCurve = bezier(0.32, 0, 0.67, 1);
export const easeIn = (p: number) => p * p * p;
export function teachSpring(msSince: number, z: number, r: number, v = 0) {
  const t = msSince / 1000;
  if (t <= 0) return 0;
  const w = (2 * Math.PI) / r;
  if (z < 1) {
    const wd = w * Math.sqrt(1 - z * z);
    return 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + ((z * w - v) / wd) * Math.sin(wd * t));
  }
  return 1 - (1 + (w - v) * t) * Math.exp(-w * t);
}
/** 位置 0.88 / 0.42，尺寸 1 / 0.38（teach.js，取自 FlickMotion.swift）。 */
export const teachPos = (msSince: number, v = 0) => teachSpring(msSince, 0.88, 0.42, v);
export const teachSize = (msSince: number) => teachSpring(msSince, 1, 0.38);
/** teach.js 侧拉的两处：靠边 DOCKED、收到边外 TUCKED（x 按屏宽 %，y 按屏高 %）。 */
export const TEACH_DOCKED = { x: 1.2, y: 8.6 + 1.9, w: 31, h: 87.5 - 1.9 - (8.6 + 1.9) };
export const TEACH_TUCKED = { ...TEACH_DOCKED, x: -TEACH_DOCKED.w + 0.7 };
export const TEACH_HANDLE = { x: 1.6, y: 46 };
