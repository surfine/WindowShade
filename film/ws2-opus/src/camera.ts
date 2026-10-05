// 鏡頭只用 dolly（response 1.6、ζ 1）的形狀。
// 收起、放回、島展開、窗口變形期間鏡頭停住。移動只發生在兩拍之間、主角動作已經停穩之後。
// 每一幀再把機身上緣推到標題安全區下面，中文和英文整段都在機身外面。
import { OUT_TOTAL, SHOT_AT, SHOTS, outOf, type Framing } from './cut';
import { AIR, type Layout } from './layout';
import { dolly } from './motion/direction';
import { FPS, NOTCH } from './motion/site';

export type Cam = { z: number; ax: number; ay: number; tx: number; ty: number };

function targetOf(framing: Framing, L: Layout): Cam {
  const { width: W, height: H, screen: S } = L;
  const cqw = S.w / 100;
  const notch = { x: S.x + S.w / 2, y: S.y + (NOTCH.h * cqw) / 2 };
  const top = { x: S.x + S.w / 2, y: S.y };
  const tall = L.name !== 'landscape';
  switch (framing) {
    case 'close':
      // 略退后，窗口下部和目标区仍留在画内（审片 B10-04）。
      return { z: ((tall ? 1.45 : 1.32) * W) / S.w, ax: notch.x, ay: notch.y + S.h * 0.04, tx: W / 2, ty: H * (tall ? 0.34 : 0.4) };
    case 'near':
      return { z: ((tall ? 1.12 : 1.02) * W) / S.w, ax: notch.x, ay: notch.y + S.h * 0.06, tx: W / 2, ty: H * (tall ? 0.28 : 0.3) };
    case 'medium':
      return { z: ((tall ? 0.92 : 0.86) * W) / S.w, ax: top.x, ay: top.y + S.h * 0.08, tx: W / 2, ty: H * (tall ? 0.24 : 0.3) };
    case 'desk':
      return tall
        ? { z: 0.62, ax: top.x, ay: top.y + S.h * 0.35, tx: W / 2, ty: H * 0.42 }
        : { z: 0.58, ax: S.x + S.w / 2, ay: S.y + S.h * 0.22, tx: W / 2, ty: H * 0.36 };
    case 'wide':
      // 開場要讓整塊螢幕佔住畫面，擠滿的窗口才看得清；片尾同一景別，片名在上面。
      return { z: tall ? 0.72 : 0.92, ax: top.x, ay: S.y + S.h * 0.18, tx: W / 2, ty: H * (tall ? 0.36 : 0.4) };
  }
}

/** 標題帶的下緣（畫面像素）。片名比章節標題更高，安全區取較高的那一個。 */
function titleSafe(L: Layout): number {
  const wide = L.name === 'landscape';
  const zh = wide ? 66 : 76 * (L.width / 1080);
  const en = wide ? 30 : 30 * (L.width / 1080);
  const top = L.height * (wide ? 0.062 : 0.1);
  const head = zh * 1.25 + en * 0.45 + en;
  const mark = zh * 1.45 * 1.12 + en * 0.62 * 0.45 + en * 0.62;
  return top + Math.max(head, mark) + (wide ? 40 : 28);
}

/**
 * 透視裡蓋子的銀邊上緣比螢幕平面更高。把 ty 往下推，直到這條上緣落在標題帶下面。
 * 銀邊厚度用 Product Bezels 的上邊框加外緣，再留一截給俯視時露出的頂面。
 */
function clearTitle(cam: Cam, L: Layout): Cam {
  const S = L.screen;
  const lip = ((AIR.bezel + AIR.rim + 28) * S.w) / AIR.glassW;
  const overhang = cam.z * lip * 2.15;
  const top = cam.ty + cam.z * (S.y - cam.ay) - overhang;
  const safe = titleSafe(L);
  if (top >= safe) return cam;
  return { ...cam, ty: cam.ty + (safe - top) };
}

const mix = (a: number, b: number, p: number) => a + (b - a) * p;

function mixCam(a: Cam, b: Cam, p: number): Cam {
  const z = Math.exp(mix(Math.log(a.z), Math.log(b.z), p));
  return { z, ax: mix(a.ax, b.ax, p), ay: mix(a.ay, b.ay, p), tx: mix(a.tx, b.tx, p), ty: mix(a.ty, b.ty, p) };
}

/** dolly 彈簧走到 1.6 秒時的歸一化進度，間隙結束時正好到 1。 */
const DOLLY_END = dolly(Math.round(1.6 * FPS), 0) || 1;
function dollyUnit(p: number) {
  if (p <= 0) return 0;
  if (p >= 1) return 1;
  return dolly(p * 1.6 * FPS, 0) / DOLLY_END;
}

