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

  // 收起内容的高度。open 高度记在元素上，弹簧是 settle（尺寸，不回弹）。
  function roll(el, folded) {
    if (!el) return;
    const measured = el.getBoundingClientRect().height;
    if (!el.dataset.openHeight && measured > 1) el.dataset.openHeight = String(measured);
    const from = measured;
    const to = folded ? 0 : Number(el.dataset.openHeight || measured);
    el.style.height = `${from}px`;
    return play('settle', p => { el.style.height = `${from + (to - from) * p}px`; }, () => {
      el.style.height = folded ? '0px' : '';
    });
  }

  // 插图里 1pt 占多少 cqw。没写 --pt 时按 Air 15 默认模式：100cqw = 1710pt。
  function ptInCqw(el) {
    const raw = el && getComputedStyle(el).getPropertyValue('--pt').trim();
    if (raw.endsWith('cqw')) return parseFloat(raw) || 100 / 1710;
    return 100 / 1710;
  }

  window.WSMotion = { tokens, solve, progress, named, kick, play, roll, reduced, ptInCqw };
})();
