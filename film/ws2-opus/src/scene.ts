// 屏里、屏外每一帧有什么。全部是帧号的函数。
import { CROSSFADE, FADE_IN, FADE_OUT } from './motion/direction';
import {
  FPS, TEACH, TEACH_DOCKED, TEACH_HANDLE, TEACH_TUCKED, TUCK_FRAMES, clamp01, easeIn, mix, moveCurve, ms, seg,
  slideSpring, teachPos, teachSize, tuckProgress, untuckProgress,
} from './motion/site';
import type { Rect } from './layout';
import { LIFT_DRAW, LOCK_AT, PHONE_GONE, PRESS_LONG_A, PRESS_LONG_B, TUCK_A, TUCK_B, UNTUCK_A, CLICK_CARD } from './timeline';

type Pt = { x: number; y: number };

const fadeWindow = (f: number, inAt: number, inDur: number, outAt: number, outDur: number) =>
  Math.min(clamp01((f - inAt) / inDur), 1 - clamp01((f - outAt) / outDur));

// ---- 占位块：真机画面还没录，块上写要录什么 ----
export type Slot = {
  id: string;
  /** 要录的动作和大约几秒。 */
  record: string;
  seconds: number;
  /** 怎么录：录屏、单独录一扇窗、实拍。 */
  how: string;
  /** 字从块宽的百分之几开始写，躲开叠在上面的块。 */
  labelLeft?: number;
};

export const SLOTS: Record<string, Slot> = {
  P0: { id: 'P0', record: '桌面开着两扇窗，静止不动', seconds: 6, how: '录屏，合盖的折叠由片子按应用参数画' },
  P1: { id: 'P1', record: '在音乐 App 里按播放，第 1 秒按下', seconds: 3, how: '录屏' },
  P2: { id: 'P2', record: '戴上 AirPods，第 1 秒戴好', seconds: 3, how: '实拍' },
  P3: { id: 'P3', record: '打开妙控鼠标的开关，第 1 秒打开', seconds: 3, how: '实拍' },
  P4: { id: 'P4', record: '终端窗口在跑构建', seconds: 3, how: '单独录这一扇窗，四周留透明' },
  P5: { id: 'P5', record: '点一下刘海，主屏幕铺开，指针不动', seconds: 4, how: '录屏', labelLeft: 34 },
  P6: { id: 'P6', record: '从主屏幕把一个图标拖到左边，变成侧拉的窗口', seconds: 5, how: '单独录这一扇窗；和 P5 同一次录' },
  P7: { id: 'P7', record: '甩一下标题栏，侧拉的窗口收到边外；点把手拉回', seconds: 5, how: '单独录这一扇窗，再录一遍整屏核对' },
  P8: { id: 'P8', record: '番茄钟开始后，聊天窗口自己收进刘海', seconds: 3, how: '单独录这一扇窗，再录一遍整屏核对' },
};

export type SlotFrame = {
  id: string;
  rect: Rect; // 屏宽、屏高的百分比
  opacity: number;
  /** 飞进刘海时的缩放与圆角（cqw）。 */
  scale: number;
  radius: number;
};

const FULL: Rect = { x: 4, y: 12, w: 92, h: 83 };
const CENTER: Rect = { x: 24, y: 26, w: 52, h: 66 }; // 让开提醒展开后的高度（14cqw ≈ 屏高 22.4%）
const TERM: Rect = { x: 30, y: 22, w: 40, h: 56 };
const CHAT: Rect = { x: 58, y: 20, w: 32, h: 52 };
const WIN_RADIUS = 2.6; // island.js 飞行的起点圆角
const TUCK_RADIUS = 6;

/** site/island.js tuck()：窗口中心移到屏宽正中、屏高 3%，宽缩到屏宽 7%。 */
function tucked(r: Rect, p: number): { rect: Rect; scale: number; radius: number } {
  const cx = r.x + r.w / 2, cy = r.y + r.h / 2;
  const scale = mix(1, 7 / r.w, p);
  const nx = mix(cx, 50, p), ny = mix(cy, 3, p);
  return { rect: { ...r, x: nx - r.w / 2, y: ny - r.h / 2 }, scale, radius: mix(WIN_RADIUS, TUCK_RADIUS, p) };
}

