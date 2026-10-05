// 安靜的劉海 动效样片.html 的求解器，原樣搬過來。
// SP 表在那份稿約第 496 行；質量 1，ω = 2π/response，ζ 是阻尼比。換目標時保留位置和速度。
// bounce = 1 − ζ。稿面：expand 0.40/0.92（bounce 0.08），calm 0.34/1（bounce 0），bloom 0.42/0.84（bounce 0.16）。

export const SPRING = {
  calm: [0.34, 1],
  settle: [0.38, 1],
  expand: [0.4, 0.92],
  bloom: [0.42, 0.84],
  catch: [0.4, 0.8],
  glide: [0.42, 0.88],
  flyOut: [0.38, 0.9],
  pull: [0.36, 0.86],
  pop: [0.3, 0.75],
  reduced: [0.25, 1],
  dolly: [1.6, 1],
} as const;

export type SpringName = keyof typeof SPRING;
export type SpringPair = readonly [number, number];

/** 位移 d0、速度 v0，過了 t 秒之後的 [位移, 速度]。 */
export function solve(d0: number, v0: number, s: SpringPair, t: number): [number, number] {
  if (t <= 0) return [d0, v0];
  const w = (2 * Math.PI) / s[0];
  const z = s[1];
  if (z < 1) {
    const wd = w * Math.sqrt(1 - z * z);
    const e = Math.exp(-z * w * t);
    const c = Math.cos(wd * t);
    const n = Math.sin(wd * t);
    const B = (v0 + z * w * d0) / wd;
    const d = e * (d0 * c + B * n);
    return [d, -z * w * d + e * wd * (B * c - d0 * n)];
  }
  if (z === 1) {
    const e = Math.exp(-w * t);
    const C = v0 + w * d0;
    return [(d0 + C * t) * e, (C - w * (d0 + C * t)) * e];
  }
  const q = Math.sqrt(z * z - 1);
  const a = -w * (z - q);
  const b = -w * (z + q);
  const C2 = (v0 - a * d0) / (b - a);
  const C1 = d0 - C2;
  return [C1 * Math.exp(a * t) + C2 * Math.exp(b * t), C1 * a * Math.exp(a * t) + C2 * b * Math.exp(b * t)];
}

/** 從 0 走向 1。v0 單位是「每秒多少個全程」，正值表示松手時已經在往目標走。 */
export function approach(ms: number, name: SpringName, v0 = 0) {
  if (ms <= 0) return 0;
  const [d] = solve(-1, v0, SPRING[name], ms / 1000);
  return 1 + d;
}
