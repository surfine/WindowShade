// 一条 60fps 时间线，10140 帧（169 秒）。横版、竖版共用；只有版面不同。
import { BEAT } from './motion/direction';
import { ALERT_HOLD, HOVER_DELAY, TUCK_FRAMES, ms, TEACH, type IslandMode } from './motion/site';

export const TOTAL = 10140;

export type Segment = { id: string; from: number; to: number; line: string; concept?: [number, number] };

// 每段一句，照 docs/copy-guide.md：说用户遇到的事，一屏一句，不超过 12 个字。
// drop / approve / nod / back 是 126 秒版之后插进来的四段，后面的旧段整体往后挪。
export const SEGMENTS: Segment[] = [
  { id: 'lid', from: 0, to: 840, line: '合上盖子，桌面还在' },
  { id: 'live', from: 840, to: 1800, line: '正在发生的事，在刘海里' },
  { id: 'tuck', from: 1800, to: 2880, line: '窗口收进刘海，再放回' },
  { id: 'home', from: 2880, to: 3720, line: '点一下刘海，回到主屏幕' },
  { id: 'side', from: 3720, to: 4320, line: '甩出去，点回来' },
  // 落点小岛已经在 prototype/App/Notch.swift 里，整段不挂概念标签（Aaron 2026-10-04）。
  { id: 'drop', from: 4320, to: 4980, line: '拖到刘海，选个位置' },
  { id: 'draw', from: 4980, to: 6060, line: '画一笔，说一句', concept: [4980, 6060] },
  { id: 'approve', from: 6060, to: 6660, line: '要你放行的，只问一次', concept: [6060, 6660] },
  { id: 'hold', from: 6660, to: 7380, line: '长按刘海，换一种用法', concept: [6660, 7380] },
  { id: 'nod', from: 7380, to: 8040, line: '不出声，点头就照做', concept: [7380, 8040] },
  { id: 'away', from: 8040, to: 9060, line: '专注时安静，走开就锁', concept: [8260, 9060] },
  { id: 'back', from: 9060, to: 9720, line: '回来，窗口都在原处', concept: [9060, 9720] },
  { id: 'end', from: 9720, to: TOTAL, line: 'WindowShade 2' },
];

/** 每句出现的帧（含起、不含止）。 */
export const CAPTIONS: { text: string; from: number; to: number }[] = [
  { text: SEGMENTS[0].line, from: 120, to: 660 },
  { text: SEGMENTS[1].line, from: 990, to: 1740 },
  { text: SEGMENTS[2].line, from: 2000, to: 2800 },
  { text: SEGMENTS[3].line, from: 3080, to: 3660 },
  { text: SEGMENTS[4].line, from: 3800, to: 4260 },
  { text: SEGMENTS[5].line, from: 4400, to: 4930 },
  { text: SEGMENTS[6].line, from: 5300, to: 6000 },
  { text: SEGMENTS[7].line, from: 6180, to: 6620 },
  { text: SEGMENTS[8].line, from: 6880, to: 7320 },
  { text: SEGMENTS[9].line, from: 7470, to: 7990 },
  { text: SEGMENTS[10].line, from: 8220, to: 9000 },
  { text: SEGMENTS[11].line, from: 9120, to: 9700 },
];
export const WORDMARK_AT = 9780;
export const FADE_TO_BLACK = [10080, TOTAL] as const;

// ---- 第 1 段：开盖 ----
export const LID_PLAYS = [90, 420];
export const DOLLY_AT = 680;

// ---- 刘海：每一次换样子 ----
export type Content =
  | 'none' | 'music' | 'headphones' | 'mouse' | 'window' | 'windowChanged' | 'card' | 'build'
  | 'stroke' | 'session' | 'road' | 'focus' | 'countdown'
  | 'drop' | 'ask' | 'cited' | 'lips' | 'preview' | 'verify' | 'unlocked' | 'summary';

/** at：起因确定的那一帧，旧内容从这里开始淡出；形状 exit.gap 之后换目标；新内容在形状走到 40% 时进场。 */
export type IslandEvent = { at: number; mode: IslandMode; content: Content; inAt?: number };

