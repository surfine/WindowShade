// 屏里、屏外每一帧有什么。全部是帧号的函数。
import { CROSSFADE, FADE_IN, FADE_OUT, dolly } from './motion/direction';
import {
  FPS, ISLAND_SHAPES, NOTCH, SITE_NOTCH_H, TEACH, TEACH_DOCKED, TEACH_HANDLE, TEACH_TUCKED, TUCK_FRAMES, clamp01, easeIn, mix,
  moveCurve, ms, seg, slideSpring, teachPos, teachSize, tuckProgress, untuckProgress,
} from './motion/site';
import { SCREEN_ASPECT, type Rect } from './layout';
import {
  BUILD_DONE, CAUSE_MOUSE, CAUSE_PODS, CLICK_ALLOW, CLICK_CARD, CLICK_SUMMARY, DRAG_SIDE, DRAG_UP, DROP_OPEN, DROP_RELEASE, EDITS, GRAB,
  LIFT_DRAW, LOCK_AT, MOUSE_END, MUSIC_PLAY, NOD_DEG, NOD_DONE, NOD_DOWN, NOD_FRAMES, PHONE_BACK, PHONE_GONE, PODS_END, PRESS_LONG_A,
  PRESS_LONG_B, PREVIEW_AT, TUCK_A, TUCK_B, UNLOCK, UNTUCK_A, UNTUCK_C, ZOOM_BACK, ZOOM_LIPS,
} from './timeline';

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
  P9: { id: 'P9', record: '按住终端的标题栏拖到刘海，横移到左半屏那一格松手', seconds: 6, how: '单独录这一扇窗，再录一遍整屏核对落点小岛' },
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
const MUSIC: Rect = { x: 36, y: 26, w: 28, h: 64 };
// 指针点在刘海上：屏高的百分比，落在真机刘海 1.96cqw 高度的中间。
const ON_NOTCH = { x: 50, y: 1.6 };
export const PLAY_BUTTON = { x: 50, y: 80 };
const TERM: Rect = { x: 30, y: 22, w: 40, h: 56 };
const CHAT: Rect = { x: 58, y: 20, w: 32, h: 52 };
/** 后面那扇不在前台的“文章草稿”（画出来的那一版才有）。 */
export const DRAFT: Rect = { x: 27, y: 17, w: 66, h: 72 };
/** 左半屏：菜单栏（刘海高 1.96cqw ≈ 屏高 3%）下面，四边留一道窄缝。 */
const LEFT: Rect = { x: 0.8, y: 3.9, w: 48.8, h: 95.3 };

// 主屏幕一排六个图标：系统自带的 App，名字照系统简体中文。
export const LAUNCH_APPS: { key: string; name: string }[] = [
  { key: 'mail', name: '邮件' }, { key: 'notes', name: '备忘录' }, { key: 'calendar', name: '日历' },
  { key: 'photos', name: '照片' }, { key: 'music', name: '音乐' }, { key: 'settings', name: '系统设置' },
];
export const iconCenter = (i: number) => ({ x: 50 + (i - 2.5) * 12, y: 46 });
export const ICON_SIZE = 6; // 屏宽 %
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
const DRAG = { from: iconCenter(1), to: { x: 12, y: 50 }, press: 3150, start: 3191 };
export const RELEASE_ICON = DRAG.start + ms(TEACH.move);
const dragX = (f: number) => mix(DRAG.from.x, DRAG.to.x, moveCurve(seg(f, DRAG.start, RELEASE_ICON)));
const ICON = ICON_SIZE;
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

// ---- 落点小岛：五格横排在刘海下面（Notch.swift DropChoice 的顺序与名字） ----
export const DROP_CHOICES = ['左半屏', '铺满屏幕', '收进刘海', '魔法平铺', '右半屏'] as const;
/** 岛里的格子：左右各留 1.2cqw；竖着从硬件刘海下沿往下 0.6 到岛底上面 1.0（cqw）。 */
export const DROP_UI = (() => {
  const { w, h } = ISLAND_SHAPES.drop;
  const pad = 1.2, pitch = (w - 2 * pad) / DROP_CHOICES.length;
  return { pad, pitch, top: NOTCH.h + 0.6, bottom: h - 1.0 };
})();
const cqwToH = (v: number) => v * SCREEN_ASPECT; // 竖向 cqw → 屏高 %
const dropCell = (i: number) => ({
  x: 50 - ISLAND_SHAPES.drop.w / 2 + DROP_UI.pad + DROP_UI.pitch * (i + 0.5),
  y: cqwToH((DROP_UI.top + DROP_UI.bottom) / 2),
});
/** 按住终端标题栏的那一点（标题字的左边，不挡字）。 */
const GRAB_PT = { x: 44, y: TERM.y + cqwToH(5) / 2 };

