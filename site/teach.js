// 手势课：照“系统设置 → 触控板”的样子教手势。
//
// 画法和节奏照系统自带的那几段演示（TrackpadExtension.appex 里的 Trackpad.mov，2026-09-27 逐帧量过）：
// - 触控板只画一圈轮廓。手指悬着时是一圈细边、淡淡的底，按上去变成实心的蓝点（rgb(26,89,184)，66%）；两指相距约触控板宽的
//   16%，三指时中间那根高一点。按着移动时身后拖一道渐隐的尾巴，长度是最近 0.27 秒走过的路。
// - 一笔的节奏：出现（悬着）0.4 秒 → 停 0.2 → 按下 0.19 → 停 0.5 → 移动约 1 秒（cubic-bezier(.32,0,.67,1)）→ 抬起 0.22 →
//   停 1.1。能往回做的招接着往回做一遍，一圈首尾相接；接不上的最后淡出复位。最后淡出 0.38、空 0.42。
// - 右边的小桌面和手指走同一条曲线：移动时窗口跟着走一段，抬手（松手才算数）后按应用本身的弹簧落定
//   （位置 0.88 / 0.42，尺寸 1 / 0.38，见 prototype/Core/FlickMotion.swift）。
// 甩一下是系统里没有的招：按下后加速甩出去（0.28 秒、ease-in），还在动时就抬手，尾巴最长，窗口接上这股速度带点回弹落定。
// 减少动态效果时不循环，只摆出这一招做完的样子，手指停在划完的位置。
(() => {
  const root = document.querySelector('[data-teach]');
  if (!root) return;

  // ---- 曲线和弹簧 ----
  const clamp01 = v => Math.max(0, Math.min(1, v));
  const seg = (t, a, b) => (b <= a ? (t >= b ? 1 : 0) : clamp01((t - a) / (b - a)));
  const mix = (a, b, p) => a + (b - a) * p;
  function bezier(x1, y1, x2, y2) {
    const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
    const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
    const X = t => ((ax * t + bx) * t + cx) * t, Y = t => ((ay * t + by) * t + cy) * t, dX = t => (3 * ax * t + 2 * bx) * t + cx;
    return x => {
      if (x <= 0) return 0;
      if (x >= 1) return 1;
      let t = x;
      for (let i = 0; i < 8; i++) { const d = X(t) - x, s = dX(t); if (Math.abs(d) < 1e-5 || !s) break; t -= d / s; }
      return Y(clamp01(t));
    };
  }
  const moveCurve = bezier(0.32, 0, 0.67, 1);
  const easeIn = p => p * p * p;
  const easeOut = p => 1 - Math.pow(1 - p, 3);
  function spring(ms, z, r, v = 0) {
    const t = ms / 1000;
    if (t <= 0) return 0;
    const w = (2 * Math.PI) / r;
    if (z < 1) {
      const wd = w * Math.sqrt(1 - z * z);
      return 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + ((z * w - v) / wd) * Math.sin(wd * t));
    }
    return 1 - (1 + (w - v) * t) * Math.exp(-w * t);
  }
  const pos = (ms, v = 0) => spring(ms, 0.88, 0.42, v);
  const size = ms => spring(ms, 1, 0.38);
  const glide = (a, b, pp, ps = pp) => ({ x: mix(a.x, b.x, pp), y: mix(a.y, b.y, pp), w: mix(a.w, b.w, ps), h: mix(a.h, b.h, ps) });
  const off = (r, dx, dy) => ({ ...r, x: r.x + dx, y: r.y + dy });
  const rubber = (x, d) => (x * d * 0.55) / (d + 0.55 * x);

  // ---- 节奏（毫秒）----
  const T = { appear: 400, settle: 200, press: 190, dwell: 500, move: 1000, lift: 220, hold: 1100, fade: 380, empty: 420, flick: 280 };

  // ---- 小桌面（x 按屏宽百分比，y 按屏高百分比）----
  const BAR = 5.4, TOP = 7.4, DOCK = 87.5, GX = 1.2, GY = 1.9;
  const HOME = { x: 22, y: 17, w: 56, h: 58 };
  const AREA = { x: GX, y: TOP, w: 100 - 2 * GX, h: DOCK - GY - TOP };
  const HALF = (AREA.w - GX) / 2, HH = (AREA.h - GY) / 2;
  const FILL = { ...AREA };
  const LEFT = { x: GX, y: TOP, w: HALF, h: AREA.h };
  const RIGHT = { x: GX * 2 + HALF, y: TOP, w: HALF, h: AREA.h };
  const L23 = { x: GX, y: TOP, w: ((AREA.w - GX) * 2) / 3, h: AREA.h };
  const L13 = { x: GX, y: TOP, w: (AREA.w - GX) / 3, h: AREA.h };
  const BL = { x: GX, y: TOP + HH + GY, w: HALF, h: HH };
  const ROLLED = { ...HOME, h: BAR };
  // 刘海与侧拉：带刘海的 MacBook 屏，刘海和菜单栏一样高。
  const NOTCH = { w: 17, h: 8.6 }, SIDE = 5.6;
  const REST = { w: NOTCH.w, h: NOTCH.h, compact: 0 };
  const MID = { x: 30, y: 27, w: 40, h: 50 };
  const DOCKED = { x: GX, y: NOTCH.h + GY, w: 31, h: DOCK - GY - (NOTCH.h + GY) };
  const TUCKED = { ...DOCKED, x: -DOCKED.w + 0.7 };
  const INTO = { x: 50 - 4, y: 1, w: 8, h: 5.6 };
  const bar = r => ({ x: r.x + r.w * 0.56, y: r.y + BAR * 0.55 });
  const ON_NOTCH = { x: 50, y: 4.4 };
  const ON_HANDLE = { x: 1.6, y: 46 };

  // ---- 手指（按触控板宽高的百分比）----
  const TWO = [[42, 50], [58, 50]];
  const ONE = [[50, 58]];
  const THREE = [[36, 52], [50, 45], [64, 52]];

  // ---- 桌面怎么响应一笔 ----
  // fx(e)：e.p 移动进度（0–1），e.since 抬手后过了多少毫秒（还没抬手为 -1）。返回窗口、指针（跟着走时）、刘海、把手。
  const S = {
    // 移动时窗口朝目标走 0.3，抬手后弹簧走完。
    glide: (from, to) => e => ({ win: e.since < 0 ? glide(from, to, 0.3 * e.p) : glide(glide(from, to, 0.3), to, pos(e.since), size(e.since)) }),
    // 甩出去：窗口和指针跟着拖走一段，抬手后接上速度落到目标。
    flick: (from, to, drag) => e => {
      if (e.since < 0) {
        const moving = off(from, drag[0] * e.p, drag[1] * e.p);
        return { win: moving, ptr: bar(moving) };
      }
      const dragged = off(from, drag[0], drag[1]);
      return { win: glide(dragged, to, pos(e.since, 2.4), size(e.since)), ptr: bar(dragged) };
    },
    // 往上甩收起：拖一段，抬手后在那儿卷起来。
    flickRoll: (from, drag) => e => {
      if (e.since < 0) {
        const moving = off(from, 0, drag * e.p);
        return { win: moving, ptr: bar(moving) };
      }
      const dragged = off(from, 0, drag);
      return { win: { ...dragged, h: mix(from.h, BAR, size(e.since)) }, ptr: bar(dragged) };
    },
  };

  const threePath = p => [p < 0.78 ? 12 * moveCurve(p / 0.78) : 12 + 16 * easeIn((p - 0.78) / 0.22), 0];

  const lessons = {
    shade: { strokes: [
      { fingers: TWO, move: [0, -20], ptr: bar(HOME), fx: S.glide(HOME, ROLLED) },
      { move: [0, 20], ptr: bar(HOME), fx: S.glide(ROLLED, HOME) },
    ] },
    fill: { strokes: [
      { fingers: TWO, move: [0, 20], ptr: bar(HOME), fx: S.glide(HOME, FILL) },
      { move: [0, -20], ptr: bar(HOME), fx: S.glide(FILL, HOME) },
    ] },
    halves: { reset: true, strokes: [
      { fingers: TWO, move: [-18, 0], ptr: bar(HOME), fx: S.glide(HOME, LEFT) },
      { fingers: TWO, regrip: true, move: [-18, 0], ptr: bar(LEFT), fx: S.glide(LEFT, L23) },
      { fingers: TWO, regrip: true, move: [-18, 0], ptr: bar(L23), fx: S.glide(L23, L13) },
    ] },
    corner: { reset: true, strokes: [
      { fingers: TWO, duration: 1400, ptr: bar(HOME), fx: S.glide(HOME, BL),
        path: p => (p < 0.5 ? [-18 * moveCurve(p / 0.5), 0] : [-18, 18 * moveCurve((p - 0.5) / 0.5)]) },
    ] },
    spread: { strokes: [
      { fingers: [[46, 54], [54, 46]], spread: [[-14, 14], [14, -14]], ptr: bar(HOME), fx: S.glide(HOME, FILL) },
      { spread: [[14, -14], [-14, 14]], ptr: bar(HOME), fx: S.glide(FILL, HOME) },
    ] },
    tap: { strokes: [
      { fingers: TWO, taps: 2, ptr: bar(HOME), fx: e => ({ win: e.since < 0 ? HOME : glide(HOME, FILL, pos(e.since), size(e.since)) }) },
      { taps: 2, ptr: bar(HOME), fx: e => ({ win: e.since < 0 ? FILL : glide(FILL, HOME, pos(e.since), size(e.since)) }) },
    ] },

    'flick-up': { reset: true, strokes: [{ fingers: ONE, move: [0, -28], flick: true, ptr: bar(HOME), fx: S.flickRoll(HOME, -6) }] },
    'flick-down': { reset: true, strokes: [{ fingers: ONE, move: [0, 26], flick: true, ptr: bar(HOME), fx: S.flick(HOME, FILL, [0, 6]) }] },
    'flick-side': { reset: true, strokes: [{ fingers: ONE, move: [-30, 0], flick: true, ptr: bar(HOME), fx: S.flick(HOME, LEFT, [-8, 0]) }] },
    'flick-corner': { reset: true, strokes: [{ fingers: ONE, move: [-24, 22], flick: true, ptr: bar(HOME), fx: S.flick(HOME, BL, [-6, 5]) }] },
    // 三指拖移：拖着慢慢走，最后加速甩出去、手指一离开就算。
    'flick-three': { reset: true, strokes: [{
      fingers: THREE, duration: 1250, flick: true, path: threePath, ptr: bar(HOME),
      fx: e => {
        const moving = off(HOME, threePath(e.since < 0 ? e.p : 1)[0] * 0.4, 0);
        return e.since < 0 ? { win: moving, ptr: bar(moving) } : { win: glide(moving, RIGHT, pos(e.since, 2.2), size(e.since)), ptr: bar(moving) };
      },
    }] },
  };

  // 刘海：甩进去，再两指拉出来（或者反过来）。窗口缩小飞进刘海、被摄像头那一块挡住；落进去那一下刘海鼓一下，
  // 两边露出图标和个数。拉的时候刘海跟着手往下长、越往下越拉不动；松手，窗口从刘海里飞回原处。
  const notchIn = {
    fingers: ONE, move: [0, -28], flick: true, ptr: bar(MID),
    fx: e => {
      if (e.since < 0) {
        const moving = off(MID, 0, -6 * e.p);
        return { win: moving, ptr: bar(moving), notch: REST };
      }
      const lifted = off(MID, 0, -6);
      const grow = e.since > 380 ? WSMotion.progress((e.since - 380) / 1000, ...WSMotion.named('expand')) : 0;
      const swellT = Math.max(0, (e.since - 380) / 1000);
      // 课里的坐标是屏宽、屏高的百分比。Air 15 默认 1710×1107 pt。
      const bumpW = WSMotion.kick(swellT, 700 * 100 / 1710);
      const bumpH = WSMotion.kick(swellT, 300 * 100 / 1107);
      const flyP = WSMotion.progress(e.since / 1000, ...WSMotion.named('settle'));
      return {
        win: { ...lifted, hidden: true }, ptr: bar(lifted),
        fly: e.since < 700 ? glide(lifted, INTO, flyP, flyP) : null,
        notch: { w: NOTCH.w + 2 * SIDE * grow + bumpW, h: NOTCH.h + bumpH, compact: grow },
      };
    },
  };
  const notchOut = {
    fingers: TWO, move: [0, 22], ptr: ON_NOTCH,
    fx: e => {
      if (e.since < 0) {
        const extra = rubber(26 * e.p, 14);
        return { win: { ...MID, hidden: true }, notch: { w: NOTCH.w + 2 * SIDE + extra * 0.5, h: NOTCH.h + extra, compact: 1, pull: extra / 10 } };
      }
      const extra = rubber(26, 14) * (1 - WSMotion.progress(e.since / 1000, ...WSMotion.named('pull')));
      const back = WSMotion.progress(e.since / 1000, ...WSMotion.named('calm'));
      const from = { x: 50 - 3, y: NOTCH.h + extra * 0.4, w: 6, h: 4.2 };
      return {
        win: e.since > 650 ? MID : { ...MID, hidden: true },
        fly: e.since < 650 ? glide(from, MID, pos(e.since), size(e.since)) : null,
        notch: { w: NOTCH.w + 2 * SIDE * (1 - back) + extra * 0.5, h: NOTCH.h + extra, compact: 1 - back, pull: extra / 10 },
      };
    },
  };
  lessons['notch-in'] = { scene: 'notch', strokes: [notchIn, notchOut] };
  lessons['notch-out'] = { scene: 'notch', strokes: [notchOut, notchIn] };

  // 侧拉：朝屏幕边甩，收到边外、留个把手；在把手上两指往里划，拉出来（或者反过来）。
  const slideHide = {
    fingers: ONE, move: [-28, 0], flick: true, ptr: bar(DOCKED),
    fx: e => {
      if (e.since < 0) {
        const moving = off(DOCKED, -5 * e.p, 0);
        return { win: { ...moving, docked: true }, ptr: bar(moving), handle: 0 };
      }
      return { win: { ...glide(off(DOCKED, -5, 0), TUCKED, pos(e.since, 2.4)), docked: true }, ptr: bar(off(DOCKED, -5, 0)), handle: seg(e.since, 250, 500) };
    },
  };
  const slideShow = {
    fingers: TWO, move: [22, 0], ptr: ON_HANDLE,
    fx: e => {
      if (e.since < 0) return { win: { ...off(TUCKED, rubber(22 * e.p, 12) * 0.5, 0), docked: true }, handle: 1 };
      const from = off(TUCKED, rubber(22, 12) * 0.5, 0);
      return { win: { ...glide(from, DOCKED, spring(e.since, 0.88, 0.42, 1.4)), docked: true }, handle: 1 - seg(e.since, 0, 220) };
    },
  };
  lessons['slide-hide'] = { scene: 'notch', strokes: [slideHide, slideShow] };
  lessons['slide-show'] = { scene: 'notch', strokes: [slideShow, slideHide] };

  // ---- 把一课排成时间线 ----
  function plan(lesson) {
    const strokes = [];
    let t = T.appear + T.settle;
    let fingers = lesson.strokes[0].fingers;
    let at = fingers.map(p => [...p]);
    lesson.strokes.forEach((s, i) => {
      const regrip = i > 0 && (s.regrip || (s.fingers && s.fingers !== fingers));
      if (s.fingers) fingers = s.fingers;
      const start = i === 0 || regrip ? fingers.map(p => [...p]) : at.map(p => [...p]);
      // 换手时，上一笔的手指先淡出，这一笔的手指在新位置出现后再按下。
      const press = t + (regrip ? 500 : 0);
      let move0, move1;
      if (s.taps) {
        move0 = press;
        move1 = press + s.taps * 360 - 230;
      } else {
        move0 = press + T.press + (s.flick ? 140 : T.dwell);
        move1 = move0 + (s.duration ?? (s.flick ? T.flick : T.move));
      }
      const offset = p => {
        if (s.taps) return start.map(q => [...q]);
        if (s.spread) return start.map((q, k) => [q[0] + s.spread[k][0] * p, q[1] + s.spread[k][1] * p]);
        const d = s.path ? s.path(p) : [s.move[0] * p, s.move[1] * p];
        return start.map(q => [q[0] + d[0], q[1] + d[1]]);
      };
      const hold = move1 + T.lift + (s.flick ? 1300 : T.hold);
      strokes.push({ s, press, move0, move1, lift: move1, hold, offset, regrip });
      at = offset(1);
      t = hold;
    });
    return { lesson, strokes, total: t + T.fade + T.empty, fadeAt: t };
  }

  // 这一笔的移动进度：手画的路径自己带曲线；甩一下用 ease-in；其余用系统的那条曲线。
  const progress = (st, t) => {
    if (st.s.taps) return t >= st.move1 ? 1 : 0;
    const raw = seg(t, st.move0, st.move1);
    return st.s.path ? raw : (st.s.flick ? easeIn : moveCurve)(raw);
  };

  // 指针：每一笔之前挪到该在的地方（标题栏、刘海、把手），甩的时候跟着窗口走。
  function pointerAt(P, t) {
    const { strokes } = P;
    let p = strokes[0].s.ptr;
    for (let j = 1; j < strokes.length; j++) {
      const a = strokes[j].press - 650;
      if (t < a) break;
      const prev = strokes[j - 1].s.fx({ p: 1, since: 1e6 }).ptr ?? strokes[j - 1].s.ptr;
      const g = moveCurve(seg(t, a, strokes[j].press - 80));
      p = { x: mix(prev.x, strokes[j].s.ptr.x, g), y: mix(prev.y, strokes[j].s.ptr.y, g) };
    }
    return p;
  }

  function frameAt(P, t) {
    const { strokes } = P;
    let k = strokes.length - 1;
    while (k > 0 && t < strokes[k].press - (strokes[k].regrip ? 480 : 0)) k--;
    const st = strokes[k];
    const s = st.s;
    const p = progress(st, t);
    const since = t >= st.lift ? t - st.lift : -1;

    // 手指：出现、按下、抬起、换手、淡出。
    let press = 0;
    if (s.taps) {
      for (let i = 0; i < s.taps; i++) {
        const a = st.press + i * 360;
        press = Math.max(press, seg(t, a, a + 130) * (1 - seg(t, a + 130, a + 230)));
      }
    } else {
      press = seg(t, st.press, st.press + T.press) * (1 - seg(t, st.lift, st.lift + T.lift));
    }
    let presence = Math.min(seg(t, 0, T.appear), 1 - seg(t, P.fadeAt, P.fadeAt + T.fade));
    if (st.regrip) presence = Math.min(presence, seg(t, st.press - 460, st.press - 120));
    const next = strokes[k + 1];
    if (next?.regrip) presence = Math.min(presence, 1 - seg(t, next.press - 780, next.press - 500));
    const pts = st.offset(s.path ? seg(t, st.move0, st.move1) : p);
    const trailing = !s.taps && t >= st.move0 && (t < st.move1 || (s.flick && t < st.move1 + 110));
    const behind = trailing ? st.offset(s.path ? seg(t - 270, st.move0, st.move1) : progress(st, t - 270)) : null;
    const dots = pts.map((q, i) => ({ x: q[0], y: q[1], press, o: presence, trail: behind && press > 0.3 ? behind[i] : null }));
    const ripples = s.taps ? pts.flatMap(q => Array.from({ length: s.taps }, (_, i) => {
      const r = seg(t, st.press + i * 360, st.press + i * 360 + 420);
      return r > 0 && r < 1 ? { x: q[0], y: q[1], s: 1 + 1.2 * easeOut(r), o: 0.45 * (1 - r) } : null;
    }).filter(Boolean)) : [];

    // 桌面：每一笔的结果按顺序叠上来（前面的笔停在下一笔按下的那一刻）。
    let scene = { ...strokes[0].s.fx({ p: 0, since: -1 }) };
    for (let i = 0; i <= k; i++) {
      const si = strokes[i];
      const ti = i < k ? Math.min(t, strokes[i + 1].press) : t;
      scene = { ...scene, ...si.s.fx({ p: progress(si, ti), since: ti >= si.lift ? ti - si.lift : -1 }) };
    }
    const own = s.fx({ p, since });
    let ptr = own.ptr && t >= st.move0 ? own.ptr : pointerAt(P, t);

    // 首尾接不上的几课：最后窗口淡出、复位、淡入。
    let fade = 1;
    if (P.lesson.reset) {
      fade = 1 - seg(t, P.fadeAt - 200, P.fadeAt + 150);
      if (t >= P.fadeAt + 150) {
        scene = { ...scene, ...strokes[0].s.fx({ p: 0, since: -1 }) };
        ptr = strokes[0].s.ptr;
        fade = seg(t, P.total - 420, P.total - 60);
      }
    }
    return { dots, ripples, ...scene, ptr, fade };
  }

  // ---- 画出来 ----
  const pad = root.querySelector('.tpad');
  const screen = root.querySelector('.tscreen');
  const dotEls = [...pad.querySelectorAll('.tdot')];
  const trailEls = [...pad.querySelectorAll('.ttrail')];
  const rippleEls = [...pad.querySelectorAll('.tripple')];
  const win = screen.querySelector('.twin');
  const fly = screen.querySelector('.tfly');
  const ptr = screen.querySelector('.tptr');
  const notch = screen.querySelector('.tnotch');
  const handle = screen.querySelector('.thandle');
  const pct = v => `${v.toFixed(3)}%`;
  const place = (el, r) => { el.style.left = pct(r.x); el.style.top = pct(r.y); el.style.width = pct(r.w); el.style.height = pct(r.h); };

  function render(f) {
    const box = pad.getBoundingClientRect();
    const dot = box.width * 0.12;
    dotEls.forEach((el, i) => {
      const d = f.dots[i];
      const trail = trailEls[i];
      if (!d || d.o <= 0) { el.style.opacity = '0'; trail.style.opacity = '0'; return; }
      el.style.opacity = d.o.toFixed(3);
      el.style.left = pct(d.x); el.style.top = pct(d.y);
      el.style.setProperty('--press', d.press.toFixed(3));
      if (d.trail) {
        const dx = ((d.x - d.trail[0]) / 100) * box.width, dy = ((d.y - d.trail[1]) / 100) * box.height;
        const len = Math.min(Math.hypot(dx, dy), dot * 2);
        trail.style.left = pct(d.x); trail.style.top = pct(d.y);
        trail.style.width = `${(len + dot / 2).toFixed(1)}px`;
        trail.style.transform = `translateY(-50%) rotate(${Math.atan2(-dy, -dx)}rad)`;
        trail.style.opacity = (d.o * d.press * Math.min(1, len / 3)).toFixed(3);
      } else {
        trail.style.opacity = '0';
      }
    });
    rippleEls.forEach((el, i) => {
      const r = f.ripples[i];
      el.style.opacity = r ? r.o.toFixed(3) : '0';
      if (!r) return;
      el.style.left = pct(r.x); el.style.top = pct(r.y);
      el.style.transform = `translate(-50%,-50%) scale(${r.s.toFixed(3)})`;
    });
    const fade = f.fade ?? 1;
    place(win, f.win);
    win.style.opacity = f.win.hidden ? '0' : fade.toFixed(3);
    win.classList.toggle('is-strip', f.win.h <= BAR + 0.5);
    win.classList.toggle('is-docked', !!f.win.docked);
    if (f.fly) { place(fly, f.fly); fly.style.opacity = '1'; } else { fly.style.opacity = '0'; }
    ptr.style.opacity = f.ptr ? fade.toFixed(3) : '0';
    if (f.ptr) { ptr.style.left = pct(f.ptr.x); ptr.style.top = pct(f.ptr.y); }
    const n = f.notch ?? REST;
    notch.style.width = pct(n.w);
    notch.style.height = pct(n.h);
    notch.style.setProperty('--compact', clamp01(n.compact ?? 0).toFixed(3));
    notch.style.setProperty('--pull', (n.pull ?? 0).toFixed(3));
    handle.style.opacity = (f.handle ?? 0).toFixed(3);
  }

  // ---- 选哪一招 ----
  const plans = Object.fromEntries(Object.entries(lessons).map(([id, l]) => [id, plan(l)]));
  const tabs = [...root.querySelectorAll('[data-teach-tab]')];
  const lists = [...root.querySelectorAll('[data-teach-list]')];
  const rows = [...root.querySelectorAll('[data-teach-row]')];
  const thumb = root.querySelector('.teach-tabs-thumb');
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  let current = rows[0]?.dataset.teachRow;
  let started = performance.now();
  let loops = 0, picked = false, running = false, visible = false, raf = 0, frozen = false;

  // 减少动态效果：摆出第一笔做完的样子，手指按在划完的位置。
  function still(id) {
    const P = plans[id];
    const st = P.strokes[0];
    const f = frameAt(P, Math.min(st.hold - 200, st.lift + 900));
    const end = st.offset(1);
    f.dots = end.map(q => ({ x: q[0], y: q[1], o: 1, press: 1, trail: null }));
    f.fade = 1;
    render(f);
  }

  function select(id, { user = false } = {}) {
    if (!plans[id]) return;
    if (user) picked = true;
    if (id === current && !user) return;
    current = id;
    started = performance.now();
    loops = 0;
    rows.forEach(r => r.setAttribute('aria-pressed', String(r.dataset.teachRow === id)));
    root.classList.toggle('is-notch-scene', plans[id].lesson.scene === 'notch');
    if (reduce.matches) still(id);
  }

  function showTab(index, { user = false, row } = {}) {
    tabs.forEach((tab, i) => { tab.setAttribute('aria-selected', String(i === index)); tab.tabIndex = i === index ? 0 : -1; });
    lists.forEach((list, i) => { list.hidden = i !== index; });
    thumb?.style.setProperty('--index', String(index));
    select(row || lists[index].querySelector('[data-teach-row]').dataset.teachRow, { user });
  }

  tabs.forEach((tab, i) => {
    tab.addEventListener('click', () => showTab(i, { user: true }));
    tab.addEventListener('keydown', e => {
      const step = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
      if (!step) return;
      e.preventDefault();
      const next = (i + step + tabs.length) % tabs.length;
      tabs[next].focus();
      showTab(next, { user: true });
    });
  });
  let hoverTimer = 0;
  rows.forEach(row => {
    const id = row.dataset.teachRow;
    row.addEventListener('click', () => select(id, { user: true }));
    row.addEventListener('focus', () => select(id, { user: true }));
    // 和系统设置一样：指到哪一行演示哪一行；停一小会儿才换，划过去不算。
    row.addEventListener('pointerenter', e => {
      if (e.pointerType !== 'mouse') return;
      clearTimeout(hoverTimer);
      hoverTimer = setTimeout(() => select(id, { user: true }), 90);
    });
    row.addEventListener('pointerleave', () => clearTimeout(hoverTimer));
  });

  // 没人碰的时候，每一招演一遍就换下一招，一组演完换下一组；碰过就只演选中的那一招。
  function advance() {
    const index = rows.findIndex(r => r.dataset.teachRow === current);
    const next = rows[(index + 1) % rows.length];
    showTab(lists.findIndex(list => list.contains(next)), { row: next.dataset.teachRow });
  }

  function tick(now) {
    raf = 0;
    if (!running) return;
    let t = now - started;
    if (t >= plans[current].total) {
      loops += 1;
      if (!picked) advance();
      started = now;
      t = 0;
    }
    render(frameAt(plans[current], t));
    raf = requestAnimationFrame(tick);
  }

  function sync() {
    const want = visible && !document.hidden && !reduce.matches && !frozen;
    if (want === running) return;
    running = want;
    if (running) { started = performance.now(); raf = requestAnimationFrame(tick); }
    else { cancelAnimationFrame(raf); if (reduce.matches) still(current); }
  }

  if ('IntersectionObserver' in window) {
    new IntersectionObserver(entries => { visible = entries[0].isIntersecting; sync(); }, { threshold: 0.25 }).observe(root);
  } else {
    visible = true;
  }
  document.addEventListener('visibilitychange', sync);
  reduce.addEventListener?.('change', () => { sync(); if (reduce.matches) still(current); });
  // 审图用：定格在某一招的某一刻（毫秒）。
  root.freezeAt = (id, t) => {
    frozen = true;
    running = false;
    cancelAnimationFrame(raf);
    const tab = lists.findIndex(list => list.querySelector(`[data-teach-row="${id}"]`));
    showTab(tab, { row: id, user: true });
    render(frameAt(plans[id], t));
    return plans[id].total;
  };
  showTab(0);
  render(frameAt(plans[current], 0));
  if (reduce.matches) still(current);
  sync();
})();
