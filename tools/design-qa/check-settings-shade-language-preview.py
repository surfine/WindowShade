#!/usr/bin/env python3
"""第27批消费者：设置「卷帘」页/「高级」页/外壳的中英夹具。
输入：AFTER 输出目录；可选 --baseline BEFORE 输出目录（改动前同夹具跑出的 zh 基线）。
断言（只覆盖夹具能证明的范围；真机可见效果不在此列）：
  1. 帧齐全：zh/en × 浅/深 × 696/560 卷帘页 + 高级页 zh / 同进程重建 en / 重建回 zh。
  2. zh 回归：改动后的 zh 帧包含改动前 zh 帧的每一处文字（标题/控件/提示/读屏标签），
     标签几何（x/宽/高）逐项一致（卷帘页连 y 一并核对）；多出来的文字只允许语言行白名单。
  3. en 无汉字（白名单只有语言名“简体中文”），并含关键英文锚点；外壳侧栏、语言行都在。
  4. 同进程重建：en 后含语言行英文；切回 zh 后与初始 zh 完全一致（立即生效的组件级证据）。
  5. 夹具声明零持久偏好写、零权限弹窗；读到的系统状态原样记录。
  6. 输入身份当前：sources.json 每项 SHA 与磁盘一致；renderer.json 是 Swift6 严格未优化。
"""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AFTER = Path(sys.argv[1]).resolve()
BASELINE = None
if "--baseline" in sys.argv:
    BASELINE = Path(sys.argv[sys.argv.index("--baseline") + 1]).resolve()

FAILURES = []
HAN = re.compile(r"[\u4e00-\u9fff]")
LANGUAGE_ROW_ALLOWLIST = {"语言", "界面语言", "切换后立即生效", "跟随系统", "简体中文", "English"}
EN_HAN_ALLOWLIST = {"简体中文"}


def check(ok, label):
    if not ok:
        FAILURES.append(label)


def frame_map(out):
    data = json.loads((out / "frames.json").read_text())
    return data, {f["name"]: f for f in data["frames"]}


def texts(frame):
    out = set()
    for key in ("labels",):
        for item in frame.get(key, []):
            out.add(item["text"])
    for item in frame.get("buttons", []):
        out.add(item["title"])
    for item in frame.get("segments", []):
        out.update(item.get("labels", []))
    for item in frame.get("popups", []):
        out.update(item.get("items", []))
    out.update(frame.get("tooltips", []))
    return out


def ax_texts(frame):
    return set(frame.get("axLabels", []))


def label_geometry(frame):
    return {item["text"]: (item["x"], item["y"], item["width"], item["height"])
            for item in frame.get("labels", [])}


after_data, after = frame_map(AFTER)
required = [
    "zh-light-696-shade", "zh-dark-696-shade", "zh-light-560-shade", "zh-dark-560-shade",
    "en-light-696-shade", "en-dark-696-shade",
    "zh-aqua-900-advanced", "rebuild-en-advanced", "rebuild-zh-advanced",
]
for name in required:
    check(name in after, f"missing frame {name}")

check(after_data.get("preferencesWritten") is False, "after fixture must not write preferences")
check(after_data.get("persistentDefaultsTouched") is False, "after fixture must not touch persistent defaults")
check(after_data.get("permissionPrompts") == 0, "after fixture must not prompt for permissions")
check(isinstance(after_data.get("permissionReads"), dict) and after_data["permissionReads"],
      "after fixture must record the non-prompting permission reads")

