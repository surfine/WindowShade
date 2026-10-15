#!/bin/bash
# 来处推断询问（两次才问、每个来处一次、小叉后不再问）。纯逻辑，不碰用户的设置。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/origin-guess-tests
swiftc -parse-as-library prototype/Core/SwitcherOrigin.swift prototype/Core/GestureCoach.swift \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/Core/HabitRules.swift tests/OriginGuessTests.swift -o .build/origin-guess-tests/guess
.build/origin-guess-tests/guess
