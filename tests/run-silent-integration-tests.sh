#!/bin/bash
# r00–r04。不签名、不发布、不启动正在运行的应用。
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  --case) CASE="${2:-}" ;;
  *)
    echo "usage: $0 --case r00|r01|r02|r03|r04" >&2
    exit 2
    ;;
esac

status_r00() {
  python3 - << 'PY'
import json
from pathlib import Path
data = json.loads(Path("docs/handoff/silent-v3/STATUS.json").read_text())
blob = json.dumps(data)
for banned in ("hardware_pass", "qualified", "%"):
    if banned in blob:
        raise SystemExit(f"FAIL status contains {banned}")
if not str(data.get("auditBaseline", "")).startswith("c89fe767"):
    raise SystemExit("FAIL audit baseline")
if not str(data.get("head", "")).startswith("b271fcf"):
    raise SystemExit("FAIL head")
columns = ["catalog", "port", "input", "device", "qualification", "release"]
if data.get("columns") != columns:
    raise SystemExit("FAIL columns")
print("ok   r00 status ledger")
PY
}

run_case() {
  mkdir -p .build/silent-integration-tests
  swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
    prototype/Core/Contracts.swift \
    prototype/Core/WS2SilentCatalog.swift \
    prototype/Core/WS2SilentIntent.swift \
    prototype/Core/WS2SilentSession.swift \
    prototype/Core/WS2SilentExecution.swift \
    prototype/Core/WS2DeviceEvidence.swift \
    prototype/Core/WS2HeadGesture.swift \
    prototype/Core/WS2CameraChoice.swift \
    prototype/Core/WS2ScreenDistance.swift \
    prototype/Core/WS2Posture.swift \
    prototype/Core/WS2SilentProductPort.swift \
    prototype/Core/WS2SilentDraft.swift \
    prototype/Core/WS2SilentGates.swift \
    prototype/Core/WS2SilentPhrases.swift \
    prototype/Core/WS2SilentSecurity.swift \
    prototype/Core/WS2SilentCopy.swift \
    prototype/Core/PresenceLock.swift \
    prototype/Core/WS2AwaySimulation.swift \
    prototype/Core/WS2JournalWrite.swift \
    prototype/Core/WS2HookConfigPreview.swift \
    tests/SilentIntegrationTests.swift \
    -o .build/silent-integration-tests/silent-integration
  .build/silent-integration-tests/silent-integration "$1"
}

case "$CASE" in
  r00) status_r00 ;;
  r01|r02|r03|r04) run_case "$CASE" ;;
  *)
    echo "usage: $0 --case r00|r01|r02|r03|r04" >&2
    exit 2
    ;;
esac
