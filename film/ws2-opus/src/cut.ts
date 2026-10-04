// B 站剪辑版：从 169 秒的母带（timeline.ts）里按 1:1 速度取几段接起来，踩着配乐的拍子剪，约 87.6 秒。
// 母带里的弹簧、收起 0.52 秒、提醒停留、先等一拍一帧不改；只剪掉等待、指针走路和重复的演示。
// 每个剪接点两边的刘海是同一个状态（scripts/report.ts 会列出来核对），刘海就是贯穿全片的那条线。
// 对拍的办法：每段写“从第几拍开始、到第几拍结束、哪个动作落在第几拍”，母带的起点由此倒推，所以剪接点和那个动作都在拍上。
import { CAPTION_IN, CAPTION_OUT } from './motion/direction';
import { FPS } from './motion/site';
import { SEGMENTS } from './timeline';
import { SECTIONS, beatFrame } from './music';

type Plan = { id: string; from: number; to: number; key: number; on: number; why: string; punch?: boolean };
export type Shot = { id: string; src: [number, number]; why: string; punch?: boolean; key: number; on: number };

/** from / to / on 是曲子的拍号；key 是母带里那个动作的帧，落在第 on 拍。第一段从成片第 0 帧开始。 */
const PLANS: Plan[] = [
  { id: 'open', from: -1, to: 5, key: 1899, on: 2, why: '冷开场：终端窗口被吸进刘海，落在第一个小节线' },
  { id: 'peek', from: 5, to: 17, key: 2127, on: 8, why: '停到刘海上，看见收起来的那扇' },
  { id: 'back', from: 17, to: 47, key: 2460, on: 18, why: '构建跑完从刘海开口（小节线）；点格子放回；点刘海回到主屏幕，图标拖成侧拉' },
  { id: 'drop', from: 47, to: 65, key: 4530, on: 52, why: '拖到刘海，五个落点垂下来；镜头跨过剪接点往刘海靠（lean）' },
  { id: 'draw', from: 65, to: 77, key: 5267, on: 75, why: '触控板画一笔，原样落进刘海' },
  { id: 'say', from: 77, to: 87, key: 5532, on: 78, why: '说一句，刘海接着做（小节线）' },
  { id: 'allow', from: 87, to: 107, key: 6166, on: 89, why: '要你放行的，在刘海里问一次' },
  { id: 'nod', from: 107, to: 122, key: 7740, on: 119, why: '推近读口型，点头照做' },
  { id: 'away', from: 122, to: 146, key: 8166, on: SECTIONS.surge, why: '专注时聊天自己收进刘海，落在第一次推高；手机走开开始倒数' },
  { id: 'lock', from: 146, to: SECTIONS.fall, key: 9310, on: SECTIONS.peak, why: '锁上；回来，面容 ID 打勾落在全曲最大的推高；离开期间；聊天放回；片名', punch: true },
];

const outAt = (k: number) => (k < 0 ? 0 : beatFrame(k));
/** 片尾：能量落下的那一拍之后，片名再停 2.5 秒，音乐跟着淡完，最后 0.4 秒淡到黑。 */
const TAIL = 150;

export const SHOTS: Shot[] = PLANS.map((p, i) => {
  const start = outAt(p.from), end = beatFrame(p.to) + (i === PLANS.length - 1 ? TAIL : 0);
  const s0 = p.key - (beatFrame(p.on) - start);
  return { id: p.id, src: [s0, s0 + end - start], why: p.why, punch: p.punch, key: p.key, on: p.on };
});

const STARTS = SHOTS.reduce<number[]>((a, s, i) => [...a, i ? a[i - 1] + (SHOTS[i - 1].src[1] - SHOTS[i - 1].src[0]) : 0], []);
export const SHOT_AT = STARTS;
export const OUT_TOTAL = STARTS[STARTS.length - 1] + (SHOTS[SHOTS.length - 1].src[1] - SHOTS[SHOTS.length - 1].src[0]);

/** 成片第 out 帧放母带的哪一帧。 */
export function srcAt(out: number): number {
  for (let i = SHOTS.length - 1; i >= 0; i--) if (out >= STARTS[i]) return SHOTS[i].src[0] + (out - STARTS[i]);
  return SHOTS[0].src[0];
}

/** 母带第 src 帧在成片里是第几帧（必须落在某一段里）。 */
export function outOf(src: number): number {
  const i = SHOTS.findIndex((s) => src >= s.src[0] && src < s.src[1]);
  if (i < 0) throw new Error(`母带第 ${src} 帧没剪进成片`);
  return STARTS[i] + (src - SHOTS[i].src[0]);
}

