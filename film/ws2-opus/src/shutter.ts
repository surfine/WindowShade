// 快門：鏡頭在動，或窗口正在飛的時候多取幾樣。180° 快門，樣數跟速度走。
import { cameraSpeed } from './camera';
import { LANDSCAPE } from './layout';
import { TUCK_A, TUCK_B, UNTUCK_A, UNTUCK_C, DROP_RELEASE } from './timeline';
import { TUCK_FRAMES } from './motion/site';
import { outOf } from './cut';

function covers(src: number) {
  try {
    return outOf(src);
  } catch {
    return -1;
  }
}

const FAST: [number, number][] = [
  [TUCK_A, TUCK_A + TUCK_FRAMES],
  [UNTUCK_A, UNTUCK_A + TUCK_FRAMES],
  [TUCK_B, TUCK_B + TUCK_FRAMES],
  [DROP_RELEASE, DROP_RELEASE + 40],
  [UNTUCK_C, UNTUCK_C + TUCK_FRAMES],
].map(([a, b]) => [covers(a), covers(b)] as [number, number]).filter(([a]) => a >= 0);

export function shutterSamples(out: number): number {
  const v = cameraSpeed(out, LANDSCAPE);
  let n = v > 36 ? Math.min(8, Math.max(3, Math.round(v / 22))) : 1;
  for (const [a, b] of FAST) if (out >= a && out <= b) n = Math.max(n, 6);
  return n;
}

export const SHUTTER_FRAMES = 0;
