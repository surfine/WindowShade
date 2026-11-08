// 横版与竖版各自摆。屏幕按 15 英寸 MacBook Air，刘海永远贴着这块屏的上沿正中；句子在屏幕外面。
export type Rect = { x: number; y: number; w: number; h: number };

/**
 * 15 英寸 MacBook Air（M5）正面轮廓，量自 Apple Design Resources 的 Product Bezels（Bezel-MacBook-Air-M5，
 * 15-inch Silver PNG）。那张图的屏幕洞正好 2880 × 1864，等于面板原生像素（224 ppi），
 * 所以下面的数都以「屏幕像素」为单位，画的时候乘以 屏宽 / 2880。
 * 底座比盖子宽，是 Apple 那张正面图本身的透视。
 */
export const AIR = {
  glassW: 2880,
  glassH: 1864,
  bezel: 59, // 上沿、两侧一样宽（≈ 6.7 mm）
  rim: 6, // 盖子外缘露出的一圈铝
  lidR: 100, // 盖子上角
  glassR: 42, // 屏幕上角
  chin: 120, // 屏幕下沿到盖子下沿（≈ 13.6 mm）
  chinGlass: 43, // 其中上面一截黑玻璃，下面是转轴前那截深色
  lidBottomR: 12,
  baseW: 3514, // 底座在正面图里的宽度（盖子 2998）
  baseH: 78, // 盖子下沿到底座最下面
  deckH: 41, // 其中上面看得到的键盘面，下面是前沿
  baseBottomR: 40,
  scoopW: 520, // 键盘面正中开盖用的凹口
  footW: 190,
  footH: 18,
  footInset: 178, // 底座左沿到脚垫
} as const;
export const SCREEN_ASPECT = AIR.glassW / AIR.glassH;

export type Layout = {
  name: 'landscape' | 'portrait' | 'phone';
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
};

const screenOf = (x: number, y: number, w: number): Rect => ({ x, y, w, h: w / SCREEN_ASPECT });

export const LANDSCAPE: Layout = {
  name: 'landscape',
  width: 1920,
  height: 1080,
  screen: screenOf(380, 64, 1160),
  far: 0.72,
  caption: { cx: 960, cy: 988, size: 60 },
  wordmark: { cx: 960, cy: 984, size: 84 },
  side: { x: 1636, y: 360, w: 240, h: 300 },
};

export const PORTRAIT: Layout = {
  name: 'portrait',
  width: 1080,
  height: 1920,
  // 屏宽 880：底座（官方正面图里比屏宽 22%）在 1080 宽里刚好不出画。
  screen: screenOf(100, 520, 880),
  far: 0.74,
  caption: { cx: 540, cy: 1314, size: 64 },
  wordmark: { cx: 540, cy: 1314, size: 92 },
  side: { x: 300, y: 1460, w: 480, h: 380 },
};

/**
 * iPhone 18 Pro Max 原生竖屏 1320 × 2868（apple.com/iphone-18-pro/specs：2868‑by‑1320，460 ppi）。
 * 照 PORTRAIT 的摆法按宽放大 1320/1080 倍，比 9:16 多出来的高度上下分掉，整组（电脑、字幕、屏外物件）稍偏上居中。
 * 机身比例不变：屏宽 1076，底座（比屏宽 22%）1313，不出画。
 */
export const PHONE: Layout = {
  name: 'phone',
  width: 1320,
  height: 2868,
  screen: screenOf(122, 640, 1076),
  far: 0.74,
  caption: { cx: 660, cy: 1610, size: 78 },
  wordmark: { cx: 660, cy: 1610, size: 112 },
  side: { x: 367, y: 1790, w: 587, h: 464 },
};

/** 屏幕坐标（按屏宽、屏高的百分比）→ 屏内像素。 */
export const px = (L: Layout, r: Rect): Rect => ({
  x: (r.x / 100) * L.screen.w,
  y: (r.y / 100) * L.screen.h,
  w: (r.w / 100) * L.screen.w,
  h: (r.h / 100) * L.screen.h,
});
