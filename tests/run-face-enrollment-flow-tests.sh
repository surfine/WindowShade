#!/bin/bash
# 录脸流程（ID-04）：Touch ID 确认才保存。纯逻辑 + 真的账本，不碰相机、钥匙串和界面。
# 另做静态检查：偏好键不再能换模板——App 里写模板只经 FaceEnrollmentFlow.confirm 交出的 FaceEnrollmentSave。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/face-enrollment-flow-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/SessionLockState.swift prototype/Core/AuthorizationModels.swift prototype/Core/IdentityEvidence.swift \
  prototype/Core/AuthorizationLedger.swift prototype/Core/FaceCaptureQuality.swift prototype/Core/FaceScanGuard.swift \
  prototype/Core/FaceTemplateSet.swift prototype/Core/FaceEnrollmentFlow.swift tests/FaceEnrollmentFlowTests.swift \
  -o .build/face-enrollment-flow-tests/flow
.build/face-enrollment-flow-tests/flow

fail() { echo "FAIL $1"; if [[ $# -gt 1 ]]; then printf '%s\n' "$2"; fi; exit 1; }
# 1. App 里调钥匙串写模板的地方只有一种：store.save(confirmed)，confirmed 来自 flow.confirm。
saves=$(grep -rn --include='*.swift' -E 'store\.save\(' prototype/App || true)
bad=$(printf '%s\n' "$saves" | grep . | grep -v 'store\.save(confirmed)' || true)
[[ -z "$bad" ]] || fail "templates are written without a confirmed FaceEnrollmentSave:" "$bad"
[[ -n "$saves" ]] || fail "no confirmed save site found in prototype/App"
grep -q 'let confirmed = flow.confirm(grant)' prototype/App/FaceScanExperiment.swift \
  || fail "FaceScanExperiment does not take the save from flow.confirm"
# 2. FaceEnrollmentSave 只在流程文件里造（fileprivate init）。
makers=$(grep -rn --include='*.swift' -E 'FaceEnrollmentSave\(' prototype | grep -v '^prototype/Core/FaceEnrollmentFlow.swift:' || true)
[[ -z "$makers" ]] || fail "FaceEnrollmentSave is constructed outside FaceEnrollmentFlow:" "$makers"
grep -q 'fileprivate init(modelVersion: String, templates: \[FaceTemplate\], added: Int)' prototype/Core/FaceEnrollmentFlow.swift \
  || fail "FaceEnrollmentSave's init is no longer fileprivate"
# 3. 旧入口不在了：App 不再自己拼一组模板去存。
old=$(grep -rn --include='*.swift' -E 'FaceTemplateSet\.appending' prototype/App || true)
[[ -z "$old" ]] || fail "App code still merges templates on its own (old enroll path):" "$old"
echo "ok   static: the enroll preference only starts the flow; templates are written only after Touch ID"
