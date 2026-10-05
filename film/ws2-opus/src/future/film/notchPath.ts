// 15 吋 Air 顯示開口，量自 public/mesh/macbook-air-15in-silver.glb。
// 面板 2880×1864。豎邊寬 312 px，深 56 px。
// 肩圓 r = 9.9 px，同時切頂邊和豎邊。底圓 r = 18.5 px，同時切豎邊和底邊。
// 靜止時畫量到的洞。展開後肩部退出：一整塊不透明圓角矩形，頂邊貼邊框蓋住洞，
// 左右是豎直邊，只有底角用稿上的圓角。沒有窄頸，也沒有肩下的 S 形外撇。

/** 洞邊的 UV，只用來把鏡頭蓋進洞裡，不拿來畫島的外輪廓。 */
export const NOTCH_UV: ReadonlyArray<readonly [number, number]> = [
  [0.44124, 0], [0.44248, 0.00001], [0.44348, 0.00014], [0.44417, 0.00049], [0.4448, 0.00113],
  [0.44527, 0.00191], [0.44567, 0.00317], [0.44581, 0.00464], [0.44583, 0.00686], [0.4459, 0.02093],
  [0.44608, 0.02264], [0.44641, 0.02428], [0.44695, 0.0258], [0.44753, 0.02693], [0.44829, 0.02801],
  [0.44916, 0.02885], [0.4502, 0.02951], [0.45167, 0.02993], [0.45465, 0.03004], [0.5, 0.03004],
  [0.54535, 0.03004], [0.54833, 0.02993], [0.54981, 0.0295], [0.55084, 0.02885], [0.55171, 0.02801],
  [0.55247, 0.02693], [0.55305, 0.0258], [0.55359, 0.02428], [0.55392, 0.02264], [0.5541, 0.02093],
  [0.55417, 0.00686], [0.55419, 0.00464], [0.55433, 0.00317], [0.55474, 0.00191], [0.5552, 0.00112],
  [0.55583, 0.00049], [0.55653, 0.00014], [0.55753, 0.00001], [0.55877, 0],
];

const K = 1710 / 2880;
const BLEED = 0.45 * K;

export const SCREEN = { w: 1710, h: 1107 };

export const HOLE = {
  side: 156 * K,
  depth: 56 * K,
  rs: 9.9 * K,
  rb: 18.5 * K,
  w: 312 * K,
  h: 56 * K,
};

const r3 = (n: number) => Math.round(n * 1000) / 1000;

type Box = { x: number; y: number; w: number; h: number };
type Pt = [number, number];

/** 螢幕座標：0 指向 +x，角度增大朝 +y。取短弧。 */
function qarc(cx: number, cy: number, r: number, a0: number, a1: number, pts: Pt[]) {
  let da = a1 - a0;
  while (da > Math.PI) da -= Math.PI * 2;
  while (da < -Math.PI) da += Math.PI * 2;
  const n = 12;
  for (let i = 1; i <= n; i++) {
    const t = a0 + (da * i) / n;
    pts.push([cx + r * Math.cos(t), cy + r * Math.sin(t)]);
  }
}

/** 靜止：量到的硬體洞。肩圓切頂邊和豎邊，底圓切豎邊和底邊。 */
function hole(cx: number): { d: string; box: Box } {
  const hW = HOLE.side + BLEED;
  const rs = HOLE.rs + BLEED;
  const deep = HOLE.depth + BLEED;
  const useRb = HOLE.rb + BLEED;
  const sL = cx - hW;
  const sR = cx + hW;
  const pts: Pt[] = [[sL - rs, -0.5], [sL - rs, 0]];
  qarc(sL - rs, rs, rs, -Math.PI / 2, 0, pts);
  pts.push([sL, deep - useRb]);
  qarc(sL + useRb, deep - useRb, useRb, Math.PI, Math.PI / 2, pts);
  pts.push([sR - useRb, deep]);
  qarc(sR - useRb, deep - useRb, useRb, Math.PI / 2, 0, pts);
  pts.push([sR, rs]);
  qarc(sR + rs, rs, rs, Math.PI, -Math.PI / 2, pts);
  pts.push([sR + rs, -0.5]);
  const d = pts.map((p, i) => `${i === 0 ? 'M' : 'L'}${r3(p[0])} ${r3(p[1])}`).join('') + 'Z';
  return { d, box: { x: sL, y: 0, w: sR - sL, h: deep } };
}

/**
 * 展開：一整塊藥丸。頂邊貼著邊框（略伸進邊框，蓋住洞），
 * 左右豎直，底角用傳進來的稿上圓角。沒有頸，也沒有肩下的外擴。
 */
function grownPill(cx: number, w: number, h: number, rb: number): { d: string; box: Box } {
  const half = Math.max(w / 2, HOLE.w / 2 + HOLE.rs);
  const deep = Math.max(h, HOLE.depth);
  const rad = Math.max(HOLE.rb, Math.min(Math.max(0, rb), half, deep * 0.46));
  const x0 = cx - half;
  const x1 = cx + half;
  const y0 = -1.6;
  const y1 = deep;
  const pts: Pt[] = [[x0, y0], [x0, y1 - rad]];
  if (rad > 0.8) qarc(x0 + rad, y1 - rad, rad, Math.PI, Math.PI / 2, pts);
  else pts.push([x0, y1]);
  pts.push([x1 - rad, y1]);
  if (rad > 0.8) qarc(x1 - rad, y1 - rad, rad, Math.PI / 2, 0, pts);
  else pts.push([x1, y1]);
  pts.push([x1, y0]);
  const d = pts.map((p, i) => `${i === 0 ? 'M' : 'L'}${r3(p[0])} ${r3(p[1])}`).join('') + 'Z';
  return { d, box: { x: x0, y: 0, w: x1 - x0, h: deep } };
}

/** 靜止就是量到的洞。展開後是一整塊圓角矩形，肩部不再留在輪廓上。 */
export function fusedIslandD(w: number, h: number, rb: number, grown: boolean): { d: string; box: Box } {
  const cx = SCREEN.w / 2;
  if (!grown) return hole(cx);
  return grownPill(cx, Math.max(w, HOLE.w), Math.max(h, HOLE.depth), rb);
}

/** Neo 沒有硬體劉海：一顆膠囊，四個角都是切邊的四分之一圓。 */
export function capsuleD(x: number, y: number, w: number, h: number, r: number): string {
  const rad = Math.max(0, Math.min(r, w / 2, h / 2));
  const x0 = x;
  const y0 = y;
  const x1 = x + w;
  const y1 = y + h;
  if (rad < 0.5) return `M${r3(x0)} ${r3(y0)}H${r3(x1)}V${r3(y1)}H${r3(x0)}Z`;
  const pts: Pt[] = [[x0 + rad, y0], [x1 - rad, y0]];
  qarc(x1 - rad, y0 + rad, rad, -Math.PI / 2, 0, pts);
  pts.push([x1, y1 - rad]);
  qarc(x1 - rad, y1 - rad, rad, 0, Math.PI / 2, pts);
  pts.push([x0 + rad, y1]);
  qarc(x0 + rad, y1 - rad, rad, Math.PI / 2, Math.PI, pts);
  pts.push([x0, y0 + rad]);
  qarc(x0 + rad, y0 + rad, rad, Math.PI, -Math.PI / 2, pts);
  return pts.map((p, i) => `${i === 0 ? 'M' : 'L'}${r3(p[0])} ${r3(p[1])}`).join('') + 'Z';
}
