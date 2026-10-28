#!/usr/bin/env python3
"""Give every HTML design draft the same top bar and its errata box.

Reads docs/design-drafts/_spine.json (order, groups, status, url) and _errata.json
(per draft: decisions made after the draft). Rewrites each draft in place:
- replaces an existing <nav class="ws-sys"> (or inserts one) with the shared spine nav;
- replaces / inserts <aside id="ws-errata"> right after the nav;
- keeps one <style id="ws-spine"> with the nav + errata styles.
Idempotent: running it twice gives the same files.
"""
import html
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "docs" / "design-drafts"
TOTAL = "WindowShade 设计系统.html"

STYLE = """<style id="ws-spine">
.ws-sys{display:flex;flex-wrap:wrap;align-items:center;gap:6px 14px;max-width:1160px;margin:0 auto;padding:10px 16px;font:12.5px/1.4 "IBM Plex Sans","Noto Sans SC",-apple-system,system-ui,sans-serif;border-bottom:1px solid color-mix(in srgb,currentColor 14%,transparent)}
.ws-sys a{color:inherit;text-decoration:none;opacity:.78}.ws-sys a:hover,.ws-sys a:focus-visible{opacity:1;text-decoration:underline}
.ws-sys b{font-weight:600}.ws-sys .ws-n{opacity:.55;font-variant-numeric:tabular-nums}.ws-sys .ws-sp{flex:1}
.ws-sys .ws-st{font-size:11px;padding:2px 7px;border-radius:999px;border:1px solid color-mix(in srgb,currentColor 22%,transparent);opacity:.8;white-space:nowrap}
.ws-sys .ws-st.ws-old{border-color:#c77d00;color:#b06d00;opacity:1}
.ws-errata{max-width:1128px;margin:12px auto 0;padding:10px 14px;border-left:3px solid #c77d00;background:color-mix(in srgb,currentColor 5%,transparent);border-radius:0 8px 8px 0;font:13px/1.6 "Noto Sans SC",-apple-system,system-ui,sans-serif}
.ws-errata summary{cursor:pointer;font-weight:600}
.ws-errata ol{margin:6px 0 2px;padding-left:1.4em}.ws-errata li{margin:3px 0}
.ws-errata .was{opacity:.7}.ws-errata .src{opacity:.6;font-size:12px}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]) .ws-sys .ws-st.ws-old{color:#ffb340;border-color:#ffb340}:root:not([data-theme="light"]) .ws-errata{border-left-color:#ffb340}}
:root[data-theme="dark"] .ws-sys .ws-st.ws-old{color:#ffb340;border-color:#ffb340}:root[data-theme="dark"] .ws-errata{border-left-color:#ffb340}
</style>"""

NAV_RE = re.compile(r'<nav class="ws-sys"[^>]*>.*?</nav>', re.S)
ERR_RE = re.compile(r'\n?<aside class="ws-errata" id="ws-errata">.*?</aside>', re.S)
STYLE_RE = re.compile(r'\n?<style id="ws-spine">.*?</style>', re.S)
FIRST_BLOCK = re.compile(r'<(header|div|main|section|article|h1)\b')


def esc(s):
    return html.escape(s, quote=True)


def nav_html(i, items, total_url):
    it = items[i]
    n = len(items)
    prev_it, next_it = items[i - 1] if i else None, items[i + 1] if i + 1 < n else None
    where = "总稿" if it["file"] == TOTAL else f'{it["group"]} · 第 {i} / {n - 1} 张'
    old = " ws-old" if it.get("errata") else ""
    parts = [
        f'<nav class="ws-sys" aria-label="WindowShade 设计稿"><a href="{total_url}"><b>WindowShade 设计系统</b></a>',
        f'<span class="ws-n">{esc(where)} · {esc(it["title"])}</span>',
        f'<span class="ws-st{old}">{esc(it["status"])}</span><span class="ws-sp"></span>',
    ]
    if prev_it:
        parts.append(f'<a href="{prev_it["url"]}">← {esc(prev_it["title"])}</a>')
    if next_it:
        parts.append(f'<a href="{next_it["url"]}">{esc(next_it["title"])} →</a>')
    parts.append("</nav>")
    return "".join(parts)


def errata_html(entries):
    if not entries:
        return ""
    lis = []
    for e in entries:
        was = f'<span class="was">原来：{esc(e["was"])}</span> → ' if e.get("was") else ""
        lis.append(f'<li>{was}<b>现在：</b>{esc(e["now"])} <span class="src">（{esc(e["src"])}）</span></li>')
    return (f'\n<aside class="ws-errata" id="ws-errata"><details open><summary>这张稿之后又定了 {len(entries)} 件'
            f'（2026-10-29 统合；下面的正文保留原样，以这里为准）</summary><ol>{"".join(lis)}</ol></details></aside>')


HEAD_WRAP = ('<!doctype html><html lang="zh-CN"><head><meta charset=utf8><meta name=viewport '
             'content="width=device-width,initial-scale=1,viewport-fit=cover"><style>')


def body_only(text):
    # Publishing replaces a page's own <head>, so styles kept there are lost online.
    # Keep these drafts in the body-only form they were first published in.
    if text.startswith(HEAD_WRAP) and "</style></head><body>" in text:
        text = "<style>" + text[len(HEAD_WRAP):]
        text = text.replace("</style></head><body>", "</style>", 1)
        text = re.sub(r"\s*</body></html>\s*$", "\n", text)
    return text


def apply(text, nav, errata):
    text = body_only(text)
    text = STYLE_RE.sub("", text)
    text = ERR_RE.sub("", text)
    block = nav + errata
    if NAV_RE.search(text):
        text = NAV_RE.sub(lambda _: block, text, count=1)
    else:
        m = FIRST_BLOCK.search(text, text.find("</style>"))
        if not m:
            raise SystemExit("no insertion point")
        text = text[: m.start()] + block + "\n" + text[m.start():]
    # the shared style goes right before the nav so it wins over older copies of .ws-sys
    i = text.find('<nav class="ws-sys"')
    return text[:i] + STYLE + "\n" + text[i:]


def main():
    spine = json.loads((ROOT / "_spine.json").read_text())
    errata = json.loads((ROOT / "_errata.json").read_text()) if (ROOT / "_errata.json").exists() else {}
    items = spine["items"]
    for it in items:
        it["errata"] = errata.get(it["file"], [])
    total_url = next(it["url"] for it in items if it["file"] == TOTAL)
    only = set(sys.argv[1:])
    for i, it in enumerate(items):
        if only and it["file"] not in only:
            continue
        p = ROOT / it["file"]
        new = apply(p.read_text(encoding="utf-8"), nav_html(i, items, total_url), errata_html(it["errata"]))
        p.write_text(new, encoding="utf-8")
        print(f'{i:2d} {it["file"]} errata={len(it["errata"])}')


if __name__ == "__main__":
    main()