// 拖图标到左边：teach.js 的移动（1.0 秒，cubic-bezier(.32,0,.67,1)），松手那一刻按最近 6 帧量速度。
const DRAG = { from: { x: 50, y: 55 }, to: { x: 12, y: 50 }, start: 3191 };
export const RELEASE_ICON = DRAG.start + ms(TEACH.move);
const dragX = (f: number) => mix(DRAG.from.x, DRAG.to.x, moveCurve(seg(f, DRAG.start, RELEASE_ICON)));
const ICON = 6; // 图标约屏宽 6%
const dockCx = TEACH_DOCKED.x + TEACH_DOCKED.w / 2, dockCy = TEACH_DOCKED.y + TEACH_DOCKED.h / 2;
const releaseVx = ((dragX(RELEASE_ICON) - dragX(RELEASE_ICON - 6)) / 6) * FPS; // 屏宽 %/秒
const V0X = releaseVx / (dockCx - DRAG.to.x);

// 侧拉：teach.js slideHide（单指往左甩，0.14 秒后 0.28 秒 ease-in，抬手后位置弹簧带 2.4 的速度）。
export const SIDE = (() => {
  const appear = 3740;
  const press = appear + ms(TEACH.appear) + ms(TEACH.settle);
  const move0 = press + ms(TEACH.press) + ms(TEACH.flickLead);
  const lift = move0 + ms(TEACH.flick);
  const fade = lift + ms(TEACH.lift) + ms(TEACH.flickHold);
  return { pad: 3720, appear, press, move0, lift, fade, gone: fade + ms(TEACH.fade) };
})();
export const HANDLE_CLICK = 4041; // 点把手：site/app.js settle(false)，初速度 0

function sideRect(f: number): Rect {
  const D = TEACH_DOCKED;
  if (f < RELEASE_ICON) return D;
  if (f < SIDE.move0) {
    // 图标变成窗口：位置用侧拉弹簧（带松手速度），大小用 teach.js 的尺寸弹簧。
    const px = slideSpring(f, RELEASE_ICON, V0X), py = slideSpring(f, RELEASE_ICON, 0);
    const s = teachSize(((f - RELEASE_ICON) / FPS) * 1000);
    const cx = mix(DRAG.to.x, dockCx, px), cy = mix(DRAG.to.y, dockCy, py);
    const w = mix(ICON, D.w, s), h = mix(ICON * 1.6, D.h, s);
    return { x: cx - w / 2, y: cy - h / 2, w, h };
  }
  if (f < SIDE.lift) return { ...D, x: D.x - 5 * easeIn(seg(f, SIDE.move0, SIDE.lift)) };
  if (f < HANDLE_CLICK) {
    const p = teachPos(((f - SIDE.lift) / FPS) * 1000, 2.4);
    return { ...D, x: mix(D.x - 5, TEACH_TUCKED.x, p) };
  }
  return { ...D, x: mix(TEACH_TUCKED.x, D.x, slideSpring(f, HANDLE_CLICK, 0)) };
}

export function slotsAt(f: number): SlotFrame[] {
  const out: SlotFrame[] = [];
  const add = (id: string, rect: Rect, opacity: number, scale = 1, radius = WIN_RADIUS) => {
    if (opacity > 0.001) out.push({ id, rect, opacity, scale, radius });
  };
  add('P0', FULL, f < 840 ? 1 : 1 - clamp01((f - 840) / CROSSFADE));
  add('P1', CENTER, fadeWindow(f, 840, CROSSFADE, 1100, CROSSFADE), 1, 1.2);
  add('P2', CENTER, fadeWindow(f, 1100, CROSSFADE, 1420, CROSSFADE), 1, 1.2);
  add('P3', CENTER, fadeWindow(f, 1420, CROSSFADE, 1740, CROSSFADE), 1, 1.2);

  // P4：进场、飞进刘海、点格子后飞回、被主屏幕盖过。
  if (f >= 1800 && f < 3021 + CROSSFADE) {
    const flyEnd = TUCK_A + Math.ceil(TUCK_FRAMES);
    const opacity = fadeWindow(f, 1800, CROSSFADE, 3021, CROSSFADE);
    if (f < TUCK_A) add('P4', TERM, opacity);
    else if (f < flyEnd) { const t = tucked(TERM, tuckProgress(f, TUCK_A)); add('P4', t.rect, opacity, t.scale, t.radius); }
    else if (f >= UNTUCK_A) { const t = tucked(TERM, untuckProgress(f, UNTUCK_A)); add('P4', t.rect, opacity, t.scale, t.radius); }
  }
  add('P5', FULL, fadeWindow(f, 3021, CROSSFADE, 3330, CROSSFADE), 1, 1.2);
  if (f >= RELEASE_ICON) {
    const r = sideRect(f);
    add('P6', r, Math.min(clamp01((f - RELEASE_ICON) / FADE_IN), 1 - clamp01((f - 3720) / CROSSFADE)));
    add('P7', r, fadeWindow(f, 3720, CROSSFADE, 4330, CROSSFADE));
  }
  // P8：聊天窗口，番茄钟开始后自己收进刘海。
  if (f >= 6120 && f < TUCK_B + Math.ceil(TUCK_FRAMES)) {
    const opacity = clamp01((f - 6120) / CROSSFADE);
    if (f < TUCK_B) add('P8', CHAT, opacity);
    else { const t = tucked(CHAT, tuckProgress(f, TUCK_B)); add('P8', t.rect, opacity, t.scale, t.radius); }
  }
  return out;
}

