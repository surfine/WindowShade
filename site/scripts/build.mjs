import { mkdir, rm, cp, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { copy } from './content.mjs';
import { historyPage } from './history.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const dist = path.join(root, 'dist');
const origin = process.env.SITE_ORIGIN || 'https://windowshade.pages.dev';
const repo = 'https://github.com/surfine/WindowShade';
const release = `${repo}/releases/latest`;
const escape = (s) => s.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');
await rm(dist, { recursive: true, force: true });
await mkdir(dist, { recursive: true });
await cp(path.join(root, 'public'), dist, { recursive: true });
for (const name of ['style.css', 'app.js', 'history.css', 'history.js', 'era.css']) await cp(path.join(root, name), path.join(dist, name));
const download = (c) => `<a class="button primary" href="${release}">${c.download}<span aria-hidden="true">↗</span></a>`;
function page(c) {
  const history = c.lang === 'en' ? '/en/history/' : '/history/';
  return `<!doctype html>
<html lang="${c.lang}">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>${c.title}</title><meta name="description" content="${escape(c.description)}">
<link rel="canonical" href="${origin}${c.path}">
<link rel="alternate" hreflang="zh-CN" href="${origin}/"><link rel="alternate" hreflang="en" href="${origin}/en/"><link rel="alternate" hreflang="x-default" href="${origin}/">
<link rel="icon" href="/media/icon.png"><link rel="apple-touch-icon" href="/media/icon.png">
<meta property="og:type" content="website"><meta property="og:title" content="${c.title}"><meta property="og:description" content="${escape(c.description)}"><meta property="og:url" content="${origin}${c.path}"><meta property="og:image" content="${origin}/media/hero.webp"><meta property="og:locale" content="${c.lang === 'en' ? 'en_US' : 'zh_CN'}"><meta name="twitter:card" content="summary_large_image">
<script src="/app.js" defer></script><link rel="stylesheet" href="/style.css"><link rel="stylesheet" href="/history.css">
</head>
<body>
<a class="skip" href="#main">${c.skip}</a>
<header class="header"><a class="brand" href="${c.path}" aria-label="WindowShade"><img src="/media/icon.png" width="36" height="36" alt=""><span>WindowShade</span></a><nav aria-label="${c.lang === 'en' ? 'Main navigation' : '主导航'}"><a href="#experience">${c.nav[0]}</a><a href="#pinning">${c.nav[1]}</a><a href="#browsing">${c.nav[2]}</a><a href="${history}">${c.nav[3]}</a></nav><div class="header-tools"><a class="language" href="${c.languageHref}" lang="${c.lang === 'en' ? 'zh-CN' : 'en'}">${c.language}</a><button type="button" class="theme" aria-label="${c.theme}" title="${c.theme}"><span aria-hidden="true">◐</span></button><a class="nav-download" href="${release}">${c.download}<span aria-hidden="true"> ↗</span></a></div></header>
<main id="main">
<section class="hero wrap"><div class="hero-copy"><p class="eyebrow">${c.eyebrow}</p><h1>${c.hero}</h1><p class="hero-intro">${c.intro}</p><div class="actions">${download(c)}<a class="text-link" href="#experience">${c.try}<span aria-hidden="true">↘</span></a></div></div><div class="hero-art"><img src="/media/hero.webp" width="1600" height="1120" alt="${c.heroArtLabel}" fetchpriority="high"></div>
</section>
<div class="facts wrap">${c.facts.map(f => `<span>${f}</span>`).join('')}</div>

<section class="experience wrap section" id="experience"><div class="section-copy"><h2>${c.demoTitle}</h2><p>${c.demoBody}</p><p class="section-note">${c.demoNote}</p><div class="demo-buttons"><button class="button secondary" id="fold" type="button" aria-controls="reference-body" aria-expanded="true" data-fold="${c.fold}" data-unfold="${c.unfold}">${c.fold}<span aria-hidden="true">↑</span></button></div><noscript><p>${c.lang === 'en' ? 'Enable JavaScript to try the interactive illustration.' : '开启 JavaScript 即可体验交互示意。'}</p></noscript></div>
<div class="demo-column"><div class="desk" id="desk"><div class="draft"><div class="draft-label">${c.draftTitle}</div><h3>${c.draftHeading}</h3><p>${c.draftText}</p><div class="writing-lines" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i></div></div><div class="reference" id="reference"><button type="button" class="reference-bar" id="reference-bar" aria-expanded="true" aria-controls="reference-body" aria-label="${c.noteTitle}: ${c.fold}"><span class="traffic" aria-hidden="true"><i></i><i></i><i></i></span><span>${c.noteTitle}</span><span aria-hidden="true" class="bar-glyph">⌃</span></button><div class="reference-body" id="reference-body"><div class="note-rule"></div><h3>${c.noteHeading}</h3><p>${c.noteBody}</p><div class="note-footer">${c.noteFooter}</div></div><div class="paper-roll" aria-hidden="true"></div></div></div><p class="caption">${c.demoCaption}</p><p class="sr-only" id="demo-status" aria-live="polite" data-expanded="${c.expandedStatus}" data-folded="${c.foldedStatus}"></p></div></section>

<section class="pinning wrap section" id="pinning"><div class="section-copy"><h2>${c.pinTitle}</h2><p>${c.pinIntro}</p><p class="section-note">${c.pinHow}</p><div class="demo-buttons"><button class="button secondary" id="pin-example" type="button" aria-pressed="false" data-on="${c.pinUndo}" data-off="${c.pinAction}">${c.pinAction}</button><button class="text-link" id="pin-switch" type="button" data-draft="${c.pinSwitch}" data-reference="${c.pinSwitchBack}">${c.pinSwitch} ↗</button></div></div>
<div class="demo-column"><p class="pin-instruction">${c.pinInstruction}</p><div class="pin-desk" id="pin-desk"><div class="pin-source"><div class="pin-chrome">${c.pinDemoTitle}</div><strong>${c.pinDemoBody}</strong></div><div class="pin-work"><div class="pin-chrome">${c.pinWork}</div><p>${c.pinWorkBody}</p><div class="writing-lines" aria-hidden="true"><i></i><i></i><i></i></div></div></div><p class="pin-state" id="pin-state" aria-live="polite" data-on="${c.pinStatusOn}" data-off="${c.pinStatusOff}" data-ready="${c.pinStatusReady}">${c.pinStatusReady}</p><p class="caption">${c.pinDemoCaption}</p></div></section>
<section class="browsing wrap section" id="browsing"><div class="section-copy"><h2>${c.browseTitle}</h2><p>${c.browseIntro}</p><p class="section-note">${c.browseHow}</p><ul class="browse-points">${c.browsePoints.map(([title, detail]) => `<li><strong>${title}</strong><span>${detail}</span></li>`).join('')}</ul></div>
<div class="demo-column"><p class="pin-instruction">${c.browseHint}</p><div class="browse-desk" id="browse-desk"><div class="browse-panel" id="browse-panel" aria-hidden="true"><p class="browse-panel-head"><span>${c.browsePanelTitle}</span><span>${c.browsePanelCount}</span></p><ul class="browse-list"><li><span class="browse-thumb" aria-hidden="true"></span><span>${c.browseCard1}</span></li><li><span class="browse-thumb" aria-hidden="true"></span><span>${c.browseCard2}</span></li><li><span class="browse-thumb" aria-hidden="true"></span><span>${c.browseCard3}</span></li></ul></div><div class="browse-dock"><button type="button" class="browse-icon" id="browse-icon" aria-expanded="false" aria-controls="browse-panel" aria-label="${c.browseDockLabel}"><span aria-hidden="true">📄</span></button><span class="browse-icon browse-icon-ghost" aria-hidden="true">🗂</span><span class="browse-icon browse-icon-ghost" aria-hidden="true">📊</span></div></div><p class="browse-state" id="browse-state" aria-live="polite" data-on="${c.browseStatusOn}" data-off="${c.browseStatusOff}">${c.browseStatusOff}</p><p class="caption">${c.browseCaption}</p></div></section>

<section class="shortcuts wrap section"><h2>${c.shortcutTitle}</h2><ul class="shortcut-list">${c.shortcuts.map(([key, label]) => `<li><kbd>${key}</kbd><span>${label}</span></li>`).join('')}</ul></section>

<section class="motion-section section" id="motion"><div class="wrap"><div class="motion-heading"><h2>${c.motionTitle}</h2><p>${c.motionBody}</p></div><figure class="film"><div class="film-frame"><video id="effect-video" playsinline muted loop preload="none" poster="/media/duo-poster.webp" width="820" height="531" aria-label="${c.play}"><source src="/media/duo.mp4" type="video/mp4"></video><button type="button" class="video-button" id="video-toggle" data-play="${c.play}" data-pause="${c.pause}"><span aria-hidden="true">▷</span><span>${c.play}</span></button></div><figcaption class="caption">${c.videoCaption}</figcaption></figure></div></section>

<section class="settings wrap section"><div class="settings-art"><img id="settings-image" src="/media/settings.webp" loading="lazy" width="1440" height="1088" alt="${c.settingsCaption}"></div><div class="section-copy"><h2>${c.settingsTitle}</h2><p>${c.settingsBody}</p><p class="caption">${c.settingsCaption}</p></div></section>

<section class="trust wrap section" id="privacy"><h2>${c.trustTitle}</h2><div class="trust-body"><p>${c.trustBody}</p><a class="text-link" href="${repo}/blob/main/WindowShade.md">${c.researchLink} ↗</a></div></section>

<section class="questions wrap section" id="questions"><h2>${c.faqTitle}</h2><div class="faq-list">${c.faqs.map(([q, a]) => `<details><summary>${q}<span aria-hidden="true">+</span></summary><p>${a}</p></details>`).join('')}</div></section>

<section class="history-teaser wrap"><div><p class="dateline">${c.historyDateline}</p><h2>${c.historyTitle}</h2></div><div><p>${c.historyBody}</p><a class="text-link" href="${history}">${c.historyLink} ↗</a></div></section>

<section class="closing wrap section"><img src="/media/icon.png" width="72" height="72" alt="" loading="lazy"><h2>${c.endTitle}</h2><p>${c.endBody}</p>${download(c)}</section>
</main><footer class="footer wrap"><div><a class="brand" href="${c.path}">WindowShade</a><p>${c.footer}</p></div><div class="footer-links"><a href="${repo}">${c.source}</a><a href="${repo}/releases">${c.release}</a><a href="${repo}/issues">${c.issue}</a><a href="#privacy">${c.privacy}</a></div></footer>
</body></html>`;
}
for (const c of Object.values(copy)) {
  const target = path.join(dist, c.path === '/' ? '' : 'en');
  await mkdir(target, { recursive: true });
  await writeFile(path.join(target, 'index.html'), page(c));
}
for (const en of [false, true]) {
  const target = path.join(dist, en ? 'en/history' : 'history');
  await mkdir(target, { recursive: true });
  await writeFile(path.join(target, 'index.html'), historyPage(en, origin));
}
await writeFile(path.join(dist, '404.html'), `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>WindowShade · 404</title><link rel="stylesheet" href="/style.css"><main class="closing wrap section"><img src="/media/icon.png" width="72" height="72" alt=""><h1>这一页，暂时不在这里。</h1><p>This page has wandered off.</p><a class="button primary" href="/">回到首页 / Home</a></main></html>`);
await writeFile(path.join(dist, 'robots.txt'), `User-agent: *\nAllow: /\nSitemap: ${origin}/sitemap.xml\n`);
await writeFile(path.join(dist, 'sitemap.xml'), `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>${origin}/</loc></url><url><loc>${origin}/en/</loc></url><url><loc>${origin}/history/</loc></url><url><loc>${origin}/en/history/</loc></url></urlset>`);
await writeFile(path.join(dist, '_headers'), `/*\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n  X-Frame-Options: DENY\n  Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; media-src 'self'; frame-src https://infinitemac.org; object-src 'none'; base-uri 'self'; frame-ancestors 'none'\n/media/*\n  Cache-Control: public, max-age=86400\n`);
console.log(`Built Chinese and English pages in ${dist}`);
