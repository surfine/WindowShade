#!/bin/bash
# 给一份观察 JSON 分级。不扫描蓝牙，不改正在使用的 run-probe.sh。
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .build/device-evidence
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WS2DeviceEvidence.swift tools/probes/DeviceEvidenceGrade.swift \
  -o .build/device-evidence/grade
.build/device-evidence/grade
