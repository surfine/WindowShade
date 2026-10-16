#!/usr/bin/env python3
"""规格 N1 的检查实现；入口是 tests/run-n1-shortcuts-check.sh。输出 PASS/FAIL/SKIP/INFO 行。"""
import json, os, plistlib, re, shutil, sqlite3, sys, tempfile

app, require_reg, src = sys.argv[1], sys.argv[2] == "1", sys.argv[3]
EXPECTED = 7
LOCALES = ["en", "zh-Hans", "zh-Hant"]
fails = 0
def out(kind, msg):
    global fails
    if kind == "FAIL": fails += 1
    print(f"{kind}: {msg}")

res = os.path.join(app, "Contents", "Resources")
meta = os.path.join(res, "Metadata.appintents", "extract.actionsdata")
if not os.path.isfile(meta):
    out("FAIL", f"{meta} 不存在（包里没有 Metadata.appintents）")
    print("SUMMARY: FAIL"); sys.exit(1)
data = json.load(open(meta, encoding="utf-8"))
actions = data.get("actions", {})
disc = {k: v for k, v in actions.items() if v.get("isDiscoverable", True) and not v.get("visibilityMetadata", {}).get("assistantOnly", False)}
(out("PASS" if len(disc) == EXPECTED else "FAIL", f"可发现动作 {len(disc)} 个（期望 {EXPECTED}）：{', '.join(sorted(disc))}"))

# 源码里的 AppIntent 结构体
try:
    s = open(src, encoding="utf-8").read()
    in_src = set(re.findall(r"struct\s+(\w+)\s*:\s*AppIntent\b", s))
    same = in_src == set(actions)
    out("PASS" if same else "FAIL", f"源码 AppIntent 与包内元数据{'一致' if same else '不一致：仅源码 ' + str(sorted(in_src - set(actions))) + '，仅包内 ' + str(sorted(set(actions) - in_src))}")
except OSError as e:
    out("SKIP", f"读不到源码 {src}：{e}")

# 三语标题／说明
tables = {}
for loc in LOCALES:
    p = os.path.join(res, f"{loc}.lproj", "AppIntents.strings")
    try:
        with open(p, "rb") as f: tables[loc] = plistlib.load(f)
    except Exception as e:
        tables[loc] = {}; out("FAIL", f"{loc}.lproj/AppIntents.strings 读不到：{e}")
titles = {}
for ident, a in sorted(actions.items()):
    tk = a["title"]["key"]; dk = a.get("descriptionMetadata", {}).get("descriptionText", {}).get("key")
    miss = [f"{loc}:{k}" for loc in LOCALES for k in (tk, dk) if k and not str(tables[loc].get(k, "")).strip()]
    titles[ident] = {loc: tables[loc].get(tk, "") for loc in LOCALES}
    out("FAIL" if miss else "PASS", f"{ident}: " + (f"缺 {', '.join(miss)}" if miss else " / ".join(f"{loc}={titles[ident][loc]!r}" for loc in LOCALES)))
# 标题不重名（同一语言里两个动作同名，在快捷指令里分不清）
for loc in LOCALES:
    vals = [t[loc] for t in titles.values() if t[loc]]
    out("PASS" if len(vals) == len(set(vals)) else "FAIL", f"{loc} 标题互不重名")
# en 标题不应混入汉字；zh 标题应含汉字
cjk = re.compile(r"[一-鿿]")
bad = [i for i, t in titles.items() if cjk.search(t["en"]) or not cjk.search(t["zh-Hans"]) or not cjk.search(t["zh-Hant"])]
out("PASS" if not bad else "FAIL", "三语文字类型对得上（en 无汉字、zh 有汉字）" + (f"；问题：{bad}" if bad else ""))
# 语言提示（不判 FAIL）：zh-Hant 文案里的大陆用语
hint = [f"{k}={v}" for k, v in tables["zh-Hant"].items() if "窗口" in str(v)]
if hint: out("INFO", "zh-Hant 里出现大陆用词「窗口」（台湾用「視窗」）：" + "; ".join(hint))
out("INFO", f"autoShortcuts（Spotlight／Siri 短语）条目数 {len(data.get('autoShortcuts', []))}；0 表示没有 AppShortcutsProvider，只靠「快捷指令」App 的动作库发现")

# (b) 系统索引
try:
    bid = plistlib.load(open(os.path.join(app, "Contents", "Info.plist"), "rb"))["CFBundleIdentifier"]
except Exception as e:
    bid = None; out("SKIP", f"读不到 CFBundleIdentifier：{e}")
db = os.path.expanduser("~/Library/Shortcuts/ToolKit/Tools-active")
if bid and not os.path.exists(db):
    out("FAIL" if require_reg else "SKIP", "本机没有快捷指令动作索引（~/Library/Shortcuts/ToolKit/Tools-active）")
elif bid:
    tmp = tempfile.mkdtemp(prefix="n1-toolkit-")
    try:
        real = os.path.realpath(db); cp = os.path.join(tmp, "t.sqlite")
        for suf in ("", "-wal", "-shm"):
            if os.path.exists(real + suf): shutil.copy2(real + suf, cp + suf)
        con = sqlite3.connect(f"file:{cp}?mode=ro", uri=True)
        rows = con.execute("select t.id, c.bundleVersion from Tools t join ContainerMetadata c on c.rowId=t.sourceContainerId where c.id=? order by 1", (bid,)).fetchall()
        n = len(rows)
        if n:
            out("PASS" if n >= EXPECTED else "FAIL", f"系统索引里 {bid} 登记了 {n} 个动作：{', '.join(r[0] for r in rows)}")
        else:
            out("FAIL" if require_reg else "INFO", f"系统索引里没有 {bid} 的动作（未登记：这个包没在本机注册过，或系统还没索引到；包内元数据本身见上）")
    except Exception as e:
        out("FAIL" if require_reg else "SKIP", f"系统索引读取失败：{e}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
print("INFO: `shortcuts list` 只列用户的快捷指令，列不出 App 动作；「在快捷指令里搜得到」的最终确认只能看快捷指令 App 的界面")
print("SUMMARY: " + ("FAIL" if fails else "PASS"))
sys.exit(1 if fails else 0)
