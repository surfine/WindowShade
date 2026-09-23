const root = document.documentElement;
root.classList.add('js');
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
const finePointer = matchMedia('(hover: hover) and (pointer: fine)');

// Theme: follow the system unless the reader picked one.
const darkPreference = matchMedia('(prefers-color-scheme: dark)');
let manualTheme = null;
try { manualTheme = localStorage.getItem('windowshade-theme'); } catch {}
if (manualTheme === 'light' || manualTheme === 'dark') root.dataset.theme = manualTheme;
function syncTheme() {
  const dark = root.dataset.theme ? root.dataset.theme === 'dark' : darkPreference.matches;
  document.querySelector('.theme')?.setAttribute('aria-pressed', String(dark));
}
syncTheme();
darkPreference.addEventListener('change', syncTheme);
document.querySelector('.theme')?.addEventListener('click', () => {
  const dark = root.dataset.theme ? root.dataset.theme === 'dark' : darkPreference.matches;
  root.dataset.theme = dark ? 'light' : 'dark';
  try { localStorage.setItem('windowshade-theme', root.dataset.theme); } catch {}
  syncTheme();
});

// The header hairline appears only once content scrolls under it.
const syncScrolled = () => root.toggleAttribute('data-scrolled', scrollY > 4);
syncScrolled();
addEventListener('scroll', syncScrolled, { passive: true });

// Below-the-fold blocks settle in once. Anything already on screen is shown as-is.
if ('IntersectionObserver' in window && document.body.classList.contains('home')) {
  const targets = document.querySelectorAll('.section-head, .way-list, .story-head, .story-book, .today, .feature-copy, .feature-demo, .motion-heading, .lid-figure, .shortcut-list, .trust-copy, .questions, .closing');
  const reveal = new IntersectionObserver(entries => {
    for (const entry of entries) if (entry.isIntersecting) { entry.target.classList.add('is-in'); reveal.unobserve(entry.target); }
  }, { rootMargin: '0px 0px -8% 0px' });
  for (const el of targets) {
    if (el.getBoundingClientRect().top < innerHeight) continue;
    el.dataset.reveal = '';
    reveal.observe(el);
  }
}

