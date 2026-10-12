#!/usr/bin/env python3
"""第26批组合 QA 消费者：隐私登记列对齐 + 动效接力（独立 RK4 数值核对）。
输入：render-native-surfaces.sh 的输出目录（page/、motion/、sources.json、renderer.json）。
只认实际记录；配置与隐藏呈现，不是帧率/可见合成/真机验收。"""
import json
import math
import sys
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(sys.argv[1])
PAGE = json.loads((OUT / "page" / "frames.json").read_text())
MOTION = json.loads((OUT / "motion" / "retarget.json").read_text())
SOURCES = json.loads((OUT / "sources.json").read_text())
RENDERER = json.loads((OUT / "renderer.json").read_text())
FAILURES = []


def check(ok, label):
    if not ok:
        FAILURES.append(label)


# ---------- 输入身份：当前 518 ----------
check(len(SOURCES) == 518, f"sources count {len(SOURCES)} != 518")
for rel, sha in SOURCES.items():
    path = ROOT / rel
    check(path.is_file(), f"missing source {rel}")
    if path.is_file():
        check(hashlib.sha256(path.read_bytes()).hexdigest() == sha, f"source drift {rel}")
check(RENDERER["swiftLanguageVersion"] == 6 and RENDERER["strictConcurrency"] and RENDERER["warningsAsErrors"],
      "renderer not swift6/strict/warnings-as-errors")
check(RENDERER["optimized"] is False, "renderer unexpectedly optimized")

# ---------- 隐私：41 行 / 4 组 / 9 开关 / 列对齐 ----------
registry = json.loads((ROOT / "tools/privacy/registry.json").read_text())
rows = [s for s in registry["signals"] if s.get("status") != "planned" and not s.get("appearsWith")]
groups = [g["title"] if isinstance(g, dict) else g for g in registry["groups"]]
extras = [s for s in registry["signals"] if s.get("appearsWith")]
expected = [s["id"] for g in groups for s in rows if s["group"] == g]
check(PAGE["candidateOnly"] and not PAGE["pageInstantiated"], "page flags")
for key in ["sourcesRead", "settingsWrites", "globalInputEvents"]:
    check(PAGE[key] == 0, f"page {key}")
check(len(PAGE["frames"]) == 12, f"frames {len(PAGE['frames'])}")
for f in PAGE["frames"]:
    check(f["groups"] == groups, f"{f['name']} groups")
    check([r["id"] for r in f["rows"]] == expected, f"{f['name']} rows")
    check(not f["visible"] and f["alpha"] == 0 and f["actions"] == 0, f"{f['name']} host")
    check(abs(f["pageWidth"] - 640) < 0.1, f"{f['name']} pageWidth")
    previous = None
    for r in f["rows"]:
        check(abs(r["width"] - 608) < 0.5, (f["name"], r["id"], "width"))
        check(r["height"] > 20, (f["name"], r["id"], "height"))
        if previous is not None:
            check(r["y"] >= previous - 0.5, (f["name"], r["id"], "y"))
        previous = r["y"] + r["height"]
        body = [x for x in r["fields"] if x["role"] == "privacy-detail-body"]
        check(bool(body) == f["expanded"], (f["name"], r["id"], "body presence"))
        for b in body:
            check(b["height"] + 1 >= b["neededHeight"], (f["name"], r["id"], "body height"))
            check(b["x"] >= 0 and b["x"] + b["width"] <= r["width"] + 2.1, (f["name"], r["id"], "body bounds"))
    # 登记列对齐：每个登记行的标题/副题列同 x（focus-preferences 不再多 38 点）
    label_x = []
    for r in f["rows"]:
        heads = [x["x"] for x in r["fields"] if x["role"] == "header"]
        check(heads, (f["name"], r["id"], "header fields"))
        if heads:
            label_x.append(min(heads))
    spread = max(label_x) - min(label_x)
    check(spread < 0.5, (f["name"], "header x spread", spread))
    if f["expanded"]:
        details = [b["x"] for r in f["rows"] for b in r["fields"] if b["role"] == "privacy-detail-body"]
        check(details and max(details) - min(details) < 0.5, (f["name"], "detail x spread",
              (max(details) - min(details)) if details else None))
        switches = [c for c in f["controls"] if c["kind"] == "switch"]
        check(len(switches) == 9, (f["name"], "switches", len(switches)))
        check(all(c["mockTarget"] for c in f["controls"]), (f["name"], "mock targets"))
    else:
        check(not any(c["kind"] == "switch" for c in f["controls"]), (f["name"], "collapsed switches"))
    check(any(c["kind"] == "grant" for c in f["controls"]), (f["name"], "grant control"))