/** 指针停在落点小岛的哪一格：0–4；不在岛上是 -1。 */
export function dropHoverAt(f: number): number {
  if (f < DROP_OPEN || f >= DROP_RELEASE + FADE_OUT) return -1;
  const p = pointerAt(f);
  if (!p) return -1;
  const left = 50 - ISLAND_SHAPES.drop.w / 2 + DROP_UI.pad;
  const i = Math.floor((p.x - left) / DROP_UI.pitch);
  return i >= 0 && i < DROP_CHOICES.length && p.y < cqwToH(ISLAND_SHAPES.drop.h) ? i : -1;
}
/** 构建跑完、还没轮到开口时，岛角上那个点。 */
export const dropDotAt = (f: number) => (f < BUILD_DONE ? 0 : clamp01((f - BUILD_DONE) / FADE_IN));

/** 拖着走：窗口跟着按住的那一点；松手后按 glide（0.42 / 0.88，与 teach.js 窗口位置同一根）滑到左半屏。 */
function dropTermRect(f: number): Rect {
  if (f < GRAB) return TERM;
  const at = (g: number): Rect => {
    const p = pointerAt(g);
    return p ? { ...TERM, x: TERM.x + p.x - GRAB_PT.x, y: TERM.y + p.y - GRAB_PT.y } : TERM;
  };
  if (f < DROP_RELEASE) return at(f);
  const from = at(DROP_RELEASE - 1);
  const p = teachPos(((f - DROP_RELEASE) / FPS) * 1000);
  return { x: mix(from.x, LEFT.x, p), y: mix(from.y, LEFT.y, p), w: mix(from.w, LEFT.w, p), h: mix(from.h, LEFT.h, p) };
}
export const termDoneAt = (f: number) => f >= BUILD_DONE;

// ---- 刘海里问一次放行：两个按钮的位置（cqw，岛内坐标），岛和指针共用 ----
export const ASK_UI = (() => {
  const { w, h } = ISLAND_SHAPES.ask;
  const pillW = 11, pillH = 3.6, pad = 1.8, gap = 1.2;
  const allow = { x: w - pad - pillW, y: h - pad - pillH, w: pillW, h: pillH };
  const deny = { ...allow, x: allow.x - gap - pillW };
  return { allow, deny };
})();
const ALLOW_PT = { x: 50 - ISLAND_SHAPES.ask.w / 2 + ASK_UI.allow.x + ASK_UI.allow.w / 2, y: cqwToH(ASK_UI.allow.y + ASK_UI.allow.h / 2) };

// ---- 离开期间：三行（cqw，岛内坐标）。聊天是第三行 ----
export const SUMMARY_UI = { titleY: SITE_NOTCH_H + 2.6, rowY: SITE_NOTCH_H + 4, rowH: 7, x: 2.4, rows: 3 };
const CHAT_ROW = 2;
const ROW_CHAT_PT = { x: 50 - ISLAND_SHAPES.digest.w / 2 + 22, y: cqwToH(SUMMARY_UI.rowY + SUMMARY_UI.rowH * (CHAT_ROW + 0.5)) };
/** 指针在第几行上，不在是 -1。 */
export function summaryHoverAt(f: number): number {
  const p = pointerAt(f);
  if (!p) return -1;
  const { w } = ISLAND_SHAPES.digest;
  const x = p.x - (50 - w / 2), y = p.y / SCREEN_ASPECT;
  if (x < SUMMARY_UI.x || x > w - SUMMARY_UI.x) return -1;
  const i = Math.floor((y - SUMMARY_UI.rowY) / SUMMARY_UI.rowH);
  return i >= 0 && i < SUMMARY_UI.rows ? i : -1;
}

// ---- 文章草稿：放行后三处引文依次改好；静音操作点头后去左半屏 ----
export function draftAt(f: number) {
  const moved = NOD_DONE + 2;
  const p = f < moved ? 0 : teachPos(((f - moved) / FPS) * 1000);
  const rect: Rect = { x: mix(DRAFT.x, LEFT.x, p), y: mix(DRAFT.y, LEFT.y, p), w: mix(DRAFT.w, LEFT.w, p), h: mix(DRAFT.h, LEFT.h, p) };
  const marks = EDITS.map((e) => clamp01((f - e) / FADE_IN));
  // 刘海说明对象：认出“左半屏”后，被冻结的那扇窗描一圈；点头完成就收。
  const outline = fadeWindow(f, PREVIEW_AT + 6, FADE_IN, NOD_DONE, FADE_OUT);
  return { rect, marks, outline };
}

