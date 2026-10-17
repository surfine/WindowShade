// 一条时间线（秒）。画面上的每样东西都是 t 的函数；相机和刘海是逐帧积分的弹簧（确定性，结果缓存）。
// 拍表见 docs/design-drafts/WindowShade 2 宣传片 分镜.html（D1–D5 已定版）。
import { FPS, HW, TOTAL, approach, clamp01, mix, moveCurve, quad, seg, smooth, solve, type Shape } from './motion';

export type Rect = { x: number; y: number; w: number; h: number };
const cx = (r: Rect) => r.x + r.w / 2;
const cy = (r: Rect) => r.y + r.h / 2;

// ---------- 桌面上的窗口（pt）：都是真实的 WindowShade 截图 ----------
export const WIN = {
  browse: { x: 70, y: 118, w: 620, h: 468 },
  shade: { x: 545, y: 402, w: 620, h: 468 },
  effects: { x: 1020, y: 150, w: 620, h: 468 },
  panel: { x: 250, y: 640, w: 600, h: 397 },
  advanced: { x: 1060, y: 610, w: 560, h: 423 },
} satisfies Record<string, Rect>;
export const LEFT_HALF: Rect = { x: 6, y: 41, w: 845, h: 638 };
export const RIGHT_HALF: Rect = { x: 859, y: 41, w: 845, h: 638 };
const NOTCH_C = { x: HW.cx, y: HW.h / 2 };

// ---------- 拍点 ----------
export const T = {
  tuck: 0.15,
  pointerIn: 3.3, toNotch: [3.6, 4.4], shelf: 4.55, toCard: [4.75, 5.2], click: 5.4, untuck: 5.45,
  toNotch2: [6.8, 7.5], lpClick: 7.6, lpOpen: 7.65, lpClose: 11.2,
  toBar: [11.4, 11.9], press: 12.0, drag: [12.05, 12.9], drop: 12.45, slide: [12.95, 13.65], release: 13.45,
  activity: 15.9, activityOff: 17.9,
  away: 19.4, ticks: [19.8, 20.4, 21.0], lock: 21.4,
  verify: 23.4, face: 24.6, phone: 25.2, unlock: 26.0, verifyOff: 26.6,
  lips: 28.4, char0: 29.2, charGap: 0.22, sub: 30.6, lipsStop: 31.3,
  nodDown: 33.2, nodUp: 33.53, ok: 33.55, glide: 33.6, lipsOff: 34.2,
  pull: 40.0, mark: 44.0,
};

/** 真静止的段：相机钉在目标上，一个像素不动。 */
export const RESTS: [number, number][] = [
  [1.8, 2.6], [10.7, 11.2], [16.8, 17.6], [21.8, 22.8], [31.8, 32.4], [38.6, 39.6], [46.0, 48.0],
];
export const inRest = (t: number) => RESTS.some(([a, b]) => t >= a && t < b);

// ---------- B1 窗口被甩进刘海 ----------
const TUCK = { resp: 0.85, z: 0.86, v0: 1.1, ctrl: { x: 760, y: 170 } };
export function tuckP(t: number) {
  return clamp01(approach(t - T.tuck, TUCK.resp, TUCK.z, TUCK.v0));
}
/** 被吞进刘海的那一刻（进度 0.9）和当时的速度（全程/秒）。 */
export const COVER = (() => {
  for (let i = 1; i < 600; i++) {
    const t = T.tuck + i / 240;
    if (tuckP(t) >= 0.9) return { t, v: (tuckP(t + 1 / 240) - tuckP(t)) * 240 };
  }
  return { t: 0.8, v: 2 };
})();

export type WinState = { x: number; y: number; w: number; h: number; o: number; z?: number };
function rectAt(c: { x: number; y: number }, w: number, h: number, o = 1): WinState {
  return { x: c.x - w / 2, y: c.y - h / 2, w, h, o };
}