// Hero: roll the reference window up into its bar, and drag the bar anywhere on the desk.
const desk = document.querySelector('#desk');
const reference = document.querySelector('#reference');
const fold = document.querySelector('#fold');
const bar = document.querySelector('#reference-bar');
const body = document.querySelector('#reference-body');
const status = document.querySelector('#demo-status');
if (desk && reference && fold && bar && body && status) {
  let folded = false;
  let touched = false;
  let rollTimer = 0;
  new ResizeObserver(() => desk.style.setProperty('--body-h', `${body.offsetHeight}px`)).observe(body);
  // When the screen changes size (a window resized, a foldable opened or closed), a dragged
  // position measured in pixels no longer means the same place: settle the window back home.
  let deskWidth = 0;
  new ResizeObserver(([entry]) => {
    const w = Math.round(entry.contentRect.width);
    if (deskWidth && w !== deskWidth && (offset.x || offset.y)) { offset.x = offset.y = 0; reference.style.transition = 'none'; place(0, 0); }
    deskWidth = w;
  }).observe(desk);

  function setFolded(next, announce = true) {
    folded = next;
    desk.classList.add('is-rolling');
    clearTimeout(rollTimer);
    rollTimer = setTimeout(() => desk.classList.remove('is-rolling'), 540);
    desk.classList.toggle('is-folded', folded);
    fold.textContent = folded ? fold.dataset.unfold : fold.dataset.fold;
    fold.setAttribute('aria-expanded', String(!folded));
    bar.setAttribute('aria-expanded', String(!folded));
    bar.setAttribute('aria-label', `${bar.textContent.trim()}: ${folded ? fold.dataset.unfold : fold.dataset.fold}`);
    body.setAttribute('aria-hidden', String(folded));
    if (announce) status.textContent = folded ? status.dataset.folded : status.dataset.expanded;
  }
  const toggle = () => { touched = true; setFolded(!folded); };
  fold.addEventListener('click', toggle);
  // Mouse mirrors the app's double-click; keyboard gets a single activation.
  bar.addEventListener('click', e => { if (e.detail === 0) toggle(); });

  // Drag: track 1:1 from where the bar was grabbed, soften past the desk's edges,
  // and settle back inside on release. A tiny threshold keeps double-clicks clean.
  const offset = { x: 0, y: 0 };
  let drag = null;
  let lastDragEnd = 0;
  const rubber = (over, size) => (over * size * .55) / (size + .55 * Math.abs(over));
  function bounds() {
    const d = desk.getBoundingClientRect(), w = reference.getBoundingClientRect();
    const baseX = w.left - d.left - offset.x, baseY = w.top - d.top - offset.y;
    const top = d.width * .044;
    return { minX: -baseX - w.width * .55, maxX: d.width - baseX - w.width * .45, minY: top - baseY, maxY: d.height - baseY - bar.offsetHeight, w: d.width, h: d.height };
  }
  const soft = (v, lo, hi, size) => v < lo ? lo + rubber(v - lo, size) : v > hi ? hi + rubber(v - hi, size) : v;
  function place(x, y) { reference.style.translate = `${x}px ${y}px`; }
  bar.addEventListener('pointerdown', e => {
    if (e.button !== 0) return;
    touched = true;
    // Capture on press so a quick flick off the bar still reports its release here.
    try { bar.setPointerCapture(e.pointerId); } catch {}
    drag = { id: e.pointerId, sx: e.clientX, sy: e.clientY, ox: offset.x, oy: offset.y, moving: false, b: bounds() };
  });
  bar.addEventListener('pointermove', e => {
    if (!drag || e.pointerId !== drag.id) return;
    const dx = e.clientX - drag.sx, dy = e.clientY - drag.sy;
    if (!drag.moving) {
      if (Math.hypot(dx, dy) < 4) return;
      drag.moving = true;
      reference.classList.add('is-dragging');
      reference.style.transition = 'none';
    }
    const { minX, maxX, minY, maxY, w, h } = drag.b;
    offset.x = soft(drag.ox + dx, minX, maxX, w);
    offset.y = soft(drag.oy + dy, minY, maxY, h);
    place(offset.x, offset.y);
  });
  function endDrag(e) {
    if (!drag || e.pointerId !== drag.id) return;
    if (drag.moving) {
      const { minX, maxX, minY, maxY } = drag.b;
      offset.x = Math.min(maxX, Math.max(minX, offset.x));
      offset.y = Math.min(maxY, Math.max(minY, offset.y));
      reference.style.transition = 'translate .38s var(--ease-out)';
      place(offset.x, offset.y);
      reference.classList.remove('is-dragging');
      lastDragEnd = performance.now();
    }
    drag = null;
  }
  bar.addEventListener('pointerup', endDrag);
  bar.addEventListener('pointercancel', endDrag);
  bar.addEventListener('lostpointercapture', endDrag);
  bar.addEventListener('dblclick', e => { if (lastTap.touch) return; if (performance.now() - lastDragEnd > 250) toggle(); });
  // Touch browsers do not reliably send dblclick (iOS Safari least of all), so count taps here.
  const lastTap = { t: 0, x: 0, y: 0, touch: false };
  bar.addEventListener('pointerup', e => {
    lastTap.touch = e.pointerType !== 'mouse';
    if (!lastTap.touch || performance.now() - lastDragEnd < 250) return;
    const now = performance.now();
    if (now - lastTap.t < 350 && Math.hypot(e.clientX - lastTap.x, e.clientY - lastTap.y) < 24) { lastTap.t = 0; toggle(); return; }
    Object.assign(lastTap, { t: now, x: e.clientX, y: e.clientY });
  });

  // One quiet demonstration the first time the desk reaches the middle of the screen, unless the
  // reader got there first. On a phone the desk starts below the headline, half under the toolbar:
  // playing on first sight would spend the demo where nobody is looking.
  if ('IntersectionObserver' in window) {
    const once = new IntersectionObserver(entries => {
      if (!entries.some(e => e.isIntersecting)) return;
      once.disconnect();
      setTimeout(() => {
        if (touched) return;
        setFolded(true, false);
        setTimeout(() => { if (!touched) setFolded(false, false); }, 1900);
      }, 1100);
    }, { rootMargin: '-35% 0px -35% 0px' });
    once.observe(desk);
  }
}

