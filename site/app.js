const root = document.documentElement;
const darkPreference = matchMedia('(prefers-color-scheme: dark)');
const settings = document.querySelector('#settings-image');
let manualTheme = null;
try { manualTheme = localStorage.getItem('windowshade-theme'); } catch {}
if (manualTheme === 'light' || manualTheme === 'dark') root.dataset.theme = manualTheme;
function syncTheme() {
  const dark = root.dataset.theme ? root.dataset.theme === 'dark' : darkPreference.matches;
  if (settings) {
    settings.parentElement.querySelector('source')?.remove();
    settings.src = `/media/settings${dark ? '-dark' : ''}.webp`;
  }
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

const desk = document.querySelector('#desk');
const fold = document.querySelector('#fold');
const pin = document.querySelector('#pin');
const bar = document.querySelector('#reference-bar');
const body = document.querySelector('#reference-body');
const status = document.querySelector('#demo-status');
let folded = false;
let pinned = false;
if (body && desk) {
  const sizeObserver = new ResizeObserver(() => desk.style.setProperty('--roll-distance', `${-body.offsetHeight}px`));
  sizeObserver.observe(body);
}
function renderDemo() {
  desk.classList.toggle('is-folded', folded);
  desk.classList.toggle('is-pinned', pinned);
  fold.replaceChildren(document.createTextNode(folded ? fold.dataset.unfold : fold.dataset.fold));
  const arrow = document.createElement('span');
  arrow.setAttribute('aria-hidden', 'true'); arrow.textContent = folded ? '↓' : '↑'; fold.append(arrow);
  fold.setAttribute('aria-expanded', String(!folded));
  bar.setAttribute('aria-expanded', String(!folded));
  bar.setAttribute('aria-label', `${bar.children[1].textContent}: ${folded ? fold.dataset.unfold : fold.dataset.fold}`);
  body.setAttribute('aria-hidden', String(folded));
  pin.textContent = pinned ? pin.dataset.unpin : pin.dataset.pin;
  pin.setAttribute('aria-pressed', String(pinned));
  status.textContent = pinned ? status.dataset.pinned : folded ? status.dataset.folded : status.dataset.expanded;
}
function toggleFold() { folded = !folded; pinned = false; renderDemo(); }
fold?.addEventListener('click', toggleFold);
bar?.addEventListener('dblclick', toggleFold);
// Keyboard and touch users have a single-activation route; mouse mirrors the app's double-click.
bar?.addEventListener('click', e => { if (e.detail === 0) toggleFold(); });
pin?.addEventListener('click', () => { pinned = !pinned; folded = false; renderDemo(); });

const video = document.querySelector('#effect-video');
const videoToggle = document.querySelector('#video-toggle');
function videoLabel(playing) {
  videoToggle.children[0].textContent = playing ? 'Ⅱ' : '▷';
  videoToggle.children[1].textContent = playing ? videoToggle.dataset.pause : videoToggle.dataset.play;
  videoToggle.setAttribute('aria-pressed', String(playing));
}
videoToggle?.addEventListener('click', async () => {
  if (!video.paused) { video.pause(); return; }
  try { await video.play(); }
  catch {
    video.controls = true;
    videoToggle.hidden = true;
    // Native controls surface loading / playback errors and allow a retry.
  }
});
video?.addEventListener('play', () => videoLabel(true));
video?.addEventListener('pause', () => videoLabel(false));
video?.addEventListener('error', () => { video.controls = true; videoToggle.hidden = true; });
if (video) {
  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) if (!entry.isIntersecting && !video.paused) video.pause();
  }, { threshold: .1 });
  observer.observe(video);
  document.addEventListener('visibilitychange', () => { if (document.hidden) video.pause(); });
}
