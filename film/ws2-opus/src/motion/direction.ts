// docs/motion-direction.md §2.2 的节拍与镜头弹簧。不是官网的数字，单独放，表里也单独标。
import { FPS } from './site';

const f = (s: number) => Math.round(s * FPS);

/** 先等一拍：宽限 W 0.8 秒 + 事后检查 P 0.3 秒。只用在外面的事引起的开口；手直接碰到刘海时不等。 */
export const BEAT = f(0.8 + 0.3);
/** fade：入 0.18、出 0.10。 */
export const FADE_IN = f(0.18);
export const FADE_OUT = f(0.1);
/** exit.gap：内容开始淡出后 0.04 秒，形状开始收。 */
export const EXIT_GAP = f(0.04);
/** content.at：形状走到 40% 时第一层内容进场；content.step：第二层再晚 0.2 秒。 */
export const CONTENT_AT = 0.4;
export const CONTENT_STEP = f(0.2);
/** 片子叠化 0.5 秒。 */
export const CROSSFADE = f(0.5);
/** 片子屏外字幕：淡入 0.2、淡出 0.1，不位移。 */
export const CAPTION_IN = f(0.2);
export const CAPTION_OUT = f(0.1);

/** dolly：response 1.6、ζ 1.0，只给镜头。 */
export function dolly(frame: number, start: number) {
  const t = (frame - start) / FPS;
  if (t <= 0) return 0;
  const w = (2 * Math.PI) / 1.6;
  return Math.min(1, 1 - (1 + w * t) * Math.exp(-w * t));
}
