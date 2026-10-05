// promo/src/theme.ts 的具名弹簧（闭式解，response 秒、阻尼比 ζ、质量 1）。位移只走它们；淡入淡出才用平滑阶梯。
import { FPS } from './cues';

const TOKENS = {
  calm: [0.34, 1],
  settle: [0.38, 1],
  expand: [0.4, 0.92],
  bloom: [0.42, 0.84],
  catch: [0.4, 0.8],
  glide: [0.42, 0.88],
  flyOut: [0.38, 0.9],
  pull: [0.36, 0.86],
  pop: [0.3, 0.75],
  dolly: [1.6, 1],
} as const;
export type SpringName = keyof typeof TOKENS;

function solve(d0: number, v0: number, response: number, zeta: number, t: number): number {
  const w = (2 * Math.PI) / response;
  if (zeta < 1) {
    const wd = w * Math.sqrt(1 - zeta * zeta);
    const e = Math.exp(-zeta * w * t);
    const b = (v0 + zeta * w * d0) / wd;
    return e * (d0 * Math.cos(wd * t) + b * Math.sin(wd * t));
  }
  const e = Math.exp(-w * t);
  return (d0 + (v0 + w * d0) * t) * e;
}

/** 0→1，从第 at 帧起。 */
export const motion = (frame: number, at: number, name: SpringName) => {
  const t = (frame - at) / FPS;
  if (t <= 0) return 0;
  const [response, zeta] = TOKENS[name];
  const p = 1 + solve(-1, 0, response, zeta, t);
  return p < 0 ? 0 : p;
};
