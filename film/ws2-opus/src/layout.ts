// 横版与竖版各自摆。屏幕按 16:10，刘海永远贴着这块屏的上沿正中；句子在屏幕外面。
export type Rect = { x: number; y: number; w: number; h: number };

export type Layout = {
  name: 'landscape' | 'portrait';
  width: number;
  height: number;
  /** 镜头推到底（scale 1）时那块屏的位置。 */
  screen: Rect;
  /** 开场镜头的远景倍数。 */
  far: number;
  caption: { cx: number; cy: number; size: number };
  wordmark: { cx: number; cy: number; size: number };
  /** 屏外放触控板、手机线稿的地方。 */
  side: Rect;
  /** “概念示意”标签。 */
  tag: { x: number; y: number; size: number; align: 'left' | 'center' };
};

const screenOf = (x: number, y: number, w: number): Rect => ({ x, y, w, h: w / 1.6 });

export const LANDSCAPE: Layout = {
  name: 'landscape',
  width: 1920,
  height: 1080,
  screen: screenOf(352, 80, 1216),
  far: 0.72,
  caption: { cx: 960, cy: 988, size: 60 },
  wordmark: { cx: 960, cy: 984, size: 84 },
  side: { x: 1636, y: 360, w: 240, h: 300 },
  tag: { x: 960, y: 1046, size: 22, align: 'center' },
};

export const PORTRAIT: Layout = {
  name: 'portrait',
  width: 1080,
  height: 1920,
  // 屏宽 1000：占位块里的字在竖版上还读得清；代价是机身底座两端出画。
  screen: screenOf(40, 520, 1000),
  far: 0.74,
  caption: { cx: 540, cy: 1314, size: 64 },
  wordmark: { cx: 540, cy: 1314, size: 92 },
  side: { x: 300, y: 1460, w: 480, h: 380 },
  tag: { x: 540, y: 1384, size: 26, align: 'center' },
};

/** 屏幕坐标（按屏宽、屏高的百分比）→ 屏内像素。 */
export const px = (L: Layout, r: Rect): Rect => ({
  x: (r.x / 100) * L.screen.w,
  y: (r.y / 100) * L.screen.h,
  w: (r.w / 100) * L.screen.w,
  h: (r.h / 100) * L.screen.h,
});
