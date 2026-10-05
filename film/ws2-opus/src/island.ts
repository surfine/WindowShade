// 整條片子只有一個島。換目標時用動效樣片的閉式彈簧，位置和速度都留下。
import { CONTENT_AT, CONTENT_STEP, EXIT_GAP, FADE_IN, FADE_OUT } from './motion/direction';
import { FPS, ISLAND_SHAPES, NOTCH, TUCK_KICK, clamp01, islandSpring, type IslandMode, type IslandShape } from './motion/site';
import { SPRING, solve, type SpringName } from './motion/springs';
import { ISLAND_EVENTS, KICKS, TOTAL, type Content } from './timeline';

type Chan = { x: number; v: number; to: number; spr: SpringName; t: number };

function sample(c: Chan, frame: number) {
  const [d, v] = solve(c.x - c.to, c.v, SPRING[c.spr], Math.max(0, (frame - c.t) / FPS));
  return { x: c.to + d, v };
}

function retarget(c: Chan, frame: number, to: number, spr: SpringName): Chan {
  const s = sample(c, frame);
  return { x: s.x, v: s.v, to, spr, t: frame };
}

export type IslandFrame = { w: number; h: number; rb: number; rs: number; r: number; mode: IslandMode };
export type ContentLayer = { content: Content; first: number; second: number; since: number };

const W = new Float64Array(TOTAL);
const H = new Float64Array(TOTAL);
const RB = new Float64Array(TOTAL);
const RS = new Float64Array(TOTAL);
const MODE: IslandMode[] = new Array(TOTAL);

const retargets: { frame: number; from: { w: number; h: number }; to: IslandMode }[] = [];

function chan(n: number): Chan {
  return { x: n, v: 0, to: n, spr: 'calm', t: 0 };
}

(function simulate() {
  const shape = { w: chan(NOTCH.w), h: chan(NOTCH.h), rb: chan(NOTCH.rb), rs: chan(NOTCH.rs) };
  let mode: IslandMode = 'rest';
  const changes = new Map<number, IslandMode>();
  {
    let m: IslandMode = 'rest';
    for (const e of ISLAND_EVENTS) {
      if (e.mode !== m) changes.set(e.at + (e.mode === 'rest' || e.mode === 'compact' ? EXIT_GAP : 0), e.mode);
      m = e.mode;
    }
  }
  const kicks = new Set(KICKS);
  for (let f = 0; f < TOTAL; f++) {
    const next = changes.get(f);
    if (next && next !== mode) {
      const now = {
        w: sample(shape.w, f).x,
        h: sample(shape.h, f).x,
      };
      retargets.push({ frame: f, from: now, to: next });
      const spr = islandSpring(next);
      const goal = ISLAND_SHAPES[next];
      (Object.keys(shape) as (keyof IslandShape)[]).forEach((key) => {
        shape[key] = retarget(shape[key], f, goal[key], spr);
      });
      mode = next;
    }
    if (kicks.has(f)) {
      const sw = sample(shape.w, f);
      const sh = sample(shape.h, f);
      shape.w = { ...shape.w, x: sw.x, v: sw.v + TUCK_KICK.w, t: f, spr: 'calm' };
      shape.h = { ...shape.h, x: sh.x, v: sh.v + TUCK_KICK.h, t: f, spr: 'calm' };
    }
    const w = sample(shape.w, f);
    const h = sample(shape.h, f);
    const rb = sample(shape.rb, f);
    const rs = sample(shape.rs, f);
    W[f] = w.x;
    H[f] = Math.max(NOTCH.h * 0.85, h.x);
    RB[f] = Math.max(0, rb.x);
    RS[f] = Math.max(0, rs.x);
    MODE[f] = mode;
  }
})();

function fortyPercentFrame(after: number): number {
  const rt = retargets.find((r) => r.frame >= after && r.frame <= after + EXIT_GAP + 2);
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

export const CONTENT_IN = LAYERS.map((l) => l.inStart);

export function islandAt(frame: number): IslandFrame {
  const f = Math.max(0, Math.min(TOTAL - 1, Math.floor(frame)));
  return { w: W[f], h: H[f], rb: RB[f], rs: RS[f], r: RB[f], mode: MODE[f] };
}

export function layersAt(frame: number): ContentLayer[] {
  const out: ContentLayer[] = [];
  for (const l of LAYERS) {
    if (l.content === 'none') continue;
    const fadeOut = 1 - clamp01((frame - l.outStart) / FADE_OUT);
    const first = clamp01((frame - l.inStart) / FADE_IN) * fadeOut;
    const second = clamp01((frame - l.inStart - CONTENT_STEP) / FADE_IN) * fadeOut;
    if (first > 0 || second > 0) out.push({ content: l.content, first, second, since: frame - l.inStart });
  }
  return out;
}
