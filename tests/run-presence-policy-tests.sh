#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.build/presence-policy-tests"
swiftc "$root/tools/presence-probe/PresencePolicy.swift" "$root/tests/PresencePolicyTests.swift" -o "$root/.build/presence-policy-tests/tests"
exec "$root/.build/presence-policy-tests/tests"
