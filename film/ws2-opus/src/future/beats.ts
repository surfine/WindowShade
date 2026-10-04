// 配乐的拍点，离线算好写死（帧，60 fps）。曲子与混音见 public/music/future/README.md、score.py。
// Kevin MacLeod《Floating Cities》，120.00 BPM（onset 自相关在 120 处最强，拍点相位 0.036 秒）；
// 从曲子 110.536 秒的强拍开始取 60 秒，所以片子的拍点就是整半秒：一拍 30 帧，一小节 120 帧。
// 曲子 148.536 秒低音整段进来（每小节低频能量从 7.5 跳到 11.3），落在片子第 19 小节 = 第 2280 帧。

export const BPM = 120;
export const BEAT = 30;
export const BAR = 120;
/** 配乐 + 音效一次混好的母带（score.py 生成）。 */
export const MUSIC_SRC = 'music/future/ws2-future-mix.wav';

/** 第 n 拍、第 n 小节在哪一帧。 */
export const beat = (n: number) => Math.round(n * BEAT);
export const bar = (n: number, b = 0) => Math.round(n * BAR + b * BEAT);

/** 每小节第一拍。 */
export const DOWNBEATS = [
  0, 120, 240, 360, 480, 600, 720, 840, 960, 1080,
  1200, 1320, 1440, 1560, 1680, 1800, 1920, 2040, 2160, 2280,
  2400, 2520, 2640, 2760, 2880, 3000, 3120, 3240, 3360, 3480,
] as const;

/** 画面里踩在拍上的落点。 */
export const HIT = {
  /** 面容 ID 认出。 */
  faceOk: 90,
  /** 点刘海。 */
  verse: bar(4),
  notchTap: bar(4, 0.25),
  /** 收回启动台。 */
  lpClose: bar(8),
  /** 读唇。 */
  verse2: bar(9),
  /** 摇头取消。 */
  build: bar(17),
  /** 低音进来：刘海展开成 CarPlay。 */
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
