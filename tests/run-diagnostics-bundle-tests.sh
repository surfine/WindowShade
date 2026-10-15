#!/bin/bash
# 规格 R35／R13：本地诊断包的纯逻辑。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/diagnostics-bundle-tests
swiftc -O -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/DiagnosticsBundle.swift tests/DiagnosticsBundleTests.swift -o .build/diagnostics-bundle-tests/run
.build/diagnostics-bundle-tests/run