// Three ways to move a window aside, played side by side.
const ways = [...document.querySelectorAll('.way')];
if (ways.length) {
  function play(way, delay = 0) {
    if (way.classList.contains('play')) return;
    setTimeout(() => way.classList.add('play', 'rolling'), delay);
    setTimeout(() => way.classList.remove('rolling'), delay + 520);
    setTimeout(() => { way.classList.add('rolling'); way.classList.remove('play'); }, delay + 2100);
    setTimeout(() => way.classList.remove('rolling'), delay + 2620);
  }
  const playAll = () => ways.forEach((way, i) => play(way, i * 140));
  // Each tile plays when it reaches the middle of the screen: side by side on a wide screen that is
  // all three at once, stacked on a phone it is one at a time, as the reader gets to it.
  const seen = new IntersectionObserver(entries => {
    const due = entries.filter(e => e.isIntersecting).map(e => e.target);
    due.forEach((way, i) => { seen.unobserve(way); play(way, 250 + i * 140); });
  }, { rootMargin: '-30% 0px -30% 0px' });
  ways.forEach(way => seen.observe(way));
  document.querySelector('#ways-replay')?.addEventListener('click', playAll);
  for (const way of ways) {
    way.addEventListener('pointerenter', () => { if (finePointer.matches) play(way); });
    way.querySelector('.mini')?.addEventListener('click', () => play(way));
  }
}

