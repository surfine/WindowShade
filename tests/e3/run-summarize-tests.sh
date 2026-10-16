#!/bin/bash
# E3 摘要解析器的离线自测：用手写的 xctrace 导出样子（含 ref= 去重引用）喂 summarize.py，不录制、不开窗口。
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d -t e3-sum); trap 'rm -rf "$T"' EXIT
X=$T/new-1.xml; mkdir -p "$X"
cat > "$X/toc.xml" <<'XML'
<?xml version="1.0"?><trace-toc><run number="1"><info><summary><duration>15.2</duration></summary></info><data><table schema="hitches"/><table schema="hitches-frame-lifetimes"/></data></run></trace-toc>
XML
cat > "$X/hitches.xml" <<'XML'
<?xml version="1.0"?><trace-query-result><node xpath="x"><schema name="hitches"><col><mnemonic>start</mnemonic></col><col><mnemonic>duration</mnemonic></col><col><mnemonic>process</mnemonic></col><col><mnemonic>is-system</mnemonic></col></schema>
<row><start-time id="1" fmt="00:01">1000000000</start-time><duration id="2" fmt="33 ms">33000000</duration><process id="3" fmt="WindowShade (123)"/><boolean id="4">0</boolean></row>
<row><start-time id="5" fmt="00:02">2000000000</start-time><duration id="6" fmt="50 ms">50000000</duration><process ref="3"/><boolean ref="4"/></row>
<row><start-time id="7" fmt="00:03">3000000000</start-time><duration ref="2"/><process id="8" fmt="GlanceFixture (9)"/><boolean ref="4"/></row>
</node></trace-query-result>
XML
cat > "$X/hitches-frame-lifetimes.xml" <<'XML'
<?xml version="1.0"?><trace-query-result><node xpath="x"><schema name="hitches-frame-lifetimes"><col><mnemonic>start</mnemonic></col><col><mnemonic>duration</mnemonic></col><col><mnemonic>process</mnemonic></col></schema>
<row><start-time id="1" fmt="a">0</start-time><duration id="2" fmt="8 ms">8000000</duration><process id="3" fmt="WindowShade (123)"/></row>
<row><start-time id="4" fmt="b">1</start-time><duration id="5" fmt="16 ms">16000000</duration><process ref="3"/></row>
<row><start-time id="6" fmt="c">2</start-time><duration id="7" fmt="40 ms">40000000</duration><process ref="3"/></row>
</node></trace-query-result>
XML
printf 'press  1 t=1.0 before[h=1 a=1] after[h=1 a=1] UNCHANGED\npress  2 t=2.0 before[h=1 a=1] after[h=30 a=1] changed\n' > "$T/p.log"
python3 -I "$HERE/summarize.py" summarize "$X" new-1 "$T" --process WindowShade --press-log "$T/p.log"
python3 -I "$HERE/summarize.py" report "$T"
python3 - "$T/new-1.summary.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
want = {"hitch_count": 2, "worst_hitch_ms": 50.0, "hitch_total_ms": 83.0, "frame_count": 3, "frame_max_ms": 40.0, "presses": 2, "presses_changed": 1, "system_hitch_count": 0}
bad = {k: (r.get(k), v) for k, v in want.items() if r.get(k) != v}
print("FAIL parser mismatch (got, want): %s" % bad if bad else "PASS summarize.py parser fixture")
sys.exit(1 if bad else 0)
PY
grep -q '^| new ' "$T/summary.md" && echo "PASS report table"