/** 回来后点“聊天”那一行：聊天窗口从刘海放回（island.js 同一段动画倒着走）。只在画出来的那一版。 */
export function chatBackAt(f: number) {
  if (f < UNTUCK_C) return null;
  return tucked(CHAT, untuckProgress(f, UNTUCK_C));
}

export function slotsAt(f: number): SlotFrame[] {
  const out: SlotFrame[] = [];
  const add = (id: string, rect: Rect, opacity: number, scale = 1, radius = WIN_RADIUS) => {
    if (opacity > 0.001) out.push({ id, rect, opacity, scale, radius });
  };
  add('P0', FULL, f < 840 ? 1 : 1 - clamp01((f - 840) / CROSSFADE));
  add('P1', MUSIC, fadeWindow(f, 840, CROSSFADE, 1100, CROSSFADE));
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
  // P9：终端拖到落点小岛，去左半屏。
  if (f >= 4320 && f < 4980 + CROSSFADE) add('P9', dropTermRect(f), fadeWindow(f, 4320, CROSSFADE, 4980, CROSSFADE));
  // P8：聊天窗口，番茄钟开始后自己收进刘海。
  if (f >= 8040 && f < TUCK_B + Math.ceil(TUCK_FRAMES)) {
    const opacity = clamp01((f - 8040) / CROSSFADE);
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
  // 第 2 段：在音乐里按播放。
  { show: 860, hide: 960, start: { x: 62, y: 92 }, moves: [{ at: 870, to: PLAY_BUTTON }], presses: [[MUSIC_PLAY - ms(TEACH.press), MUSIC_PLAY]] },
  // 第 3 段：按住终端的标题栏甩进刘海；停到刘海上；移开；再停上去、点格子放回。
  { show: 1850, hide: TUCK_A, start: { x: 50, y: 25 }, moves: [], presses: [[1880, TUCK_A]] },
  { show: 2040, hide: 2360, start: { x: 50, y: 58 }, moves: [{ at: 2060, to: ON_NOTCH }, { at: 2300, to: { x: 50, y: 40 } }], presses: [] },
  { show: 2640, hide: 2830, start: { x: 50, y: 46 }, moves: [{ at: 2650, to: ON_NOTCH }, { at: 2725, to: { x: 50, y: 24 } }], presses: [[CLICK_CARD - ms(TEACH.press), CLICK_CARD]] },
  // 第 4 段：点刘海；按住一个图标拖到左边。
  { show: 2900, hide: RELEASE_ICON + 10, start: { x: 50, y: 50 }, moves: [{ at: 2930, to: ON_NOTCH }, { at: 3040, to: DRAG.from }, { at: DRAG.start, to: DRAG.to }], presses: [[3010, 3021], [DRAG.press, RELEASE_ICON]] },
  // 第 5 段：点把手。
  { show: 3940, hide: 4060, start: { x: 30, y: 50 }, moves: [{ at: 3950, to: TEACH_HANDLE }], presses: [[4030, HANDLE_CLICK]] },
  // drop：按住终端标题栏，往上拖到刘海，横移到左半屏那一格，松手。
  {
    show: 4380, hide: DROP_RELEASE + 40, start: { x: 56, y: 52 },
    moves: [{ at: 4395, to: GRAB_PT }, { at: DRAG_UP, to: dropCell(2) }, { at: DRAG_SIDE, to: dropCell(0) }, { at: DROP_RELEASE + 4, to: { x: 30, y: 40 } }],
    presses: [[GRAB - ms(TEACH.press), DROP_RELEASE]],
  },
  // approve：点“允许”。
  { show: 6200, hide: CLICK_ALLOW + 30, start: { x: 56, y: 48 }, moves: [{ at: 6215, to: ALLOW_PT }], presses: [[CLICK_ALLOW - ms(TEACH.press), CLICK_ALLOW]] },
  // hold：长按刘海；再长按回来。
  { show: 6700, hide: 6830, start: { x: 50, y: 45 }, moves: [{ at: 6710, to: ON_NOTCH }], presses: [[PRESS_LONG_A, 6830]] },
  { show: 7080, hide: 7210, start: { x: 50, y: 40 }, moves: [{ at: 7090, to: ON_NOTCH }], presses: [[PRESS_LONG_B, 7210]] },
  // back：点“离开期间”里的聊天那一行。
  { show: CLICK_SUMMARY - 120, hide: CLICK_SUMMARY + 30, start: { x: 54, y: 70 }, moves: [{ at: CLICK_SUMMARY - 110, to: ROW_CHAT_PT }], presses: [[CLICK_SUMMARY - ms(TEACH.press), CLICK_SUMMARY]] },
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

/** 按住的图标跟着指针走，松手那一帧变成窗口。 */
export function dragIconAt(f: number): Pt | null {
  if (f < DRAG.press || f >= RELEASE_ICON) return null;
  const p = pointerAt(f);
  return p && { x: p.x, y: p.y };
}
export const DRAGGED_APP = 'notes';
export const DRAG_PRESS = DRAG.press;

// ---- 屏外的实物线稿：耳机、鼠标（只在画出来的那一版） ----
export function deviceAt(f: number): { kind: 'pods' | 'mouse'; opacity: number; on: number } | null {
  const show = (cause: number, end: number) => Math.min(clamp01((f - (cause - 50)) / FADE_IN), 1 - clamp01((f - end) / FADE_OUT));
  if (f >= CAUSE_PODS - 50 && f < PODS_END + FADE_OUT) return { kind: 'pods', opacity: show(CAUSE_PODS, PODS_END), on: clamp01((f - CAUSE_PODS) / FADE_IN) };
  if (f >= CAUSE_MOUSE - 50 && f < MOUSE_END + FADE_OUT) return { kind: 'mouse', opacity: show(CAUSE_MOUSE, MOUSE_END), on: clamp01((f - CAUSE_MOUSE) / FADE_IN) };
  return null;
}

// ---- 屏外的触控板（site/teach.js 的画法与节奏） ----
export function trackpadAt(f: number) {
  // 侧拉一段用一次，落点小岛那段用指针，让开；画一笔那段再出来。
  const side = Math.min(clamp01((f - SIDE.pad) / FADE_IN), 1 - clamp01((f - 4320) / ms(TEACH.fade)));
  const draw = Math.min(clamp01((f - 4980) / FADE_IN), 1 - clamp01((f - 5760) / ms(TEACH.fade)));
  return Math.max(side, draw);
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
  if (f >= 8260 && f < PHONE_GONE) {
    const away = moveCurve(seg(f, PHONE_GONE - ms(TEACH.move), PHONE_GONE));
    const opacity = Math.min(clamp01((f - 8260) / FADE_IN), 1 - clamp01((f - (PHONE_GONE - FADE_OUT)) / FADE_OUT));
    return { away, opacity };
  }
  // 回来：同一条路倒着走进来，停在身边，是开锁的两样之一；解开后淡出。
  const settle = PHONE_BACK + ms(TEACH.move), leave = UNLOCK + 20;
  if (f >= PHONE_BACK && f < leave + FADE_OUT) {
    return { away: 1 - moveCurve(seg(f, PHONE_BACK, settle)), opacity: 1 - clamp01((f - leave) / FADE_OUT) };
  }
  return null;
}

/** 屏外戴着耳机的侧脸线稿：镜头拉回后出现，点一下头。读口型那一段镜头推在刘海上，看不到它。 */
export function headAt(f: number) {
  const show = ZOOM_LIPS[1] + 30, gone = 8000;
  if (f < show || f >= gone + FADE_OUT) return null;
  const opacity = Math.min(clamp01((f - show) / FADE_IN), 1 - clamp01((f - gone) / FADE_OUT));
  const tilt = NOD_DEG * (moveCurve(seg(f, NOD_DOWN, NOD_DOWN + NOD_FRAMES)) - moveCurve(seg(f, NOD_DOWN + NOD_FRAMES, NOD_DONE)));
  return { opacity, tilt };
}

/** 锁上：屏里的东西叠化成黑；系统确认解开后叠化回来。 */
export const screenDark = (f: number) => clamp01((f - LOCK_AT) / CROSSFADE) * (1 - clamp01((f - UNLOCK) / CROSSFADE));

// ---- 推近刘海：读口型、回来认人，两处小字要看清 ----
/** 推近的程度 0–1：motion-direction 的 dolly（1.6 / 1.0）推进，拉回再用同一根。 */
export function zoomAt(f: number) {
  let z = 0;
  for (const [a, b] of [ZOOM_LIPS, ZOOM_BACK]) if (f >= a) z = Math.max(z, dolly(f, a) * (1 - dolly(f, b)));
  return z;
}
