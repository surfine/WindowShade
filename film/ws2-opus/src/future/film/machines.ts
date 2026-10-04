// 两台机器的实物尺寸（厘米）与屏幕点数。
// 几何来自 Apple 的 AR 模型，已经量在 measure/measured.json（Y 向上，metersPerUnit 0.01），这里不再重测：
//   Neo  macbook-neo.usdz（与 AI System 6 assets/cmf/macbook-neo-open.usdz 同一套网格）
//   Air  macbook-air-15in-silver.usdz 的网格；午夜色取同目录 midnight USDZ 的漫反射，不取银色。
// 键位在 measured.ts。漫反射是线性光，下面的十六进制是转成 sRGB 之后的值。
//
// 没能量到、这里写明的：
//   摄像头和指示灯的左右位置不在模型里。Neo 放在上边框正中，Air 放在量到的刘海正中，都不偏移。
//   刘海底角半径不在 USDZ（顶点只有 20 个）。用 Product Bezels 的 15 px，按这块屏的宽度折算。
//   键帽上的字色不在键帽材质里（材质是一块平色）。浅键用深字、深键用浅字，只为看得清。
//   屏幕点数不在模型里：Neo 沿用 1408×881；Air 用 15 英寸默认缩放 1710×1107。
import type { KeyCap } from './measured';
import { KEYS_AIR, KEYS_NEO } from './measured';

export type MachineId = 'neo' | 'air';

export type Machine = {
  id: MachineId;
  w: number; depth: number; thick: number;
  /** 底座平面圆角（拟合圆半径）。 */
  corner: number;
  /** 盖子离竖直的后仰（度）。开合角 = 90 + lean。 */
  lean: number;
  /** 转轴在盖子坐标里的 s（显示区下沿是 0，负数在下沿以下）。 */
  hingeS: number;
  /** 转轴比底座后沿靠前多少。 */
  hingeFromBack: number;
  hinge: { w: number; dia: number };
  lidLen: number;
  lidR: number;
  lidRBottom: number;
  glass: { w: number; from: number; to: number; r: number };
  screen: { w: number; h: number; from: number; r: number };
  well: { w: number; from: number; depth: number; r: number };
  pad: { w: number; from: number; depth: number; r: number };
  pt: { w: number; h: number; menu: number };
  notch: { w: number; h: number; r: number } | null;
  /** 摄像头离转轴多远（沿盖子，厘米）。左右未核验，取 0。 */
  camAt: number;
  keys: readonly KeyCap[];
  color: {
    deck: string; edge: [number, number, number]; lid: string;
    well: string; keys: string; legend: string; pad: string; chin: string;
  };
};

const airPt = { w: 1710, h: 1107 };
// 刘海 3.8 × 0.592 cm（measured.json air.notch，n=20）折到点数。底角用 Product Bezels 的 15/2880。
const airNotch = {
  w: (3.8 / 32.573) * airPt.w,
  h: (0.592 / 21.142) * airPt.h,
  r: (15 / 2880) * airPt.w,
};

export const MACHINES: Record<MachineId, Machine> = {
  neo: {
    id: 'neo',
    w: 29.682, depth: 20.697, thick: 1.044, corner: 1.282,
    lean: 20.071, hingeS: -1.93, hingeFromBack: 0.19,
    hinge: { w: 21.932, dia: 0.67 },
    lidLen: 20.293, lidR: 1.28, lidRBottom: 0.335,
    glass: { w: 29.313, from: 1.028, to: 20.109, r: 1.087 },
    screen: { w: 27.82, h: 17.431, from: 1.93, r: 0.365 },
    well: { w: 27.881, from: 1.185, depth: 11.531, r: 0.466 },
    pad: { w: 11.505, from: 12.975, depth: 7.212, r: 0.43 },
    pt: { w: 1408, h: 881, menu: 24 },
    notch: null,
    camAt: 19.735,
    keys: KEYS_NEO,
    // 键帽 (0.95, 0.966, 1)，铝 (0.621, 0.631, 0.65)，触控板更浅 (0.716, 0.728, 0.75)，下巴 (0.02, 0.02, 0.02)
    color: {
      deck: '#cfd0d3', edge: [207, 208, 211], lid: '#cfd0d3',
      well: '#cfd0d3', keys: '#f9fbff', legend: '#1d1d1f', pad: '#dcdee1', chin: '#272727',
    },
  },
  air: {
    id: 'air',
    w: 33.95, depth: 23.756, thick: 0.947, corner: 1.033,
    lean: 19.992, hingeS: -1.601, hingeFromBack: 0.293,
    hinge: { w: 23.785, dia: 0.268 },
    lidLen: 23.432, lidR: 1.046, lidRBottom: 0.134,
    glass: { w: 33.635, from: 1.091, to: 23.279, r: 0.894 },
    screen: { w: 32.573, h: 21.142, from: 1.601, r: 0.377 },
    well: { w: 27.878, from: 2.188, depth: 11.5, r: 0.455 },
    pad: { w: 14.869, from: 13.937, depth: 9.318, r: 0.458 },
    pt: { w: airPt.w, h: airPt.h, menu: Math.round(airNotch.h) },
    notch: airNotch,
    camAt: 22.447,
    keys: KEYS_AIR,
    // 午夜铝 (0.070, 0.079, 0.098)，触控板 (0.065, 0.076, 0.098)，键帽 (0.0084, 0.0099, 0.014)，下巴纯黑
    color: {
      deck: '#4b5058', edge: [75, 80, 88], lid: '#4b5058',
      well: '#4b5058', keys: '#17191f', legend: '#d2d2d7', pad: '#484e58', chin: '#000000',
    },
  },
};
