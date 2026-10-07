#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
mkdir -p .build/game-controller-probe
xcrun swiftc -module-cache-path .build/game-controller-probe/module-cache -swift-version 6 -parse-as-library tools/probes/game-controller/GameControllerProbe.swift -framework GameController -o .build/game-controller-probe/GameControllerProbe
if [[ "${1:-}" == "--build-only" && "$#" == 1 ]]; then exit 0; fi
exec .build/game-controller-probe/GameControllerProbe "$@"