// Lid illustration: the hinge drives the page through the app's own trigger and spring.
const laptop = document.querySelector('#laptop');
const lidRange = document.querySelector('#lid-range');
const lidPlay = document.querySelector('#lid-play');
if (laptop && lidRange && lidPlay) {
  const trigger = .18;                 // the effect starts a little way into the close
  const frequency = 5.83 / .2;         // FoldSpring: settles within 2% in ~0.2 s
  let lid = 0, e = 0, v = 0, last = 0, frame = 0, playing = null;
  const target = () => Math.min(1, Math.max(0, (lid - trigger) / (.86 - trigger)));
  function tick(now) {
    const dt = Math.min(.25, last ? (now - last) / 1000 : 0);
    last = now;
    if (playing) {
      const t = (now - playing.start) / 1000;
      const ease = x => x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2;
      lid = t < 1.5 ? .9 * ease(t / 1.5) : t < 2.4 ? .9 : t < 3.6 ? .9 * (1 - ease((t - 2.4) / 1.2)) : 0;
      lidRange.value = String(Math.round(lid * 100));
      if (t >= 3.6) playing = null;
    }
    const goal = target();
    if (reduceMotion.matches) { e = goal; v = 0; }
    else {
      // Closed-form critically damped spring, as in FoldSpring.advance.
      const offset = e - goal, decay = Math.exp(-frequency * dt), slope = v + frequency * offset;
      e = goal + (offset + slope * dt) * decay;
      v = (slope - frequency * (offset + slope * dt)) * decay;
    }
    laptop.style.setProperty('--lid', lid.toFixed(4));
    if (playing || Math.abs(e - goal) > .0005 || Math.abs(v) > .002) frame = requestAnimationFrame(tick);
    else { e = goal; v = 0; frame = 0; last = 0; }
    fold(Math.min(1, Math.max(0, e)));
  }
  // The desktop stays where it was and the glass closes over it, as in Duo.metal: glass row d
  // (0 at the hinge, 1 at the top) shows page row d·cos θ, magnified by f / (f − d·sin θ).
  // That map is a plane-to-plane projection, so one matrix3d draws it exactly.
  const optics = {
    silk: { focal: 2.254, defocus: .10, dim: 11, base: .008, angle: .30 },
    shade: { focal: 2.254, defocus: .12, dim: 15, base: .012, angle: .45 },
    frost: { focal: 2.0, defocus: .16, dim: 19, base: .018, angle: .65 },
  };
  const glass = laptop.querySelector('.glass');
  // Blur grows toward the top: three blurred copies of the page, each faded in over one band.
  for (const layer of laptop.querySelectorAll('.depth > i')) layer.append(laptop.querySelector('.page').cloneNode(true));
  function fold(amount) {
    const o = optics[laptop.dataset.preset] || optics.shade;
    const s = Math.sin(amount * o.angle), c = Math.cos(amount * o.angle), f = o.focal;
    // Glass (u, v, 1) → page, v measured down from the top; inverted to draw the page on the glass.
    const g = [f, .5 * s, -.5 * s, 0, .5 * s + c * f, f - .5 * s - c * f, 0, s, f - s];
    const m = [
      g[4] * g[8] - g[5] * g[7], g[2] * g[7] - g[1] * g[8], g[1] * g[5] - g[2] * g[4],
      g[5] * g[6] - g[3] * g[8], g[0] * g[8] - g[2] * g[6], g[2] * g[3] - g[0] * g[5],
      g[3] * g[7] - g[4] * g[6], g[1] * g[6] - g[0] * g[7], g[0] * g[4] - g[1] * g[3],
    ].map(x => x / m0(g));
    // Same map in CSS pixels of the glass (origin top-left).
    const w = glass.clientWidth, h = glass.clientHeight;
    if (!w || !h) return;
    laptop.classList.toggle('is-folding', amount > 0);
    const n = x => +x.toFixed(6);
    laptop.style.setProperty('--fold', `matrix3d(${n(m[0])},${n(m[3] * h / w)},0,${n(m[6] / w)},${n(m[1] * w / h)},${n(m[4])},0,${n(m[7] / h)},0,0,1,0,${n(m[2] * w)},${n(m[5] * h)},0,${n(m[8])})`);
    // Blur radius in page heights, as in the shader; it darkens the page by `dim` per unit.
    // A Gaussian of 0.6 × that disk radius matches the app's own render (--duo-render-test).
    const radius = d => o.defocus * (d * s + o.base * amount);
    laptop.style.setProperty('--blur-top', `${(radius(1) * h * .6).toFixed(2)}px`);
    laptop.style.setProperty('--shade-top', Math.min(1, o.dim * radius(1)).toFixed(3));
    laptop.style.setProperty('--shade-hinge', Math.min(1, o.dim * radius(0)).toFixed(3));
  }
  const m0 = g => g[0] * (g[4] * g[8] - g[5] * g[7]) - g[1] * (g[3] * g[8] - g[5] * g[6]) + g[2] * (g[3] * g[7] - g[4] * g[6]);
  new ResizeObserver(() => fold(Math.min(1, Math.max(0, e)))).observe(glass);
  const wake = () => { if (!frame) { last = 0; frame = requestAnimationFrame(tick); } };
  lidRange.addEventListener('input', () => { playing = null; lid = lidRange.valueAsNumber / 100; wake(); });
  function play() {
    if (reduceMotion.matches) return;
    playing = { start: performance.now() };
    wake();
  }
  lidPlay.addEventListener('click', play);
  for (const button of document.querySelectorAll('.segmented-ctl button')) {
    button.addEventListener('click', () => {
      laptop.dataset.preset = button.dataset.preset;
      fold(Math.min(1, Math.max(0, e)));
      for (const b of document.querySelectorAll('.segmented-ctl button')) b.setAttribute('aria-pressed', String(b === button));
      if (lid < trigger) play();
    });
  }
  const seenLid = new IntersectionObserver(entries => {
    if (!entries.some(x => x.isIntersecting)) return;
    seenLid.disconnect();
    setTimeout(() => { if (lid === 0 && !playing) play(); }, 400);
  }, { threshold: .6 });
  seenLid.observe(laptop);
}

