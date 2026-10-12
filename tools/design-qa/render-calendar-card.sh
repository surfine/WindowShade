#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT="${1:?Pass an absolute output directory}"
CARD="${2:-$ROOT/prototype/App/CalendarPresenter.swift}"
WORK="$(mktemp -d "$ROOT/.build/calendar-preview.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
python3 - "$ROOT" "$WORK" "$CARD" "$OUTPUT" <<'PY'
from pathlib import Path
import sys, hashlib, json
root, work, card, output = map(Path, sys.argv[1:])
auth = root / 'prototype/App/NotchAuthentication.swift'
lease = root / 'prototype/App/NotchLeases.swift'
protocol = next(line for line in auth.read_text().splitlines() if line.startswith('@MainActor protocol NotchInteractiveContent:'))
content = lease.read_text().split('/// 刘海唯一的展示仲裁')[0]
(work / 'ContentProtocols.swift').write_text('import Cocoa\n' + protocol + '\n' + content)
(work / 'CalendarPresenter.swift').write_text('import Cocoa\nimport QuartzCore\n' + card.read_text().split('// MARK: - 图\n')[1].split('// MARK: - 接线')[0])
sources = [card, auth, lease, root/'prototype/Core/CalendarActivity.swift', root/'prototype/Core/CalendarPresentation.swift', root/'tools/design-qa/CalendarCardPreview.swift',
           root/'tools/design-qa/render-calendar-card.sh']
output.mkdir(parents=True, exist_ok=True)
(output/'sources.json').write_text(json.dumps({str(p.relative_to(root)) if p.is_relative_to(root) else str(p):
    hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}, indent=2) + '\n')
PY
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/CalendarActivity.swift" "$ROOT/prototype/Core/CalendarPresentation.swift" \
  "$WORK/ContentProtocols.swift" "$WORK/CalendarPresenter.swift" \
  "$ROOT/tools/design-qa/CalendarCardPreview.swift" -o "$WORK/render"
"$WORK/render" "$OUTPUT"
