#!/bin/bash
# 有人在看：私人窗口收进刘海的纯逻辑（策略时序、停手 30 秒门槛、名单为空不开相机、亲手放回冷却、账本）。不开相机。
# 用法：bash tests/run-bystander-tuck-tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/bystander-tuck-tests
swiftc -typecheck -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/Core/BystanderPolicy.swift prototype/Core/PrivateAppList.swift
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/Core/BystanderPolicy.swift prototype/Core/PrivateAppList.swift tests/BystanderTuckTests.swift \
  -o .build/bystander-tuck-tests/tuck
.build/bystander-tuck-tests/tuck
