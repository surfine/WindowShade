#!/usr/bin/env bash
# 说话人比对（D11 ②）：fbank 对 torchaudio 参考值、特征编码、登记、门槛、失败即关；模型在就再跑 Core ML 端到端。
# 模型来自 ../WindowShade-models/speaker（不在仓库里）；没有就跳过端到端那一段，其余照跑。
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=.build/speaker-verification-tests
mkdir -p "$OUT"
swiftc -O -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/Contracts.swift prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/Core/WireJSON.swift \
  prototype/Core/UsageReading.swift prototype/Core/NotchActivities.swift prototype/Core/IslandMetrics.swift \
  prototype/Core/ReleaseDefaults.swift prototype/Core/SessionLockState.swift prototype/Core/LockScreenExposure.swift \
  prototype/Core/FaceCaptureQuality.swift prototype/Core/FaceIdentityAttempts.swift \
  prototype/Core/CompanionLockVerify.swift prototype/Core/GazeAttention.swift prototype/Core/FaceAutofill.swift prototype/Core/VoiceprintChallenge.swift \
  prototype/Core/SpeakerFbank.swift prototype/Core/SpeakerVerification.swift \
  tests/support/WS2TestSupport.swift tests/SpeakerVerificationTests.swift -o "$OUT/speaker"
MODELS="${WS_MODELS_DIR:-/Users/aaron/Documents/WindowShade-models/speaker}"
if [ -z "${SPEAKER_MODEL:-}" ] && [ -d "$MODELS/SpeakerEmbedding.mlpackage" ]; then
  rm -rf "$OUT/model"; mkdir -p "$OUT/model"
  xcrun coremlcompiler compile "$MODELS/SpeakerEmbedding.mlpackage" "$OUT/model" >/dev/null
  export SPEAKER_MODEL="$PWD/$OUT/model/SpeakerEmbedding.mlmodelc"
fi
"$OUT/speaker"