# ---------- 动效：结构 ----------
records = {r["stage"]: r for r in MOTION["records"]}
check(MOTION["overrideRestored"] and MOTION["cacheOnly"] and not MOTION["compositorAccepted"], "motion flags")
check(MOTION["realSources"] == 0 and MOTION["globalInputEvents"] == 0 and not MOTION["productEntry"], "motion isolation")
check(MOTION["swiftLanguageVersion"] == 6 and MOTION["mainThread"], "motion swift6")
for r in MOTION["records"]:
    check(r["mainThread"] and r["delegateNil"] and not r["visible"] and not r["active"] and r["alpha"] == 0,
          (r["stage"], "host"))
    check(r["cacheOnly"], (r["stage"], "cacheOnly"))

AXES = {"position.x", "position.y", "bounds.size.width", "bounds.size.height", "cornerRadius"}
composite = {"position", "bounds.size"}


def anims(stage, kind=None):
    out = []
    for a in records[stage]["animations"]:
        if kind and a["class"] != kind:
            continue
        out.append(a)
    return out


def by_axis(stage, cls="CASpringAnimation"):
    return {a["keyPath"]: a for a in anims(stage, cls) if a["keyPath"] in AXES}


def rk4_state(m, k, c, x0, v0, t, step=1.0 / 4000):
    """独立数值积分 m·x'' + c·x' + k·x = 0。"""
    def accel(x, v):
        return (-c * v - k * x) / m
    x, v, now = x0, v0, 0.0
    while now < t:
        h = min(step, t - now)
        k1x, k1v = v, accel(x, v)
        k2x, k2v = v + h / 2 * k1v, accel(x + h / 2 * k1x, v + h / 2 * k1v)
        k3x, k3v = v + h / 2 * k2v, accel(x + h / 2 * k2x, v + h / 2 * k2v)
        k4x, k4v = v + h * k3v, accel(x + h * k3x, v + h * k3v)
        x += h / 6 * (k1x + 2 * k2x + 2 * k3x + k4x)
        v += h / 6 * (k1v + 2 * k2v + 2 * k3v + k4v)
        now += h
    return x, v


def axis_value(box, axis, radius):
    if axis == "position.x":
        return box["x"] + box["width"] / 2
    if axis == "position.y":
        return box["y"] + box["height"] / 2
    if axis == "bounds.size.width":
        return box["width"]
    if axis == "bounds.size.height":
        return box["height"]
    return radius


