#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/behavior-tests
swiftc -parse-as-library tools/behavior-lab/TimingFeatures.swift tools/behavior-lab/BehaviorRisk.swift \
  tests/BehaviorRiskTests.swift -o .build/behavior-tests/risk
.build/behavior-tests/risk