/** 第 out 帧所在那一段的第一帧：快门取样不能跨过剪接点。 */
export function shotStartAt(out: number): number {
  for (let i = STARTS.length - 1; i >= 0; i--) if (out >= STARTS[i]) return STARTS[i];
  return 0;
}

// ---- 字幕：一段一句，8 句。照 docs/copy-guide.md，每句不超过 12 个字。进场、出场都在拍上 ----
const line = (id: string) => SEGMENTS.find((s) => s.id === id)!.line;
const cap = (id: string, a: number, b: number) => ({ text: line(id), from: beatFrame(a), to: beatFrame(b) });
export const CAPTIONS: { text: string; from: number; to: number }[] = [
  cap('tuck', 2, 36),
  cap('home', 37, 47),
  cap('drop', 48, 65),
  cap('draw', 66, 87),
  cap('approve', 88, 107),
  cap('nod', 108, 122),
  cap('away', 123, 149),
  cap('back', 150, SECTIONS.lastHit),
];
/** 片名落在能量落下去之前最后一个重拍。 */
export const WORDMARK_AT = beatFrame(SECTIONS.lastHit);
export const FADE_TO_BLACK = [OUT_TOTAL - 24, OUT_TOTAL] as const;
/**
 * 配乐让到后面的两段（成片帧号，都在拍上）：音乐不停，只低 4 dB、滤掉 1.2 kHz 以上，像隔了一道门。scripts/score.py 按它混音。
 * 读口型、点头：「不出声」那一段，到聊天被收进刘海那一拍（第一次推高）整首回到前面，和冷开场收窗口押韵。
 * 锁屏：屏幕一黑音乐退后，人回来、面容 ID 打勾那一拍（全曲最大的推高）整首回来。
 * 不做真静音：Aaron 听成「声音时断时续」。
 */
export const UNDER: [number, number][] = [
  [beatFrame(107), beatFrame(SECTIONS.surge)],
  [beatFrame(149), beatFrame(SECTIONS.peak)],
];
/** 音乐收尾：最后一个重拍之后一拍开始一路淡到片尾最后一帧，中间不留空白。 */
export const MUSIC_TAIL = [beatFrame(SECTIONS.lastHit + 1), OUT_TOTAL] as const;

export function captionOpacity(out: number, from: number, to: number) {
  const c = (v: number) => Math.max(0, Math.min(1, v));
  return Math.min(c((out - from) / CAPTION_IN), 1 - c((out - (to - CAPTION_OUT)) / CAPTION_OUT));
}

// ---- 成片自己的镜头（母带里的推近照旧，跟着母带帧号走） ----
/** 冷开场：第 0 帧就推在刘海上，窗口从下面被吸进去；落定后在第 4 拍拉回整台电脑。[片子新增] */
export const OPEN_PULL = beatFrame(4);
/** 剪接点往刘海顶一下：第一帧放大 5%，用 settle（0.38 / 1.0）回到原样。[片子新增] */
export const PUNCH = { amount: 0.05, response: 0.38 };
export const PUNCH_AT = SHOTS.flatMap((s, i) => (s.punch ? [STARTS[i]] : []));
/**
 * 跨剪接点往刘海靠：剪之前 0.3 秒镜头开始绕刘海放大到 1.14 倍，剪之后 0.3 秒到位，停 0.4 秒再用 0.8 秒退回。
 * 主屏幕换成桌面时，机身和刘海是跨过这一刀还在动的东西（onetake 的 carry），不然这一刀是换幻灯片。[片子新增]
 */
export const LEAN = { amount: 0.14, rise: 18, hold: 24, back: 48 } as const;
export const LEAN_AT = [STARTS[SHOTS.findIndex((s) => s.id === 'drop')]];

export function leanAt(out: number) {
  const ease = (v: number) => 0.5 - 0.5 * Math.cos(Math.PI * Math.max(0, Math.min(1, v)));
  let k = 0;
  for (const c of LEAN_AT) {
    const up = ease((out - (c - LEAN.rise)) / (2 * LEAN.rise));
    const down = ease((out - (c + LEAN.rise + LEAN.hold)) / LEAN.back);
    k = Math.max(k, up * (1 - down));
  }
  return LEAN.amount * k;
}

export function punchAt(out: number) {
  let k = 0;
  for (const at of PUNCH_AT) {
    const t = (out - at) / FPS;
    if (t < 0) continue;
    const w = (2 * Math.PI) / PUNCH.response;
    k = Math.max(k, (1 + w * t) * Math.exp(-w * t));
  }
  return PUNCH.amount * k;
}
