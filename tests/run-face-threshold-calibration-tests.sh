#!/usr/bin/env bash
# 刷脸门槛标定：尾部拟合数学、门槛选择、标定结果校验、闸门“有标定才算标定过”、录制计划、本人样本文件权限。
# 纯逻辑；不碰相机、钥匙串、Vision。再加两条静态门：标定存储走钥匙串且不同步；Core 的标定逻辑不碰文件以外的系统。
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "FAIL $*" >&2; exit 1; }
. tests/support/rg-none.sh
OUT=.build/face-threshold-calibration-tests
mkdir -p "$OUT"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/Contracts.swift prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/Core/WireJSON.swift \
  prototype/Core/UsageReading.swift prototype/Core/NotchActivities.swift prototype/Core/IslandMetrics.swift \
  prototype/Core/ReleaseDefaults.swift prototype/Core/SessionLockState.swift prototype/Core/LockScreenExposure.swift \
  prototype/Core/FaceCaptureQuality.swift prototype/Core/FaceIdentityAttempts.swift \
  prototype/Core/CompanionLockVerify.swift prototype/Core/GazeAttention.swift prototype/Core/FaceAutofill.swift prototype/Core/VoiceprintChallenge.swift \
  prototype/Core/FaceScanGuard.swift prototype/Core/FaceTemplateSet.swift prototype/Core/FaceThresholdCalibration.swift \
  tests/support/WS2TestSupport.swift tests/FaceThresholdCalibrationTests.swift -o "$OUT/calibration"
"$OUT/calibration"

# 静态门。
rg -q "kSecAttrSynchronizable as String: false" prototype/App/FaceThresholdCalibrationStore.swift || fail "calibration item may sync"
rg -q "kSecAttrAccessibleWhenUnlockedThisDeviceOnly" prototype/App/FaceThresholdCalibrationStore.swift || fail "calibration item is not device-only"
rg_none -n "UserDefaults" prototype/App/FaceThresholdCalibrationStore.swift prototype/Core/FaceThresholdCalibration.swift \
  || fail "calibration must not fall back to preferences"
# 录制只存特征数字：录制文件里没有任何图像类型。
rg_none -n "CGImage|CIContext|pngData|tiffRepresentation" prototype/App/FaceCalibrationRecorder.swift \
  || fail "recorder touches image output"
echo "PASS face-threshold-calibration static gates"
