#!/bin/bash
# 1.0.18 N1“这一版新开了这几样”（纯逻辑）：只列真变了的；启动时走 A1 / U1 → N1 / N1 哪条路。
set -euo pipefail
cd "$(dirname "$0")/.."
grep -q 'dockEnabledKey = "WindowBrowserDockEnabled"' prototype/WindowBrowser/WindowBrowserSettings.swift
mkdir -p .build/whats-new-1018-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/ReleaseDefaults.swift prototype/Core/WhatsNew1018Changes.swift \
  tests/WhatsNew1018Tests.swift -o .build/whats-new-1018-tests/tests
.build/whats-new-1018-tests/tests
