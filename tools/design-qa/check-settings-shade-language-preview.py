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
        check(not missing, (name, "text lost vs baseline", sorted(missing)[:6]))
        ax_extra = ax_texts(a) - ax_texts(b)
        check(ax_extra <= allowed, (name, "unexpected new a11y text", sorted(ax_extra - allowed)[:6]))
        ax_missing = ax_texts(b) - ax_texts(a)
        check(not ax_missing, (name, "a11y text lost vs baseline", sorted(ax_missing)[:6]))
        bg, ag = label_geometry(b), label_geometry(a)
        for text, (bx, by, bw, bh) in bg.items():
            if text not in ag:
                continue
            x, y, w, h = ag[text]
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