/** 收进刘海的那扇（设置 · 卷帘）。B1 飞进去，B3 点卡片后飞回原处。 */
export function shadeWin(t: number): WinState {
  const S = WIN.shade;
  if (t < T.untuck) {
    const p = tuckP(t);
    const x = quad(cx(S), TUCK.ctrl.x, NOTCH_C.x, p), y = quad(cy(S), TUCK.ctrl.y, NOTCH_C.y, p);
    return rectAt({ x, y }, mix(S.w, 150, Math.pow(p, 0.7)), mix(S.h, 22, Math.pow(p, 1.5)), p > 0.995 ? 0 : 1);
  }
  // 放回：同一条弧线倒着走，先长高再长宽；欠阻尼，落位有一点点过冲。
  const q = approach(t - T.untuck, 0.62, 0.84, 0.6);
  const p = 1 - q;
  const pc = clamp01(p);
  const x = quad(cx(S), TUCK.ctrl.x, NOTCH_C.x, pc), y = quad(cy(S), TUCK.ctrl.y, NOTCH_C.y, pc);
  const w = mix(S.w, 150, Math.pow(pc, 0.7)) * (p < 0 ? 1 - p * 0.15 : 1);
  const h = mix(S.h, 22, Math.pow(pc, 1.5)) * (p < 0 ? 1 - p * 0.15 : 1);
  return rectAt({ x, y }, w, h, t < T.untuck + 0.02 ? 0 : 1);
}

// ---------- 指针 ----------
export type Pointer = { x: number; y: number; o: number; down: number };
const P0 = { x: 1180, y: 760 };
const CARD = { x: HW.cx, y: HW.h + 78 };
const BAR = { x: 1330, y: 168 };
const GRAB = { dx: BAR.x - WIN.effects.x, dy: BAR.y - WIN.effects.y };
const DROP_PT = { x: HW.cx, y: 92 };
const SLOT_R = { x: HW.cx + 132, y: 92 };
function lerpPt(a: { x: number; y: number }, b: { x: number; y: number }, p: number) {
  return { x: mix(a.x, b.x, p), y: mix(a.y, b.y, p) };
}
function pointerRaw(t: number): { x: number; y: number } {
  if (t < T.toNotch[1]) return lerpPt(P0, { x: HW.cx, y: 22 }, moveCurve(seg(t, T.toNotch[0], T.toNotch[1])));
  if (t < T.toNotch2[0]) return lerpPt({ x: HW.cx, y: 22 }, CARD, moveCurve(seg(t, T.toCard[0], T.toCard[1])));
  if (t < T.toBar[0]) return lerpPt(CARD, { x: HW.cx, y: 20 }, moveCurve(seg(t, T.toNotch2[0], T.toNotch2[1])));
  if (t < T.drag[0]) return lerpPt({ x: HW.cx, y: 20 }, BAR, moveCurve(seg(t, T.toBar[0], T.toBar[1])));
  if (t < T.slide[0]) {
    const p = moveCurve(seg(t, T.drag[0], T.drag[1]));
    return { x: quad(BAR.x, 1180, DROP_PT.x, p), y: quad(BAR.y, 60, DROP_PT.y, p) };
  }
  return lerpPt(DROP_PT, SLOT_R, moveCurve(seg(t, T.slide[0], T.slide[1])));
}
export function pointer(t: number): Pointer {
  const p = pointerRaw(t);
  const o = seg(t, T.pointerIn, T.pointerIn + 0.25) * (1 - seg(t, 14.0, 14.4));
  const click = (c: number) => Math.max(0, 1 - Math.abs(t - c) / 0.12);
  const down = Math.max(click(T.click), click(T.lpClick), t >= T.press && t < T.release ? 1 : 0);
  return { ...p, o, down };
}
const pointerVel = (t: number) => {
  const a = pointerRaw(t - 1 / 120), b = pointerRaw(t + 1 / 120);
  return { x: (b.x - a.x) * 60, y: (b.y - a.y) * 60 };
};

/** B5 被拖到刘海、放进右半屏的那扇（设置 · 效果）。 */
export function effectsWin(t: number): WinState {
  const E0 = WIN.effects;
  if (t < T.press) return { ...E0, o: 1 };
  if (t < T.release) {
    const p = pointerRaw(t);
    const k = mix(1, 0.5, smooth(seg(t, T.drag[0] + 0.3, T.drag[1])));
    // 抓着标题栏：抓点不动，窗口绕抓点缩。
    return { x: p.x - GRAB.dx * k, y: p.y - GRAB.dy * k, w: E0.w * k, h: E0.h * k, o: 1, z: 1 };
  }
  // 松手：位置用两个轴各自的弹簧，带着松手那一刻指针的速度；大小单独一根弹簧。
  const r = effectsWin(T.release - 1e-4);
  const v = pointerVel(T.release);
  const dt = t - T.release;
  const R = RIGHT_HALF;
  const sx = solve(r.x - R.x, v.x, 0.55, 0.8, dt)[0], sy = solve(r.y - R.y, v.y, 0.55, 0.8, dt)[0];
  const k = approach(dt, 0.5, 0.86);
  return { x: R.x + sx, y: R.y + sy, w: mix(r.w, R.w, k), h: mix(r.h, R.h, k), o: 1, z: 1 };
}

