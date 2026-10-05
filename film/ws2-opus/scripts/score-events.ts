// 给 scripts/score.py 的事件表：每个声音落在成片第几帧，全部从 cut.ts / timeline.ts 的常数算出来，不重打数字。
//   npx esbuild scripts/score-events.ts --bundle --platform=node --log-level=warning | node > /tmp/score-events.json
import { MUSIC_TAIL, OUT_TOTAL, UNDER, WORDMARK_AT, outOf } from '../src/cut';
import { AUDIO_OFFSET_SEC, BPM, MUSIC_FILE, SECTIONS, beatFrame } from '../src/music';
import { FPS } from '../src/motion/site';
import { CLUTTER } from '../src/scene';
import { CLICK_CARD, DROP_OPEN, DROP_RELEASE, FACE_OK, LOCK_AT, NOD_DOWN, PREVIEW_AT, TUCK_A } from '../src/timeline';

/** 点刘海打开启动台（scene.ts 里 P5 从这一帧进场）。 */
const LAUNCH_AT = 3021;

// kind 是材质（score.py 里一个材质一种做法）；比拍少得多：全片 108 拍，15 声。
const events = [
  { at: outOf(TUCK_A), kind: 'tuck', v: 1.0, why: '终端被吸进刘海' },
  ...CLUTTER.map((c) => ({ at: outOf(c.tuck), kind: 'tuck', v: 0.35, why: '其余几扇跟进去' })),
  { at: outOf(CLICK_CARD), kind: 'click', v: 0.6, why: '点格子放回' },
  { at: outOf(LAUNCH_AT), kind: 'open', v: 0.6, why: '点刘海，启动台长出来' },
  { at: outOf(DROP_OPEN), kind: 'open', v: 0.8, why: '五个落点垂下来' },
  { at: outOf(DROP_RELEASE), kind: 'land', v: 0.8, why: '放进落点' },
  { at: outOf(5267), kind: 'tuck', v: 0.5, why: '那一笔落进刘海' },
  { at: outOf(PREVIEW_AT), kind: 'chime', v: 0.5, why: '认出口型' },
  { at: outOf(NOD_DOWN), kind: 'nod', v: 0.6, why: '点头' },
  { at: outOf(LOCK_AT), kind: 'sleep', v: 0.8, why: '锁屏，屏幕一黑' },
  { at: outOf(FACE_OK), kind: 'unlock', v: 1.0, why: '人和手机都对上，整首回来' },
  { at: WORDMARK_AT, kind: 'mark', v: 0.7, why: '片名落在最后一个重拍' },
];

console.log(JSON.stringify({
  fps: FPS, total: OUT_TOTAL, bpm: BPM, music: MUSIC_FILE, offsetSec: AUDIO_OFFSET_SEC,
  under: UNDER, tail: MUSIC_TAIL, peakBeat: beatFrame(SECTIONS.peak), events,
}, null, 1));