if BASELINE is not None:
    before_data, before = frame_map(BASELINE)
    check(before_data.get("preferencesWritten") is False, "baseline fixture must not write preferences")
    for name in ["zh-light-696-shade", "zh-dark-696-shade", "zh-light-560-shade", "zh-dark-560-shade",
                 "zh-aqua-900-advanced"]:
        check(name in before and name in after, f"baseline frame {name}")
        if name not in before or name not in after:
            continue
        b, a = before[name], after[name]
        extra = texts(a) - texts(b)
        allowed = set() if b["surface"] == "shade" else LANGUAGE_ROW_ALLOWLIST
        check(extra <= allowed, (name, "unexpected new text", sorted(extra - allowed)[:6]))
        missing = texts(b) - texts(a)
        # 逐条放宽（护栏要求：逐条、写理由、留证据）——本批唯一一条"文案被替换"的豁免：
        # #39（2026-10-12）给「双击标题栏收起窗口」的副标题追加了修饰键出口
        # （"…；按住 Option 双击不收起"），是产品有意变更，不是漏译/回归。
        # 旧文案整句被新文案取代，故按“超集”判据必然报 text lost；这里逐条列出映射，
        # 只豁免这三条（系统双击动作的三种分支各一条），其余任何 missing 仍然失败。
        # 证据：docs/releases/v1.0.16-acceptance/issue39-evidence.md（截图+文案对照）。
        SUBTITLE_SUPERSEDED = {
            "三击标题栏会缩放窗口": "三击标题栏会缩放窗口；按住 Option 双击不收起",
            "三击标题栏会最小化窗口": "三击标题栏会最小化窗口；按住 Option 双击不收起",
            "在任意窗口的标题栏上双击": "在任意窗口的标题栏上双击；按住 Option 双击不收起",
        }
        allowed_missing = {old for old, new in SUBTITLE_SUPERSEDED.items() if new in texts(a)}
        missing = missing - allowed_missing
        check(not missing, (name, "text lost vs baseline", sorted(missing)[:6]))
        ax_extra = ax_texts(a) - ax_texts(b)
        check(ax_extra <= allowed, (name, "unexpected new a11y text", sorted(ax_extra - allowed)[:6]))
        ax_missing = ax_texts(b) - ax_texts(a)
        check(not ax_missing, (name, "a11y text lost vs baseline", sorted(ax_missing)[:6]))
        bg, ag = label_geometry(b), label_geometry(a)
        # 逐条放宽（护栏要求：逐条、写理由、留证据）——这两条是 wrappingLabel 的折行/
        # 自然宽歧义，改动前就存在且基线自身不稳定，不是本批改动：
        # - "需要已绑定身份的蓝牙读回来源"（WS2SupplementPane 四条 gate 注记之一，
        #   wrappingLabel）：before 基线同一 run 里 x 在 82/484.5/348.5 之间漂（dark-696
        #   四条注记三条在行中位、一条在行首），after 四帧全部稳定 82；两树该文件几何
        #   代码同构。证据：.statem/history-design-twentyseventh-round/qa/gate2-geometry-drift.md
        # - "名单里还没有 App"（PrivateAppListSettings/WS2FocusSettings 的 wrappingLabel
        #   空态行）：before 基线 dark-560 宽 94、light-560 宽 476（同一 run 内不一致），
        #   after 四帧全部稳定；固有宽度歧义同上。
        WRAP_AMBIGUOUS = {"需要已绑定身份的蓝牙读回来源", "名单里还没有 App"}
        for text, (bx, by, bw, bh) in bg.items():
            if text not in ag:
                continue
            x, y, w, h = ag[text]
            if text in WRAP_AMBIGUOUS:
                continue
            check(abs(x - bx) <= 0.5 and abs(w - bw) <= 0.5, (name, "geometry x/w drift", text, bx, x, bw, w))
            if b["surface"] == "shade":
                check(abs(y - by) <= 0.5 and abs(h - bh) <= 0.5, (name, "geometry y/h drift", text, by, y, bh, h))

for name in ["en-light-696-shade", "en-dark-696-shade", "rebuild-en-advanced"]:
    frame = after.get(name)
    if frame is None:
        continue
    all_text = texts(frame) | ax_texts(frame)
    han = sorted(t for t in all_text if HAN.search(t) and t not in EN_HAN_ALLOWLIST)
    check(not han, (name, "Han text in English frame", han[:6]))

en_shade = after.get("en-light-696-shade", {})
anchors = ["Glance", "Tuck into the notch", "File shelf", "Gap between windows",
           "Play a sound on roll up and unroll", "Triggers", "Experiments", "Silent phrases",
           "Focus & input", "Volume & brightness"]
missing_anchors = [a for a in anchors if a not in texts(en_shade)]
check(not missing_anchors, ("en shade anchors", missing_anchors))

en_advanced = after.get("rebuild-en-advanced", {})
en_advanced_anchors = ["Advanced", "Language", "Interface language", "Reset defaults",
                       "Diagnostics log", "Accessibility"]
