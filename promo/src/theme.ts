import { interpolate } from "remotion";
import { FPS } from "./timeline";

// 位移走命名弹簧的闭式解：response（秒）、阻尼比 ζ。质量 1。
// 淡入淡出才用平滑阶梯，不把路程套进贝塞尔。
const TOKENS = {
  calm: [0.34, 1],
  settle: [0.38, 1],
  expand: [0.4, 0.92],
  bloom: [0.42, 0.84],
  glide: [0.42, 0.88],
  flyOut: [0.38, 0.9],
  pull: [0.36, 0.86],
  pop: [0.3, 0.75],
  dolly: [1.6, 1],
} as const;
export type SpringName = keyof typeof TOKENS;

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

/** 0→1，从第 at 帧起。不另给一段时长。 */
export const motion = (frame: number, at: number, name: SpringName) => {
  const t = (frame - at) / FPS;
  const [response, zeta] = TOKENS[name];
  if (t <= 0) return 0;
  const p = 1 + solve(-1, 0, response, zeta, t)[0];
  return p < 0 ? 0 : p;
};

// Same palette as the website, so the film and the site read as one product.
export const C = {
  canvas: "#f4f5f7",
  dot: "rgba(20,26,38,.07)",
  ink: "#16181c",
  muted: "#6b7079",
  faint: "#9aa0a9",
  accent: "#245eea",
  black: "#0a0b0d",
  win: "#ffffff",
  bar: "#f5f5f7",
  winInk: "#24262b",
  winMuted: "#70747c",
  line: "rgba(0,0,0,.08)",
  blueSoft: "#e9effc",
  blueText: "#214884",
  wall: "radial-gradient(120% 90% at 0% 0%,#c9dbff 0%,transparent 58%),radial-gradient(90% 80% at 100% 0%,#f1d9ee 0%,transparent 62%),radial-gradient(120% 90% at 70% 110%,#ffe3c9 0%,transparent 62%),#e7eaf3",
};

export const FONT = '-apple-system, "SF Pro Display", "PingFang SC", "Helvetica Neue", sans-serif';
export const MONO = '"SF Mono", Menlo, "PingFang SC", monospace';
export const SERIF = '"Iowan Old Style", "Songti SC", STSong, serif';

/** 淡入淡出：平滑阶梯。位移不要用它。 */
export const easeOut = (p: number) => {
  const t = Math.min(1, Math.max(0, p));
  return t * t * (3 - 2 * t);
};
export const easeInOut = easeOut;
export const easeRoll = easeOut;

/** Clamped interpolate between two frames. */
export const tw = (frame: number, from: number, to: number, a = 0, b = 1, easing: (t: number) => number = easeOut) =>
  interpolate(frame, [from, to], [a, b], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing,
  });

/** 小元素确认：pop，0.30 秒、ζ 0.75，从 0.9 收到 1 由调用处决定起点。 */
export const pop = (frame: number, at: number) => motion(frame, at, "pop");

/** 尺寸变化，不回弹。 */
export const settle = (frame: number, at: number) => motion(frame, at, "settle");

export const mix = (a: number, b: number, t: number) => a + (b - a) * t;
