#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .build/ws2-mouth
swiftc -module-cache-path .build/ws2-mouth/cache -swift-version 6 -warnings-as-errors -parse-as-library \
 prototype/Core/WS2SilentCatalog.swift prototype/Core/WS2SilentPhrases.swift prototype/Core/WS2MouthTemplates.swift tools/probes/MouthProfileTool.swift -o .build/ws2-mouth/profile
exec .build/ws2-mouth/profile "$@"
