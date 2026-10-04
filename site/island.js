// 收进刘海的网页示意：一块带刘海的屏幕。窗口飞进刘海、刘海两边露出图标和个数；指针停在刘海上，往下展开成一排；
// 收着的窗口标题变了，刘海短暂展开说一句。
//
// 岛的形状（宽、高、圆角）各是一根弹簧，每一帧积分：换目标时保留当下的速度，变到一半改主意也不顿（WWDC23
// “Animate with springs”）。没有动量的变化（展开、收回）几乎不回弹；提醒带一点弹性。内容被岛裁着，随岛长出来。
// 减少动态效果时直接到位。
(() => {
  const stage = document.querySelector('#notch-desk');
  if (!stage) return;
  const island = stage.querySelector('.island');
  const compact = island.querySelector('.island-compact');
  const alertBox = island.querySelector('.island-alert');
  const shelf = island.querySelector('.island-shelf');
  const count = island.querySelector('.island-count');
  const front = stage.querySelector('#notch-front');
  const tuckButton = document.querySelector('#notch-tuck');
  const alertButton = document.querySelector('#notch-alert');
  const stateText = document.querySelector('#notch-state');
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');

  // ---- 弹簧：每个量一根。换目标时留下速度，这一帧用闭式解走到 dt 之后，不靠欧拉累积误差 ----
  class Spring {
    constructor(value) { this.value = value; this.target = value; this.velocity = 0; this.set(1, 0.34); }
    set(damping, response) { this.zeta = damping; this.response = response; }
    step(dt) {
      const [d, v] = WSMotion.solve(this.value - this.target, this.velocity, this.response, this.zeta, dt);
      this.value = this.target + d;
      this.velocity = v;
    }
    get resting() { return Math.abs(this.value - this.target) < 0.05 && Math.abs(this.velocity) < 0.5; }
    snap() { this.value = this.target; this.velocity = 0; }
  }
  const shape = { w: new Spring(0), h: new Spring(0), r: new Spring(0) };

  // 各种样子（cqw：屏宽的百分之一）。刘海和菜单栏一样高；展开时外框圆角与里面卡片的圆角同心、边距一致。
  const NOTCH = { w: 14.5, h: 5.4, r: 1.5 };
  const shapes = {
    rest: NOTCH,
    compact: { w: NOTCH.w + 2 * 4.6, h: NOTCH.h, r: 1.6 },
    alert: { w: 38, h: NOTCH.h + 8.6, r: 3.6 },
    shelf: { w: 54, h: NOTCH.h + 21, r: 4.2 },
  };
  let mode = 'rest';
  let tucked = false, changed = false, hovering = false, alertUntil = 0, frame = 0, last = 0;

  function target() {
    if (hovering && tucked) return 'shelf';
    if (performance.now() < alertUntil) return 'alert';
    return tucked ? 'compact' : 'rest';
  }

  function retarget() {
    const next = target();
    if (next === mode && frame) return;
    // 收回、换状态 calm；展开一排 expand；提醒 bloom。
    const token = next === 'alert' ? 'bloom' : next === 'shelf' ? 'expand' : 'calm';
    const [response, zeta] = WSMotion.named(token);
    for (const key of ['w', 'h', 'r']) {
      shape[key].target = shapes[next][key];
      shape[key].set(zeta, response);
      if (reduce.matches) shape[key].snap();
    }
    mode = next;
    island.dataset.mode = next;
    stage.classList.toggle('has-changed', changed);
    run();
  }

  let swellAt = 0;
  function swell() {
    if (!swellAt) return { w: 0, h: 0 };
    const t = (performance.now() - swellAt) / 1000;
    const pt = WSMotion.ptInCqw(stage);
    // +700 / +300 pt/s 踢在 calm 上。pt 换成这张插图的 cqw。
    return { w: WSMotion.kick(t, 700 * pt), h: WSMotion.kick(t, 300 * pt) };
  }
  function draw() {
    const bump = swell();
    island.style.width = `${(shape.w.value + bump.w).toFixed(3)}cqw`;
    island.style.height = `${(shape.h.value + bump.h).toFixed(3)}cqw`;
    island.style.borderBottomLeftRadius = island.style.borderBottomRightRadius = `${Math.max(0, shape.r.value).toFixed(3)}cqw`;
  }

  function tick(now) {
    const dt = Math.min(0.032, (now - last) / 1000 || 0.016);
    last = now;
    for (const s of Object.values(shape)) s.step(dt);
    draw();
    const bump = swell();
    const still = Object.values(shape).every(s => s.resting) && Math.abs(bump.w) < 0.02 && Math.abs(bump.h) < 0.02;
    if (still) {
      swellAt = 0;
      for (const s of Object.values(shape)) s.snap();
      draw();
      frame = 0;
      return;
    }
    frame = requestAnimationFrame(tick);
  }
  function run() {
    if (frame) return;
    last = performance.now();
    frame = requestAnimationFrame(tick);
  }

  // ---- 收进刘海：前面那扇窗缩小、飞进刘海（被刘海挡住），刘海鼓一下，两边露出图标和个数 ----
  let flight = 0;
  let flightPose = null;
  function placeFront(p) {
    if (!flightPose) return;
    const { dx, dy, scale } = flightPose;
    front.style.transform = `translate(${dx * p}px, ${dy * p}px) scale(${1 + (scale - 1) * p})`;
    front.style.borderRadius = `${2.6 + (6 - 2.6) * p}cqw`;
  }
  function tuck() {
    if (tucked) return release();
    tucked = true;
    changed = false;
    front.classList.add('is-leaving');
    const stageBox = stage.getBoundingClientRect();
    const box = front.getBoundingClientRect();
    flightPose = {
      dx: stageBox.left + stageBox.width / 2 - (box.left + box.width / 2),
      dy: stageBox.top + stageBox.height * 0.03 - (box.top + box.height / 2),
      scale: (stageBox.width * 0.07) / box.width,
    };
    const done = () => {
      front.hidden = true;
      retarget();
      // 完全挡住的那一帧：calm 被踢一脚，鼓一下再回到原来的尺寸。
      if (!reduce.matches) { swellAt = performance.now(); run(); }
    };
    cancelAnimationFrame(flight);
    if (reduce.matches) { placeFront(1); done(); }
    else {
      // 飞进刘海：settle，终点是个口子，不回弹。
      const [response, zeta] = WSMotion.named('settle');
      const t0 = performance.now();
      const step = now => {
        const p = WSMotion.progress((now - t0) / 1000, response, zeta);
        placeFront(Math.min(1, p));
        if (1 - p > 0.004) flight = requestAnimationFrame(step);
        else { placeFront(1); done(); }
      };
      flight = requestAnimationFrame(step);
    }
    sync();
  }

  function release() {
    tucked = false;
    changed = false;
    alertUntil = 0;
    hovering = false;
    swellAt = 0;
    retarget();
    front.hidden = false;
    front.classList.remove('is-leaving');
    cancelAnimationFrame(flight);
    if (reduce.matches || !flightPose) { front.style.transform = ''; front.style.borderRadius = ''; }
    else {
      const [response, zeta] = WSMotion.named('flyOut');
      const t0 = performance.now();
      const step = now => {
        const p = WSMotion.progress((now - t0) / 1000, response, zeta);
        placeFront(1 - Math.min(1, p));
        if (1 - p > 0.004) flight = requestAnimationFrame(step);
        else { front.style.transform = ''; front.style.borderRadius = ''; }
      };
      flight = requestAnimationFrame(step);
    }
    sync();
  }

  // ---- 提醒：收着的窗口标题变了（编译完成），刘海展开说一句，2.6 秒后收回，格子上留个点 ----
  function alertOnce() {
    if (!tucked) return;
    changed = true;
    alertUntil = performance.now() + 2600;
    retarget();
    setTimeout(retarget, 2620);
    sync();
  }

  function sync() {
    tuckButton.textContent = tucked ? tuckButton.dataset.release : tuckButton.dataset.tuck;
    alertButton.disabled = !tucked;
    stateText.textContent = tucked ? (changed ? stateText.dataset.changed : stateText.dataset.tucked) : stateText.dataset.ready;
    count.textContent = tucked ? '1' : '0';
  }

  tuckButton.addEventListener('click', tuck);
  alertButton.addEventListener('click', alertOnce);
  // 指针停在刘海上：展开成一排（停一小会儿才展开，划过去不算）；移开就收。
  let hoverTimer = 0;
  island.addEventListener('pointerenter', () => {
    clearTimeout(hoverTimer);
    hoverTimer = setTimeout(() => { hovering = true; retarget(); }, 120);
  });
  island.addEventListener('pointerleave', () => {
    clearTimeout(hoverTimer);
    if (!hovering) return;
    hovering = false;
    if (changed) { changed = false; sync(); }
    retarget();
  });
  island.addEventListener('focusin', () => { hovering = true; retarget(); });
  island.addEventListener('focusout', () => { hovering = false; retarget(); });
  shelf.querySelector('.island-card')?.addEventListener('click', () => release());

  for (const key of ['w', 'h', 'r']) shape[key].value = shape[key].target = NOTCH[key];
  draw();
  sync();
  island.dataset.mode = 'rest';
})();
