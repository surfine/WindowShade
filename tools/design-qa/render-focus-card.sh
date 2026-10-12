#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT="${1:?Pass an absolute output directory}"
CARD="${2:-$ROOT/prototype/App/FocusTimerCard.swift}"
WORK="$(mktemp -d "$ROOT/.build/focus-preview.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# Extract the actual production protocols, without compiling their host implementation.
# Rendering proves this card only; build.sh --check separately verifies the full app.
python3 - "$ROOT" "$WORK" "$CARD" "$OUTPUT" <<'PY'
from pathlib import Path
import sys, hashlib, json
root, work, card, output = map(Path, sys.argv[1:])
auth = root / 'prototype/App/NotchAuthentication.swift'
lease = root / 'prototype/App/NotchLeases.swift'
protocol = next(line for line in auth.read_text().splitlines() if line.startswith('@MainActor protocol NotchInteractiveContent:'))
content = lease.read_text().split('/// 刘海唯一的展示仲裁')[0]
(work / 'ContentProtocols.swift').write_text('import Cocoa\n' + protocol + '\n' + content)
sources = [card, auth, lease, root/'prototype/Core/Contracts.swift', root/'prototype/Core/FocusTimer.swift',
           root/'prototype/App/FocusTimerHost.swift', root/'tools/design-qa/FocusTimerCardPreview.swift',
           root/'tools/design-qa/render-focus-card.sh']
output.mkdir(parents=True, exist_ok=True)
(output/'sources.json').write_text(json.dumps({str(p.relative_to(root)) if p.is_relative_to(root) else str(p):
    hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}, indent=2) + '\n')
PY
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/FocusTimer.swift" \
  "$ROOT/prototype/App/FocusTimerHost.swift" "$WORK/ContentProtocols.swift" "$CARD" \
  "$ROOT/tools/design-qa/FocusTimerCardPreview.swift" -o "$WORK/render"
"$WORK/render" "$OUTPUT"
