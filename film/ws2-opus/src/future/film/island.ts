// 岛的宽、高、圆角各一根弹簧（屏幕点）。弹簧照 prototype/App/Notch.swift：
// 開口 bloom 0.42 / 0.84，展開 expand 0.40 / 0.92，收回 calm 0.34 / 1.0。
// 飛進劉海 settle 0.38 / 1.0，放回 flyOut 0.38 / 0.90，落進半屏 catch 0.40 / 0.80。
// Air 停着就是实体刘海；Neo 停着是 0（什么都不画），要用时才长出一颗胶囊。
import { FPS, SEGS, T, TOTAL } from './cues';
import { MACHINES, type MachineId } from './machines';

type Shape = { w: number; h: number; r: number };
const N_ = MACHINES.air.notch!;

export const SHAPES: Record<MachineId, Record<string, Shape>> = {
  neo: {
    rest: { w: 0, h: 0, r: 0 },
    hover: { w: 80, h: 18, r: 9 },
    // 认你：一颗胶囊，放下两枚小点。不是圆圈。
    face: { w: 280, h: 68, r: 34 },
    // 半岛：更厚圆角、内容可同心排布（WWDC23 10194）
    row: { w: 520, h: 108, r: 38 },
    alert: { w: 400, h: 92, r: 34 },
    // 番茄钟：照设计稿（cqw × 14.08 点），略加厚圆角
    pomoIdle: { w: 600, h: 112, r: 34 },
    pomo: { w: 300, h: 52, r: 26 },
    pomoAlert: { w: 460, h: 88, r: 34 },
    breath: { w: 400, h: 220, r: 48 },
  },
  air: {
    rest: N_,
    // Compact：尽量窄、贴紧洞（10194）
    compact: { w: N_.w + 2 * 36, h: N_.h, r: 10 },
    // 走开倒数：可读左右翼，仍同心
    tick: { w: 620, h: Math.max(N_.h + 18, 54), r: 18 },
    face: { w: 236, h: 222, r: 46 },
    // Expanded／半岛：够高以环抱感测区，无大额头
    alert: { w: 520, h: 156, r: 38 },
    share: { w: 520, h: 156, r: 38 },
    row: { w: 440, h: 100, r: 32 },
  },
};

const TUNE = { bloom: [0.84, 0.42], expand: [0.92, 0.4], calm: [1, 0.34], settle: [1, 0.38], flyOut: [0.9, 0.38], catch: [0.8, 0.4] } as const;
type Tune = keyof typeof TUNE;
type Ev = [number, string, Tune, number?];

/** 每段里岛换目标的时刻：[帧, 形状, 弹簧, 鼓一下的初速度（点/秒）]。每段第一条是起点，直接到位。 */
const EVENTS: Record<string, Ev[]> = {
  wake: [[0, 'rest', 'calm'], [T.faceOn, 'face', 'bloom', 220], [560, 'alert', 'bloom', 260], [640, 'rest', 'calm']],
  home: [[720, 'rest', 'calm'], [T.tap, 'rest', 'calm', 520], [T.lpClose, 'rest', 'calm', 380], [T.listenPre, 'row', 'bloom', 240]],
  lips: [[1080, 'row', 'calm'], [T.ask, 'alert', 'bloom', 280], [T.rest, 'rest', 'calm'], [T.ride, 'alert', 'bloom', 240]],
  live: [[1800, 'compact', 'calm'], [T.rideOpen, 'alert', 'bloom', 300], [T.rideClose, 'compact', 'calm'], [T.foodOpen, 'alert', 'bloom', 300], [T.foodClose, 'compact', 'calm'], [T.livePre, 'row', 'bloom', 220]],
  pomo: [[2280, 'pomoIdle', 'calm'], [T.pomoTap, 'pomo', 'expand', 200], [T.restAlert, 'pomoAlert', 'bloom', 260], [T.away, 'breath', 'expand', 180], [T.back, 'pomo', 'calm'], [T.pomoPre, 'face', 'bloom', 200]],
  away: [[2880, 'rest', 'calm'], [T.ticks[0] - 10, 'tick', 'bloom', 240], [T.lock - 4, 'rest', 'calm']],
  // 3300 硬切片尾后再展开同一则活动；away 段停在锁屏，不在同镜叠化回桌面。
  end: [[3300, 'share', 'bloom', 260]],
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
