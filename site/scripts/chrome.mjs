// Header, footer and share-card metadata shared by the product page and the history essay,
// so the two read as one site.
import { copy } from './content.mjs';

export const repo = 'https://github.com/surfine/WindowShade';

// 站点的三种语言（第39批加繁体）。code 同时是 <html lang> 与 hreflang 的值。
export const LANGS = [
  { code: 'zh-CN', path: '/', history: '/history/', label: '简体', navLabel: '主导航' },
  { code: 'zh-Hant', path: '/tw/', history: '/tw/history/', label: '繁體', navLabel: '主導覽' },
  { code: 'en', path: '/en/', history: '/en/history/', label: 'EN', navLabel: 'Main navigation' },
];
export const langInfo = (lang) => LANGS.find((item) => item.code === lang) ?? LANGS[0];
const copyFor = (lang) => (lang === 'en' ? copy.en : lang === 'zh-Hant' ? copy.zhHant : copy.zh);
export const release = `${repo}/releases/latest`;
const escape = (s) => s.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');
const strip = (s) => s.replace(/<br>/g, ' ').replace(/<[^>]+>/g, '');

// Some chat apps (WeChat among them) skip og:image and take the first large image in the page.
// Hidden and lazy, so browsers never fetch it; parsers still see it first.
export const shareFallback = '<img class="share-fallback" src="/media/share-square.jpg" width="512" height="512" alt="" hidden loading="lazy">';

export function siteHeader(lang, page) {
  const info = langInfo(lang);
  const c = copyFor(lang);
  const home = info.path;
  const history = info.history;
  const onHome = page === 'home';
  const anchor = (id) => onHome ? `#${id}` : `${home}#${id}`;
  // 语言切换：列出除当前语言以外的两种（第39批起是三语站点）。
  const switcher = LANGS.filter((item) => item.code !== lang)
    .map((item) => `<a class="language" href="${page === 'history' ? item.history : item.path}" lang="${item.code}">${item.label}</a>`)
    .join('');
  return `<header class="header"><a class="brand" href="${home}" aria-label="WindowShade"><img src="/media/icon.png" width="28" height="28" alt=""><span>WindowShade</span></a><nav aria-label="${info.navLabel}"><a href="${anchor('experience')}">${c.nav[0]}</a><a href="${anchor('glance')}">${c.nav[1]}</a><a href="${anchor('gestures')}">${c.nav[2]}</a><a href="${history}"${page === 'history' ? ' aria-current="page"' : ''}>${c.navHistory}</a></nav><div class="header-tools">${switcher}<button type="button" class="theme" aria-label="${c.theme}" title="${c.theme}"><svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="6.5"/><path d="M10 3.5a6.5 6.5 0 0 1 0 13z"/></svg></button><a class="nav-download" href="${release}">${c.download}</a></div>${page === 'history' ? '<span class="read-progress" aria-hidden="true"></span>' : ''}</header>`;
}

export function siteFooter(lang) {
  const info = langInfo(lang);
  const c = copyFor(lang);
  const history = info.history;
  const privacy = c.privacyHref;
  return `<footer class="footer wrap"><div><a class="brand" href="${c.path}"><img src="/media/icon.png" width="22" height="22" alt="">WindowShade</a><p>${c.footer}</p></div><div class="footer-links"><a href="${history}">${c.navHistory}</a><a href="${repo}">${c.source}</a><a href="${repo}/releases">${c.release}</a><a href="${repo}/issues">${c.issue}</a><a href="${privacy}">${c.privacy}</a></div></footer>`;
}

// Link previews in chat apps and social sites: every page carries its own card.
// JPEG at 1200 × 630 is the one format and size every preview crawler accepts.
const OG_LOCALE = { 'zh-CN': 'zh_CN', 'zh-Hant': 'zh_TW', 'en': 'en_US' };
export function shareMeta({ origin, path, title, description, image, imageAlt, type = 'website', lang = 'zh-CN' }) {
  // og:locale:alternate 每个语言一条标签（规范如此，一个标签只放一个值）。
  const alternates = LANGS.filter((item) => item.code !== lang)
    .map((item) => `<meta property="og:locale:alternate" content="${OG_LOCALE[item.code]}">`).join('');
  const t = escape(strip(title)), d = escape(strip(description)), url = `${origin}${path}`, img = `${origin}${image}`;
  return `<meta name="description" content="${d}"><link rel="canonical" href="${url}">
<meta property="og:site_name" content="WindowShade"><meta property="og:type" content="${type}"><meta property="og:title" content="${t}"><meta property="og:description" content="${d}"><meta property="og:url" content="${url}"><meta property="og:image" content="${img}"><meta property="og:image:type" content="image/jpeg"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="${escape(imageAlt)}"><meta property="og:locale" content="${OG_LOCALE[lang]}">${alternates}
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${t}"><meta name="twitter:description" content="${d}"><meta name="twitter:image" content="${img}"><meta name="twitter:image:alt" content="${escape(imageAlt)}">
<link rel="icon" href="/media/icon.png" type="image/png"><link rel="apple-touch-icon" href="/media/apple-touch-icon.png">
<meta name="theme-color" content="#f6f7f9" media="(prefers-color-scheme: light)"><meta name="theme-color" content="#111317" media="(prefers-color-scheme: dark)">`;
}