// 起因 → 先等一拍 → 开口。
export const MUSIC_PLAY = 940, CAUSE_PODS = 1160, CAUSE_MOUSE = 1480;
const CAUSE_MUSIC = MUSIC_PLAY;
export const PODS_END = CAUSE_PODS + BEAT + ALERT_HOLD;
export const MOUSE_END = CAUSE_MOUSE + BEAT + ALERT_HOLD;
export const TUCK_A = 1899; // 终端窗口飞进刘海
export const HOVER_A = 2120; // 指针停到刘海上
export const LEAVE_A = 2300;
export const ALERT_A = 2460;
export const HOVER_B = 2710;
export const CLICK_CARD = 2806; // 点一下格子，放回
export const UNTUCK_A = CLICK_CARD + 2;

// ---- drop：拖着终端的标题栏到刘海，停在左半屏上松手 ----
export const GRAB = 4470; // 按住标题栏
export const DRAG_UP = 4500; // 往刘海拖（1.0 秒，teach.js 的移动）
export const DROP_OPEN = 4530; // 拖到刘海附近，落点小岛垂下来；手直接碰到刘海，不等一拍
export const DRAG_SIDE = 4600; // 横着挪到左半屏那一格
export const BUILD_DONE = 4580; // 拖着的时候构建跑完：提醒先进次区域，留一个点
export const DROP_RELEASE = 4700; // 松手：窗口去左半屏，等着的提醒这才开口

export const LIFT_DRAW = 5201; // 画完一笔抬手
export const SESSION_AT = 5660;

// ---- approve：助手要改文章草稿，在刘海里问一次 ----
export const ASK_CAUSE = 6100;
export const CLICK_ALLOW = 6360;
export const EDITS = [6380, 6400, 6420]; // 草稿里三处引文依次改好
export const CITED_CAUSE = 6440;

export const PRESS_LONG_A = 6780, PRESS_LONG_B = 7160;
export const LONG_PRESS = 30; // 长按门槛：片子取 0.5 秒，产品值待定

// ---- nod：不出声说“左半屏”，刘海给出对象，点头才换 ----
/** 推近刘海看读口型：镜头先推稳，界面才换；界面停住，镜头才拉回（motion-direction 原则 6）。 */
export const ZOOM_LIPS = [7380, 7530] as const;
export const LIPS_AT = 7460;
export const PREVIEW_AT = 7620;
/** 点头：低下 0.33 秒、回正 0.33 秒，低 14°。[片子新增] 2.1 规格只定“回正 → 下点 → 回正”，没给时长和角度。 */
export const NOD_DOWN = 7740, NOD_FRAMES = 20, NOD_DEG = 14;
export const NOD_DONE = NOD_DOWN + 2 * NOD_FRAMES;

export const FOCUS_START = 8100;
export const TUCK_B = FOCUS_START + BEAT;
export const PHONE_GONE = 8360;
export const GRACE = 90; // 离开就锁：手机断开后 1.5 秒宽限（docs/dynamic-lock.md 的方案值）
export const COUNTDOWN = 600; // 刘海倒数 10 秒
export const LOCK_AT = PHONE_GONE + GRACE + COUNTDOWN;

// ---- back：回来就开（dynamic-lock.md）：手机回到身边、相机认出人，两样都对才开；Touch ID 和密码是后备 ----
export const PHONE_BACK = 9080;
/** 手机重新连上并读到回应，信号连续 2 秒够强（dynamic-lock.md“回来就开”第 2、3 条）。 */
export const PHONE_OK = PHONE_BACK + ms(TEACH.move) + 120;
export const ZOOM_BACK = [PHONE_BACK + ms(TEACH.move), 9380] as const;
export const VERIFY_AT = PHONE_OK; // 锁屏上的刘海只多一条窄的验证状态（2.1 OS-14）
export const FACE_OK = VERIFY_AT + 50; // 相机认出人：这一刻是示意，没有实测耗时
export const BOTH_OK = FACE_OK + 20;
export const UNLOCK = 9470; // 系统确认已解开，桌面才回来（2.1 OS-16）
export const CLICK_SUMMARY = 9640;
export const UNTUCK_C = CLICK_SUMMARY + 2;

