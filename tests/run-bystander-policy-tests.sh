#!/bin/bash
# 旁人一瞥的纯逻辑：轨迹配对、本人、朝向停留、遮得快放得慢。不开相机。
# 用法：bash tests/run-bystander-policy-tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/bystander-policy-tests
swiftc -typecheck -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift \
  prototype/Core/BystanderPolicy.swift
swiftc -parse-as-library -swift-version 6 -warnings-as-errors \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/Core/BystanderPolicy.swift tests/BystanderPolicyTests.swift \
  -o .build/bystander-policy-tests/bystander
.build/bystander-policy-tests/bystander
