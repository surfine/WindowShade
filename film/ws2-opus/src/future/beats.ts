// 配乐的拍点，离线算好写死（帧，60 fps）。曲子见 public/music/future/README.md。
// 120 BPM：一拍 30 帧，一小节 120 帧，全曲 30 小节 = 3600 帧。
// analyze-beatgrid.py 的结果：把速度读成一半（60.1 BPM，拍点在整秒后约 40 毫秒），
// 能量突增在 8 秒、38 秒、58 秒，正好是第一段、落拍、最后一个强拍。下面以合成时的网格为准。

export const BPM = 120;
export const BEAT = 30;
export const BAR = 120;
export const MUSIC_SRC = 'music/future/ws2-future.mp3';

/** 第 n 拍、第 n 小节在哪一帧。 */
export const beat = (n: number) => Math.round(n * BEAT);
export const bar = (n: number, b = 0) => Math.round(n * BAR + b * BEAT);

/** 每小节第一拍。 */
export const DOWNBEATS = [
  0, 120, 240, 360, 480, 600, 720, 840, 960, 1080,
  1200, 1320, 1440, 1560, 1680, 1800, 1920, 2040, 2160, 2280,
  2400, 2520, 2640, 2760, 2880, 3000, 3120, 3240, 3360, 3480,
] as const;

/** 曲子里专门写给画面的落点。 */
export const HIT = {
  /** 提示音：面容 ID 认出。 */
  faceOk: 90,
  /** 第一段进来，点刘海。 */
  verse: bar(4),
  notchTap: bar(4, 0.25),
  /** 收回启动台。 */
  lpClose: bar(8),
  /** 第二段：读唇。 */
  verse2: bar(9),
  /** 拉升：军鼓滚奏、噪声上扫。 */
  build: bar(17),
  /** 落拍：刘海展开成 CarPlay。 */
  drop: bar(19),
  /** Esc：收回刘海。 */
  esc: bar(24),
  /** 倒数三下。 */
  ticks: [bar(25), bar(25, 2), bar(26)],
  /** 落锁。 */
  lock: bar(26, 2),
  /** 最后一个强拍：片名。 */
  last: bar(29),
} as const;

/** 音量：开头 6 帧淡入，最后 72 帧淡出（曲子自己也收尾）。 */
export function musicVolume(f: number, total: number) {
  const inn = Math.min(1, f / 6);
  const out = Math.min(1, Math.max(0, (total - f) / 72));
  return 0.9 * inn * out;
}
