#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/liveness-tests
swiftc -parse-as-library tools/liveness-lab/LivenessChallenge.swift tests/LivenessChallengeTests.swift \
  -o .build/liveness-tests/challenge
.build/liveness-tests/challenge
