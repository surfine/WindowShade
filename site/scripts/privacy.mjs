// 隐私页：从 tools/privacy/registry.json 生成，和 App 里「权限与隐私」同样的规则。
// 只输出 status 为 current 且文字齐全的行；生成后逐字对照 prototype/App/WS2PrivacyData.swift，
// 不一样就抛错，构建失败。
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const registry = JSON.parse(readFileSync(`${repoRoot}tools/privacy/registry.json`, 'utf8'));
const swiftSource = readFileSync(`${repoRoot}prototype/App/WS2PrivacyData.swift`, 'utf8');

// 第二句和 App 页头同一句（WS2PrivacyCopy.noReporting，规格 R37）；“不离开这台 Mac”仍等联网实测。
export const privacyIntro = 'WindowShade 读到的每一样都列在这里。不收集使用数据，也不做任何统计或上报。';
const FIELDS = ['label', 'subtitle', 'reads', 'purpose', 'destination', 'activation', 'toggle', 'combined'];
const FORBIDDEN = /\b(P\d|A2[ab]|IPC|L1|Sparkle)\b|待验证|待核|磁盘行为待/;
const escape = (s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');
const unswift = (s) => s.replace(/\\(["\\])/g, '$1');
const flat = (s) => s.replace(/\n/g, ' ');

// 只取 Swift 里的字符串字段：key: "…"
function swiftFields(block) {
  const out = {};
  // 第30批起生成器会出 WSL10n.text("privacy.<id>.<field>", zh: "…")：zh 源句仍是语义身份，
  // 官网对照以 zh 为准（英文译文在目录里，官网这条链仍输出中文源站文案）。
  for (const m of block.matchAll(/\b([A-Za-z]+): WSL10n\.text\("[^"]*",\s*zh: "((?:[^"\\]|\\.)*)"/g)) {
    if (!(m[1] in out)) out[m[1]] = unswift(m[2]);
  }
  for (const m of block.matchAll(/\b([A-Za-z]+): "((?:[^"\\]|\\.)*)"/g)) if (!(m[1] in out)) out[m[1]] = unswift(m[2]);
  return out;
}
function swiftRows() {
  const rows = new Map();
  for (const chunk of swiftSource.split('WS2PrivacyRow(').slice(1)) {
    const f = swiftFields(chunk.split('\n        ),')[0]);
    if (f.id) rows.set(f.id, f);
  }
  return rows;
}
function swiftGroups() {
  const groups = new Map();
  // 第30批：分组标题/副标也走 WSL10n（zh 为语义身份，官网对照以 zh 为准）。
  // 第36批：生成器把声明改成了 static var groups，两种都认。
  const groupChunk = swiftSource.split(/static (?:let|var) groups/)[1] ?? '';
  for (const m of groupChunk.matchAll(/WS2PrivacyGroup\(title: (?:WSL10n\.text\("[^"]*", zh: "((?:[^"\\]|\\.)*)"\)|"((?:[^"\\]|\\.)*)"), subtitle: (?:WSL10n\.text\("[^"]*", zh: "((?:[^"\\]|\\.)*)"\)|"((?:[^"\\]|\\.)*)")\)/g)) {
    groups.set(unswift(m[1] ?? m[2]), unswift(m[3] ?? m[4] ?? ''));
  }
  return groups;
}

export function privacyModel() {
  const rows = registry.signals.filter((s) => s.status === 'current' && FIELDS.every((k) => s[k]));
  const problems = [];
  for (const s of rows) for (const k of FIELDS) if (FORBIDDEN.test(s[k])) problems.push(`${s.id}.${k} 含内部代号或未核句子`);
  const appRows = swiftRows(), appGroups = swiftGroups();
  for (const s of rows) {
    const a = appRows.get(s.id);
    if (!a) { problems.push(`${s.id}: WS2PrivacyData.swift 里没有这一行`); continue; }
    if (a.status !== 'current') problems.push(`${s.id}: App 里 status 是 ${a.status}`);
    for (const k of FIELDS) if (a[k] !== flat(s[k])) problems.push(`${s.id}.${k}: 官网「${s[k]}」与 App「${a[k]}」不同`);
  }
  const groups = registry.groups
    .map((g) => ({ ...g, rows: rows.filter((s) => s.group === g.title) }))
    .filter((g) => g.rows.length);
  for (const g of groups) {
    if (!appGroups.has(g.title)) problems.push(`分组「${g.title}」不在 App 里`);
    else if (appGroups.get(g.title) !== flat(g.subtitle)) problems.push(`分组「${g.title}」副标与 App 不同`);
  }
  if (problems.length) throw new Error('隐私页与 App 不一致，构建中止：\n  ' + problems.join('\n  '));
  return groups;
}

export function privacyMain() {
  const groups = privacyModel();
  const dl = (s) => [['读到什么', s.reads], ['为了什么', s.purpose], ['去了哪里', s.destination], ['什么时候读', s.activation], ['怎么关', s.toggle], ['合起来能看出什么', s.combined]]
    .map(([k, v]) => `<div><dt>${k}</dt><dd>${escape(v)}</dd></div>`).join('');
  return `<main id="main" class="wrap section privacy-page"><div class="section-head"><h1>权限与隐私</h1><p class="lead">${escape(privacyIntro)}</p></div>${groups.map((g) => `<section class="privacy-group"><h2>${escape(g.title)}</h2>${g.subtitle ? `<p class="lead">${escape(g.subtitle)}</p>` : ''}${g.rows.map((s) => `<details class="privacy-row"><summary><strong>${escape(s.label)}</strong><span>${escape(s.subtitle)}</span></summary><dl>${dl(s)}</dl></details>`).join('')}</section>`).join('')}</main>`;
}