CONTINUITY = [
    ("open-old", "open-new"),
    ("reverse-old", "reverse-new"),
    ("reopen-old", "reopen-new"),
    ("width-old", "width-new"),
    ("width-reverse-old", "width-reverse-new"),
    ("rich-exit-old", "rich-exit-new"),
    ("cancel-reopen-old", "cancel-reopen-new"),
    ("kick-old", "kick-new"),
]
for mode in ["regular"]:
    for old_stage, new_stage in CONTINUITY:
        old_key, new_key = f"{mode}-{old_stage}", f"{mode}-{new_stage}"
        if old_key not in records or new_key not in records:
            check(False, f"missing stage {old_key} or {new_key}")
            continue
        old_springs = {a["keyPath"]: a for a in records[old_key]["animations"] if a["keyPath"] in AXES}
        new_all = {a["keyPath"]: a for a in records[new_key]["animations"] if a["keyPath"] in AXES}
        check(not any(a["keyPath"] in composite for a in records[new_key]["animations"]),
              (new_key, "composite keyPath"))
        for axis, new in new_all.items():
            old = old_springs.get(axis)
            if old is None or old["class"] != "CASpringAnimation":
                continue
            elapsed = new["beginTime"] - old["beginTime"]
            check(0 < elapsed < old["duration"], (new_key, axis, "elapsed", round(elapsed, 4), old["duration"]))
            if not (0 < elapsed < old["duration"]):
                continue
            x_t, v_t = rk4_state(old["mass"], old["stiffness"], old["damping"],
                                 old["from"], -old["velocity"] * old["from"], elapsed)
            if new["class"] == "CASpringAnimation":
                f_new, nv_new = new["from"], new["velocity"]
                v_new = -nv_new * f_new
                tol_v = max(2.0, abs(v_t) * 0.05)
                check(abs(v_new - v_t) <= tol_v, (new_key, axis, "velocity continuity",
                      round(v_new, 3), round(v_t, 3)))
                old_box, new_box = records[old_key]["model"], records[new_key]["model"]
                old_r, new_r = records[old_key]["modelRadius"], records[new_key]["modelRadius"]
                expected_from = x_t + (axis_value(old_box, axis, old_r) - axis_value(new_box, axis, new_r))
                # 起点由呈现层读数换算：读位置到 beginTime 生效之间有约 4ms 的读取-挂载偏差
                # （实测 diff/|v_t| ≤ 4.0ms），所以容差随该轴瞬时速度放宽；差一个量级即真实缺陷。
                tol_f = max(0.75, abs(v_t) * 0.006)
                check(abs(f_new - expected_from) <= tol_f, (new_key, axis, "position continuity",
                      round(f_new, 3), round(expected_from, 3)))
                check(v_new == 0 or v_t == 0 or (v_new * v_t > 0), (new_key, axis, "direction sign"))
            else:
                values = new.get("values")
                times = new.get("keyTimes")
                check(isinstance(values, list) and isinstance(times, list) and len(values) == len(times),
                      (new_key, axis, "kick keyframes"))
                if isinstance(values, list) and isinstance(times, list) and len(values) >= 2:
                    check(times == sorted(times) and abs(times[0]) < 1e-9 and abs(times[-1] - 1) < 1e-9,
                          (new_key, axis, "kick times"))
                    # 起点就是这跳的起点位移（目标取整到 0.05 点，所以接近 0），收尾钉回 0。
                    check(abs(values[0]) <= 0.1, (new_key, axis, "kick start", values[0]))
                    check(abs(values[-1]) < 1e-6, (new_key, axis, "kick end"))
                    check(all(math.isfinite(v) for v in values), (new_key, axis, "kick finite"))
                    check(new["duration"] <= 1.3, (new_key, axis, "kick duration"))
                    # 惯性延续：kick 是同一物理弹簧从（此刻位移, 旧弹簧此刻速度）积分出来的
                    # 解析采样，抽稀后首段斜率不再等于瞬时速度（段长 2/120s），所以做全程曲线对照。
                    # 新弹簧系数取同一条 morph 里仍是 CASpringAnimation 的轴（同参数）；
                    # 只有在没有弹簧轴可比时才退回旧弹簧系数（同一 token 时参数相同）。
                    ref = next((a for a in records[new_key]["animations"]
                                if a["keyPath"] in AXES and a["class"] == "CASpringAnimation"), None)
                    if ref is None and old is not None:
                        ref = old
                    check(ref is not None, (new_key, axis, "kick reference spring"))
                    if ref is not None:
                        worst = 0.0
                        for kt, kv in zip(times, values):
                            num, _ = rk4_state(ref["mass"], ref["stiffness"], ref["damping"],
                                               values[0], v_t, kt * new["duration"])
                            worst = max(worst, abs(num - kv))
                        scale = max(1.0, max(abs(v) for v in values))
                        check(worst <= max(0.5, 0.03 * scale), (new_key, axis, "kick curve RK4", round(worst, 4)))
                        check((values[1] - values[0]) * v_t > 0, (new_key, axis, "kick first direction",
                              round(values[1] - values[0], 4), round(v_t, 3)))
                    target = axis_value(records[new_key]["model"], axis, records[new_key]["modelRadius"])
                    if axis in ("bounds.size.width", "bounds.size.height", "cornerRadius"):
                        check(min(values) + target >= -0.01, (new_key, axis, "kick floor"))

# 停稳后再起跳：没有活跃旧动画 → 归一化初速度为调用者的（0），不复用幽灵速度。
wr_new = by_axis("regular-width-reverse-new")
check(wr_new, "width-reverse springs")
for axis, a in wr_new.items():
    check(a["velocity"] == 0, ("settled retarget keeps caller velocity", axis, a["velocity"]))

