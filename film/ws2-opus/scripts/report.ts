// 从同一份时间线算出交界帧的状态、内容进场帧，并核对“同一帧号算两次结果一样”。
// 用法：npx esbuild scripts/report.ts --bundle --platform=node --log-level=warning | node
import { CONTENT_IN, islandAt, layersAt } from '../src/island';
import { ISLAND_EVENTS, SEGMENTS, TOTAL } from '../src/timeline';
import { pointerAt, slotsAt } from '../src/scene';

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

let mismatch = 0;
for (let f = 0; f < TOTAL; f += 7) {
  const a = JSON.stringify([islandAt(f), layersAt(f), slotsAt(f), pointerAt(f)]);
  const b = JSON.stringify([islandAt(f), layersAt(f), slotsAt(f), pointerAt(f)]);
  if (a !== b) mismatch++;
}
console.log(`\n# 重算核对：${mismatch === 0 ? '一致' : `${mismatch} 帧不一致`}`);
