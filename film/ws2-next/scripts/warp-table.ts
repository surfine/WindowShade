// 给 score.py 用：故事时间每 0.01 秒对应的片子时间，以及片长。
import { writeFileSync } from 'node:fs';
import { FILM_LEN, STORY_END, filmOf } from '../src/warp';
import { COVER } from '../src/plan';

const step = 0.01;
const table: number[] = [];
for (let t = 0; t <= STORY_END + 1e-9; t += step) table.push(+filmOf(t).toFixed(4));
writeFileSync('audio/warp.json', JSON.stringify({ step, film_len: FILM_LEN, cover: COVER.t, table }));
console.log('film_len', FILM_LEN.toFixed(3), 'cover(story)', COVER.t.toFixed(3));
