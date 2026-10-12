// 数字跟官网同一套：site/app.js 的开盖与侧拉，site/island.js 的岛。
// 每一帧只由帧号决定。dt 固定 1/60，不读墙上的钟。

export const FPS = 60;
export const SITE_FRAMES = 2100;

const DT = 1 / FPS;

export function easeInOutCubic(x: number) {
  const t = Math.min(1, Math.max(0, x));
  return t < 0.5 ? 4 * t * t * t : 1 - ((-2 * t + 2) ** 3) / 2;
}

/** site/app.js play()：1.5 秒开到 0.9，停到 2.4，1.2 秒合上。 */
export function lidOpen(frame: number) {
  const t = frame / FPS;
  if (t < 1.5) return 0.9 * easeInOutCubic(t / 1.5);
  if (t < 2.4) return 0.9;
  if (t < 3.6) return 0.9 * (1 - easeInOutCubic((t - 2.4) / 1.2));
  return 0;
}

/** FoldSpring：约 0.2 秒收到 2%。临界阻尼，频率 5.83/0.2。触发点 0.18，满程 0.86。 */
export function foldAmount(frame: number) {
  const frequency = 5.83 / 0.2;
  const trigger = 0.18;
  const span = 0.86 - trigger;
  let e = 0;
  let v = 0;
  for (let i = 0; i <= frame; i++) {
    const lid = lidOpen(i);
    const goal = Math.min(1, Math.max(0, (lid - trigger) / span));
    const offset = e - goal;
    const decay = Math.exp(-frequency * DT);
    const slope = v + frequency * offset;
    e = goal + (offset + slope * DT) * decay;
    v = (slope - frequency * (offset + slope * DT)) * decay;
  }
  return Math.min(1, Math.max(0, e));
}

/** site/app.js shade 预设的玻璃投影。返回 CSS matrix3d 的 16 个数。 */
export function shadeMatrix(amount: number) {
  const focal = 2.254;
  const angle = 0.45;
  const s = Math.sin(amount * angle);
  const c = Math.cos(amount * angle);
  const f = focal;
  const g = [f, 0.5 * s, -0.5 * s, 0, 0.5 * s + c * f, f - 0.5 * s - c * f, 0, s, f - s];
  const det =
    g[0] * (g[4] * g[8] - g[5] * g[7]) -
    g[1] * (g[3] * g[8] - g[5] * g[6]) +
    g[2] * (g[3] * g[7] - g[4] * g[6]);
  const m = [
    g[4] * g[8] - g[5] * g[7],
    g[2] * g[7] - g[1] * g[8],
    g[1] * g[5] - g[2] * g[4],
    g[5] * g[6] - g[3] * g[8],
    g[0] * g[8] - g[2] * g[6],
    g[2] * g[3] - g[0] * g[5],
    g[3] * g[7] - g[4] * g[6],
    g[1] * g[6] - g[0] * g[7],
    g[0] * g[4] - g[1] * g[3],
  ].map((x) => x / det);
  return [m[0], m[3], 0, m[6], m[1], m[4], 0, m[7], 0, 0, 1, 0, m[2], m[5], 0, m[8]];
}

function unitBezierY(x1: number, y1: number, x2: number, y2: number, x: number) {
  const cx = 3 * x1;
  const bx = 3 * (x2 - x1) - cx;
  const ax = 1 - cx - bx;
  const cy = 3 * y1;
  const by = 3 * (y2 - y1) - cy;
  const ay = 1 - cy - by;
  const sampleX = (t: number) => ((ax * t + bx) * t + cx) * t;
  const sampleY = (t: number) => ((ay * t + by) * t + cy) * t;
  const slope = (t: number) => (3 * ax * t + 2 * bx) * t + cx;
  let t = x;
  for (let i = 0; i < 8; i++) {
    const err = sampleX(t) - x;
    const d = slope(t);
    if (Math.abs(err) < 1e-6 || Math.abs(d) < 1e-6) break;
    t -= err / d;
  }
  t = Math.min(1, Math.max(0, t));
  return sampleY(t);
}

/** 官网收进刘海那 520ms：cubic-bezier(.3,.05,.2,1)。 */
export function tuckProgress(frame: number, start: number) {
  const u = (frame - start) / (0.52 * FPS);
  if (u <= 0) return 0;
  if (u >= 1) return 1;
  return unitBezierY(0.3, 0.05, 0.2, 1, u);
}

