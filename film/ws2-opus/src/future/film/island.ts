// 岛的宽、高、圆角各一根弹簧（屏幕点）。弹簧照 prototype/App/Notch.swift：
// 认证 0.28 / 0.98，提醒 bloom 0.42 / 0.84，展开 0.40 / 0.92，收回 calm 0.34 / 1.0。
// Air 停着就是实体刘海；Neo 停着是 0（什么都不画），要用时才长出一颗胶囊。
import { FPS, SEGS, T, TOTAL } from './cues';
import { MACHINES, type MachineId } from './machines';

type Shape = { w: number; h: number; r: number };
const N_ = MACHINES.air.notch!;

export const SHAPES: Record<MachineId, Record<string, Shape>> = {
  neo: {
    rest: { w: 0, h: 0, r: 0 },
    hover: { w: 80, h: 18, r: 9 },
    face: { w: 132, h: 132, r: 40 },
    row: { w: 400, h: 92, r: 32 },
    alert: { w: 380, h: 84, r: 30 },
    // 番茄钟：照设计稿（cqw × 14.08 点）
    pomoIdle: { w: 620, h: 118, r: 31 },
    pomo: { w: 310, h: 51, r: 25.5 },
    pomoAlert: { w: 479, h: 90, r: 32 },
    breath: { w: 422, h: 239, r: 48 },
  },
  air: {
    rest: N_,
    compact: { w: N_.w + 2 * 46, h: N_.h, r: 10 },
    face: { w: 236, h: 222, r: 46 },
    alert: { w: 404, h: 96, r: 28 },
    row: { w: 470, h: 112, r: 30 },
  },
};

const TUNE = { auth: [0.98, 0.28], bloom: [0.84, 0.42], expand: [0.92, 0.4], calm: [1, 0.34] } as const;
type Tune = keyof typeof TUNE;
type Ev = [number, string, Tune, number?];

/** 每段里岛换目标的时刻：[帧, 形状, 弹簧, 鼓一下的初速度（点/秒）]。每段第一条是起点，直接到位。 */
const EVENTS: Record<string, Ev[]> = {
  wake: [[0, 'rest', 'calm'], [T.faceOn, 'face', 'auth']],
  home: [[600, 'rest', 'calm'], [T.tap, 'rest', 'calm', 520], [T.lpClose, 'rest', 'calm', 380], [T.listenPre, 'row', 'bloom']],
  lips: [[1080, 'row', 'calm'], [T.rest, 'rest', 'calm'], [T.ride, 'alert', 'bloom']],
  live: [[1800, 'compact', 'calm'], [T.rideOpen, 'alert', 'bloom'], [T.rideClose, 'compact', 'calm'], [T.foodOpen, 'alert', 'bloom'], [T.foodClose, 'compact', 'calm'], [T.livePre, 'row', 'bloom']],
  pomo: [[2280, 'pomoIdle', 'calm'], [T.pomoTap, 'pomo', 'expand'], [T.restAlert, 'pomoAlert', 'bloom'], [T.away, 'breath', 'expand'], [T.back, 'pomo', 'calm'], [T.pomoPre, 'face', 'bloom']],
  away: [[2880, 'face', 'calm'], [T.ticks[0] - 10, 'compact', 'calm'], [T.lock - 12, 'face', 'auth'], [3240, 'rest', 'calm']],
  end: [[3240, 'rest', 'calm']],
};

function step(x: number, v: number, goal: number, z: number, response: number, dt: number): [number, number] {
  const w = (2 * Math.PI) / response;
  const e = x - goal;
  if (z >= 1) {
    const decay = Math.exp(-w * dt), slope = v + w * e;
    return [goal + (e + slope * dt) * decay, (slope - w * (e + slope * dt)) * decay];
  }
  const wd = w * Math.sqrt(1 - z * z), a = z * w;
  const c = Math.cos(wd * dt), s = Math.sin(wd * dt), decay = Math.exp(-a * dt);
  const B = (v + a * e) / wd;
  const nx = decay * (e * c + B * s);
  return [goal + nx, decay * (-a * (e * c + B * s) + (-e * wd * s + B * wd * c))];
}

const N = TOTAL + 2;
const W = new Float64Array(N), H = new Float64Array(N), R = new Float64Array(N);
const NAME = new Array<string>(N);
for (const sg of SEGS) {
  const m: MachineId = sg.m === 'both' ? 'air' : sg.m;
  const evs = EVENTS[sg.id];
  let cur = evs[0];
  let { w, h, r } = SHAPES[m][cur[1]];
  let vw = 0, vh = 0, vr = 0;
  const end = Math.min(N, sg.to + 1);
  for (let f = sg.from; f < end; f++) {
    for (const ev of evs) if (ev[0] === f && ev !== evs[0]) { cur = ev; if (ev[3]) { vw += ev[3]; vh += ev[3] * 0.29; } }
    if (f > sg.from) {
      const [z, resp] = TUNE[cur[2]], g = SHAPES[m][cur[1]], dt = 1 / FPS;
      [w, vw] = step(w, vw, g.w, z, resp, dt);
      [h, vh] = step(h, vh, g.h, z, resp, dt);
      [r, vr] = step(r, vr, g.r, z, resp, dt);
    }
    if (f < N) { W[f] = Math.max(0, w); H[f] = Math.max(0, h); R[f] = Math.max(0, r); NAME[f] = cur[1]; }
  }
}

/** 帧之间线性插值（快门在一帧里取好几个时刻）。 */
export function islandAt(f: number) {
  const a = Math.max(0, Math.min(N - 2, Math.floor(f))), u = Math.max(0, Math.min(1, f - a));
  const l = (x: Float64Array) => x[a] + (x[a + 1] - x[a]) * u;
  return { w: l(W), h: l(H), r: l(R), name: NAME[a] };
}

/** 岛在屏幕上的位置（点）：Air 贴着顶边从刘海长出来，Neo 浮在顶边下 4 点。 */
export function islandRect(m: MachineId, f: number) {
  const s = islandAt(f), P = MACHINES[m].pt;
  const top = m === 'air' ? 0 : 4;
  return { x: (P.w - s.w) / 2, y: top, w: s.w, h: s.h, r: Math.min(s.r, s.h / 2, s.w / 2) };
}
