// 官网动画的数字，原样搬过来，改成只看帧号。每一段都注明出处；没有出处的数字不放在这里。
// 島的彈簧改走動效樣片的命名彈簧（springs.ts），不再用官網那組 0.96/0.38。
// dt 固定 1/60。
import { approach, SPRING, type SpringName } from './springs';

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

// ---- 島的寬、高、底角、肩（單位 cqw，屏寬的百分之一） ----
// 畫面以動效樣片為準：HW = 312×56 px、底角 18.2、肩 8.6，畫在 2880 寬的 15 吋面板上（K = 1.684 → 185.3×33.3 pt）。
// 1710 pt 邏輯寬是同一塊屏。書面 10.63%×1.91%（Product Bezels 306×55）讓給這張稿的輪廓。
/** pt → cqw。15 吋 Air 預設模式寬 1710 pt。 */
export const pt = (n: number) => (n / 1710) * 100;

// 寬 312、深 56 與網格洞一致。肩 9.9、底角 18.5 是網格折線擬合的相切圓，不是舊的 8.6 / 18.2。
// 出處：public/mesh/macbook-air-15in-silver.glb 的顯示網格 OQzaQDtbMVhhlAr，見 notchPath.ts。
export const NOTCH = {
  w: (312 / 2880) * 100,
  h: (56 / 2880) * 100,
  rb: (18.5 / 2880) * 100,
  rs: (9.9 / 2880) * 100,
};
/** 舊欄位：底角。肩另計。 */
export const NOTCH_R = NOTCH.rb;

export type IslandShape = { w: number; h: number; rb: number; rs: number };

// 大小照 design-system §5.1 的表，和樣片 M3 的像素對得上的地方用稿（展開一排 700×295 px、底角 47.2 px）。
// 落點：Notch.swift dropZone 是劉海正下方 340×84 pt，圓角 island.drop = 22，不畫肩。
export const ISLAND_SHAPES = {
  rest: { w: NOTCH.w, h: NOTCH.h, rb: NOTCH.rb, rs: NOTCH.rs },
  // Compact：尽量窄、贴紧洞（WWDC23 10194）
  compact: { w: NOTCH.w + 2 * pt(28), h: NOTCH.h, rb: pt(12), rs: NOTCH.rs },
  // Expanded／半岛：同心厚圆角，高度够排两行，忌空额头
  alert: { w: pt(388), h: NOTCH.h + pt(56), rb: pt(26), rs: 0 },
  shelf: { w: (700 / 2880) * 100, h: (295 / 2880) * 100, rb: (47.2 / 2880) * 100, rs: 0 },
  full: { w: 100, h: (100 * 1864) / 2880, rb: pt(16), rs: 0 },
  drop: { w: pt(340), h: NOTCH.h + pt(84), rb: pt(22), rs: 0 },
  ask: { w: pt(420), h: NOTCH.h + pt(86), rb: pt(24), rs: 0 },
  digest: { w: pt(380), h: NOTCH.h + pt(118), rb: pt(24), rs: 0 },
} as const satisfies Record<string, IslandShape>;
export type IslandMode = keyof typeof ISLAND_SHAPES;

/** 進場用這個狀態自己的彈簧；收到更小的狀態（compact / rest）走 calm，不回彈。 */
export function islandSpring(mode: IslandMode): SpringName {
  switch (mode) {
    case 'shelf':
    case 'full':
      return 'expand';
    case 'alert':
    case 'ask':
    case 'digest':
      return 'bloom';
    case 'drop':
      return 'catch';
    default:
      return 'calm';
  }
}

export const islandTuning = (mode: IslandMode) => {
  const [response, damping] = SPRING[islandSpring(mode)];
  return { damping, response };
};

/**
 * 窗口完全擋進劉海的那一幀，島用 calm 加一腳初速度鼓一下。
 * 樣片 M3：bw.kick(700×K px/s)、bh.kick(300×K)。K = 1.684，屏寬 2880 px → cqw/s。
 */
export const TUCK_KICK = { w: (700 * 1.684 / 2880) * 100, h: (300 * 1.684 / 2880) * 100 };
/** 提醒停 2.6 秒；island.js 在 2620ms 时重新取目标。 */
export const ALERT_HOLD = Math.round(2.62 * FPS);
/** 指针停 120ms 才展开成一排。樣片 M3：停 0.12 s 再 expand。 */
export const HOVER_DELAY = Math.round(0.12 * FPS);

/** settle 收到 0.1% 約 0.56 秒（motion-direction 表）。飛行用這根，不用貝塞爾。 */
export const TUCK_FRAMES = 0.56 * FPS;
/** 擋進劉海、鼓一下的時刻：settle 走到大約沒入的時候，比停穩早。 */
export const TUCK_COVER = Math.round(0.22 * FPS);
/** 松手時已經在往劉海走。樣片 M3 的 vy 約 −2600 px/s，行程約 440 px → 約 6 個全程/秒。取 4，避免臨界阻尼帶著初速度衝過頭頂。 */
const TUCK_V0 = 4;
export function tuckProgress(frame: number, start: number) {
  return approach(((frame - start) / FPS) * 1000, 'settle', TUCK_V0);
}
/** 放回：flyOut（0.38 / 0.90）。1 是還在劉海里，0 是回到原處。 */
export function untuckProgress(frame: number, start: number) {
  return 1 - approach(((frame - start) / FPS) * 1000, 'flyOut');
}

// ---- site/app.js：开盖播放与合盖的折叠 ----
const easeInOutCubic = (x: number) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
/** play()：1.5 秒合到 0.9，停到 2.4 秒，1.2 秒打开。0 是开着。 */
export const LID_PLAY_FRAMES = Math.round(3.6 * FPS);
export function lidPlay(frame: number, start: number) {
  const t = (frame - start) / FPS;
  if (t <= 0) return 0;
  if (t < 1.5) return 0.9 * easeInOutCubic(t / 1.5);
  if (t < 2.4) return 0.9;
  if (t < 3.6) return 0.9 * (1 - easeInOutCubic((t - 2.4) / 1.2));
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

// ---- site/app.js 侧拉：响应 0.42、阻尼 0.88，带上松手时的速度；1.1 秒后停住 ----
export const SLIDE_FRAMES = Math.round(1.1 * FPS);
export function slideSpring(frame: number, start: number, v0 = 0) {
  const t = (frame - start) / FPS;
  if (t <= 0) return 0;
  if (t >= 1.1) return 1;
  const w = (2 * Math.PI) / 0.42, z = 0.88, wd = w * Math.sqrt(1 - z * z);
  return 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + ((z * w - v0) / wd) * Math.sin(wd * t));
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
