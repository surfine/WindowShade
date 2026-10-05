// 从同一份时间线算出交界帧的状态、内容进场帧，并核对“同一帧号算两次结果一样”。
// 用法：npx esbuild scripts/report.ts --bundle --platform=node --log-level=warning | node
import { CONTENT_IN, islandAt, layersAt } from '../src/island';
import { ISLAND_EVENTS, SEGMENTS, TOTAL } from '../src/timeline';
import { pointerAt, slotsAt } from '../src/scene';
import { CAPTIONS, OUT_TOTAL, SHOTS, SHOT_AT, WORDMARK_AT } from '../src/cut';
import { BPM, isDownbeat, nearestBeat } from '../src/music';

const r = (v: number) => v.toFixed(2);
const state = (f: number) => {
  const s = islandAt(f);
  const layers = layersAt(f).filter((l) => l.first > 0.01).map((l) => l.content).join('+') || '—';
  const slots = slotsAt(f).map((x) => `${x.id}@${x.opacity.toFixed(2)}`).join(' ') || '—';
  return `${s.mode} w${r(s.w)} h${r(s.h)} r${r(s.r)} | 岛内 ${layers} | 屏内 ${slots}${pointerAt(f) ? ' | 指针' : ''}`;
};

console.log('# 段落交界');
for (const s of SEGMENTS) {
  console.log(`${s.id} [${s.from}, ${s.to})`);
  console.log(`  首帧 ${s.from}: ${state(s.from)}`);
  console.log(`  末帧 ${s.to - 1}: ${state(s.to - 1)}`);
}
console.log('\n# 岛的事件（at = 旧内容开始淡出；in = 新内容进场）');
ISLAND_EVENTS.forEach((e, i) => console.log(`  ${e.at}\t${e.mode}\t${e.content}\tin ${CONTENT_IN[i]}`));

const sec = (f: number) => `${(f / 60).toFixed(1)}s`;
const beat = (out: number) => { const b = nearestBeat(out); return `第 ${b.k} 拍${isDownbeat(b.k) ? '（小节线）' : ''} ${b.off >= 0 ? '+' : ''}${b.off} 帧`; };
console.log(`\n# 成片剪接（cut.ts）：${OUT_TOTAL} 帧，${sec(OUT_TOTAL)}，配乐 ${BPM} BPM`);
SHOTS.forEach((s, i) => {
  const keyOut = SHOT_AT[i] + s.key - s.src[0];
  console.log(`${s.id}${s.punch ? ' [顶一下]' : ''}  成片 ${SHOT_AT[i]}–${SHOT_AT[i] + s.src[1] - s.src[0]}（${sec(SHOT_AT[i])}）  母带 [${s.src[0]}, ${s.src[1]})  ${s.why}`);
  console.log(`  剪接点距拍：${i ? beat(SHOT_AT[i]) : '片头'}；动作 ${s.key} 在成片 ${keyOut}（${sec(keyOut)}）距拍：${beat(keyOut)}`);
  if (i) {
    console.log(`  接前 ${SHOTS[i - 1].src[1] - 1}: ${state(SHOTS[i - 1].src[1] - 1)}`);
    console.log(`  接后 ${s.src[0]}: ${state(s.src[0])}`);
  }
});
console.log('\n# 成片字幕');
CAPTIONS.forEach((c) => console.log(`  ${c.from}–${c.to}（${sec(c.from)}–${sec(c.to)}）${c.text}  进场距拍：${beat(c.from)}`));
console.log(`  片名 ${WORDMARK_AT}（${sec(WORDMARK_AT)}）距拍：${beat(WORDMARK_AT)}`);

let mismatch = 0;
for (let f = 0; f < TOTAL; f += 7) {
  const a = JSON.stringify([islandAt(f), layersAt(f), slotsAt(f), pointerAt(f)]);
  const b = JSON.stringify([islandAt(f), layersAt(f), slotsAt(f), pointerAt(f)]);
  if (a !== b) mismatch++;
}
console.log(`\n# 重算核对：${mismatch === 0 ? '一致' : `${mismatch} 帧不一致`}`);
