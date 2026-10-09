#!/bin/bash
# M02b：刘海上一句话的排法（主句 8 字、名字中间截断、窗口变化、0.6 秒合成一句、私人 App 不露标题）。纯 Foundation。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/notch-sentence-tests
swiftc -swift-version 6 -parse-as-library prototype/Core/NotchSentence.swift tests/NotchSentenceTests.swift \
  -o .build/notch-sentence-tests/tests
.build/notch-sentence-tests/tests
