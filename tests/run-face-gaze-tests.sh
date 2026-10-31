#!/bin/bash
# 注视（决定 75）：合成特征点 → 开度与瞳孔偏移、五点校准拟合与拒绝、校准那一步、锁屏判定（回滞、眨眼、闭眼、没校准）、
# 钥匙串编码与 Touch ID 目标、录脸流程里的校准。纯逻辑 + 真的账本，不碰相机、Vision、钥匙串和界面。
# 另做静态检查：注视只读数字（不存图像或特征点），代填那一侧的注视来自扫描报告。
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=.build/face-gaze-tests
mkdir -p "$OUT"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/Core/SessionLockState.swift \
  prototype/Core/AuthorizationModels.swift prototype/Core/IdentityEvidence.swift prototype/Core/AuthorizationLedger.swift \
  prototype/Core/FaceCaptureQuality.swift prototype/Core/FaceScanGuard.swift prototype/Core/FaceTemplateSet.swift \
  prototype/Core/GazeAttention.swift prototype/Core/FaceEnrollmentFlow.swift tests/GazeAttentionTests.swift \
  -o "$OUT/gaze"
"$OUT/gaze"

fail() { echo "FAIL $1"; exit 1; }
# 1. Core 的注视文件不碰相机、Vision、钥匙串、界面。
! grep -nE '^import (AVFoundation|Vision|Security|AppKit|Cocoa)' prototype/Core/GazeAttention.swift \
  || fail "GazeAttention.swift imports a framework it must not touch"
# 2. 钥匙串里存的校准只有系数（GazeCalibration 的字段），没有样本或特征点。
fields=$(sed -n '/^struct GazeCalibration:/,/^}/p' prototype/Core/GazeAttention.swift | grep -E '^    var [a-zA-Z]+: [^{]*$' | sed -E 's/^    var ([a-zA-Z]+):.*/\1/' | sort | tr '\n' ' ')
[[ "$fields" == "format mean openEyeReference residual scale weightsX weightsY " ]] \
  || fail "GazeCalibration stores more than coefficients: $fields"
# 3. 代填那一侧的注视来自扫描报告（不再写死 .unknown）。
grep -q 'gaze: { $0.gaze }' prototype/App/FaceAutofillController.swift || fail "autofill gaze is not wired to the scan report"
# 4. 日志里不插值注视的数值。
! grep -nE 'log\(.*\\\((gaze\.(features|calibration)|.*predict|.*openness)' prototype/App/FaceScanExperiment.swift \
  || fail "a log line interpolates gaze values"
echo "PASS face-gaze static gates"
