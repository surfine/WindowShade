// 片子时间 τ → 故事时间 t。动作段整体快 BASE 倍（等于所有弹簧变硬、指针变快）；
// 落定之后的空档（DEAD）再快一截，下一拍在上一拍落定时就接上。倍率在 0.18 秒里平滑过渡，
// 而且只在东西几乎不动的地方换挡，所以不会在运动中途出现折角。
import { FPS } from './motion';

const BASE = 1.03;
/** [故事起, 故事止, 倍率]：这些段里画面已经落定或只剩收尾。 */
const DEAD: [number, number, number][] = [
  [1.85, 2.6, 1.9],
  [9.0, 11.2, 2.4],
  [14.4, 15.0, 1.8],
  [16.8, 17.6, 1.5],
  [21.8, 22.8, 1.3],
  [26.7, 28.3, 1.7],
  [31.8, 32.4, 1.4],
  [37.6, 40.0, 2.4],
];
/** 故事结束：字标 42.6 秒进，落定后停 1 秒多就收（片尾不拖）。 */
export const STORY_END = 44.9;
const RAMP = 0.18;

function rate(t: number) {
  let r = BASE;
  for (const [a, b, k] of DEAD) {
    const w = Math.max(0, Math.min(1, (t - a) / RAMP, (b - t) / RAMP));
    if (w > 0) r = Math.max(r, BASE + (k - BASE) * w);
  }
  if (t > 43.2) r = BASE + (1 - BASE) * Math.min(1, (t - 43.2) / RAMP); // 片尾回到 1 倍
  return r;
}

const DT = 1 / 960;
const TAB: number[] = (() => {
  // TAB[i] = 故事时间 i·DT 对应的片子时间
  const out = [0];
  let tau = 0;
  for (let i = 1; i * DT <= STORY_END + 1e-9; i++) {
    const t = (i - 0.5) * DT;
    tau += DT / rate(t);
    out.push(tau);
  }
  return out;
})();

/** 故事时间 → 片子时间（秒）。 */
export function filmOf(t: number) {
  const x = Math.max(0, Math.min(TAB.length - 1, t / DT));
  const i = Math.floor(x), f = x - i;
  return i + 1 < TAB.length ? TAB[i] + (TAB[i + 1] - TAB[i]) * f : TAB[i];
}
export const FILM_LEN = TAB[TAB.length - 1];
export const FILM_FRAMES = Math.ceil(FILM_LEN * FPS);

/** 片子时间 → 故事时间。 */
export function storyOf(tau: number) {
  let lo = 0, hi = TAB.length - 1;
  if (tau >= TAB[hi]) return STORY_END;
  while (hi - lo > 1) {
    const m = (lo + hi) >> 1;
    if (TAB[m] <= tau) lo = m;
    else hi = m;
  }
  const f = (tau - TAB[lo]) / (TAB[hi] - TAB[lo] || 1);
  return (lo + f) * DT;
}
