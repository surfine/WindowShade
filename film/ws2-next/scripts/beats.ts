// 打印关键看点在片子里的时间（核对 3 秒、5–7 秒一个看点、70–80% 第二高点）。
import { FILM_LEN, filmOf } from '../src/warp';
import { COVER, T } from '../src/plan';
const P: [string, number][] = [
  ['窗口被刘海吞进', COVER.t], ['刘海里一排卡片', T.shelf], ['窗口飞回', T.untuck + 0.3], ['启动台从刘海倒出', T.lpOpen + 0.4],
  ['落点小岛', T.drop], ['放进右半屏', T.release + 0.3], ['实时活动', T.activity], ['离开倒数', T.away], ['锁上', T.lock],
  ['认出你', T.phone + 0.35], ['解开', T.unlock], ['读唇出字', T.char0 + 0.6], ['点头确认', T.ok], ['滑到左半屏', T.glide + 0.4],
  ['拉远见 Neo', 41.5], ['字标', T.mark],
];
for (const [n, t] of P) console.log(filmOf(t).toFixed(2).padStart(6), (100 * filmOf(t) / FILM_LEN).toFixed(0).padStart(3) + '%', n);
console.log('len', FILM_LEN.toFixed(2));