// Pinning: a self-contained layer-order illustration, not an operating-system window controller.
const pinExample = document.querySelector('#pin-example');
const pinDesk = document.querySelector('#pin-desk');
const pinState = document.querySelector('#pin-state');
const pinSwitch = document.querySelector('#pin-switch');
if (pinExample && pinDesk && pinState && pinSwitch) {
  function renderPin() {
    const pinned = pinExample.getAttribute('aria-pressed') === 'true';
    const draftFront = pinDesk.classList.contains('draft-front');
    pinExample.textContent = pinned ? pinExample.dataset.on : pinExample.dataset.off;
    pinDesk.classList.toggle('has-pin', pinned);
    pinState.textContent = draftFront ? (pinned ? pinState.dataset.on : pinState.dataset.off) : pinState.dataset.ready;
    pinSwitch.textContent = draftFront ? pinSwitch.dataset.reference : pinSwitch.dataset.draft;
  }
  const bringForward = (draft) => { pinDesk.classList.toggle('draft-front', draft); renderPin(); };
  pinExample.addEventListener('click', () => {
    pinExample.setAttribute('aria-pressed', String(pinExample.getAttribute('aria-pressed') !== 'true'));
    renderPin();
  });
  pinSwitch.addEventListener('click', () => bringForward(!pinDesk.classList.contains('draft-front')));
  // Clicking a window brings it forward, as on the real desktop.
  pinDesk.querySelector('[data-window=draft]')?.addEventListener('pointerdown', () => bringForward(true));
  pinDesk.querySelector('[data-window=reference]')?.addEventListener('pointerdown', () => bringForward(false));
}

// Window browsing: pointer-hover opens a read-only panel that grows out of its Dock icon.
const browseDesk = document.querySelector('#browse-desk');
const browseIcon = document.querySelector('#browse-icon');
const browsePanel = document.querySelector('#browse-panel');
const browseState = document.querySelector('#browse-state');
if (browseDesk && browseIcon && browsePanel && browseState) {
  let browseOpen = false;
  let browseLocked = false;
  function anchor() {
    const p = browsePanel.getBoundingClientRect(), i = browseIcon.getBoundingClientRect();
    if (!p.width) return;
    const x = ((i.left + i.width / 2 - p.left) / p.width) * 100;
    browsePanel.style.setProperty('--origin', `${Math.max(0, Math.min(100, x)).toFixed(1)}% 100%`);
  }
  function renderBrowse(open) {
    if (open) anchor();
    browseOpen = open;
    browseDesk.classList.toggle('is-open', open);
    browseIcon.setAttribute('aria-expanded', String(open));
    browsePanel.setAttribute('aria-hidden', String(!open));
    browseState.textContent = open ? browseState.dataset.on : browseState.dataset.off;
  }
  browseIcon.addEventListener('mouseenter', () => { if (!browseOpen) renderBrowse(true); });
  browseDesk.addEventListener('mouseleave', () => { if (!browseLocked) renderBrowse(false); });
  browseIcon.addEventListener('focus', () => { if (!browseOpen) renderBrowse(true); });
  browseIcon.addEventListener('blur', () => { if (!browseLocked) renderBrowse(false); });
  browseIcon.addEventListener('click', () => { browseLocked = !browseLocked; renderBrowse(browseLocked); });
  browseIcon.addEventListener('keydown', event => {
    if (event.key !== 'Escape') return;
    browseLocked = false;
    renderBrowse(false);
  });
  renderBrowse(true);
}
