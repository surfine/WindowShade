set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO=$(CDPATH= cd -- "$HERE/../.." && pwd)
OUT=${1:?请提供显式输出路径}
# WS2UnixSocket 用 WS2AtomicConfiguration 的根级链接规范化（macOS 上 /var 是符号链接），一起编。
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library "$REPO/prototype/Support/WS2AtomicConfiguration.swift" "$REPO/prototype/Support/WS2HookConfiguration.swift" "$REPO/prototype/Support/WS2UnixSocket.swift" "$REPO/prototype/Support/WS2BoundedInput.swift" "$HERE/main.swift" -o "$OUT"
