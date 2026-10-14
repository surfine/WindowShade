// 官网的繁体（台湾用语）查表（第39批）。
// 由 tools/localize/site-zh-hant.py 生成：把 content.mjs 与 history.mjs 里的中文串
// 走 App 那套流水线（OpenCC s2twp + 台湾专名表）转好，写进 zh-hant.json。
// 站点构建时按原文查表：查得到用繁体，查不到原样输出（宁可留简体，不出错字）。
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const table = JSON.parse(readFileSync(fileURLToPath(new URL('./zh-hant.json', import.meta.url)), 'utf8'));

/** 一句中文 → 台湾繁体；没收录就原样返回。 */
export const hant = (text) => (typeof text === 'string' ? (table[text] ?? text) : text);

/** 深层转换（对象/数组/字符串）；函数与其它类型原样返回，调用方按需覆写。 */
export function toTraditional(value) {
  if (typeof value === 'string') return hant(value);
  if (Array.isArray(value)) return value.map(toTraditional);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, toTraditional(item)]));
  }
  return value;
}

// 整页兜底：生成好的 HTML 里还有别的模块（launchpad.mjs 等）写的简体串，
// 繁体页面整页过一遍对照表：按关键词从长到短替换，只替换表里收录的串。
const keys = Object.keys(table).sort((a, b) => b.length - a.length);
const escapeRe = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const phraseRe = new RegExp(keys.map(escapeRe).join('|'), 'g');

export function translateHtml(html) {
  return html.replace(phraseRe, (match) => table[match] ?? match);
}

/** 注入给 history.js 的繁体对照表（客户端按原文查表）。 */
export const twScript = `<script>window.WS_TW = ${JSON.stringify(table)};</script>`;
