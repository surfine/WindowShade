#!/usr/bin/env bash
# 锁屏分层露出（决定 68）与「认你」指示的纯规则测试，加上第 5 步的静态门：
# 认你不再是独立浮窗（FaceScanStatusController 不在了，刷脸相关的窗口都不是 .floating），
# 锁屏上那一层只走 LockSpaceBridge、只拿 .faceRecognition 的锁屏租约。不碰 AppKit 运行时，不锁屏。
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "FAIL $*" >&2; exit 1; }
. tests/support/rg-none.sh
OUT=.build/lock-screen-exposure-tests
mkdir -p "$OUT"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/Contracts.swift prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/Core/WireJSON.swift \
  prototype/Core/UsageReading.swift prototype/Core/NotchActivities.swift prototype/Core/IslandMetrics.swift \
  prototype/Core/ReleaseDefaults.swift prototype/Core/SessionLockState.swift prototype/Core/LockScreenExposure.swift \
  tests/support/WS2TestSupport.swift tests/LockScreenExposureTests.swift -o "$OUT/exposure"
"$OUT/exposure"

# 静态门。
[ ! -e prototype/App/FaceScanStatusController.swift ] || fail "FaceScanStatusController.swift still exists"
rg_none -n "FaceScanStatusController|FaceScanStatusView|faceScanStatus" prototype -g '*.swift' || fail "old floating indicator still referenced"
rg_none -n "level *= *\.floating|desktop: false\)" prototype/App/NotchFaceRecognition.swift prototype/App/FaceScan*.swift \
    prototype/App/FaceFill*.swift prototype/App/FaceEnrollmentHost.swift || fail "a face window is still .floating"
rg -q "bridge.attach\(panel\)" prototype/App/NotchFaceRecognition.swift || fail "lock layer does not go through LockSpaceBridge"
rg -q "acquireLockScreen\(\.faceRecognition" prototype/App/NotchFaceRecognition.swift || fail "lock layer does not take the lock-screen lease"
rg -q "case \.authorization, \.agentReview, \.faceRecognition: return \.authorization" prototype/App/NotchLeases.swift \
  || fail "faceRecognition is not on the authorization layer"
rg -q "faceRecognition.show\(phase\)" prototype/App/FaceScanExperiment.swift || fail "scan phases do not reach the notch host"
# D11 代填这一步不碰：认你那一层不输入任何东西。
rg_none -n "CGEvent|keyboardSetUnicodeString|postToPid|SecItemCopyMatching|LAContext" prototype/App/NotchFaceRecognition.swift \
  prototype/Core/LockScreenExposure.swift || fail "recognise layer touches input or secrets"
echo "PASS lock-screen-exposure static gates"