type Span = { start: number; end: number; action: number; id: string };

function spans(): Span[] {
  return SHOTS.map((s, i) => {
    const start = SHOT_AT[i];
    const end = start + (s.src[1] - s.src[0]);
    let action = start;
    try {
      action = outOf(s.key);
    } catch {
      action = start;
    }
    return { start, end, action, id: s.id };
  });
}

/**
 * 這一鏡的主角要佔到哪一幀。在這之前鏡頭必須是這一鏡的景別，速度為零。
 * 開場先停住看擠滿的桌面，最後才朝下一鏡走。畫一筆、說一句、口型、點頭整段都是主角。
 */
function busyUntil(s: Span): number {
  const hold = (sec: number) => Math.min(s.end, s.action + Math.round(sec * FPS));
  switch (s.id) {
    case 'open':
      return Math.max(s.start, s.end - Math.round(0.85 * FPS));
    case 'tuck':
      return hold(1.15);
    case 'peek':
      return s.end;
    case 'back':
      return hold(0.8);
    case 'launch':
      return hold(0.9);
    case 'drag':
      return s.end;
    case 'slots':
      return s.end;
    case 'draw':
    case 'say':
    case 'lips':
    case 'nod':
      return s.end;
    case 'away':
      return hold(1.15);
    case 'count':
      return hold(0.7);
    case 'return':
      return hold(1.05);
    case 'face':
      return hold(1.0);
    case 'unlocked':
      return hold(0.85);
    default:
      return s.end;
  }
}

type Move = { a: number; b: number; from: number; to: number };

/** 下一鏡的主角從這裡開始。dolly 必須在這之前走完。 */
function actStart(s: Span): number {
  switch (s.id) {
    case 'open':
    case 'peek':
    case 'drag':
    case 'slots':
    case 'draw':
    case 'say':
    case 'lips':
    case 'nod':
    case 'end':
      return s.start;
    case 'back':
    case 'launch':
      return Math.max(s.start, s.action - Math.round(0.25 * FPS));
    default:
      return Math.max(s.start, s.action - Math.round(0.2 * FPS));
  }
}

function movesOf(list: Span[]): Move[] {
  const out: Move[] = [];
  const minGap = Math.round(0.45 * FPS);
  for (let i = 0; i < list.length - 1; i++) {
    const tailFrom = busyUntil(list[i]);
    const tailTo = list[i].end;
    const headFrom = list[i + 1].start;
    const headTo = actStart(list[i + 1]);
    if (tailTo - tailFrom >= minGap) out.push({ a: tailFrom, b: tailTo, from: i, to: i + 1 });
    else if (headTo - headFrom >= minGap) out.push({ a: headFrom, b: headTo, from: i, to: i + 1 });
  }
  return out;
}

type Pack = { cam: Cam[] };

const cache = new Map<string, Pack>();

function build(L: Layout): Pack {
  const key = `${L.name}-${L.width}`;
  const hit = cache.get(key);
  if (hit) return hit;
  const poses = SHOTS.map((s) => targetOf(s.framing, L));
  const list = spans();
  const moves = movesOf(list);
  const cam: Cam[] = [];
  for (let f = 0; f < OUT_TOTAL; f++) {
    let i = 0;
    for (let k = list.length - 1; k >= 0; k--) if (f >= list[k].start) { i = k; break; }
    const move = moves.find((m) => f >= m.a && f < m.b);
    const raw = move ? mixCam(poses[move.from], poses[move.to], dollyUnit((f - move.a) / Math.max(1, move.b - move.a))) : poses[i];
    cam.push(clearTitle(raw, L));
  }
  const pack = { cam };
  cache.set(key, pack);
  return pack;
}

export function cameraAt(frame: number, L: Layout): Cam {
  const { cam } = build(L);
  const f = Math.max(0, Math.min(cam.length - 1, Math.floor(frame)));
  return cam[f];
}

/** 畫面坐標裡，屏幕一角這一幀走了多少像素（1920 寬的片子）。停住的鏡頭是 0。 */
export function cameraSpeed(frame: number, L: Layout): number {
  const { cam } = build(L);
  const f = Math.max(0, Math.min(cam.length - 1, Math.floor(frame)));
  if (!f) return 0;
  const corner = (c: Cam) => ({ x: c.tx + (L.screen.x - c.ax) * c.z, y: c.ty + (L.screen.y - c.ay) * c.z });
  const a = corner(cam[f]);
  const b = corner(cam[f - 1]);
  return Math.hypot(a.x - b.x, a.y - b.y);
}
