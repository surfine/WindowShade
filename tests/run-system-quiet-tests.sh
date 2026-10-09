#!/usr/bin/env bash
# R03：共享屏幕、录屏、专注模式时收敛。真值表、共享时卡住提示静默、专注时第 4 层只留点。不碰真机，不读私有符号的真值。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/system-quiet-tests"
mkdir -p "$OUT"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" \
  "$ROOT/prototype/Core/InteractionCoordinator.swift" \
  "$ROOT/prototype/Core/SwitcherOrigin.swift" \
  "$ROOT/prototype/Core/GestureCoach.swift" \
  "$ROOT/prototype/Core/WSL10n.swift" \
  "$ROOT/prototype/Core/HabitRules.swift" \
  "$ROOT/prototype/App/SystemQuietState.swift" \
  "$ROOT/tests/SystemQuietStateTests.swift" -o "$OUT/system-quiet-tests"
"$OUT/system-quiet-tests"
