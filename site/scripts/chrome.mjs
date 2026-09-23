// Header, footer and share-card metadata shared by the product page and the history essay,
// so the two read as one site.
import { copy } from './content.mjs';

export const repo = 'https://github.com/surfine/WindowShade';
export const release = `${repo}/releases/latest`;
const escape = (s) => s.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');
const strip = (s) => s.replace(/<br>/g, ' ').replace(/<[^>]+>/g, '');

// Some chat apps (WeChat among them) skip og:image and take the first large image in the page.
// Hidden and lazy, so browsers never fetch it; parsers still see it first.
export const shareFallback = '<img class="share-fallback" src="/media/share-square.jpg" width="512" height="512" alt="" hidden loading="lazy">';

export function siteHeader(en, page) {
  const c = en ? copy.en : copy.zh;
  const home = c.path;
  const history = en ? '/en/history/' : '/history/';
  const onHome = page === 'home';
  const anchor = (id) => onHome ? `#${id}` : `${home}#${id}`;
  const other = page === 'history' ? (en ? '/history/' : '/en/history/') : c.languageHref;
  return `<header class="header"><a class="brand" href="${home}" aria-label="WindowShade"><img src="/media/icon.png" width="28" height="28" alt=""><span>WindowShade</span></a><nav aria-label="${en ? 'Main navigation' : '主导航'}"><a href="${anchor('experience')}">${c.nav[0]}</a><a href="${anchor('pinning')}">${c.nav[1]}</a><a href="${anchor('browsing')}">${c.nav[2]}</a><a href="${history}"${page === 'history' ? ' aria-current="page"' : ''}>${c.navHistory}</a></nav><div class="header-tools"><a class="language" href="${other}" lang="${en ? 'zh-CN' : 'en'}">${c.language}</a><button type="button" class="theme" aria-label="${c.theme}" title="${c.theme}"><svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="6.5"/><path d="M10 3.5a6.5 6.5 0 0 1 0 13z"/></svg></button><a class="nav-download" href="${release}">${c.download}</a></div>${page === 'history' ? '<span class="read-progress" aria-hidden="true"></span>' : ''}</header>`;
}

export function siteFooter(en, page) {
  const c = en ? copy.en : copy.zh;
  const history = en ? '/en/history/' : '/history/';
  const privacy = page === 'home' ? '#privacy' : `${c.path}#privacy`;
  return `<footer class="footer wrap"><div><a class="brand" href="${c.path}"><img src="/media/icon.png" width="22" height="22" alt="">WindowShade</a><p>${c.footer}</p></div><div class="footer-links"><a href="${history}">${c.navHistory}</a><a href="${repo}">${c.source}</a><a href="${repo}/releases">${c.release}</a><a href="${repo}/issues">${c.issue}</a><a href="${privacy}">${c.privacy}</a></div></footer>`;
}

// Link previews in chat apps and social sites: every page carries its own card.
// JPEG at 1200 × 630 is the one format and size every preview crawler accepts.
export function shareMeta({ origin, path, title, description, image, imageAlt, type = 'website', en }) {
  const t = escape(strip(title)), d = escape(strip(description)), url = `${origin}${path}`, img = `${origin}${image}`;
  return `<meta name="description" content="${d}"><link rel="canonical" href="${url}">
<meta property="og:site_name" content="WindowShade"><meta property="og:type" content="${type}"><meta property="og:title" content="${t}"><meta property="og:description" content="${d}"><meta property="og:url" content="${url}"><meta property="og:image" content="${img}"><meta property="og:image:type" content="image/jpeg"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="${escape(imageAlt)}"><meta property="og:locale" content="${en ? 'en_US' : 'zh_CN'}"><meta property="og:locale:alternate" content="${en ? 'zh_CN' : 'en_US'}">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${t}"><meta name="twitter:description" content="${d}"><meta name="twitter:image" content="${img}"><meta name="twitter:image:alt" content="${escape(imageAlt)}">
<link rel="icon" href="/media/icon.png" type="image/png"><link rel="apple-touch-icon" href="/media/apple-touch-icon.png">
<meta name="theme-color" content="#f6f7f9" media="(prefers-color-scheme: light)"><meta name="theme-color" content="#111317" media="(prefers-color-scheme: dark)">`;
}