/** B10 点头后滑到左半屏的那扇（设置 · 窗口浏览）。 */
export function browseWin(t: number): WinState {
  const B = WIN.browse, L = LEFT_HALF;
  if (t < T.glide) return { ...B, o: 1 };
  const dt = t - T.glide;
  // 点头回正那一刻的速度交给窗口：往目标方向 700 pt/s。
  const dx = L.x - B.x, dy = L.y - B.y, len = Math.hypot(dx, dy) || 1;
  const v = 700;
  const sx = solve(B.x - L.x, (dx / len) * v, 0.6, 0.82, dt)[0], sy = solve(B.y - L.y, (dy / len) * v, 0.6, 0.82, dt)[0];
  const k = approach(dt, 0.55, 0.86, 0.8);
  return { x: L.x + sx, y: L.y + sy, w: mix(B.w, L.w, k), h: mix(B.h, L.h, k), o: 1, z: 1 };
}

// ---------- 启动台 ----------
export const APPS = [
  ['mail', '邮件'], ['messages', '信息'], ['calendar', '日历'], ['photos', '照片'],
  ['notes', '备忘录'], ['music', '音乐'], ['terminal', '终端'], ['settings', '系统设置'],
] as const;
const ICON = 118, GAPX = 92, ROWS = [372, 600];
export function appSlot(i: number) {
  const col = i % 4, row = Math.floor(i / 4);
  const total = 4 * ICON + 3 * GAPX;
  return { x: HW.cx - total / 2 + col * (ICON + GAPX) + ICON / 2, y: ROWS[row], size: ICON };
}
/** 图标一个接一个从刘海倒出来，越来越快（发牌）；收回时反过来、更快。 */
export function appState(i: number, t: number) {
  const n = APPS.length;
  const start = T.lpOpen + 0.12 + 0.62 * (1 - Math.pow(1 - i / n, 1.7));
  const back = T.lpClose + 0.035 * (n - 1 - i);
  const slot = appSlot(i);
  let p = approach(t - start, 0.5, 0.74, 1.2);
  if (t >= back) p = p * (1 - approach(t - back, 0.34, 1, 0));
  const pc = clamp01(p);
  const x = quad(NOTCH_C.x, mix(NOTCH_C.x, slot.x, 0.35), slot.x, pc);
  const y = quad(NOTCH_C.y, slot.y - 40, slot.y, pc) + (p - pc) * 40;
  const s = mix(0.18, 1, p);
  return { x, y, s, o: t < start ? 0 : clamp01(p * 3) , label: seg(p, 0.85, 1) };
}
export function launchBackdrop(t: number) {
  const on = approach(t - T.lpOpen, 0.5, 1);
  const off = approach(t - T.lpClose, 0.4, 1);
  return on * (1 - off);
}

// ---------- 锁 ----------
export function lockAmount(t: number) {
  return approach(t - T.lock, 0.7, 1) * (1 - approach(t - T.unlock, 0.6, 1));
}

