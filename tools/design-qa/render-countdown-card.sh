#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT="${1:?Pass an absolute output directory}"
CARD="${2:-$ROOT/prototype/App/CountdownTimerCard.swift}"
WORK="$(mktemp -d "$ROOT/.build/countdown-preview.XXXXXX")"
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
(work / 'CountdownTimerCard.swift').write_text(card.read_text().split('/// 把计时器宿主、刘海的展示租约和卡片接在一起。')[0])
sources = [card, auth, lease, root/'prototype/Core/Contracts.swift', root/'prototype/Core/CountdownTimer.swift',
           root/'prototype/App/CountdownTimerHost.swift', root/'tools/design-qa/CountdownTimerCardPreview.swift',
           root/'tools/design-qa/render-countdown-card.sh']
output.mkdir(parents=True, exist_ok=True)
(output/'sources.json').write_text(json.dumps({str(p.relative_to(root)) if p.is_relative_to(root) else str(p):
    hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}, indent=2) + '\n')
PY
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/CountdownTimer.swift" \
  "$ROOT/prototype/App/CountdownTimerHost.swift" "$WORK/ContentProtocols.swift" "$WORK/CountdownTimerCard.swift" \
  "$ROOT/tools/design-qa/CountdownTimerCardPreview.swift" -o "$WORK/render"
"$WORK/render" "$OUTPUT"
