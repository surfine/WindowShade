// B 站版（第二稿，约 54 秒）：从 169 秒的母带（timeline.ts）里按 1:1 速度取 17 个镜头，踩着配乐的拍子剪。
// 故事照 Aaron 的公式：（刷脸解锁 + 唇语控制 + 头部动作）× 窗口管理 × 启动台 @ 灵动岛——
// 先说问题（桌面挤满了），再一段一件事：收进刘海、启动台、拖到刘海、画一笔说一句、读口型点头、走开就锁、看一眼解锁。
// 语法照第一部：每段一句大标题，每一刀都换景别（整机 / 桌面 / 中景 / 近景 / 特写），只在拍上剪。
// 母带里的弹簧、收起 0.52 秒、提醒停留一帧不改；只剪掉等待和指针走路。
import { FPS } from './motion/site';
import { beatFrame, SECTIONS } from './music';

/**
 * 景别（镜头离刘海多近）：
 * wide 整机，盖子后仰约 110°、略俯视（只在开头、结尾）；desk 正面整机加屏外的触控板、手机；
 * medium 屏幕铺满画面宽；near 屏幕比画面宽一点，刘海靠上；close 刘海占画面宽 15–20%。
 */
export type Framing = 'wide' | 'desk' | 'medium' | 'near' | 'close';
export type HeadId = 'problem' | 'tuck' | 'launch' | 'drop' | 'draw' | 'nod' | 'away' | 'face' | 'end';

/** 每段一句（照 docs/copy-guide.md：说用户遇到的事，一屏一句，不超过 12 个字），下面一行英文小字。 */
export const HEADLINES: Record<Exclude<HeadId, 'end'>, { zh: string; en: string }> = {
  problem: { zh: '窗口太多，桌面挤满了', en: 'Too many windows. No room left.' },
  tuck: { zh: '收进刘海，点一下放回', en: 'Tuck it into the notch. Tap to bring it back.' },
  launch: { zh: '点一下刘海，打开启动台', en: 'Tap the notch for Launchpad.' },
  drop: { zh: '拖到刘海，选个位置', en: 'Drag to the notch, pick a spot.' },
  draw: { zh: '画一笔，说一句', en: 'Draw a stroke. Say a line.' },
  nod: { zh: '不出声，点头就照做', en: 'Mouth it. Nod to confirm.' },
  away: { zh: '走开就锁', en: 'Walk away. It locks.' },
  face: { zh: '回来看一眼，窗口都在', en: 'Look back. Everything stays put.' },
};

type Plan = { id: string; from: number; to: number; key: number; on: number; framing: Framing; head: HeadId; why: string };
export type Shot = { id: string; src: [number, number]; why: string; key: number; on: number; framing: Framing; head: HeadId; punch?: boolean };

/** from / to / on 是片子的拍号；key 是母带里那个动作的帧，落在第 on 拍。 */
const PLANS: Plan[] = [
  { id: 'open', from: 0, to: 4, key: 1777, on: 0, framing: 'wide', head: 'problem', why: '整机：桌面一扇扇堆满（问题先说）' },
  { id: 'tuck', from: 4, to: 10, key: 1899, on: 5, framing: 'close', head: 'tuck', why: '特写：终端被吸进刘海，其余几扇跟着进去' },
  { id: 'peek', from: 10, to: 12, key: 2127, on: 11, framing: 'medium', head: 'tuck', why: '中景：停到刘海上，看见收起来的那扇' },
  { id: 'back', from: 12, to: 18, key: 2806, on: 15, framing: 'close', head: 'tuck', why: '特写：点格子，终端从刘海飞回原处' },
  { id: 'launch', from: 18, to: 24, key: 3021, on: 20, framing: 'near', head: 'launch', why: '近景：点刘海，启动台从刘海长出来' },
  { id: 'drag', from: 24, to: 28, key: 4470, on: 26, framing: 'medium', head: 'drop', why: '中景：按住标题栏往刘海拖（曲子抬升）' },
  { id: 'slots', from: 28, to: 36, key: 4530, on: 28, framing: 'close', head: 'drop', why: '特写：五个落点垂下来，选左半屏松手' },
  { id: 'draw', from: 36, to: 46, key: 5201, on: 44, framing: 'desk', head: 'draw', why: '整机加触控板：画一笔' },
  { id: 'say', from: 46, to: 58, key: 5532, on: 55, framing: 'medium', head: 'draw', why: '中景：那一笔落进刘海，说一句，刘海接着做' },
  { id: 'lips', from: 58, to: 66, key: 7620, on: 64, framing: 'close', head: 'nod', why: '特写：读口型，认出“左半屏”' },
  { id: 'nod', from: 66, to: 72, key: 7740, on: 67, framing: 'medium', head: 'nod', why: '中景：刘海里的 AirPods 点一下头，草稿去左半屏' },
  { id: 'away', from: 72, to: 78, key: 8360, on: 74, framing: 'desk', head: 'away', why: '整机：手机走开' },
  { id: 'count', from: 78, to: 82, key: 9050, on: 81, framing: 'close', head: 'away', why: '特写：倒数走完，锁上' },
  { id: 'return', from: 82, to: 86, key: 9080, on: 82, framing: 'desk', head: 'face', why: '整机：手机回到身边' },
  { id: 'face', from: 86, to: 92, key: 9310, on: SECTIONS.peak, framing: 'close', head: 'face', why: '特写：面容 ID 打勾、两样都对上，落在全曲最大的推高' },
  { id: 'unlocked', from: 92, to: 98, key: 9470, on: 93, framing: 'medium', head: 'face', why: '中景：解开，窗口都在原处' },
  { id: 'end', from: 98, to: SECTIONS.fall, key: 9640, on: 99, framing: 'wide', head: 'end', why: '整机：聊天放回；片名落在最后一个重拍' },
];

