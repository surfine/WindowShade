// 岛的宽、高、圆角各一根弹簧，单位是屏幕点（15 英寸 MacBook Air 默认 1710 × 1107 点）。
// 弹簧照 prototype/App/Notch.swift：认证 0.28 / 回弹 0.02，提醒 bloom 0.42 / 0.84，展开 0.40 / 0.92，收回 calm 0.34 / 1.0。
import { FPS, TOTAL } from './time';

export const PT = { w: 1710, h: 1107 };
// Product Bezels：刘海 306 × 55 像素、下角约 15 像素，屏宽 2880 像素。
export const NOTCH_PT = { w: (306 / 2880) * 1710, h: (55 / 2880) * 1710, r: (15 / 2880) * 1710 };

type Shape = { w: number; h: number; r: number };
const S = {
  rest: NOTCH_PT,
  face: { w: 252, h: 238, r: 48 },
  alert: { w: 404, h: 96, r: 28 },
  listen: { w: 470, h: 124, r: 30 },
  confirm: { w: 432, h: 106, r: 28 },
  compact: { w: NOTCH_PT.w + 2 * 46, h: NOTCH_PT.h, r: 10 },
  full: { w: PT.w + 4, h: PT.h + 4, r: 0 },
} satisfies Record<string, Shape>;
export type IslandShape = keyof typeof S;

const TUNE = {
  auth: { z: 0.98, r: 0.28 },
  bloom: { z: 0.84, r: 0.42 },
  expand: { z: 0.92, r: 0.4 },
  calm: { z: 1, r: 0.34 },
};

type Ev = { f: number; to: IslandShape; tune: keyof typeof TUNE; kick?: { w: number; h: number } };
/** 什么时候换目标。kick 是那一下的初速度（点 / 秒），和收进刘海「鼓一下」同一个做法。 */
export const EVENTS: Ev[] = [
  { f: -16, to: 'face', tune: 'auth' },
  { f: 112, to: 'rest', tune: 'calm' },
  { f: 292, to: 'alert', tune: 'bloom' },
  { f: 404, to: 'rest', tune: 'calm' },
  { f: 512, to: 'rest', tune: 'calm', kick: { w: 520, h: 150 } },
  { f: 960, to: 'rest', tune: 'calm', kick: { w: 380, h: 110 } },
  // 读唇：岛先长成「读到的」，镜头钻进那块小画面，再从里面退回来；接着长成问话，钻进 AirPods。
  { f: 1040, to: 'listen', tune: 'bloom' },
  { f: 1552, to: 'confirm', tune: 'bloom' },
  { f: 1822, to: 'rest', tune: 'calm' },
  { f: 1962, to: 'confirm', tune: 'bloom' },
  { f: 2090, to: 'rest', tune: 'calm' },
  // iPhone 连上来；长按刘海，落拍那一下整块屏变成 CarPlay；Esc 收回刘海。
  { f: 2166, to: 'alert', tune: 'bloom' },
  { f: 2268, to: 'full', tune: 'expand' },
  { f: 2880, to: 'rest', tune: 'calm', kick: { w: -900, h: -500 } },
  { f: 2968, to: 'compact', tune: 'expand' },
  // 倒数走完：岛像开场刷脸那样长成方块，锁扣合上，屏幕跟着锁；再收回刘海。
  { f: 3168, to: 'face', tune: 'auth' },
  { f: 3270, to: 'rest', tune: 'calm' },
];

// 一维阻尼振子精确步进。
function step(x: number, v: number, goal: number, z: number, response: number, dt: number) {
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
  const nv = decay * (-a * (e * c + B * s) + (-e * wd * s + B * wd * c));
  return [goal + nx, nv];
}

const START = -16;
const N = TOTAL - START + 2;
const W = new Float64Array(N), H = new Float64Array(N), Rr = new Float64Array(N);
const SHAPE = new Array<IslandShape>(N);
(() => {
  let w = S.rest.w, h = S.rest.h, r = S.rest.r, vw = 0, vh = 0, vr = 0;
  let cur: Ev = { f: START, to: 'rest', tune: 'calm' };
  for (let i = 0; i < N; i++) {
    const f = START + i;
    for (const ev of EVENTS) if (ev.f === f) {
      cur = ev;
      if (ev.kick) { vw += ev.kick.w; vh += ev.kick.h; }
    }
    if (i > 0) {
      const t = TUNE[cur.tune], g = S[cur.to], dt = 1 / FPS;
      [w, vw] = step(w, vw, g.w, t.z, t.r, dt);
      [h, vh] = step(h, vh, g.h, t.z, t.r, dt);
      [r, vr] = step(r, vr, g.r, t.z, t.r, dt);
    }
    W[i] = w; H[i] = h; Rr[i] = Math.max(0, r); SHAPE[i] = cur.to;
  }
})();

const idx = (f: number) => Math.max(0, Math.min(N - 1, Math.floor(f) - START));
/** 帧之间线性插值：快门在一帧里取好几个时刻。 */
export function islandAt(f: number) {
  const i = idx(f), j = Math.min(N - 1, i + 1), u = Math.max(0, Math.min(1, f - Math.floor(f)));
  const l = (a: Float64Array) => a[i] + (a[j] - a[i]) * u;
  return { w: l(W), h: l(H), r: l(Rr), target: SHAPE[i] };
}
export const SHAPES = S;
