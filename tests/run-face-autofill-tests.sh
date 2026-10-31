#!/usr/bin/env bash
# 第 6 步（D11 代填与声纹）：闸门真值表、3 次上限、手表与声纹都不能单独放行、密码会话清除、短语挑战、攻击矩阵。
# 再加静态门：密码只在 App/UnlockPassword*.swift 与 App/LockScreenPasswordEntry.swift 里出现；日志不带密码；
# 认你那一层（第 5 步）仍不碰输入和秘密；攻击矩阵 JSON 与 Swift 表一致。不碰 AppKit 运行时，不锁屏，不读钥匙串。
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "FAIL $*" >&2; exit 1; }
OUT=.build/face-autofill-tests
mkdir -p "$OUT"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/Contracts.swift prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/Core/WireJSON.swift \
  prototype/Core/UsageReading.swift prototype/Core/NotchActivities.swift prototype/Core/IslandMetrics.swift \
  prototype/Core/ReleaseDefaults.swift prototype/Core/SessionLockState.swift prototype/Core/LockScreenExposure.swift \
  prototype/Core/FaceCaptureQuality.swift prototype/Core/FaceIdentityAttempts.swift \
  prototype/Core/CompanionLockVerify.swift prototype/Core/GazeAttention.swift prototype/Core/FaceAutofill.swift prototype/Core/VoiceprintChallenge.swift \
  tests/support/WS2TestSupport.swift tests/FaceAutofillTests.swift -o "$OUT/autofill"
"$OUT/autofill"

# 静态门。
# 1) 代填的键盘输入只在一个文件里；认你那一层和闸门里没有。
# 代填打字用 keyboardSetUnicodeString；别处已有的这种调用（如果有）不在这份名单里就失败。
sites=$(rg -l "keyboardSetUnicodeString" prototype -g '*.swift' | sort | tr '\n' ' ' || true)
[ "$sites" = "prototype/App/LockScreenPasswordEntry.swift " ] || fail "unicode keystroke posting outside LockScreenPasswordEntry.swift: $sites"
! rg -n "CGEvent|keyboardSetUnicodeString|postToPid|SecItemCopyMatching|LAContext" prototype/App/NotchFaceRecognition.swift \
  prototype/Core/LockScreenExposure.swift prototype/Core/FaceAutofill.swift || fail "recognise layer or gate touches input or secrets"
# 2) 生物识别保护的钥匙串项：biometryCurrentSet + 仅本机。
rg -q "\.biometryCurrentSet" prototype/App/UnlockPasswordKeychainStore.swift || fail "password item is not biometryCurrentSet"
rg -q "kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly" prototype/App/UnlockPasswordKeychainStore.swift \
  || fail "password item is not device-only"
rg -q "kSecAttrSynchronizable as String: false" prototype/App/UnlockPasswordKeychainStore.swift || fail "password item may sync"
# 3) 日志里不出现密码：代填相关文件的 wlog/log 行不插值 secret/password/bytes。
! rg -n "(wlog|log)\(.*\\\\\((secret|password|bytes|phrase|heard)" prototype/App/FaceAutofillController.swift \
  prototype/App/UnlockPasswordKeychainStore.swift prototype/App/LockScreenPasswordEntry.swift \
  prototype/App/FaceAutofillSettings.swift || fail "a log line interpolates a secret"
# 4) 占位的说话人比对永远失败。
rg -q "func verify\(sample: \[Float\], purpose: VoiceprintPurpose\) -> SpeakerVerdict \{ \.unavailable \}" \
  prototype/Core/VoiceprintChallenge.swift || fail "placeholder verifier no longer fails closed"
# 5) 攻击矩阵：JSON（Aaron 在真机上填）与 Swift 表一致。
python3 - <<'PY' || fail "attack matrix JSON and FaceAttackMatrix.current disagree"
import json, re, sys
rows = json.load(open("tools/probes/face-attack-matrix.json"))["attacks"]
want = ["photo", "phone-screen", "video", "different-person", "different-phone"]
assert [r["id"] for r in rows] == want, [r["id"] for r in rows]
src = open("prototype/Core/VoiceprintChallenge.swift").read()
all_not_run = "Attack.allCases.map { Row(attack: $0, status: .notRun, evidence: nil) }" in src
for r in rows:
    assert r["status"] in ("not_run", "blocked", "not_blocked", "inconclusive"), r
    if r["status"] != "not_run":
        assert r.get("evidence"), ("result without evidence", r)
        assert not all_not_run, ("JSON has a device result but Swift still says all not_run", r)
    elif not all_not_run:
        assert re.search(r'Row\(attack: \.%s, status: \.notRun' % re.sub(r'-(.)', lambda m: m[1].upper(), r["id"]), src), r
print("PASS attack matrix json/swift in sync")
PY
echo "PASS face-autofill static gates"
