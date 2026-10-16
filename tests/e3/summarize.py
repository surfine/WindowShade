#!/usr/bin/env python3
"""E3：把 xctrace 的 Animation Hitches 导出成小摘要（不依赖第三方库）。

三个子命令：
  export <trace> <xml 目录>           用 xctrace export 把卡顿相关的表导成 XML（先导 TOC，再按表名挑）
  summarize <xml 目录> <标签> <输出目录> [--process 名字] [--press-log 文件] [--meta 文件]
                                      读 XML，写 <标签>.summary.json（卡顿次数、最长一次、p95 帧时间、hitch 时间比）
  report <输出目录>                   把目录里所有 *.summary.json 合成 summary.md（按构建分组，取中位数）

表结构按 xctrace 的 <schema><col><mnemonic> 顺序对列，行里的 ref= 引用按 id= 还原；
没有哪一列就在摘要里写 null，并在 notes 里说明，不编数。
"""
import json, os, re, statistics, subprocess, sys, xml.etree.ElementTree as ET

HITCH_SCHEMAS = ("hitches",)
FRAME_SCHEMAS = ("hitches-frame-lifetimes", "hitches-renders", "hitches-updates")


def run_export(args):
    return subprocess.run(["xcrun", "xctrace", "export", *args], capture_output=True, text=True)


def cmd_export(trace, xmldir):
    os.makedirs(xmldir, exist_ok=True)
    toc = os.path.join(xmldir, "toc.xml")
    r = run_export(["--input", trace, "--toc", "--output", toc])
    if r.returncode != 0 or not os.path.exists(toc):
        print("FAIL export toc: " + (r.stderr or r.stdout).strip()[:300])
        return 1
    schemas = []
    for t in ET.parse(toc).getroot().iter("table"):
        s = t.get("schema")
        if s and s not in schemas:
            schemas.append(s)
    print("INFO schemas: " + ",".join(schemas))
    wanted = [s for s in schemas if s in HITCH_SCHEMAS + FRAME_SCHEMAS]
    if not wanted:
        print("FAIL no hitch tables in trace")
        return 1
    for s in wanted:
        out = os.path.join(xmldir, s + ".xml")
        r = run_export(["--input", trace, "--xpath", f'/trace-toc/run[@number="1"]/data/table[@schema="{s}"]', "--output", out])
        print(("PASS" if r.returncode == 0 and os.path.exists(out) else "FAIL") + f" export {s}")
    return 0


def read_table(path):
    """返回 [{mnemonic: 文本或 None}]；只认第一个 schema 的列顺序。"""
    ids, rows, cols = {}, [], None
    for ev, el in ET.iterparse(path, events=("end",)):
        if el.tag == "schema" and cols is None:
            cols = [(c.findtext("mnemonic") or "").strip() for c in el.iter("col")]
        elif el.tag == "row":
            row = {}
            for i, child in enumerate(list(el)):
                key = cols[i] if cols and i < len(cols) else f"c{i}"
                txt = (child.text or "").strip()
                if not txt and child.get("fmt"):
                    txt = ""  # 嵌套对象（进程等）：fmt 当文本用
                ident, ref = child.get("id"), child.get("ref")
                fmt = child.get("fmt") or ""
                if ref is not None and ref in ids:
                    txt, fmt = ids[ref]
                if ident is not None:
                    ids[ident] = (txt, fmt)
                row[key] = (txt, fmt)
            rows.append(row)
            el.clear()
    return rows


def num(v):
    try:
        return float(v[0])
    except (TypeError, ValueError, IndexError):
        return None


def pick(row, *names):
    for n in names:
        if n in row:
            return row[n]
    return None


