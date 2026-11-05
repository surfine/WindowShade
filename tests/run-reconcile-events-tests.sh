#!/bin/bash
# 折叠会话核对的事件触发规则（纯逻辑），不需要图形会话。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/reconcile-events-tests
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/Support/SkyLightFramework.swift prototype/Support/MainTimer.swift \
  prototype/Private/SkyLightNotify.swift prototype/Window/WindowStateHub.swift \
  prototype/Core/ReconcileEvents.swift tests/ReconcileEventsTests.swift \
  -framework Cocoa -o .build/reconcile-events-tests/tests
.build/reconcile-events-tests/tests