// ---------- 刘海：逐帧积分的三根弹簧（宽、高、底角），换目标时保留速度 ----------
type Key = { t: number; s: Shape; resp: number; z: number; kick?: [number, number] };
const sh = (w: number, dh: number, rb: number): Shape => ({ w, h: HW.h + dh, rb });
export const SHAPES = {
  rest: { w: HW.w, h: HW.h, rb: HW.rb },
  compact: sh(HW.w + 2 * 30, 0, HW.rb),
  shelf: sh(380, 132, 30),
  drop: sh(440, 84, 26),
  activity: sh(430, 64, 28),
  away: sh(HW.w + 2 * 70, 0, HW.rb),
  lock: sh(HW.w + 2 * 30, 0, HW.rb),
  verify: sh(450, 46, 24),
  lips: sh(500, 98, 30),
};
const CALM = { resp: 0.34, z: 1 }, BLOOM = { resp: 0.42, z: 0.84 }, EXPAND = { resp: 0.4, z: 0.92 }, CATCH = { resp: 0.4, z: 0.8 };
const KEYS: Key[] = [
  { t: 0, s: SHAPES.rest, ...CALM },
  { t: COVER.t, s: SHAPES.compact, ...BLOOM, kick: [COVER.v * 170, COVER.v * 60] },
  { t: T.shelf, s: SHAPES.shelf, ...EXPAND },
  { t: T.click + 0.05, s: SHAPES.rest, ...CALM },
  { t: T.drop, s: SHAPES.drop, ...CATCH },
  { t: T.release + 0.15, s: SHAPES.rest, ...CALM },
  { t: T.activity, s: SHAPES.activity, ...BLOOM },
  { t: T.activityOff, s: SHAPES.rest, ...CALM },
  { t: T.away, s: SHAPES.away, ...BLOOM },
  { t: T.lock, s: SHAPES.lock, ...CALM },
  { t: T.verify, s: SHAPES.verify, ...BLOOM },
  { t: T.verifyOff, s: SHAPES.rest, ...CALM },
  { t: T.lips, s: SHAPES.lips, ...EXPAND },
  { t: T.lipsOff, s: SHAPES.rest, ...CALM },
];
let islandCache: Shape[] | null = null;
function islandTrack(): Shape[] {
  if (islandCache) return islandCache;
  const out: Shape[] = [];
  const st = { w: HW.w, h: HW.h, rb: HW.rb }, v = { w: 0, h: 0, rb: 0 };
  const SUB = 8, dt = 1 / (FPS * SUB);
  let k = 0;
  for (let f = 0; f < TOTAL; f++) {
    for (let s = 0; s < SUB; s++) {
      const t = (f * SUB + s) / (FPS * SUB);
      while (k + 1 < KEYS.length && t >= KEYS[k + 1].t) {
        k++;
        const kick = KEYS[k].kick;
        if (kick) { v.w += kick[0]; v.h += kick[1]; }
      }
      const key = KEYS[k];
      const w = (2 * Math.PI) / key.resp;
      (['w', 'h', 'rb'] as const).forEach((n) => {
        const acc = -w * w * (st[n] - key.s[n]) - 2 * key.z * w * v[n];
        v[n] += acc * dt;
        st[n] += v[n] * dt;
      });
    }
    out.push({ w: st.w, h: Math.max(HW.h, st.h), rb: Math.max(2, st.rb) });
  }
  islandCache = out;
  return out;
}
export const islandAt = (f: number) => islandTrack()[Math.max(0, Math.min(TOTAL - 1, Math.round(f)))];

/** 刘海里显示哪一样内容，以及透明度：形状走出去约 40% 再进，下一次换形前 0.08 秒先退。 */
export type IslandContent =
  | 'count' | 'shelf' | 'drop' | 'activity' | 'away' | 'lock' | 'verify' | 'lips' | 'none';
const CONTENT: { from: number; to: number; c: IslandContent }[] = [
  { from: COVER.t + 0.1, to: T.shelf, c: 'count' },
  { from: T.shelf + 0.12, to: T.click + 0.05, c: 'shelf' },
  { from: T.drop + 0.12, to: T.release + 0.15, c: 'drop' },
  { from: T.activity + 0.13, to: T.activityOff, c: 'activity' },
  { from: T.away + 0.1, to: T.lock, c: 'away' },
  { from: T.lock + 0.1, to: T.verify, c: 'lock' },
  { from: T.verify + 0.13, to: T.verifyOff, c: 'verify' },
  { from: T.lips + 0.14, to: T.lipsOff, c: 'lips' },
];
export function islandContent(t: number): { c: IslandContent; o: number; since: number } {
  for (const k of CONTENT) {
    if (t >= k.from && t < k.to) return { c: k.c, o: smooth(seg(t, k.from, k.from + 0.18)) * (1 - seg(t, k.to - 0.08, k.to)), since: t - k.from };
  }
  return { c: 'none', o: 0, since: 0 };
}

// ---------- 字幕：全片 4 句 + 片尾字标 = 5 行 ----------
export const CAPTIONS = [
  { from: 23.6, to: 27.4, text: '看一眼，就解锁' },
  { from: 28.8, to: 32.8, text: '不出声，动动嘴' },
  { from: 33.3, to: 35.9, text: '点个头，就照做' },
];
export const WORDMARK = { at: T.mark, text: 'WindowShade 2', sub: '刘海，从此有用' };

