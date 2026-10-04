// MacBook Neo（Mac17,5）的实物尺寸，单位厘米。
// 量自 Apple 的 3D 模型 macbook-neo-open.usdz（AI System 6 的 assets/cmf，metersPerUnit 0.01）：
//   底座 29.75 × 20.64、盖子展开长 20.66（升 19.05、后仰 8.0 → 开合角约 113°），
//   显示区 27.89 × 17.44（= 2408 × 1506 px ÷ 219 ppi，和规格页对得上）。
// 屏幕顶角、无刘海、摄像头在均匀边框里：docs/design-system.md §3.2 / §3.5（Product Bezels 图稿）。

export const NEO = {
  w: 29.75,
  depth: 20.64,
  thick: 1.27,
  lidLen: 20.66,
  lidOpen: 113, // 度；盖子相对底座
  lidR: 1.1,
  glass: { w: 29.38, from: 1.39, to: 20.46 }, // 黑玻璃：沿盖子从转轴量起
  screen: { w: 27.89, h: 17.44, from: 2.29 }, // 显示区下沿离转轴 2.29
  screenR: 33.6 / (219 / 2.54), // 33.6 px → cm
  well: { w: 27.95, from: 1.13, depth: 11.5 }, // 键盘区：离后沿 1.13
  pad: { w: 12.02, from: 12.64, depth: 7.68 }, // 触控板
} as const;

/** 屏幕坐标系：默认分辨率 1408 × 881 点（design-system 表 A）。 */
export const NPT = { w: 1408, h: 881, menu: 24 } as const;

/** 盖子后仰角（离竖直）。 */
export const LEAN = NEO.lidOpen - 90;
