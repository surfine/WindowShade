#!/bin/bash
# 离开期间摘要纯逻辑：空进空出、去重、上限、顺序、区间边界、账本收账。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/away-summary-tests
swiftc -swift-version 6 -parse-as-library prototype/Core/WSL10n.swift prototype/Core/AwaySummary.swift tests/AwaySummaryTests.swift \
  -o .build/away-summary-tests/away
.build/away-summary-tests/away
