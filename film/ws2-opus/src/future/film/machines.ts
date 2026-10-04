// 两台机器的实物尺寸（厘米）与屏幕点数。
// Neo：量自 Apple 的 macbook-neo-open.usdz（见 ../neo/geom.ts）。
// 15 英寸 Air：量自 Product Bezels（../../layout.ts 的 AIR，224 ppi → 88.19 px/cm）与规格页（34.04 × 23.76 × 1.15 cm）。
import { AIR } from '../../layout';
import { NEO } from '../neo/geom';

export type MachineId = 'neo' | 'air';

export type Machine = {
  id: MachineId;
  w: number; depth: number; thick: number;
  lidLen: number; lidR: number;
  glass: { w: number; from: number; to: number };
  screen: { w: number; h: number; from: number; r: number };
  well: { w: number; from: number; depth: number };
  pad: { w: number; from: number; depth: number };
  /** 屏幕默认分辨率（点）与菜单栏高。 */
  pt: { w: number; h: number; menu: number };
  /** 实体刘海（点）；Neo 没有。 */
  notch: { w: number; h: number; r: number } | null;
  /** 摄像头离转轴多远（沿盖子，厘米）。 */
  camAt: number;
  color: { deck: [string, string]; edge: [number, number, number]; lid: [string, string]; well: [string, string]; keys: [string, string]; pad: [string, string] };
};

const PXCM = 224 / 2.54;
const airPt = { w: 1710, h: 1107 };
const notchPt = { w: (306 / 2880) * airPt.w, h: (55 / 2880) * airPt.w, r: (15 / 2880) * airPt.w };

export const MACHINES: Record<MachineId, Machine> = {
  neo: {
    id: 'neo',
    w: NEO.w, depth: NEO.depth, thick: NEO.thick, lidLen: NEO.lidLen, lidR: NEO.lidR,
    glass: NEO.glass,
    screen: { ...NEO.screen, r: NEO.screenR },
    well: NEO.well, pad: NEO.pad,
    pt: { w: 1408, h: 881, menu: 24 },
    notch: null,
    camAt: (NEO.screen.from + NEO.screen.h + NEO.glass.to) / 2,
    // 银色
    color: {
      deck: ['#b9bcc1', '#dfe1e4'], edge: [196, 198, 202], lid: ['#a4a7ac', '#878a8f'],
      well: ['#a7aaaf', '#b6b9bd'], keys: ['#2b2b2e', '#1d1d20'], pad: ['#ccced2', '#d6d8db'],
    },
  },
  air: {
    id: 'air',
    w: 34.04, depth: 23.76, thick: 1.15,
    lidLen: (AIR.glassH + AIR.bezel + AIR.rim + AIR.chin) / PXCM,
    lidR: AIR.lidR / PXCM,
    glass: { w: (AIR.glassW + 2 * AIR.bezel) / PXCM, from: (AIR.chin - AIR.chinGlass) / PXCM, to: (AIR.glassH + AIR.bezel + AIR.chin) / PXCM },
    screen: { w: AIR.glassW / PXCM, h: AIR.glassH / PXCM, from: AIR.chin / PXCM, r: AIR.glassR / PXCM },
    well: { w: 28.2, from: 1.4, depth: 11.4 },
    pad: { w: 16.1, from: 13.1, depth: 10.0 },
    pt: { w: airPt.w, h: airPt.h, menu: notchPt.h },
    notch: notchPt,
    camAt: (AIR.glassH + AIR.chin) / PXCM - (notchPt.h / airPt.w) * (AIR.glassW / PXCM) * 0.5,
    // 午夜色
    color: {
      deck: ['#262b33', '#343a44'], edge: [52, 58, 68], lid: ['#2b3039', '#1f232a'],
      well: ['#1c2027', '#222730'], keys: ['#0f1013', '#08090b'], pad: ['#2f353f', '#363c47'],
    },
  },
};

export const LEAN = 23; // 盖子后仰（开合 113°）
