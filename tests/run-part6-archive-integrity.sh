#!/usr/bin/env bash
# 第五、六份归档与交付清单逐文件比对（哈希来自交付包自己的 FILES.sha256.json / ARTIFACTS.sha256.json）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
ok = 0
problems = []
for part, manifest in (("part6", "FILES.sha256.json"),):
    base = root / "docs/handoff/chatgpt-review-2" / part
    data = json.loads((base / manifest).read_text())
    for rel, expected in data.items():
        path = base / rel
        if not path.is_file():
            problems.append(f"{part}:{rel}: missing"); continue
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected:
            problems.append(f"{part}:{rel}: hash mismatch"); continue
        ok += 1
print(f"{'PASS' if not problems else 'FAIL'} archive-integrity: {ok} files verified")
for problem in problems[:10]: print(problem)
raise SystemExit(1 if problems else 0)
PY