/** 片尾：能量落下的那一拍之后再停半秒，音乐跟着淡完，最后 0.4 秒淡到黑。 */
const TAIL = 30;

export const SHOTS: Shot[] = PLANS.map((p, i) => {
  const start = beatFrame(p.from), end = beatFrame(p.to) + (i === PLANS.length - 1 ? TAIL : 0);
  const s0 = p.key - (beatFrame(p.on) - start);
  return { id: p.id, src: [s0, s0 + end - start], why: p.why, key: p.key, on: p.on, framing: p.framing, head: p.head };
});

const STARTS = SHOTS.reduce<number[]>((a, s, i) => [...a, i ? a[i - 1] + (SHOTS[i - 1].src[1] - SHOTS[i - 1].src[0]) : 0], []);
export const SHOT_AT = STARTS;
export const OUT_TOTAL = STARTS[STARTS.length - 1] + (SHOTS[SHOTS.length - 1].src[1] - SHOTS[SHOTS.length - 1].src[0]);

const shotIndex = (out: number) => {
  for (let i = STARTS.length - 1; i >= 0; i--) if (out >= STARTS[i]) return i;
  return 0;
};
export const shotAt = (out: number) => SHOTS[shotIndex(out)];

/** 成片第 out 帧放母带的哪一帧。 */
export function srcAt(out: number): number {
  const i = shotIndex(out);
  return SHOTS[i].src[0] + (out - STARTS[i]);
}

/** 母带第 src 帧在成片里是第几帧（必须落在某一段里；落在两段重叠处取前一段）。 */
export function outOf(src: number): number {
  const i = SHOTS.findIndex((s) => src >= s.src[0] && src < s.src[1]);
  if (i < 0) throw new Error(`母带第 ${src} 帧没剪进成片`);
  return STARTS[i] + (src - SHOTS[i].src[0]);
}

/** 第 out 帧所在那一段的第一帧：快门取样不能跨过剪接点。 */
export const shotStartAt = (out: number) => STARTS[shotIndex(out)];

// ---- 标题：一段一句，从这一段第一刀进、到最后一刀出 ----
export const CAPTIONS: { head: HeadId; text: string; en: string; from: number; to: number }[] = [];
for (let i = 0; i < SHOTS.length; i++) {
  const h = SHOTS[i].head;
  if (h === 'end') continue;
  const last = CAPTIONS[CAPTIONS.length - 1];
  const to = STARTS[i] + SHOTS[i].src[1] - SHOTS[i].src[0];
  if (last && last.head === h) last.to = to;
  else CAPTIONS.push({ head: h, text: HEADLINES[h].zh, en: HEADLINES[h].en, from: STARTS[i], to });
}
/** 片名落在最后一个重拍。 */
export const WORDMARK_AT = beatFrame(SECTIONS.lastHit);
export const FADE_TO_BLACK = [OUT_TOTAL - 24, OUT_TOTAL] as const;

/** 标题进场：0.3 秒淡入、往上升 0.6 个字高（正弦缓动）；出场 0.1 秒淡出。 */
export const HEAD_IN = Math.round(0.3 * FPS), HEAD_OUT = Math.round(0.1 * FPS);
export function captionOpacity(out: number, from: number, to: number) {
  const c = (v: number) => Math.max(0, Math.min(1, v));
  return Math.min(c((out - from) / HEAD_IN), 1 - c((out - (to - HEAD_OUT)) / HEAD_OUT));
}

/**
 * 配乐退到后面的两段（成片帧号，都在拍上）：音乐不停，只低 4 dB、滤掉 1.2 kHz 以上，像隔了一道门。scripts/score.py 按它混音。
 * 读口型（「不出声」）一段；锁上到面容 ID 打勾一段，打勾那一拍整首回来。不做真静音：Aaron 听成「声音时断时续」。
 */
export const UNDER: [number, number][] = [
  [beatFrame(58), beatFrame(66)],
  [beatFrame(81), beatFrame(SECTIONS.peak)],
];
/** 音乐收尾：最后一个重拍之后一拍开始一路淡到片尾最后一帧。 */
export const MUSIC_TAIL = [beatFrame(SECTIONS.lastHit + 1), OUT_TOTAL] as const;
