// 镜头：俯角、侧转、变焦（换长焦：每厘米像素 U 和透视距离一起乘），对准一个点（厘米，世界坐标）。
// 两个键之间走一根临界阻尼弹簧（promo/ 的做法：位移只走弹簧），响应时间按间隔定，到下一个键时已经停稳。
// 相邻两个键一样就是定住：一帧不差。
import { LEAN, MACHINES, type MachineId } from './machines';

export const U0 = 34, P0 = 2600;
export type V3 = [number, number, number];
export type CamState = { zoom: number; elev: number; yaw: number; focus: V3 };

const rad = (d: number) => (d * Math.PI) / 180;

/** 片尾两台并排：Air 在原点，Neo 在左边。 */
export const PLACE: Record<MachineId, V3> = { air: [0, 0, 0], neo: [-39, 0, 0] };

/** 盖子上离转轴 s 厘米、离中线 x 厘米的点（机器自己的坐标）。 */
export const lidPoint = (s: number, x = 0): V3 => [x, -s * Math.cos(rad(LEAN)), -s * Math.sin(rad(LEAN))];

/** 屏幕上的点（点坐标）→ 世界坐标。 */
export function sp(m: MachineId, px: number, py: number, placed = false): V3 {
  const M = MACHINES[m];
  const p = lidPoint(M.screen.from + ((M.pt.h - py) / M.pt.h) * M.screen.h, (px / M.pt.w - 0.5) * M.screen.w);
  const o = placed ? PLACE[m] : [0, 0, 0];
  return [p[0] + o[0], p[1] + o[1], p[2] + o[2]];
}

const NEO_LED: V3 = lidPoint(MACHINES.neo.camAt, 0.47);
const neoMid: V3 = [0, -5.5, MACHINES.neo.depth * 0.22];
const N = (x: number, y: number) => sp('neo', x, y);
const A = (x: number, y: number) => sp('air', x, y);

type Key = [number, number, number, number, V3];
/** [帧, 变焦, 俯角, 侧转, 对准]。交接那一帧前后各一个键：前一台推进岛，后一台从岛里拉出。 */
const KEYS: Key[] = [
  [0, 7, 4, -4, NEO_LED], [90, 7, 4, -4, NEO_LED],
  [300, 0.95, 17, -24, neoMid], [360, 0.95, 17, -24, neoMid],
  [430, 3.0, 9, -12, N(704, 70)], [560, 3.15, 9, -11, N(704, 70)],
  [600, 4.4, 8, -9, N(704, 66)],
  // Air：主屏幕
  [600.001, 4.2, 8, 10, A(855, 16)], [680, 1.55, 13, 14, A(855, 420)], [940, 1.6, 13, 13, A(855, 420)],
  [1040, 3.0, 8, 8, A(855, 60)], [1080, 4.2, 7, 6, A(855, 56)],
  // Neo：读唇、点头
  [1080.001, 4.6, 6, -6, N(704, 52)], [1110, 4.2, 6, -6, N(704, 52)], [1290, 4.2, 6, -6, N(704, 52)],
  [1400, 1.9, 10, 9, N(560, 300)], [1640, 1.9, 10, 9, N(560, 300)],
  [1750, 3.0, 8, -8, N(704, 50)], [1800, 4.2, 7, -6, N(704, 46)],
  // Air：实时活动
  [1800.001, 4.0, 7, 8, A(855, 40)], [1840, 2.6, 8, 10, A(855, 70)], [2000, 2.6, 8, 10, A(855, 70)],
  [2060, 2.3, 10, -12, A(855, 80)], [2230, 2.3, 10, -12, A(855, 80)], [2280, 3.8, 8, -8, A(855, 52)],
  // Neo：番茄钟
  [2280.001, 3.4, 8, 8, N(704, 80)], [2320, 2.5, 9, 10, N(704, 110)], [2400, 2.5, 9, 10, N(704, 110)],
  [2460, 1.45, 13, 16, N(704, 380)], [2820, 1.45, 13, 16, N(704, 380)], [2880, 3.4, 8, 8, N(704, 66)],
  // Air：走开
  [2880.001, 3.6, 7, -8, A(855, 60)], [2920, 2.5, 8, -10, A(855, 100)], [3150, 2.5, 8, -10, A(855, 100)],
  [3250, 1.15, 15, -20, A(855, 500)],
  // 片尾：拉远，Neo 出现在左边
  [3430, 0.6, 18, -6, [-19.5, -6.5, 6]], [TOTAL_END(), 0.6, 18, -6, [-19.5, -6.5, 6]],
];
function TOTAL_END() { return 3600; }

const same = (a: Key, b: Key) => a[1] === b[1] && a[2] === b[2] && a[3] === b[3] && a[4].every((v, i) => v === b[4][i]);

function crit(t: number, resp: number) {
  if (t <= 0) return 0;
  const w = (2 * Math.PI) / resp;
  return 1 - (1 + w * t) * Math.exp(-w * t);
}

export function camAt(f: number): CamState {
  let i = 0;
  while (i < KEYS.length - 1 && f >= KEYS[i + 1][0]) i++;
  const a = KEYS[i], b = KEYS[Math.min(i + 1, KEYS.length - 1)];
  if (a === b || same(a, b) || b[0] - a[0] < 0.01) return { zoom: a[1], elev: a[2], yaw: a[3], focus: a[4] };
  const gap = (b[0] - a[0]) / 60;
  const p = crit((f - a[0]) / 60, gap * 0.62);
  const lerp = (x: number, y: number) => x + (y - x) * p;
  return {
    zoom: Math.exp(lerp(Math.log(a[1]), Math.log(b[1]))),
    elev: lerp(a[2], b[2]), yaw: lerp(a[3], b[3]),
    focus: [lerp(a[4][0], b[4][0]), lerp(a[4][1], b[4][1]), lerp(a[4][2], b[4][2])],
  };
}

/** 是否定住（快门、颗粒用）。 */
export function holding(f: number) {
  let i = 0;
  while (i < KEYS.length - 1 && f >= KEYS[i + 1][0]) i++;
  const a = KEYS[i], b = KEYS[Math.min(i + 1, KEYS.length - 1)];
  return a === b || same(a, b);
}

export const worldTransform = (c: CamState) => {
  const U = U0 * c.zoom;
  const [fx, fy, fz] = c.focus.map((v) => v * U);
  return `rotateX(${-c.elev}deg) rotateY(${c.yaw}deg) translate3d(${-fx}px, ${-fy}px, ${-fz}px)`;
};

/** 世界坐标（厘米）投到画面（像素），和 CSS 的做法一样。 */
export function project(c: CamState, p: V3, W: number, H: number): [number, number] {
  const U = U0 * c.zoom, P = P0 * c.zoom;
  let x = (p[0] - c.focus[0]) * U, y = (p[1] - c.focus[1]) * U, z = (p[2] - c.focus[2]) * U;
  const cy = Math.cos(rad(c.yaw)), sy = Math.sin(rad(c.yaw));
  [x, z] = [x * cy + z * sy, -x * sy + z * cy];
  const th = rad(-c.elev), ct = Math.cos(th), st = Math.sin(th);
  [y, z] = [y * ct - z * st, y * st + z * ct];
  const k = P / (P - z);
  return [W / 2 + x * k, H / 2 + y * k];
}