/** 侧拉收到边外时露出的把手（teach.js：抬手后 250–500ms 出现；点一下就收）。 */
export function handleAt(f: number) {
  if (f < SIDE.lift || f >= HANDLE_CLICK + FADE_OUT) return 0;
  const since = ((f - SIDE.lift) / FPS) * 1000;
  return seg(since, 250, 500) * (1 - clamp01((f - HANDLE_CLICK) / FADE_OUT));
}
export const HANDLE_POS = TEACH_HANDLE;

// ---- 指针：屏里一个圆点，代表他的手 ----
type Move = { at: number; to: Pt; dur?: number };
type Track = { show: number; hide: number; start: Pt; moves: Move[]; presses: [number, number][] };

const TRACKS: Track[] = [
  // 第 3 段：按住终端的标题栏甩进刘海；停到刘海上；移开；再停上去、点格子放回。
  { show: 1850, hide: TUCK_A, start: { x: 50, y: 25 }, moves: [], presses: [[1880, TUCK_A]] },
  { show: 2040, hide: 2360, start: { x: 50, y: 58 }, moves: [{ at: 2060, to: { x: 50, y: 4 } }, { at: 2300, to: { x: 50, y: 40 } }], presses: [] },
  { show: 2640, hide: 2830, start: { x: 50, y: 46 }, moves: [{ at: 2650, to: { x: 50, y: 4 } }, { at: 2725, to: { x: 50, y: 24 } }], presses: [[CLICK_CARD - ms(TEACH.press), CLICK_CARD]] },
  // 第 4 段：点刘海；按住一个图标拖到左边。
  { show: 2900, hide: RELEASE_ICON + 10, start: { x: 50, y: 50 }, moves: [{ at: 2930, to: { x: 50, y: 4 } }, { at: 3040, to: DRAG.from }, { at: DRAG.start, to: DRAG.to }], presses: [[3010, 3021], [3150, RELEASE_ICON]] },
  // 第 5 段：点把手。
  { show: 3940, hide: 4060, start: { x: 30, y: 50 }, moves: [{ at: 3950, to: TEACH_HANDLE }], presses: [[4030, HANDLE_CLICK]] },
  // 第 7 段：长按刘海；再长按回来。
  { show: 5420, hide: 5570, start: { x: 50, y: 45 }, moves: [{ at: 5440, to: { x: 50, y: 4 } }], presses: [[PRESS_LONG_A, 5570]] },
  { show: 5820, hide: 5950, start: { x: 50, y: 40 }, moves: [{ at: 5830, to: { x: 50, y: 4 } }], presses: [[PRESS_LONG_B, 5950]] },
];

export type PointerFrame = Pt & { opacity: number; pressed: number };