# 反向：配置的物理速度方向必须接着旧的走（25 批的缺陷就是这里取错号）
rev_old = by_axis("regular-reverse-old")
rev_new = by_axis("regular-reverse-new")
check("position.y" in rev_old and "position.y" in rev_new, "reverse position.y springs")
if "position.y" in rev_old and "position.y" in rev_new:
    o, n = rev_old["position.y"], rev_new["position.y"]
    elapsed = n["beginTime"] - o["beginTime"]
    _, v_t = rk4_state(o["mass"], o["stiffness"], o["damping"], o["from"], -o["velocity"] * o["from"], elapsed)
    v_new = -n["velocity"] * n["from"]
    check(v_t < 0 and v_new < 0, ("reverse continues toward expanded", round(v_t, 3), round(v_new, 3)))
    check(n["velocity"] < 0, ("reverse normalized velocity negative", n["velocity"]))

# 各轴使用自己的剩余行程：只改宽度的那一跳里，宽度轴的余程与其它轴不成比例，归一化速度
# 必须跟着不同（position.y/height/radius 余程同比例，三者相同是数学必然；宽度单独一个值
# 才证明逐轴换算）。（反向那一跳四轴 excursion 同比例，四值相同是正确结果，不检查差异。）
w_new = by_axis("regular-width-new")
check(all(a in w_new for a in ["position.y", "bounds.size.width", "bounds.size.height", "cornerRadius"]),
      ("width retarget four axes", sorted(w_new)))
if "bounds.size.width" in w_new and "position.y" in w_new:
    nv_w = w_new["bounds.size.width"]["velocity"]
    nv_y = w_new["position.y"]["velocity"]
    check(abs(nv_w - nv_y) > 1.0, ("width axis own travel", nv_w, nv_y))

# kick：近零行程只剩惯性 → 关键帧；轴取到 keyframe 才算走对路
kick_springs = by_axis("regular-kick-new")
kick_frames = {a["keyPath"]: a for a in anims("regular-kick-new", "CAKeyframeAnimation") if a["keyPath"] in AXES}
check(bool(kick_frames), ("kick uses keyframes", sorted(kick_frames)))
check("bounds.size.width" in kick_frames or "bounds.size.height" in kick_frames,
      ("kick on a size axis", sorted(kick_frames)))

# 减少动态效果：全无形状动画
for r in MOTION["records"]:
    if r["reduced"]:
        check(not r["animations"], (r["stage"], "reduced animations"))

# 取消：旧退场的回调不重放；新内容不被清掉。回调用聚合计数核对——完成回调在动画落定后才
# 触发，单条记录的 counts 快照可能早于落定（regular-final-closed 记录时还没到）。
final = MOTION["counts"]
check(final.get("regular-cancel-close", 0) == 0, ("expired cancel-close callback", final.get("regular-cancel-close")))
expected_one_counts = ["regular-initial", "regular-open", "regular-reverse", "regular-reopen", "regular-width",
                       "regular-width-reverse", "regular-pre-compact", "regular-rich-exit-open", "regular-rich-exit",
                       "regular-kick-open", "regular-kick", "regular-cancel-open", "regular-cancel-reopen",
                       "regular-final-close", "reduced-rm-open", "reduced-rm-close"]
for key in expected_one_counts:
    check(final.get(key, 0) == 1, ("callback count", key, final.get(key)))
check(all(v <= 1 for v in final.values()), ("no double callbacks", final))
reopen_new = records["regular-cancel-reopen-new"]
reopen_settled = records["regular-cancel-reopen-settled"]
check(reopen_new["currentIdentity"] != None and reopen_new["currentIdentity"] == reopen_settled["currentIdentity"],
      "cancel keeps new content")
check(reopen_settled["tileIDs"] == [{"id": 901}], ("reopen tiles", reopen_settled["tileIDs"]))
check(reopen_settled["pendingExit"] is False, "pendingExit cleared")