export const ISLAND_EVENTS: IslandEvent[] = [
  { at: CAUSE_MUSIC + BEAT, mode: 'compact', content: 'music' },
  { at: CAUSE_PODS + BEAT, mode: 'alert', content: 'headphones' },
  { at: CAUSE_PODS + BEAT + ALERT_HOLD, mode: 'compact', content: 'music' },
  { at: CAUSE_MOUSE + BEAT, mode: 'alert', content: 'mouse' },
  { at: CAUSE_MOUSE + BEAT + ALERT_HOLD, mode: 'compact', content: 'music' },
  // 窗口落进刘海那一帧，两边换成窗口和个数。
  { at: TUCK_A, mode: 'compact', content: 'window', inAt: TUCK_A + Math.ceil(TUCK_FRAMES) + 1 },
  { at: HOVER_A + HOVER_DELAY, mode: 'shelf', content: 'card' },
  { at: LEAVE_A, mode: 'compact', content: 'window' },
  { at: ALERT_A, mode: 'alert', content: 'build' },
  { at: ALERT_A + ALERT_HOLD, mode: 'compact', content: 'windowChanged' },
  { at: HOVER_B + HOVER_DELAY, mode: 'shelf', content: 'card' },
  { at: CLICK_CARD, mode: 'rest', content: 'none' },
  // 落点小岛：你正在做的事（第 2 层）占着刘海，构建跑完只留一个点；松手后提醒从落点小岛直接变过去。
  { at: DROP_OPEN, mode: 'drop', content: 'drop' },
  { at: DROP_RELEASE, mode: 'alert', content: 'build' },
  { at: DROP_RELEASE + ALERT_HOLD, mode: 'rest', content: 'none' },
  { at: LIFT_DRAW + BEAT, mode: 'shelf', content: 'stroke' },
  { at: SESSION_AT, mode: 'compact', content: 'session' },
  // 要你放行的事（第 1 层）：外面的事引起的开口，先等一拍。
  { at: ASK_CAUSE + BEAT, mode: 'ask', content: 'ask' },
  { at: CLICK_ALLOW, mode: 'compact', content: 'session' },
  { at: CITED_CAUSE + BEAT, mode: 'alert', content: 'cited' },
  { at: CITED_CAUSE + BEAT + ALERT_HOLD, mode: 'compact', content: 'session' },
  { at: PRESS_LONG_A + LONG_PRESS, mode: 'full', content: 'road' },
  { at: PRESS_LONG_B + LONG_PRESS, mode: 'compact', content: 'session' },
  // 静音操作：读口型时两边换内容；认出“左半屏”后给出对象；点头之后窗口真的动了，刘海才收。
  { at: LIPS_AT, mode: 'compact', content: 'lips' },
  { at: PREVIEW_AT, mode: 'alert', content: 'preview' },
  { at: NOD_DONE + 2, mode: 'compact', content: 'session' },
  { at: FOCUS_START, mode: 'compact', content: 'focus' },
  { at: PHONE_GONE + GRACE, mode: 'alert', content: 'countdown' },
  { at: LOCK_AT, mode: 'rest', content: 'none' },
  { at: VERIFY_AT, mode: 'compact', content: 'verify' },
  { at: BOTH_OK, mode: 'alert', content: 'unlocked' },
  // 提醒直接长成“离开期间”，不先收回。
  { at: UNLOCK + BEAT, mode: 'digest', content: 'summary' },
  { at: CLICK_SUMMARY, mode: 'rest', content: 'none' },
];

/** 落进刘海那一下的速度（帧）。 */
export const KICKS = [TUCK_A + Math.ceil(TUCK_FRAMES) + 1, TUCK_B + Math.ceil(TUCK_FRAMES) + 1];

export const LAND_A = KICKS[0];
export const LAND_B = KICKS[1];