export function pointerAt(f: number): PointerFrame | null {
  for (const t of TRACKS) {
    if (f < t.show || f >= t.hide + FADE_OUT) continue;
    let p = t.start;
    for (const m of t.moves) {
      const dur = m.dur ?? ms(TEACH.move);
      if (f >= m.at) p = { x: mix(p.x, m.to.x, moveCurve(seg(f, m.at, m.at + dur))), y: mix(p.y, m.to.y, moveCurve(seg(f, m.at, m.at + dur))) };
    }
    let pressed = 0;
    for (const [a, b] of t.presses) if (f >= a && f < b) pressed = Math.max(pressed, clamp01((f - a) / ms(TEACH.press)));
    const opacity = Math.min(clamp01((f - t.show) / FADE_IN), 1 - clamp01((f - t.hide) / FADE_OUT));
    return { ...p, opacity, pressed };
  }
  return null;
}

// ---- 屏外的触控板（site/teach.js 的画法与节奏） ----
export function trackpadAt(f: number) {
  return Math.min(clamp01((f - SIDE.pad) / FADE_IN), 1 - clamp01((f - 5100) / ms(TEACH.fade)));
}

/** 画一笔：一条横躺的 S，按触控板宽高的百分比。 */
export const STROKE: Pt[] = Array.from({ length: 41 }, (_, i) => {
  const t = i / 40;
  return { x: 22 + 56 * t, y: 50 - 16 * Math.sin(t * Math.PI * 2) * (0.6 + 0.4 * t) };
});
const strokeAt = (p: number): Pt => {
  const k = clamp01(p) * (STROKE.length - 1), i = Math.min(STROKE.length - 2, Math.floor(k)), u = k - i;
  return { x: mix(STROKE[i].x, STROKE[i + 1].x, u), y: mix(STROKE[i].y, STROKE[i + 1].y, u) };
};
export const DRAW = (() => {
  const move1 = LIFT_DRAW;
  const move0 = move1 - ms(1400);
  const press = move0 - ms(TEACH.dwell) - ms(TEACH.press);
  const appear = press - ms(TEACH.settle) - ms(TEACH.appear);
  return { appear, press, move0, move1, fade: move1 + ms(TEACH.lift) + ms(TEACH.hold) };
})();

export type FingerFrame = Pt & { opacity: number; down: number; trail: Pt[] };

export function fingerAt(f: number): FingerFrame | null {
  // 第 5 段：单指往左甩。
  if (f >= SIDE.appear && f < SIDE.gone) {
    const start = { x: 50, y: 58 };
    const p = easeIn(seg(f, SIDE.move0, SIDE.lift));
    const at = { x: start.x - 28 * p, y: start.y };
    const down = f >= SIDE.press && f < SIDE.lift ? 1 : 0;
    const trail: Pt[] = [];
    if (down) for (let k = ms(270); k >= 0; k -= 2) trail.push({ x: start.x - 28 * easeIn(seg(f - k, SIDE.move0, SIDE.lift)), y: start.y });
    const opacity = Math.min(clamp01((f - SIDE.appear) / ms(TEACH.appear)), 1 - clamp01((f - SIDE.fade) / ms(TEACH.fade)));
    return { ...at, opacity, down, trail };
  }
  // 第 6 段：画一笔（teach.js 自己带路径的那种，移动 1.4 秒）。
  if (f >= DRAW.appear && f < DRAW.fade + ms(TEACH.fade)) {
    const p = seg(f, DRAW.move0, DRAW.move1);
    const at = strokeAt(p);
    const down = f >= DRAW.press && f < DRAW.move1 ? 1 : 0;
    const trail: Pt[] = [];
    if (down) for (let k = ms(270); k >= 0; k -= 2) trail.push(strokeAt(seg(f - k, DRAW.move0, DRAW.move1)));
    const opacity = Math.min(clamp01((f - DRAW.appear) / ms(TEACH.appear)), 1 - clamp01((f - DRAW.fade) / ms(TEACH.fade)));
    return { ...at, opacity, down, trail };
  }
  return null;
}

// ---- 屏外的手机线稿：走开 ----
export function phoneAt(f: number) {
  if (f < 6340 || f >= PHONE_GONE) return null;
  const away = moveCurve(seg(f, PHONE_GONE - ms(TEACH.move), PHONE_GONE));
  const opacity = Math.min(clamp01((f - 6340) / FADE_IN), 1 - clamp01((f - (PHONE_GONE - FADE_OUT)) / FADE_OUT));
  return { away, opacity };
}

/** 锁上：屏里的东西叠化成黑。 */
export const screenDark = (f: number) => clamp01((f - LOCK_AT) / CROSSFADE);
