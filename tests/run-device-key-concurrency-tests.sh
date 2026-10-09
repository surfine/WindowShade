#!/bin/bash
# S06：设备密钥并发创建串行化；进程内换回移出主线程。纯本地，不碰 Secure Enclave、Touch ID 和真实更新状态。
# InProcessRestore 从 App/UpdaterLaunch.swift 里原样截出（那个文件其余部分依赖整套更新器），截不到就失败。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
WORK=$(mktemp -d "$(pwd)/.build/device-key-concurrency.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
MARK='// MARK: - 进程内换回：后台串行、只许一份'
grep -qF "$MARK" prototype/App/UpdaterLaunch.swift || { echo "UpdaterLaunch.swift 里找不到 InProcessRestore 段" >&2; exit 2; }
{ echo 'import Foundation'; awk -v m="$MARK" 'index($0, m) { on = 1 } on' prototype/App/UpdaterLaunch.swift; } > "$WORK/InProcessRestore.swift"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/App/DeviceAuthorizationKey.swift "$WORK/InProcessRestore.swift" tests/DeviceKeyConcurrencyTests.swift \
  -o "$WORK/device-key-concurrency"
"$WORK/device-key-concurrency"
