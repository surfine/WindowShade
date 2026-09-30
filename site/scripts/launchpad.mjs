// 启动台（开发版）官网小样：文案与结构。样式在 launchpad.css，交互在 launchpad.js。
const t = {
  zh: {
    kicker: '启动台 · 开发版',
    title: 'App 有位置，<br>窗口也有去处。',
    lead: '⌃⌘L 打开启动台。把 App 收进文件夹，或去最后一页的 App 资料库里找。',
    points: [
      ['负一屏查看实时活动', '音乐、耳机、隔空投送与路线和刘海共用最多三个入口，轻扫切换，长按展开。'],
      ['长按整理主屏幕', '按住一个图标进入编辑，再拖动排序、建文件夹。'],
      ['从主屏幕移除不卸载', '拿掉图标，App 还在 Mac 上，随时可以再添回来。'],
      ['拖到屏幕边可侧拉', '不在编辑时，把图标直接拖到屏幕边，打开的窗口就放进侧拉。'],
      ['在刘海里验证 Touch ID', '菜单里选“验证 Touch ID…”，刘海展开确认本次应用请求。无刘海的屏幕显示独立胶囊，完成后收回，恢复原来的实时活动。'],
    ],
    note: '启动台与 Touch ID 入口仍是开发版，还没有发布，当前下载版不含这些改动。这是网页示意。',
    tabHome: '主屏幕',
    tabLibrary: 'App 资料库',
    tabLabel: '启动台视图',
    home: '主屏幕',
    library: 'App 资料库',
    apps: { mail: '邮件', notes: '笔记', calendar: '日历', photos: '照片', reference: '参考', tools: '工具文件夹' },
    openIn: '在这个示意里打开',
    close: '关闭窗口',
    folder: '工具',
    folderItems: { terminal: '终端', calculator: '计算器', preview: '预览' },
    groups: [
      ['工具', ['终端', '计算器', '预览', '活动监视器', '磁盘工具', '钥匙串']],
      ['效率', ['备忘录', '日历', '提醒事项', '快捷指令', '专注', '通讯录']],
      ['创意', ['照片', '预览', '音乐', '播客', '图书', '画图']],
    ],
    groupHint: '点分组展开',
    windowTitle: { mail: '邮件', notes: '笔记', calendar: '日历', photos: '照片', reference: '参考' },
    caption: '网页示意，不会打开应用或改变你的排列。',
  },
  en: {
    kicker: 'Launchpad · Developer build',
    title: 'Every app has a place.<br>Every window has somewhere to go.',
    lead: 'Press ⌃⌘L to open Launchpad. Drop apps into folders, or find them in the App Library on the last page.',
    points: [
      ['Live activities on the Today page', 'Music, headphones, shares and routes share up to three entries with the notch. Swipe to switch and hold to expand.'],
      ['Rearrange the Home grid', 'Press and hold an icon to edit. Drag icons to rearrange them or make folders.'],
      ['Remove from Home, not from the Mac', 'Taking an icon off the grid leaves the app installed. Add it back whenever you like.'],
      ['Drag out into Slide Over', 'Outside editing mode, drag an app icon straight to the screen edge to open its window in Slide Over.'],
      ['Verify Touch ID in the notch', 'Choose “Verify Touch ID…” to confirm this application request in the notch. Displays without a notch use a separate capsule. When finished, it closes and restores the previous live activity.'],
    ],
    note: 'Launchpad and the Touch ID entry point are still a developer build and have not shipped; the current download doesn’t include these changes. This is a web illustration.',
    tabHome: 'Home grid',
    tabLibrary: 'App Library',
    tabLabel: 'Launchpad views',
    home: 'Home grid',
    library: 'App Library',
    apps: { mail: 'Mail', notes: 'Notes', calendar: 'Calendar', photos: 'Photos', reference: 'Reference', tools: 'Tools folder' },
    openIn: 'Open in this illustration',
    close: 'Close window',
    folder: 'Tools',
    folderItems: { terminal: 'Terminal', calculator: 'Calculator', preview: 'Preview' },
    groups: [
      ['Tools', ['Terminal', 'Calculator', 'Preview', 'Activity Monitor', 'Disk Utility', 'Keychain']],
      ['Productivity', ['Notes', 'Calendar', 'Reminders', 'Shortcuts', 'Focus', 'Contacts']],
      ['Creativity', ['Photos', 'Preview', 'Music', 'Podcasts', 'Books', 'Freeform']],
    ],
    groupHint: 'Open the group',
    windowTitle: { mail: 'Mail', notes: 'Notes', calendar: 'Calendar', photos: 'Photos', reference: 'Reference' },
    caption: 'A web illustration. It won’t open an app or change your layout.',
  },
};
const outline = (inner, extra = '') => `<svg viewBox="0 0 32 32" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" ${extra}>${inner}</svg>`;
// 六个原创极简图标：邮件的信封、笔记的横线页、日历、日历网格、照片、文件夹。
const icons = {
  mail: outline('<rect x="4" y="8" width="24" height="16" rx="3"/><path d="M5.5 10.5 16 18l10.5-7.5"/>'),
  notes: outline('<rect x="7" y="5" width="18" height="22" rx="3"/><path d="M11.5 11.5h9M11.5 16h9M11.5 20.5h5"/>'),
  calendar: outline('<rect x="5" y="7" width="22" height="20" rx="3"/><path d="M5 13h22M11 4.5v5M21 4.5v5"/>'),
  photos: outline('<rect x="5" y="7" width="22" height="18" rx="3"/><circle cx="12" cy="14" r="2.4"/><path d="M6.5 22.5 14 17l5 4.5 4-3 3.5 3"/>'),
  reference: outline('<path d="M6.5 6.5h9a3 3 0 0 1 3 3v16H9.5a3 3 0 0 1-3-3z"/><path d="M18.5 9.5h4a3 3 0 0 1 3 3v13h-7"/><path d="M11 12.5h5M11 17h5"/>'),
  tools: outline(Array.from({length:9},(_,i)=>`<rect x="${5+i%3*8}" y="${5+Math.floor(i/3)*8}" width="6" height="6" rx="1.5" fill="currentColor" stroke="none"/>`).join('')),
};
const icon = (key) => icons[key];
const cell = (key, label, info) => `<li class="lp-slot"><button type="button" class="lp-app" data-lp-app="${key}" aria-label="${label}"${info ? ` title="${info}"` : ''}><span class="lp-ico lp-ico-${key}">${icon(key)}</span><span class="lp-name">${label}</span></button></li>`;
const big = (i, j) => outline('<rect x="6" y="6" width="20" height="20" rx="5"/>');
const small = (i, j) => outline('<rect x="7" y="7" width="18" height="18" rx="5"/>');
const group = (name, apps, hint, i) => `<li class="lp-group"><button type="button" class="lp-group-btn" data-lp-group="${i}" aria-label="${name}：${hint}"><span class="lp-group-head">${name}</span><span class="lp-group-apps">${apps.slice(0, 3).map((_, j) => `<span class="lp-ico lp-ico-g${i}-${j}">${big(i, j)}</span>`).join('')}</span><span class="lp-group-cluster" aria-hidden="true">${apps.slice(3).map((_, j) => `<i class="lp-ico lp-ico-g${i}-c${j}">${small(i, j)}</i>`).join('')}</span><span class="lp-group-label">${apps.join(' · ')}</span></button></li>`;

