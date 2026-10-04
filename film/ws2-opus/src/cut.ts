// B 站剪辑版：从 169 秒的母带（timeline.ts）里按 1:1 速度取几段接起来，约 86 秒。
// 母带里的弹簧、收起 0.52 秒、提醒停留、先等一拍一帧不改；只剪掉等待、指针走路和重复的演示。
// 每个剪接点两边的刘海是同一个状态（scripts/report.ts 会列出来核对），刘海就是贯穿全片的那条线。
import { CAPTION_IN, CAPTION_OUT } from './motion/direction';
import { FPS } from './motion/site';
import { SEGMENTS } from './timeline';

export type Shot = { id: string; src: [number, number]; why: string; punch?: boolean };

/** 母带里的 [起, 止)。punch：剪接点两边屏里的东西不一样，镜头往刘海顶一下再回来。 */
export const SHOTS: Shot[] = [
  { id: 'open', src: [1868, 1990], why: '冷开场：终端窗口被吸进刘海，0.5 秒内发生' },
  { id: 'peek', src: [2040, 2370], why: '停到刘海上，看见收起来的那扇' },
  { id: 'back', src: [2440, 3300], why: '构建跑完从刘海开口；点格子放回；点刘海回到主屏幕，图标拖成侧拉' },
  { id: 'drop', src: [4360, 4900], why: '拖到刘海，五个落点', punch: true },
  { id: 'draw', src: [4980, 5340], why: '触控板画一笔，原样落进刘海' },
  { id: 'say', src: [5500, 5790], why: '说一句，刘海接着做' },
  { id: 'allow', src: [6110, 6700], why: '要你放行的，在刘海里问一次' },
  { id: 'nod', src: [7380, 8560], why: '推近读口型，点头照做；专注时聊天自己收起；手机走开开始倒数' },
  { id: 'lock', src: [8990, 9900], why: '锁上；回来人和手机都对上才开；离开期间；聊天放回；片名', punch: true },
];

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
  const i = SHOTS.findIndex((s) => src >= s.src[0] && src <= s.src[1]);
  if (i < 0) throw new Error(`母带第 ${src} 帧没剪进成片`);
  return STARTS[i] + (src - SHOTS[i].src[0]);
}

// ---- 字幕：一段一句，8 句（母带是 12 句）。照 docs/copy-guide.md，每句不超过 12 个字 ----
const line = (id: string) => SEGMENTS.find((s) => s.id === id)!.line;
export const CAPTIONS: { text: string; from: number; to: number }[] = [
  { text: line('tuck'), from: 30, to: outOf(2880) },
  { text: line('home'), from: outOf(2900), to: outOf(3300) },
  { text: line('drop'), from: outOf(4380), to: outOf(4900) },
  { text: line('draw'), from: outOf(5000), to: outOf(5790) },
  { text: line('approve'), from: outOf(6130), to: outOf(6700) },
  { text: line('nod'), from: outOf(7400), to: outOf(8040) },
  { text: line('away'), from: outOf(8060), to: outOf(9040) },
  { text: line('back'), from: outOf(9080), to: outOf(9700) },
];
export const WORDMARK_AT = outOf(9700);
export const FADE_TO_BLACK = [OUT_TOTAL - 24, OUT_TOTAL] as const;

export function captionOpacity(out: number, from: number, to: number) {
  const c = (v: number) => Math.max(0, Math.min(1, v));
  return Math.min(c((out - from) / CAPTION_IN), 1 - c((out - (to - CAPTION_OUT)) / CAPTION_OUT));
}

// ---- 成片自己的镜头（母带里的推近照旧，跟着母带帧号走） ----
/** 冷开场：第 0 帧就推在刘海上，窗口从下面被吸进去；落定半秒后拉回整台电脑。[片子新增] */
export const OPEN_PULL = 96;
/** 剪接点往刘海顶一下：第一帧放大 5%，用 settle（0.38 / 1.0）回到原样。[片子新增] */
export const PUNCH = { amount: 0.05, response: 0.38 };
export const PUNCH_AT = SHOTS.flatMap((s, i) => (s.punch ? [STARTS[i]] : []));

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
