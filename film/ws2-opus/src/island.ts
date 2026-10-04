// 整条片子只有一个岛。从第 0 帧按 site/island.js 的积分一帧一帧推到最后一帧，结果按帧号查。
import { CONTENT_AT, CONTENT_STEP, EXIT_GAP, FADE_IN, FADE_OUT } from './motion/direction';
import { DT, ISLAND_SHAPES, NOTCH, TUCK_KICK, clamp01, islandTuning, solve, type IslandMode } from './motion/site';
import { ISLAND_EVENTS, KICKS, TOTAL, type Content } from './timeline';

type Spring = { value: number; target: number; velocity: number; response: number; zeta: number };
const spring = (v: number): Spring => ({ value: v, target: v, velocity: 0, response: 0.34, zeta: 1 });
function tune(s: Spring, zeta: number, response: number) {
  s.zeta = zeta;
  s.response = response;
}
function step(s: Spring) {
  const [d, v] = solve(s.value - s.target, s.velocity, s.response, s.zeta, DT);
  s.value = s.target + d;
  s.velocity = v;
}
const resting = (s: Spring) => Math.abs(s.value - s.target) < 0.05 && Math.abs(s.velocity) < 0.5;

export type IslandFrame = { w: number; h: number; r: number; mode: IslandMode };
export type ContentLayer = { content: Content; first: number; second: number; since: number };

const W = new Float64Array(TOTAL), H = new Float64Array(TOTAL), R = new Float64Array(TOTAL);
const MODE: IslandMode[] = new Array(TOTAL);

// 每次换目标的帧与起点，用来找“形状走到 40%”的那一帧。
const retargets: { frame: number; from: { w: number; h: number }; to: IslandMode }[] = [];

(function simulate() {
  const shape = { w: spring(NOTCH.w), h: spring(NOTCH.h), r: spring(NOTCH.r) };
  for (const s of Object.values(shape)) tune(s, 1, 0.34);
  let mode: IslandMode = 'rest';
  const changes = new Map<number, IslandMode>();
  {
    let m: IslandMode = 'rest';
    for (const e of ISLAND_EVENTS) {
      if (e.mode !== m) changes.set(e.at + EXIT_GAP, e.mode);
      m = e.mode;
    }
  }
  const kicks = new Set(KICKS);
  for (let f = 0; f < TOTAL; f++) {
    const next = changes.get(f);
    if (next && next !== mode) {
      retargets.push({ frame: f, from: { w: shape.w.value, h: shape.h.value }, to: next });
      const { damping, response } = islandTuning(next);
      for (const key of ['w', 'h', 'r'] as const) {
        shape[key].target = ISLAND_SHAPES[next][key];
        tune(shape[key], damping, response);
      }
      mode = next;
    }
    if (kicks.has(f)) {
      shape.w.velocity += TUCK_KICK.w;
      shape.h.velocity += TUCK_KICK.h;
    }
    step(shape.w); step(shape.h); step(shape.r);
    if (resting(shape.w) && resting(shape.h) && resting(shape.r)) {
      for (const s of Object.values(shape)) { s.value = s.target; s.velocity = 0; }
    }
    W[f] = shape.w.value; H[f] = shape.h.value; R[f] = Math.max(0, shape.r.value); MODE[f] = mode;
  }
})();

function fortyPercentFrame(after: number): number {
  const rt = retargets.find((r) => r.frame >= after && r.frame <= after + EXIT_GAP + 1);
  if (!rt) return after + FADE_OUT;
  const to = ISLAND_SHAPES[rt.to];
  for (let f = rt.frame; f < TOTAL; f++) {
    const parts: number[] = [];
    if (Math.abs(to.w - rt.from.w) > 0.01) parts.push((W[f] - rt.from.w) / (to.w - rt.from.w));
    if (Math.abs(to.h - rt.from.h) > 0.01) parts.push((H[f] - rt.from.h) / (to.h - rt.from.h));
    if (!parts.length || Math.min(...parts) >= CONTENT_AT) return f;
  }
  return rt.frame;
}

const LAYERS = ISLAND_EVENTS.map((e, i) => ({
  content: e.content,
  inStart: e.inAt ?? fortyPercentFrame(e.at),
  outStart: i + 1 < ISLAND_EVENTS.length ? ISLAND_EVENTS[i + 1].at : TOTAL,
}));

/** 每个事件的内容实际进场帧，给说明文档和检查用。 */
export const CONTENT_IN = LAYERS.map((l) => l.inStart);

export function islandAt(frame: number): IslandFrame {
  const f = Math.max(0, Math.min(TOTAL - 1, Math.floor(frame)));
  return { w: W[f], h: H[f], r: R[f], mode: MODE[f] };
}

export function layersAt(frame: number): ContentLayer[] {
  const out: ContentLayer[] = [];
  for (const l of LAYERS) {
    if (l.content === 'none') continue;
    const fade = (p: number) => { const t = clamp01(p); return t * t * (3 - 2 * t); };
    const fadeOut = 1 - fade((frame - l.outStart) / FADE_OUT);
    const first = fade((frame - l.inStart) / FADE_IN) * fadeOut;
    const second = fade((frame - l.inStart - CONTENT_STEP) / FADE_IN) * fadeOut;
    if (first > 0 || second > 0) out.push({ content: l.content, first, second, since: frame - l.inStart });
  }
  return out;
}