type Spring = { value: number; target: number; velocity: number; k: number; c: number };

function makeSpring(value: number): Spring {
  const s: Spring = { value, target: value, velocity: 0, k: 1, c: 1 };
  tune(s, 0.96, 0.38);
  return s;
}
function tune(s: Spring, damping: number, response: number) {
  s.k = (2 * Math.PI / response) ** 2;
  s.c = (4 * Math.PI * damping) / response;
}
function stepSpring(s: Spring) {
  const force = -s.k * (s.value - s.target) - s.c * s.velocity;
  s.velocity += force * DT;
  s.value += s.velocity * DT;
}

// 跟 site/island.js 的 cqw 一样：屏宽的百分数。
const NOTCH = { w: 14.5, h: 5.4, r: 1.5 };
const SHAPES = {
  rest: NOTCH,
  compact: { w: NOTCH.w + 2 * 4.6, h: NOTCH.h, r: 1.6 },
  alert: { w: 38, h: NOTCH.h + 8.6, r: 3.6 },
  shelf: { w: 54, h: NOTCH.h + 21, r: 4.2 },
} as const;

export type IslandMode = keyof typeof SHAPES;

type Island = {
  w: number;
  h: number;
  r: number;
  mode: IslandMode;
  tucked: boolean;
  fly: number;
  bulge: boolean;
};

function retarget(shape: Record<'w' | 'h' | 'r', Spring>, mode: IslandMode) {
  const bouncy = mode === 'alert';
  const damping = bouncy ? 0.82 : 0.96;
  const response = bouncy ? 0.42 : 0.38;
  for (const key of ['w', 'h', 'r'] as const) {
    shape[key].target = SHAPES[mode][key];
    tune(shape[key], damping, response);
  }
}

function buildIsland(): Island[] {
  const shape = { w: makeSpring(NOTCH.w), h: makeSpring(NOTCH.h), r: makeSpring(NOTCH.r) };
  let mode: IslandMode = 'rest';
  let tucked = false;
  const tuckStart = 280;
  const flyFrames = Math.round(0.52 * FPS);
  const shelfAt = 700;
  const shelfEnd = 1040;
  const alertAt = 1120;
  const alertEnd = alertAt + Math.round(2.6 * FPS);
  const releaseAt = 1400;
  const out: Island[] = [];
  for (let frame = 0; frame < SITE_FRAMES; frame++) {
    let next: IslandMode = 'rest';
    if (frame >= releaseAt) {
      tucked = false;
      next = 'rest';
    } else if (frame >= tuckStart + flyFrames) {
      tucked = true;
      if (frame >= alertAt && frame < alertEnd) next = 'alert';
      else if (frame >= shelfAt && frame < shelfEnd) next = 'shelf';
      else next = 'compact';
    }
    if (next !== mode) {
      mode = next;
      retarget(shape, mode);
      if (frame === tuckStart + flyFrames) {
        shape.w.velocity += 60;
        shape.h.velocity += 18;
      }
    }
    stepSpring(shape.w);
    stepSpring(shape.h);
    stepSpring(shape.r);
    out.push({
      w: shape.w.value,
      h: shape.h.value,
      r: shape.r.value,
      mode,
      tucked,
      fly: tuckProgress(frame, tuckStart),
      bulge: frame === tuckStart + flyFrames,
    });
  }
  return out;
}

const ISLAND = buildIsland();

export function islandAt(frame: number) {
  const i = Math.min(SITE_FRAMES - 1, Math.max(0, frame));
  return ISLAND[i];
}

/** 侧拉弹簧：response 0.42，阻尼 0.88，初速度 0。1.1 秒后停住。 */
export function slideProgress(frame: number, start: number) {
  const t = (frame - start) / FPS;
  if (t <= 0) return 0;
  if (t >= 1.1) return 1;
  const w = (2 * Math.PI) / 0.42;
  const z = 0.88;
  const wd = w * Math.sqrt(1 - z * z);
  return 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + ((z * w) / wd) * Math.sin(wd * t));
}

export function captionAt(frame: number): string | null {
  if (frame >= 144 && frame < 240) return '合上，桌面还在';
  if (frame >= 280 && frame < 620) return '收进刘海';
  if (frame >= 700 && frame < 1040) return '点一下放回';
  if (frame >= 1560 && frame < 1960) return '靠到屏幕边';
  if (frame >= 1960) return '刘海安静了';
  return null;
}

export const SLIDE_START = 1560;