def percentile(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    k = (len(xs) - 1) * p
    lo, hi = int(k), min(int(k) + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def toc_duration_s(xmldir):
    try:
        for d in ET.parse(os.path.join(xmldir, "toc.xml")).getroot().iter("duration"):
            v = float((d.text or "").strip())
            return v
    except Exception:
        pass
    return None


def cmd_summarize(xmldir, tag, outdir, process=None, press_log=None, meta=None):
    notes, res = [], {"tag": tag}
    res["build"] = tag.split("-")[0]
    # 卡顿表
    hp = os.path.join(xmldir, "hitches.xml")
    hitches = read_table(hp) if os.path.exists(hp) else []
    if not os.path.exists(hp):
        notes.append("no hitches table")

    def mine(row):
        if not process:
            return True
        p = pick(row, "process", "proc")
        return p is None or process.lower() in (p[1] + p[0]).lower()

    hs = [h for h in hitches if mine(h)]
    ds = [num(pick(h, "duration", "hitch-duration")) for h in hs]
    ds = [d / 1e6 for d in ds if d is not None]  # ns -> ms
    sysflag = [h for h in hs if (pick(h, "is-system", "system") or ("", ""))[0] in ("1", "true")]
    res["hitch_count"] = len(ds)
    res["system_hitch_count"] = len(sysflag) if any(("is-system" in h or "system" in h) for h in hs) else None
    res["worst_hitch_ms"] = round(max(ds), 2) if ds else (0.0 if os.path.exists(hp) else None)
    res["hitch_total_ms"] = round(sum(ds), 2) if ds else (0.0 if os.path.exists(hp) else None)
    dur = toc_duration_s(xmldir)
    res["trace_seconds"] = round(dur, 2) if dur else None
    res["hitch_ms_per_s"] = round(sum(ds) / dur, 3) if ds and dur else (0.0 if dur and os.path.exists(hp) else None)
    # 帧时间：按优先级取第一张有 duration 的表
    res["frame_source"], res["frame_count"], res["frame_p95_ms"], res["frame_max_ms"] = None, 0, None, None
    for s in FRAME_SCHEMAS:
        fp = os.path.join(xmldir, s + ".xml")
        if not os.path.exists(fp):
            continue
        fr = [f for f in read_table(fp) if mine(f)]
        fd = [num(pick(f, "duration", "frame-duration", "lifetime")) for f in fr]
        fd = [d / 1e6 for d in fd if d is not None]
        if fd:
            res["frame_source"], res["frame_count"] = s, len(fd)
            res["frame_p95_ms"], res["frame_max_ms"] = round(percentile(fd, 0.95), 2), round(max(fd), 2)
            break
    if res["frame_source"] is None:
        notes.append("no frame duration table; p95 unavailable")
    elif res["frame_source"] != "hitches-frame-lifetimes":
        notes.append(f"frame time taken from {res['frame_source']}")
    # 按键日志：证明收起/展开真的发生过
    if press_log and os.path.exists(press_log):
        lines = [l for l in open(press_log, errors="replace") if l.startswith("press")]
        res["presses"] = len(lines)
        res["presses_changed"] = sum(1 for l in lines if re.search(r" changed\s*$", l))
        if lines and res["presses_changed"] == 0:
            notes.append("hotkey never changed fixture window; run is not a valid comparison")
    if meta and os.path.exists(meta):
        res["meta"] = [l.strip() for l in open(meta, errors="replace")]
    res["notes"] = notes
    os.makedirs(outdir, exist_ok=True)
    path = os.path.join(outdir, tag + ".summary.json")
    json.dump(res, open(path, "w"), ensure_ascii=False, indent=2)
    print(f"PASS summary {path}")
    print("INFO " + json.dumps({k: res[k] for k in ("hitch_count", "worst_hitch_ms", "frame_p95_ms", "hitch_ms_per_s", "presses_changed") if k in res}))
    return 0


def cmd_report(outdir):
    runs = [json.load(open(os.path.join(outdir, f))) for f in sorted(os.listdir(outdir)) if f.endswith(".summary.json")]
    if not runs:
        print("FAIL no summaries")
        return 1

    def med(rs, k):
        v = [r[k] for r in rs if r.get(k) is not None]
        return round(statistics.median(v), 2) if v else None

    lines = ["# E3 卡顿对比", "", "| 构建 | 轮数 | 卡顿次数(中位) | 最长卡顿 ms(中位) | 最长卡顿 ms(最大) | p95 帧时间 ms(中位) | hitch ms/s(中位) | 有效按键 |", "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for b in sorted({r["build"] for r in runs}):
        rs = [r for r in runs if r["build"] == b]
        worst = [r["worst_hitch_ms"] for r in rs if r.get("worst_hitch_ms") is not None]
        eff = "/".join(f'{r.get("presses_changed", "?")}of{r.get("presses", "?")}' for r in rs)
        lines.append(f"| {b} | {len(rs)} | {med(rs, 'hitch_count')} | {med(rs, 'worst_hitch_ms')} | {max(worst) if worst else None} | {med(rs, 'frame_p95_ms')} | {med(rs, 'hitch_ms_per_s')} | {eff} |")
    lines += ["", "## 逐轮", ""]
    for r in runs:
        lines.append(f"- {r['tag']}: hitches={r['hitch_count']} worst={r['worst_hitch_ms']}ms p95={r['frame_p95_ms']}ms({r['frame_source']}) ms/s={r['hitch_ms_per_s']} presses={r.get('presses_changed', '?')}/{r.get('presses', '?')} notes={'; '.join(r['notes']) or '-'}")
    open(os.path.join(outdir, "summary.md"), "w").write("\n".join(lines) + "\n")
    print("PASS report " + os.path.join(outdir, "summary.md"))
    return 0


def main(a):
    if len(a) >= 3 and a[0] == "export":
        return cmd_export(a[1], a[2])
    if len(a) >= 4 and a[0] == "summarize":
        opts = {}
        rest = a[4:]
        for i in range(0, len(rest) - 1, 2):
            opts[rest[i].lstrip("-").replace("-", "_")] = rest[i + 1]
        return cmd_summarize(a[1], a[2], a[3], opts.get("process"), opts.get("press_log"), opts.get("meta"))
    if len(a) >= 2 and a[0] == "report":
        return cmd_report(a[1])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