# 富内容延迟：形状实际开始比呼叫晚一拍（0.10 淡出 + 0.04）
rich_call = records["regular-rich-exit-old"]["time"]
rich_new = records["regular-rich-exit-new"]
starts = [a["beginTime"] for a in rich_new["animations"] if a["keyPath"] in AXES]
check(starts and min(starts) - rich_call > 0.12, ("rich delayed start", (min(starts) - rich_call) if starts else None))

# 轨迹：分段解析预测对照实测呈现层。目标切换前按旧弹簧解、切换后按新动画解（弹簧积分解
# 或 kick 关键帧插值），逐样本比对中点高度。这是位置/速度连续（含反向、再次改向、富内容
# 延迟起点、kick 惯性）的直接实机证据：任何方向跳变都会让预测与实测分离。
FLIGHTS = [
    ("regular-open-flight", "regular-open-old", "regular-open-new"),
    ("regular-reverse-flight", "regular-reverse-old", "regular-reverse-new"),
    ("regular-reopen-flight", "regular-reopen-old", "regular-reopen-new"),
    ("regular-width-flight", "regular-width-old", "regular-width-new"),
    ("regular-rich-exit-gap", "regular-rich-exit-old", "regular-rich-exit-new"),
    ("regular-kick-flight", "regular-kick-old", "regular-kick-new"),
]


def keyframe_value(a, t):
    vals, kt, dur = a["values"], a["keyTimes"], a["duration"]
    if t <= 0:
        return vals[0]
    if t >= dur:
        return vals[-1]
    f = t / dur
    for i in range(len(kt) - 1):
        if f <= kt[i + 1]:
            span = kt[i + 1] - kt[i]
            u = 0.0 if span <= 0 else (f - kt[i]) / span
            return vals[i] + (vals[i + 1] - vals[i]) * u
    return vals[-1]


traj_by_stage = {t["stage"]: t for t in MOTION["trajectory"]}
for stage, old_stage, new_stage in FLIGHTS:
    tr = traj_by_stage.get(stage)
    check(tr is not None, ("missing trajectory", stage))
    if tr is None:
        continue
    old_spring = by_axis(old_stage).get("position.y")
    new_spring = by_axis(new_stage).get("position.y")
    new_frames = {a["keyPath"]: a for a in anims(new_stage, "CAKeyframeAnimation")
                  if a["keyPath"] in AXES}.get("position.y")
    samples = [s for s in tr["samples"] if s.get("presentation")]
    check(len(samples) >= 4, (stage, "samples", len(samples)))
    worst = 0.0
    for s in samples:
        model = s["model"]
        model_mid = model["y"] + model["height"] / 2
        t = s["t"]
        if new_frames is not None and t >= new_frames["beginTime"]:
            x = keyframe_value(new_frames, t - new_frames["beginTime"])
        elif new_spring is not None and t >= new_spring["beginTime"]:
            x, _ = rk4_state(new_spring["mass"], new_spring["stiffness"], new_spring["damping"],
                             new_spring["from"], -new_spring["velocity"] * new_spring["from"],
                             t - new_spring["beginTime"])
        elif old_spring is not None:
            x, _ = rk4_state(old_spring["mass"], old_spring["stiffness"], old_spring["damping"],
                             old_spring["from"], -old_spring["velocity"] * old_spring["from"],
                             t - old_spring["beginTime"])
        else:
            check(False, (stage, "no animation to predict from"))
            continue
        worst = max(worst, abs(model_mid + x - s["midY"]))
    check(worst <= 1.0, (stage, "piecewise prediction", round(worst, 4)))

# 减少动态效果：形状不动，呈现层恒等于模型（trajectory 的 reduced 段）。
for t in MOTION["trajectory"]:
    if not t.get("reduced"):
        continue
    if "samples" not in t:
        continue
    for s in t["samples"]:
        if not s.get("presentation"):
            continue
        model = s["model"]
        check(abs(s["midY"] - (model["y"] + model["height"] / 2)) <= 1e-9,
              (t["stage"], "reduced presentation == model"))

if FAILURES:
    print(f"FAIL {len(FAILURES)} checks:")
    for f in FAILURES[:40]:
        print(" -", f)
    sys.exit(1)
print("PASS privacy 12 frames/41 rows/9 switches aligned; motion per-axis continuity via RK4; "
      "kick keyframes bounded; cancel/stale callbacks; reduced no animation; 518 current inputs")