// ---------- 相机 ----------
/** ax/ay：对准屏上哪一点（pt）；s：每 pt 多少画面像素（1920 宽）；q：片尾拉远到双机（0–1）。 */
export type Cam = { ax: number; ay: number; s: number };
type Target = Cam & { resp: number; z: number };
function camTarget(t: number): Target {
  const base = (ax: number, ay: number, s: number, resp = 0.8, z = 0.88): Target => ({ ax, ay, s, resp, z });
  if (t < 1.6) {
    // 落后主体 0.1 秒跟着窗口往上走，同时往刘海推近。
    const w = shadeWin(t - 0.1), p = tuckP(t - 0.1);
    const ay = 128 + 0.1 * Math.max(0, cy(w) - 128) * (w.o > 0 ? 1 : 0);
    return base(HW.cx, ay, 3.0 + 0.35 * p, 0.42, 0.86);
  }
  if (t < 2.6) return base(HW.cx, 128, 3.35, 0.42, 0.86);
  if (t < 7.0) {
    if (t < 4.3) return base(HW.cx, 553, 1.0, 0.95, 0.9);
    if (t < T.untuck) return base(HW.cx, 470, 1.04, 0.8, 0.9);
    const w = shadeWin(t - 0.1);
    return base(mix(HW.cx, cx(w), 0.3), mix(470, cy(w), 0.3), 1.02, 0.7, 0.88);
  }
  if (t < 11.2) {
    const pour = seg(t, T.lpOpen, T.lpOpen + 1.2);
    return base(HW.cx, 500, mix(1.1, 1.2, smooth(pour)), 0.9, 0.9);
  }
  if (t < 15.0) {
    if (t < T.drag[0]) return base(1080, 420, 1.12, 0.8, 0.9);
    if (t < T.release) {
      // 拖向刘海：相机提前到落点。
      const p = pointerRaw(t + 0.15);
      return base(mix(HW.cx, p.x, 0.25), mix(300, p.y, 0.25), 1.45, 0.6, 0.88);
    }
    const w = effectsWin(t - 0.1);
    return base(mix(HW.cx, cx(w), 0.55), mix(330, cy(w), 0.45), 1.12, 0.7, 0.86);
  }
  if (t < 18.6) return base(HW.cx, 150, 2.4, 0.75, 0.9);
  if (t < 23.0) return base(HW.cx, 553, 0.98, 1.0, 0.92);
  if (t < 28.0) return base(HW.cx, 215, 2.0, 1.1, 0.9);
  if (t < 33.0) {
    // 读口型：字一个个出来，相机跟着慢慢凑近候选（落定后 31.8–32.4 真静止）。
    const k = smooth(seg(t, 28.6, 30.8));
    return base(mix(HW.cx, HW.cx + 40, k), mix(190, 150, k), mix(2.3, 2.75, k), 1.0, 0.92);
  }
  if (t < 36.4) {
    if (t < T.nodUp) return base(HW.cx, 255, 2.3, 0.3, 0.75);
    if (t < T.glide + 0.1) return base(HW.cx, 190, 2.3, 0.3, 0.75);
    const w = browseWin(t - 0.1);
    return base(mix(HW.cx, cx(w), 0.6), mix(300, cy(w), 0.5), 1.18, 0.8, 0.86);
  }
  return base(HW.cx, 553, 0.92, 1.0, 0.92);
}
let camCache: Cam[] | null = null;
function camTrack(): Cam[] {
  if (camCache) return camCache;
  const out: Cam[] = [];
  const t0 = camTarget(0);
  const st = { ax: t0.ax, ay: t0.ay + 25, ls: Math.log(t0.s * 0.96) }, v = { ax: 0, ay: 0, ls: 0 };
  const SUB = 8, dt = 1 / (FPS * SUB);
  for (let f = 0; f < TOTAL; f++) {
    const tf = f / FPS;
    if (inRest(tf) && tf < T.pull) {
      const g = camTarget(tf);
      st.ax = g.ax; st.ay = g.ay; st.ls = Math.log(g.s); v.ax = v.ay = v.ls = 0;
    } else {
      for (let s = 0; s < SUB; s++) {
        const t = (f * SUB + s) / (FPS * SUB);
        const g = camTarget(t);
        const w = (2 * Math.PI) / g.resp;
        const tgt = { ax: g.ax, ay: g.ay, ls: Math.log(g.s) };
        (['ax', 'ay', 'ls'] as const).forEach((n) => {
          const acc = -w * w * (st[n] - tgt[n]) - 2 * g.z * w * v[n];
          v[n] += acc * dt;
          st[n] += v[n] * dt;
        });
      }
    }
    out.push({ ax: st.ax, ay: st.ay, s: Math.exp(st.ls) });
  }
  camCache = out;
  return out;
}
export const camAt = (f: number) => camTrack()[Math.max(0, Math.min(TOTAL - 1, Math.round(f)))];
/** 片尾拉远：1.6 秒临界阻尼，46 秒前停稳；之后钉死。 */
export const pullQ = (t: number) => (t >= 46 ? 1 : approach(t - T.pull, 1.9, 1));