missing_advanced = [a for a in en_advanced_anchors if a not in texts(en_advanced)]
check(not missing_advanced, ("en advanced anchors", missing_advanced))
check(en_advanced.get("windowTitle") == "WindowShade Settings",
      ("en window title", en_advanced.get("windowTitle")))
popup_items = {item for popup in en_advanced.get("popups", []) for item in popup.get("items", [])}
for item in ["Follow the system", "简体中文", "English"]:
    check(item in popup_items, ("language popup item", item))
for item in ["Roll up", "Mouse & trackpad", "Window browsing"]:
    check(item in texts(en_advanced), ("en sidebar title", item))

zh_advanced = after.get("zh-aqua-900-advanced", {})
zh_rebuild = after.get("rebuild-zh-advanced", {})
check(texts(zh_advanced) == texts(zh_rebuild), "zh rebuild must match the initial zh window")
check(zh_advanced.get("windowTitle") == zh_rebuild.get("windowTitle") == "WindowShade 设置",
      "zh window title across rebuild")
check(label_geometry(zh_advanced) == label_geometry(zh_rebuild), "zh rebuild geometry must match")

# 门0 判据（卡点 B）：夹具卷帘页的滑杆行必须落在产品真实形态上（labels 拉伸、控件
# 自然宽右对齐，读数右缘贴行右缘）。实测：产品真窗口（走 allowHorizontalExpansion）
# 行宽 608 时 span=612（labels.leadingAnchor=行左缘，读数右缘有 4pt 视图内边距）；
# 560 宽档行宽 472，span 相应为 476。C 形态（控件被拉宽、右侧留空段）readout.x≈299，
# span≈283，两种期望都覆盖不到。
EXPECTED_SPANS = {"zh-light-696-shade": 612, "zh-dark-696-shade": 612,
                  "zh-light-560-shade": 476, "zh-dark-560-shade": 476}

def readout_span(frame):
    name_x = next((item["x"] for item in frame.get("labels", [])
                   if item["text"] in ("卷帘条半透明", "缩略图半透明")), None)
    readout = next((item for item in frame.get("labels", []) if item["text"].endswith("%")
                    and len(item["text"]) <= 4), None)
    if name_x is None or readout is None:
        return None
    return name_x, readout["x"] + readout["width"]

product = after.get("product-zh-aqua-900-shade")
check(product is not None, "missing frame product-zh-aqua-900-shade")
if product:
    span = readout_span(product)
    check(span is not None, "product frame missing slider row labels")
    if span:
        check(abs((span[1] - span[0]) - 612) <= 0.5,
              ("product frame must be in the natural-width form",
               "span", span[1] - span[0], "expected", 612))
    for name, expected in EXPECTED_SPANS.items():
        frame = after.get(name)
        if frame is None:
            continue
        span = readout_span(frame)
        check(span is not None, (name, "missing slider row labels"))
        if span:
            check(abs((span[1] - span[0]) - expected) <= 0.5,
                  (name, "fixture shade layout must match product form",
                   "span", span[1] - span[0], "expected", expected))

for name in required:
    png = AFTER / f"{name}.png"
    check(png.is_file() and png.read_bytes()[:8] == b"\x89PNG\r\n\x1a\n", f"png {name}")

renderer = json.loads((AFTER / "renderer.json").read_text())
check(renderer["swiftLanguageVersion"] == 6 and renderer["strictConcurrency"] and renderer["warningsAsErrors"],
      "renderer must be Swift 6 strict warnings-as-errors")
check(renderer["optimized"] is False, "renderer must be unoptimized")
sources = json.loads((AFTER / "sources.json").read_text())
check(len(sources) > 500, f"sources count {len(sources)}")
for rel, sha in sources.items():
    path = ROOT / rel
    if not path.is_file():
        check(False, f"missing source {rel}")
        continue
    check(hashlib.sha256(path.read_bytes()).hexdigest() == sha, f"source drift {rel}")

if FAILURES:
    print(f"FAIL {len(FAILURES)} checks:")
    for item in FAILURES[:40]:
        print(" -", item)
    sys.exit(1)
print(json.dumps({
    "passed": True,
    "after_frames": len(after),
    "zh_regression_vs_baseline": BASELINE is not None,
    "en_frames_checked": 3,
    "same_process_rebuild": "zh→en→zh labels equal",
    "permission_reads": after_data.get("permissionReads"),
    "current_inputs": len(sources),
}, ensure_ascii=False))
