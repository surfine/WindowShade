// 同一個場景裡的鏡頭。兩台機器隔開擺，交接是鏡頭走過去，不再用一塊黑島蓋住畫面。
// 俯仰、側轉、距離都繞著模型自己的點（米，glTF Y 向上）。蓋子的開合是網格裡的，這裡不改。
import type { MachineId } from './machines';

export type V3 = [number, number, number];

/** 中心距 0.56 m，寬鏡頭看一台時另一台在畫面外；片尾拉遠才同時看見。 */
export const SEAT: Record<MachineId, number> = { neo: -0.28, air: 0.28 };

const L = {
  neo: {
    led: [0, 0.184, -0.178] as V3,
    island: [0, 0.172, -0.168] as V3,
    screen: [0, 0.098, -0.146] as V3,
    deck: [0, 0.006, 0.008] as V3,
  },
  air: {
    island: [0, 0.2, -0.188] as V3,
    screen: [0, 0.113, -0.161] as V3,
    deck: [0, 0.006, 0.014] as V3,
  },
};

const world = (m: MachineId, p: V3): V3 => [p[0] + SEAT[m], p[1], p[2]];

type Shot = { f: number; aim: V3; dist: number; elev: number; yaw: number };

const BOTH: V3 = [0, 0.09, -0.1];

const KEYS: Shot[] = [
  // 开场拉开：看得见备忘录窗和即将收进的胶囊（审片 C11-05）。
  { f: 0, aim: world('neo', L.neo.screen), dist: 0.56, elev: 16, yaw: -8 },
  { f: 240, aim: world('neo', L.neo.screen), dist: 0.54, elev: 15, yaw: -6 },
  // 解锁：机身上缘低于字幕带（审片 C10-02）。略拉远、略俯，银边不穿标题。
  { f: 400, aim: world('neo', L.neo.screen), dist: 0.52, elev: 15, yaw: -5 },
  { f: 560, aim: world('neo', L.neo.screen), dist: 0.58, elev: 16, yaw: -4 },
  // 露出→收进→结果保持同一参照（审片 C13-01），不平移抢戏：整段停在屏上。
  { f: 710, aim: world('neo', L.neo.screen), dist: 0.60, elev: 16, yaw: -2 },
  // Air 主屏幕
  { f: 760, aim: world('air', L.air.screen), dist: 0.56, elev: 16, yaw: 12 },
  { f: 960, aim: world('air', L.air.screen), dist: 0.54, elev: 16, yaw: 10 },
  { f: 1060, aim: world('air', L.air.island), dist: 0.30, elev: 10, yaw: 6 },
  // 口型：候选停稳；确认后镜头先到桌面（节拍已缩短）。
  { f: 1120, aim: world('neo', L.neo.island), dist: 0.34, elev: 10, yaw: -4 },
  { f: 1380, aim: world('neo', L.neo.island), dist: 0.34, elev: 10, yaw: -4 },
  { f: 1460, aim: world('neo', L.neo.screen), dist: 0.50, elev: 14, yaw: 8 },
  { f: 1780, aim: world('neo', L.neo.screen), dist: 0.50, elev: 14, yaw: 6 },
  // 实时活动
  { f: 1840, aim: world('air', [-0.04, 0.15, -0.16]), dist: 0.64, elev: 14, yaw: 8 },
  { f: 2000, aim: world('air', [-0.03, 0.15, -0.16]), dist: 0.62, elev: 14, yaw: 6 },
  { f: 2060, aim: world('air', L.air.island), dist: 0.36, elev: 11, yaw: -2 },
  { f: 2220, aim: world('air', L.air.island), dist: 0.36, elev: 11, yaw: -2 },
  // 番茄钟：字幕段机身上缘让开标题。
  { f: 2320, aim: world('neo', L.neo.screen), dist: 0.52, elev: 15, yaw: 8 },
  { f: 2620, aim: world('neo', L.neo.screen), dist: 0.56, elev: 16, yaw: 6 },
  { f: 2720, aim: world('neo', L.neo.screen), dist: 0.50, elev: 14, yaw: 4 },
  { f: 2900, aim: world('neo', L.neo.screen), dist: 0.50, elev: 14, yaw: 4 },
  // 离开就锁：停在锁屏上，硬切片尾前不再叠化回桌面。
  { f: 2960, aim: world('air', [-0.05, 0.16, -0.15]), dist: 0.74, elev: 14, yaw: -6 },
  { f: 3180, aim: world('air', L.air.island), dist: 0.42, elev: 12, yaw: -4 },
  { f: 3299, aim: world('air', L.air.island), dist: 0.42, elev: 12, yaw: -4 },
  // 3300 硬切：两台同一套桌面。
  { f: 3300, aim: BOTH, dist: 1.22, elev: 16, yaw: -4 },
  { f: 3600, aim: BOTH, dist: 1.22, elev: 16, yaw: -4 },
];

const rad = (d: number) => (d * Math.PI) / 180;

/** 動效樣片的 dolly：1.6 / 1.0，只給鏡頭。 */
function dolly(t: number) {
  if (t <= 0) return 0;
  const w = (2 * Math.PI) / 1.6;
  const p = 1 - (1 + w * t) * Math.exp(-w * t);
  return p < 0 ? 0 : p;
}

const same = (a: Shot, b: Shot) => a.dist === b.dist && a.elev === b.elev && a.yaw === b.yaw && a.aim.every((v, i) => v === b.aim[i]);

function pair(f: number) {
  let i = 0;
  while (i < KEYS.length - 1 && f >= KEYS[i + 1].f) i++;
  return [KEYS[i], KEYS[Math.min(i + 1, KEYS.length - 1)]] as const;
}

export function holding(f: number) {
  const [a, b] = pair(f);
  return a === b || same(a, b);
}

export type Pose = { pos: V3; aim: V3; fov: number };

export function shotAt(f: number): Pose {
  const [a, b] = pair(f);
  const mix = (x: number, y: number, p: number) => x + (y - x) * p;
  let p = 0;
  if (a !== b && !same(a, b) && b.f - a.f >= 0.01) {
    p = dolly((f - a.f) / 60);
  }
  const dist = Math.exp(mix(Math.log(a.dist), Math.log(b.dist), p));
  const elev = mix(a.elev, b.elev, p);
  const yaw = mix(a.yaw, b.yaw, p);
  const aim: V3 = [mix(a.aim[0], b.aim[0], p), mix(a.aim[1], b.aim[1], p), mix(a.aim[2], b.aim[2], p)];
  const er = rad(elev), yr = rad(yaw), cp = Math.cos(er);
  return {
    fov: 30,
    aim,
    pos: [aim[0] + dist * Math.sin(yr) * cp, aim[1] + dist * Math.sin(er), aim[2] + dist * Math.cos(yr) * cp],
  };
}
