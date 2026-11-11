// 位移只用命名弹簧，不报时长、不套贝塞尔。
// 两个数：response（秒）和阻尼比 ζ。质量 1，刚度 (2π/response)²，阻尼 4πζ/response。
// solve(d0, v0, response, zeta, t) 是停在终点上的闭式解：d0 为离开终点的位移，v0 为点/秒。
(() => {
  const tokens = {
    calm: [0.34, 1],
    settle: [0.38, 1],
    expand: [0.40, 0.92],
    bloom: [0.42, 0.84],
    catch: [0.40, 0.80],
    glide: [0.42, 0.88],
    flyOut: [0.38, 0.90],
    pull: [0.36, 0.86],
    pop: [0.30, 0.75],
    reduced: [0.25, 1],
    dolly: [1.6, 1],
  };

  function solve(d0, v0, response, zeta, t) {
    if (t <= 0) return [d0, v0];
    const w = (2 * Math.PI) / response;
    const z = zeta;
    if (z < 1) {
      const wd = w * Math.sqrt(1 - z * z);
      const e = Math.exp(-z * w * t);
      const c = Math.cos(wd * t);
      const s = Math.sin(wd * t);
      const b = (v0 + z * w * d0) / wd;
      const d = e * (d0 * c + b * s);
      return [d, -z * w * d + e * wd * (b * c - d0 * s)];
    }
    const e = Math.exp(-w * t);
    const k = v0 + w * d0;
    const d = (d0 + k * t) * e;
    return [d, (k - w * (d0 + k * t)) * e];
  }

  // 从 0 走向 1。v0 是这段路程的归一化初速度（每秒走完全程的几倍）。
  function progress(t, response, zeta, v0 = 0) {
    if (t <= 0) return 0;
    return 1 + solve(-1, v0, response, zeta, t)[0];
  }

  function named(name) {
    return tokens[name] || tokens.calm;
  }

  // 临界阻尼、从终点被踢一脚。峰值在 t = response/(2π)，大小 v0/(ωe)。
  function kick(t, velocity, response = tokens.calm[0]) {
    return solve(0, velocity, response, 1, t)[0];
  }

  const reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

  // apply(p) 收到 0→1。返回取消函数。停在残差里，不等一段写死的时长。
  function play(name, apply, done) {
    const [response, zeta] = named(name);
    if (reduced()) { apply(1); if (done) done(); return () => {}; }
    const t0 = performance.now();
    let frame = 0;
    const step = now => {
      const t = (now - t0) / 1000;
      const p = progress(t, response, zeta);
      if (Math.abs(1 - p) > 0.004 && t < 1.6) { apply(p); frame = requestAnimationFrame(step); }
      else { apply(1); if (done) done(); }
    };
    frame = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame);
  }

  // 收起 / 展开一块内容。弹簧是 settle（尺寸，不回弹）。
  // commit()：调用方在这里切换收起状态的 class；roll 在切换前后各量一次高度（只在开始时量，不缓存，
  // 窗口改过尺寸也准）。同一个元素上一段还没走完就再点，上一段被取消，从它当下露出的高度接着走。
  //
  // 默认（窗口绝对定位、不推动别的内容）：版面在动画期间钉在两种高度里较大的那个，只每帧改 clip-path
  // 露出多少，结束时才把版面交给 CSS。opts.clip 是被裁的元素（默认 el 本身），opts.round 是被裁形状的
  // 圆角，opts.edge(cut) 每帧收到被裁掉的像素数，给需要跟着底边走的装饰（比如窗口底边框）。
  // opts.layout：窗口在文档流里、它的高度会推动下面整页内容（往事页 02、05）。这种“下面的内容跟着
  // 滑动”本身就是版面变化，用 transform 做不出来，所以这两处有意保留逐帧改 height。
  const rolls = new WeakMap();
  function roll(el, folded, opts = {}) {
    if (!el) { opts.commit?.(); return () => {}; }
    const prev = rolls.get(el);
    prev?.cancel();
    const clipEl = opts.clip || el;
    // 读：上一段停下时露出的高度（没有上一段就是现在的高度）。
    const from = prev ? prev.shown : el.getBoundingClientRect().height;
    el.style.height = '';
    opts.commit?.();
    // 读：切换之后 CSS 给的高度（展开时就是展开后的高度；收起时是 0）。
    const to = el.getBoundingClientRect().height;
    const state = { shown: from, cancel: () => {} };
    rolls.set(el, state);
    const finish = () => {
      if (rolls.get(el) !== state) return;
      rolls.delete(el);
      el.style.height = '';
      clipEl.style.clipPath = '';
      opts.edge?.(null);
    };
    if (opts.layout) {
      el.style.height = `${from}px`;
      const stop = play('settle', p => { state.shown = from + (to - from) * p; el.style.height = `${state.shown}px`; }, finish);
      state.cancel = () => { stop(); };
      return state.cancel;
    }
    const pinned = Math.max(from, to);
    el.style.height = `${pinned}px`;
    const round = opts.round ? ` round ${opts.round}` : '';
    const draw = shown => {
      state.shown = shown;
      // Whole pixels, as the old height animation landed on: a fractional cut smears the bottom edge.
      const cut = Math.max(0, Math.round(pinned - shown));
      clipEl.style.clipPath = opts.clipPath ? opts.clipPath(cut) : `inset(0 0 ${cut.toFixed(2)}px 0${round})`;
      opts.edge?.(cut);
    };
    draw(from);
    const stop = play('settle', p => draw(from + (to - from) * p), finish);
    state.cancel = () => { stop(); };
    return state.cancel;
  }

  // 插图里 1pt 占多少 cqw。没写 --pt 时按 Air 15 默认模式：100cqw = 1710pt。
  function ptInCqw(el) {
    const raw = el && getComputedStyle(el).getPropertyValue('--pt').trim();
    if (raw.endsWith('cqw')) return parseFloat(raw) || 100 / 1710;
    return 100 / 1710;
  }

  // 一根可打断的弹簧：to() 换终点时保留此刻的位置和速度（WWDC23 10158 的叠加：位置、速度都连续，
  // 中途掉头不撞墙）。每帧用闭式解从上一帧推到这一帧，帧率高低（60 / 120 Hz）走的是同一条曲线。
  // onFrame(value) 每帧调用；静止后自己停，不空转 requestAnimationFrame。
  class Spring {
    constructor(value, onFrame, token = 'calm') {
      this.value = value; this.target = value; this.velocity = 0;
      this.onFrame = onFrame; this.frame = 0; this.last = 0;
      this.use(token);
    }
    use(token) { [this.response, this.zeta] = named(token); return this; }
    // velocity：单位/秒（和 value 同一单位）。不传就沿用当下的速度。
    to(target, { token, velocity } = {}) {
      if (token) this.use(token);
      if (velocity !== undefined) this.velocity = velocity;
      this.target = target;
      if (reduced()) { this.snap(target); return this; }
      if (!this.frame) { this.last = 0; this.frame = requestAnimationFrame(t => this.step(t)); }
      return this;
    }
    snap(value = this.target) {
      cancelAnimationFrame(this.frame); this.frame = 0;
      this.value = this.target = value; this.velocity = 0;
      this.onFrame(value);
      return this;
    }
    stop() { cancelAnimationFrame(this.frame); this.frame = 0; this.velocity = 0; this.target = this.value; }
    get moving() { return !!this.frame; }
    step(now) {
      const dt = this.last ? Math.min(0.05, (now - this.last) / 1000) : 1 / 120;
      this.last = now;
      const [d, v] = solve(this.value - this.target, this.velocity, this.response, this.zeta, dt);
      this.value = this.target + d; this.velocity = v;
      // 停在残差里：位移和速度都小到看不出来就落定，不等一段写死的时长。
      const span = Math.max(1e-6, this.rest ?? 0.001);
      if (Math.abs(d) < span && Math.abs(v) < span * 10) { this.frame = 0; this.value = this.target; this.velocity = 0; this.onFrame(this.value); return; }
      this.onFrame(this.value);
      this.frame = requestAnimationFrame(t => this.step(t));
    }
  }

  window.WSMotion = { tokens, solve, progress, named, kick, play, roll, reduced, ptInCqw, Spring };
})();
