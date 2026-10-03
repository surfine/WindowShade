#!/usr/bin/env bash
# 第三份的纯核：配对限流与 TLV、认证后的事件路由、手柄映射、HID 写入事务、
# 多触点准入、输入资格、锁来源策略、配置事务、有界输入与 Unix socket。
# 证据与逐例结果保留在 docs/handoff/chatgpt-review-2/part3/。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/part3-core"
mkdir -p "$BUILD"
# 与第三份自己的 run-core.sh 同一份清单：三份的纯核 + 这次新加的状态核与支持层。
CORE=(
  Contracts ConductorGesture AgentSessions ConductorSession ConductorCapabilities SmoothScroll InputDeviceKind
  MiddleDrag TouchTap SiriRemoteButtons RemoteMode FocusNavigator PresenceLock FocusTimer
  RemoteSessionGate PresenceReadDeadline InteractionCoordinator CodexWire WS2StrictJSON PairingAttemptWindow
  PairingTLV RemoteEventRouter MultitouchQualification HIDMappingTransaction WS2InputEligibility
  GamepadMapping WS2LockRequestPolicy
)
SOURCES=()
for source in "${CORE[@]}"; do SOURCES+=("$ROOT/prototype/Core/$source.swift"); done
for source in WS2AtomicConfiguration WS2BoundedInput WS2HookConfiguration WS2ProcessChannel WS2UnixSocket; do
  SOURCES+=("$ROOT/prototype/Support/$source.swift")
done
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "${SOURCES[@]}" "$ROOT/tests/Part3CoreTests.swift" -o "$BUILD/part3-core-tests"
"$BUILD/part3-core-tests" "$ROOT" "$(command -v python3)"
