#!/bin/bash
# 终端回跳（A1）：身份校验、TERM_PROGRAM 认 App、tty/目录匹配、tmux 参数。纯 Foundation 逻辑，无权限、无 UI、无网络、不起进程。
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.build/terminal-binding-tests"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$root/prototype/Core/WSL10n.swift" "$root/prototype/Core/PrivacyPaneName.swift" \
  "$root/prototype/Core/WireJSON.swift" "$root/prototype/Core/UsageReading.swift" "$root/prototype/Core/NotchActivities.swift" "$root/prototype/Core/ReleaseDefaults.swift" \
  "$root/prototype/Core/TerminalIdentity.swift" "$root/prototype/Core/TerminalBinding.swift" "$root/tests/TerminalBindingTests.swift" \
  -o "$root/.build/terminal-binding-tests/tests"
exec "$root/.build/terminal-binding-tests/tests"
