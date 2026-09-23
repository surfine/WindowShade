import { mkdir, rm, cp, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { copy } from './content.mjs';
import { historyPage, historyIndex } from './history.mjs';
import { siteHeader, siteFooter, shareMeta, shareFallback, repo, release } from './chrome.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const dist = path.join(root, 'dist');
const origin = process.env.SITE_ORIGIN || 'https://windowshade.pages.dev';
const escape = (s) => s.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');
await rm(dist, { recursive: true, force: true });
await mkdir(dist, { recursive: true });
await cp(path.join(root, 'public'), dist, { recursive: true });
for (const name of ['style.css', 'app.js', 'history.css', 'history.js', 'era.css']) await cp(path.join(root, name), path.join(dist, name));
const arrow = (d) => `<svg class="glyph" viewBox="0 0 16 16" aria-hidden="true"><path d="${{
  out: 'M5 11 11 5M6.5 5H11v4.5',
  down: 'M8 3.5v9M4 8.5l4 4 4-4',
  right: 'M3.5 8h9M8.5 4l4 4-4 4',
  up: 'M8 12.5v-9M4 7.5l4-4 4 4',
}[d]}"/></svg>`;
const download = (c, extra = '') => `<a class="button primary${extra}" href="${release}">${c.download}${arrow('out')}</a>`;
const lights = '<span class="lights" aria-hidden="true"><i></i><i></i><i></i></span>';
// Period title bars reuse the history essay's calibrated chrome (history.css + era.css).
const eraBar = (kind, label) => ({
  classic: `<div class="classic-bar"><i></i><b>${label}</b><i></i></div>`,
  platinum: `<div class="platinum-bar"><i class="era-close"></i><b>${label}</b><span class="platinum-controls-art"><i class="era-zoom"></i><i class="era-shade"></i></span></div>`,
  aqua: `<div class="aqua-bar"><span class="aqua-lamps"><i class="lamp-close"></i><i class="lamp-minimize"></i><i class="lamp-zoom"></i></span><b>${label}</b><i class="aqua-toolbar-pill"></i></div>`,
  now: `<div class="now-bar"><span class="traffic"><i></i><i></i><i></i></span><b>${label}</b><i>⌃</i></div>`,
}[kind]);
const keys = (k) => k.split(' ').map(x => `<kbd>${x}</kbd>`).join('');
const miniDesk = (kind) => `<div class="mini" data-way="${kind}" aria-hidden="true"><div class="mini-win"><span class="cast" aria-hidden="true"></span><div class="mini-bar">${lights}</div><div class="mini-body"><i></i><i></i><i></i></div><span class="mini-roll"></span></div><div class="mini-dock"><i></i><i></i><i class="mini-slot"></i></div></div>`;
const thumb = (i) => `<span class="thumb thumb-${i}" aria-hidden="true"><span class="thumb-bar"></span><span class="thumb-art"></span></span>`;
const actionIcons = [
  '<svg viewBox="0 0 16 16"><path d="M3 5.5h10M8 13V8.5M5.8 10.6 8 8.4l2.2 2.2"/></svg>',
  '<svg viewBox="0 0 16 16"><path d="M5.5 2.5h5M6.5 2.5v4l-2 2.5h7l-2-2.5v-4M8 9v4.5"/></svg>',
  '<svg viewBox="0 0 16 16"><circle cx="3.5" cy="8" r=".9"/><circle cx="8" cy="8" r=".9"/><circle cx="12.5" cy="8" r=".9"/></svg>',
];
function page(c) {
  const history = c.lang === 'en' ? '/en/history/' : '/history/';
  const en = c.lang === 'en';
  const book = historyIndex(en);
  return `<!doctype html>
<html lang="${c.lang}">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light dark">
<title>${c.title}</title>
${shareMeta({ origin, path: c.path, title: c.title, description: c.description, image: en ? '/media/og-en.jpg' : '/media/og.jpg', imageAlt: c.shareAlt, en })}
<link rel="alternate" hreflang="zh-CN" href="${origin}/"><link rel="alternate" hreflang="en" href="${origin}/en/"><link rel="alternate" hreflang="x-default" href="${origin}/">
<script src="/app.js" defer></script><link rel="stylesheet" href="/style.css"><link rel="stylesheet" href="/history.css"><link rel="stylesheet" href="/era.css">
</head>
<body class="home">
${shareFallback}<a class="skip" href="#main">${c.skip}</a>
${siteHeader(en, 'home')}
<main id="main">

<section class="hero wrap">
<div class="hero-copy"><p class="eyebrow">${c.eyebrow}</p><h1>${c.hero}</h1><p class="hero-intro">${c.intro}</p><div class="actions">${download(c)}<a class="text-link" href="#experience">${c.try}${arrow('down')}</a></div><ul class="facts">${c.facts.map(f => `<li>${f}</li>`).join('')}</ul></div>
<div class="hero-demo">
<div class="stage" id="desk" role="group" aria-label="${c.stageLabel}">
<div class="stage-menubar" aria-hidden="true"><b>${c.stageMenu[0]}</b>${c.stageMenu.slice(1).map(m => `<span>${m}</span>`).join('')}<span class="stage-clock">9:41</span></div>
<div class="win win-draft" aria-hidden="true"><div class="win-bar">${lights}<span class="win-title">${c.draftTitle}</span></div><div class="win-body"><p class="win-kicker">${c.draftKicker}</p><h3>${c.draftHeading}</h3><p>${c.draftText}</p><div class="writing-lines"><i></i><i></i><i></i><i></i></div></div></div>
<div class="win win-ref" id="reference"><span class="cast" aria-hidden="true"></span><button type="button" class="win-bar" id="reference-bar" aria-expanded="true" aria-controls="reference-body" aria-label="${c.noteTitle}: ${c.fold}">${lights}<span class="win-title">${c.noteTitle}</span></button><div class="win-body" id="reference-body"><p class="win-kicker">${c.noteKicker}</p><h3>${c.noteHeading}</h3><p>${c.noteBody}</p></div><span class="roller" aria-hidden="true"></span></div>
</div>
<div class="stage-foot"><p class="stage-hint">${c.stageHint}</p><button class="chip" id="fold" type="button" aria-controls="reference-body" aria-expanded="true" data-fold="${c.fold}" data-unfold="${c.unfold}">${c.fold}</button></div>
<p class="sr-only" id="demo-status" aria-live="polite" data-expanded="${c.expandedStatus}" data-folded="${c.foldedStatus}"></p>
<noscript><p class="caption">${en ? 'Enable JavaScript to try the interactive illustration.' : '开启 JavaScript 即可体验交互示意。'}</p></noscript>
</div>
</section>

<section class="ways wrap section" id="experience">
<div class="section-head"><p class="kicker">${c.waysKicker}</p><h2>${c.waysTitle}</h2><p class="lead">${c.waysBody}</p></div>
<ol class="way-list">${c.ways.map(([kind, name, text], i) => `<li class="way" data-way="${kind}">${miniDesk(kind)}<div class="way-text"><span class="way-no">0${i + 1}</span><h3>${name}</h3><p>${text}</p></div></li>`).join('')}</ol>
<div class="ways-foot"><p>${c.waysNote}</p></div>
</section>

<section class="story section" id="story">
<div class="wrap story-grid">
<div class="story-head"><p class="kicker">${c.storyKicker}</p><h2>${c.storyTitle}</h2><p class="lead">${c.storyLead}</p><div class="story-actions"><a class="button secondary" href="${history}">${c.storyLink}${arrow('right')}</a><p class="story-meta">${c.storyMeta(book.sources.length)}</p></div></div>
<div class="story-book history-page"><a class="cover" href="${history}" aria-label="${c.storyCoverLabel}"><p class="dateline">WINDOWSHADE FIELD NOTES · № 001</p><p class="cover-title">${c.storyCover}</p><div class="cover-bars" aria-hidden="true">${[['1994', 'classic', 'WindowShade'], ['1997', 'platinum', 'WindowShade'], ['2001', 'aqua', 'Untitled'], ['2026', 'now', 'WindowShade']].map(([year, kind, label]) => `<div class="cover-row"><span>${year}</span>${eraBar(kind, label)}</div>`).join('')}</div></a>
<ol class="chapters">${[...book.chapters, book.lab].map(([id, num, title, hook]) => `<li><a href="${history}#${id}"><span class="chapter-num">${num}</span><strong>${title}</strong><small>${hook}</small></a></li>`).join('')}</ol></div>
</div>
</section>

<section class="today wrap section"><p class="kicker">${c.todayKicker}</p><h2>${c.todayTitle}</h2><p class="lead">${c.todayBody}</p></section>

<section class="feature pinning wrap" id="pinning">
<div class="feature-copy"><p class="kicker">${c.pinKicker}</p><h2>${c.pinTitle}</h2><p class="lead">${c.pinIntro}</p><p class="note">${c.pinHow}</p><div class="demo-buttons"><button class="chip" id="pin-example" type="button" aria-pressed="false" data-on="${c.pinUndo}" data-off="${c.pinAction}">${c.pinAction}</button><button class="chip ghost" id="pin-switch" type="button" data-draft="${c.pinSwitch}" data-reference="${c.pinSwitchBack}">${c.pinSwitch}</button></div></div>
<div class="feature-demo"><div class="stage stage-pin" id="pin-desk"><div class="win pin-source" data-window="reference"><div class="win-bar">${lights}<span class="win-title">${c.pinDemoTitle}</span></div><div class="win-body"><p class="win-kicker">${c.pinDemoLabel}</p><strong>${c.pinDemoBody}</strong></div></div><div class="win pin-work" data-window="draft"><div class="win-bar">${lights}<span class="win-title">${c.pinWork}</span></div><div class="win-body"><p>${c.pinWorkBody}</p><div class="writing-lines" aria-hidden="true"><i></i><i></i><i></i><i></i></div></div></div></div><p class="demo-state" id="pin-state" aria-live="polite" data-on="${c.pinStatusOn}" data-off="${c.pinStatusOff}" data-ready="${c.pinStatusReady}">${c.pinStatusReady}</p><p class="caption">${c.pinDemoCaption}</p></div>
</section>

<section class="feature browsing wrap" id="browsing">
<div class="feature-copy"><p class="kicker">${c.browseKicker}</p><h2>${c.browseTitle}</h2><p class="lead">${c.browseIntro}</p><ul class="points">${c.browsePoints.map(([title, detail]) => `<li><strong>${title}</strong><span>${detail}</span></li>`).join('')}</ul><p class="note">${c.browseHow}</p></div>
<div class="feature-demo"><div class="stage stage-browse" id="browse-desk"><div class="panel" id="browse-panel" aria-hidden="true"><div class="panel-head"><span>${c.browsePanelCount}</span><span class="segmented" aria-hidden="true"><i class="on"><svg viewBox="0 0 16 16"><rect x="2.5" y="2.5" width="4.5" height="4.5" rx="1"/><rect x="9" y="2.5" width="4.5" height="4.5" rx="1"/><rect x="2.5" y="9" width="4.5" height="4.5" rx="1"/><rect x="9" y="9" width="4.5" height="4.5" rx="1"/></svg></i><i><svg viewBox="0 0 16 16"><path d="M5.5 4h8M5.5 8h8M5.5 12h8"/><circle cx="2.8" cy="4" r=".8"/><circle cx="2.8" cy="8" r=".8"/><circle cx="2.8" cy="12" r=".8"/></svg></i></span></div><ul class="cards">${c.browseCards.map((title, i) => `<li class="card">${thumb(i)}<span class="card-actions" aria-hidden="true">${actionIcons.map((svg, j) => `<i title="${c.browseActions[j]}">${svg}</i>`).join('')}</span><span class="card-title">${title}</span></li>`).join('')}</ul><p class="panel-app">${c.browseApp}</p></div><div class="dock"><button type="button" class="dock-icon app-text" id="browse-icon" aria-expanded="false" aria-controls="browse-panel" aria-label="${c.browseDockLabel}"><span class="icon-paper"><i></i><i></i><i></i><i></i></span></button><span class="dock-icon app-folder" aria-hidden="true"></span><span class="dock-icon app-photo" aria-hidden="true"></span><span class="dock-sep" aria-hidden="true"></span><span class="dock-icon app-shade" aria-hidden="true"><img src="/media/icon.png" alt="" width="96" height="96" loading="lazy"></span></div></div><p class="demo-state" id="browse-state" aria-live="polite" data-on="${c.browseStatusOn}" data-off="${c.browseStatusOff}">${c.browseStatusOff}</p><p class="caption">${c.browseCaption}</p></div>
</section>

<section class="motion-section" id="motion"><div class="wrap"><div class="motion-heading"><p class="kicker">${c.motionKicker}</p><h2>${c.motionTitle}</h2><p class="lead">${c.motionBody}</p></div><figure class="lid-figure"><div class="laptop" id="laptop" data-preset="shade" role="img" aria-label="${c.lidLabel}"><div class="lid"><div class="bezel"><div class="glass"><div class="page"><div class="stage-menubar"><b>${c.stageMenu[0]}</b>${c.stageMenu.slice(1).map(m => `<span>${m}</span>`).join('')}<span class="stage-clock">9:41</span></div><div class="win win-draft inactive"><div class="win-bar">${lights}<span class="win-title">${c.draftTitle}</span></div><div class="win-body"><p class="win-kicker">${c.draftKicker}</p><h3>${c.draftHeading}</h3><div class="writing-lines"><i></i><i></i><i></i></div></div></div><div class="win win-note"><div class="win-bar">${lights}<span class="win-title">${c.noteTitle}</span></div></div></div><span class="depth" aria-hidden="true"><i></i><i></i><i></i><b></b></span></div></div></div><div class="deck"><span class="lip"></span></div></div><div class="lid-controls"><div class="segmented-ctl" role="group" aria-label="${c.lidPresetsLabel}">${['silk', 'shade', 'frost'].map((key, i) => `<button type="button" data-preset="${key}" aria-pressed="${key === 'shade'}">${c.lidPresets[i]}</button>`).join('')}</div><label class="lid-slider"><span aria-hidden="true">${c.lidOpen}</span><input type="range" id="lid-range" min="0" max="100" value="0" aria-label="${c.lidSlider}"><span aria-hidden="true">${c.lidClosed}</span></label><button type="button" class="chip" id="lid-play">${c.lidPlay}</button></div><figcaption class="caption">${c.lidCaption}</figcaption></figure></div></section>

<section class="shortcuts wrap section"><h2>${c.shortcutTitle}</h2><ul class="shortcut-list">${c.shortcuts.map(([key, label]) => `<li><span class="keys">${keys(key)}</span><span>${label}</span></li>`).join('')}</ul></section>

<section class="trust wrap section" id="privacy"><div class="trust-copy"><h2>${c.trustTitle}</h2><p class="lead">${c.trustBody}</p><a class="text-link" href="${repo}/blob/main/WindowShade.md">${c.researchLink}${arrow('out')}</a></div><div class="questions" id="questions"><h3>${c.faqTitle}</h3><div class="faq-list">${c.faqs.map(([q, a]) => `<details><summary>${q}<span class="plus" aria-hidden="true"></span></summary><p>${a}</p></details>`).join('')}</div></div></section>

<section class="closing wrap section"><img src="/media/icon-256.png" width="88" height="88" alt="" loading="lazy"><h2>${c.endTitle}</h2>${download(c, ' large')}<p>${c.endBody}</p></section>
</main>${siteFooter(en, 'home')}
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
await writeFile(path.join(dist, '_headers'), `/*\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n  X-Frame-Options: DENY\n  Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; frame-src https://infinitemac.org; object-src 'none'; base-uri 'self'; frame-ancestors 'none'\n/media/*\n  Cache-Control: public, max-age=86400\n`);
console.log(`Built Chinese and English pages in ${dist}`);
