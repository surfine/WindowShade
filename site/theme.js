// Shared by every page: the stored light/dark choice, the header's theme button, and the
// header hairline that appears once content scrolls under it. Kept apart from app.js so pages
// without the product demos (privacy, 404, the history essay) do not load them.
(() => {
  const root = document.documentElement;
  // Follow the system unless the reader picked one.
  const darkPreference = matchMedia('(prefers-color-scheme: dark)');
  let manualTheme = null;
  try { manualTheme = localStorage.getItem('windowshade-theme'); } catch {}
  if (manualTheme === 'light' || manualTheme === 'dark') root.dataset.theme = manualTheme;
  const button = document.querySelector('.theme');
  const isDark = () => (root.dataset.theme ? root.dataset.theme === 'dark' : darkPreference.matches);
  const syncTheme = () => button?.setAttribute('aria-pressed', String(isDark()));
  syncTheme();
  darkPreference.addEventListener('change', syncTheme);
  button?.addEventListener('click', () => {
    root.dataset.theme = isDark() ? 'light' : 'dark';
    try { localStorage.setItem('windowshade-theme', root.dataset.theme); } catch {}
    syncTheme();
  });

  // The header hairline appears only once content scrolls under it.
  const syncScrolled = () => root.toggleAttribute('data-scrolled', scrollY > 4);
  syncScrolled();
  addEventListener('scroll', syncScrolled, { passive: true });
})();
