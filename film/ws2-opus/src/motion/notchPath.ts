// 顯示網格 OQzaQDtbMVhhlAr（public/mesh/macbook-air-15in-silver.glb，Apple 15 吋 Air USDZ）。
// 面板本地寬 32.573 cm。根節點縮放 0.01，本地單位是厘米。UV 鋪滿 2880×1864 px。
// 洞的折線對相切圓（殘差是折線到圓的最大距離）：
//   寬 312.00 px = 35.288 mm（豎邊 x = 1284 與 1596）
//   深 56.00 px；沿板面從頂邊到洞底的弦長 6.351 mm
//   肩 r = 9.9 px = 1.120 mm。圓心在頂邊法線和豎邊法線的交點，殘差 0.55 px
//   底角 r = 18.5 px = 2.093 mm。圓心在豎邊法線和底邊法線的交點，殘差 0.13 px
// 靜止時畫這條洞。展開後肩退出：一塊不透明圓角矩形，頂邊貼齊螢幕上沿蓋住洞，
// 兩側在展開寬度上豎直，底角用設計稿的 rb。沒有頸，也沒有肩下的 S 形外撇。

const K = 100 / 2880; // cqw / px。viewBox 的 x、y 都是屏寬的百分之一，圓在這套單位裡不變形。
// 往螢幕一側偏不到 1 px，蓋住洞邊的抗鋸齒。
const BLEED = 0.45 * K;

const HOLE = {
  side: 156 * K,
  depth: 56 * K,
  rs: 9.9 * K,
  rb: 18.5 * K,
};

const r3 = (n: number) => Math.round(n * 1000) / 1000;

function arc(r: number, x: number, y: number, sweep: 0 | 1) {
  return `A${r3(r)} ${r3(r)} 0 0 ${sweep} ${r3(x)} ${r3(y)}`;
}

/** 靜止：順時針的硬體洞。肩圓切頂邊和豎邊，底圓切豎邊和底邊。 */
function hole(): string {
  const hW = HOLE.side + BLEED;
  const rs = HOLE.rs + BLEED;
  const deep = HOLE.depth + BLEED;
  const useRb = HOLE.rb + BLEED;
  const sL = 50 - hW;
  const sR = 50 + hW;
  const ySh = rs;
  const yBot = deep;
  const yRb = yBot - useRb;
  const topL = sL - rs;
  const topR = sR + rs;
  return [
    `M${r3(topL)} -0.5`,
    `L${r3(topL)} 0`,
    arc(rs, sL, ySh, 1),
    `L${r3(sL)} ${r3(yRb)}`,
    arc(useRb, sL + useRb, yBot, 0),
    `L${r3(sR - useRb)} ${r3(yBot)}`,
    arc(useRb, sR, yRb, 0),
    `L${r3(sR)} ${r3(ySh)}`,
    arc(rs, topR, 0, 1),
    `L${r3(topR)} -0.5Z`,
  ].join('');
}

/**
 * 展開：一塊藥丸。頂邊貼齊螢幕上沿（略往上出血，貼圖裁切後仍蓋住洞），
 * 左右在展開寬度上豎直，只倒底角。寬度至少蓋過洞的兩肩，所以不會露出頸。
 */
function pill(outerHalf: number, depth: number, rb: number): string {
  const cover = HOLE.side + HOLE.rs + BLEED;
  const oW = Math.max(outerHalf, cover);
  const deep = Math.max(depth, HOLE.depth + BLEED);
  const useRb = Math.max(0, Math.min(rb, oW, deep));
  const oL = 50 - oW;
  const oR = 50 + oW;
  const yBot = deep;
  const yRb = yBot - useRb;
  const d = [`M${r3(oL)} -0.5`, `L${r3(oL)} ${r3(yRb)}`];
  d.push(useRb > 0.0008 ? arc(useRb, oL + useRb, yBot, 0) : `L${r3(oL)} ${r3(yBot)}`);
  d.push(`L${r3(oR - useRb)} ${r3(yBot)}`);
  if (useRb > 0.0008) d.push(arc(useRb, oR, yRb, 0));
  d.push(`L${r3(oR)} -0.5Z`);
  return d.join('');
}

/** 靜止就是網格洞。展開後是一塊黑藥丸，肩已經退出，不再把洞的輪廓放大。 */
export function fusedIslandD(w: number, h: number, rb: number, _rs: number, grown: boolean): string {
  if (!grown) return hole();
  return pill(Math.max(w / 2, HOLE.side) + BLEED, Math.max(h, HOLE.depth) + BLEED, Math.max(0, rb));
}