export function launchpadSection(lang) {
  const c = t[lang === 'en' ? 'en' : 'zh'];
  const home = `<ul class="lp-grid" id="lp-home" data-lp-pane="home" aria-label="${c.home}">${['mail', 'notes', 'calendar', 'photos', 'reference', 'tools'].map(key => cell(key, c.apps[key], key === 'tools' ? '' : c.openIn)).join('')}</ul>`;
  const library = `<ul class="lp-library" id="lp-library" data-lp-pane="library" aria-label="${c.library}" hidden>${c.groups.map(([name, apps], i) => group(name, apps, c.groupHint, i)).join('')}</ul>`;
  return `<section class="feature wrap" id="launchpad">
<div class="feature-copy"><p class="kicker">${c.kicker}</p><h2>${c.title}</h2><p class="lead">${c.lead}</p><ul class="points">${c.points.map(([title, detail]) => `<li><strong>${title}</strong><span>${detail}</span></li>`).join('')}</ul><p class="note">${c.note}</p></div>
<div class="feature-demo">
<div class="lp-demo" data-lp-demo
  data-close="${c.close}" data-window="${c.openIn}" data-folder="${c.folder}" data-folder-items="${Object.values(c.folderItems).join(' · ')}" data-home="${c.home}" data-library="${c.library}">
<div class="lp-tabs" role="group" aria-label="${c.tabLabel}"><button type="button" class="lp-tab" data-lp-tab="home" aria-pressed="true" aria-controls="lp-home">${c.tabHome}</button><button type="button" class="lp-tab" data-lp-tab="library" aria-pressed="false" aria-controls="lp-library">${c.tabLibrary}</button></div>
<div class="lp-stage">
${home}
${library}
<template data-lp-folder-template><div class="lp-folder-grid">${Object.values(c.folderItems).map((name,i)=>cell(["reference","calendar","photos"][i],name,c.openIn)).join('')}</div></template>
<div class="lp-overlay" data-lp-overlay role="group" aria-labelledby="lp-overlay-title" hidden>
<span class="lp-lights" aria-hidden="true"><i></i><i></i><i></i></span>
<p id="lp-overlay-title" class="lp-overlay-title"></p>
<div class="lp-overlay-body"></div>
<button type="button" class="lp-close" data-lp-close aria-label="${c.close}">${outline('<path d="M10 10l12 12M22 10 10 22"/>')}</button>
</div>
</div>
</div>
<p class="caption lp-caption">${c.caption}</p>
</div>
</section>`;
}
