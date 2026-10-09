#!/bin/bash
# 身份证据进授权账（ID-01）：纯逻辑，不碰相机、界面和 Touch ID。
# 另做一道静态检查：AuthorizationGrant 只在 complete 里、验签之后造一次；证据票据只能经 complete 当门槛。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/identity-evidence-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/SessionLockState.swift prototype/Core/AuthorizationModels.swift prototype/Core/IdentityEvidence.swift \
  prototype/Core/AuthorizationLedger.swift tests/IdentityEvidenceLedgerTests.swift -o .build/identity-evidence-tests/evidence
.build/identity-evidence-tests/evidence

# 没有从证据到授权的路径：整个 prototype 里构造授权只有账本里那一处，且在验签那一行之后。
sites=$(grep -rn --include='*.swift' -E 'AuthorizationGrant\(request' prototype || true)
count=$(printf '%s\n' "$sites" | grep -c . || true)
if [[ "$count" != 1 || "$sites" != prototype/Core/AuthorizationLedger.swift:* ]]; then
  echo "FAIL AuthorizationGrant is constructed outside the ledger's complete():"; echo "$sites"; exit 1
fi
grant_line=${sites#*:}; grant_line=${grant_line%%:*}
sig_line=$(grep -n 'else { return .failure(.badSignature) }' prototype/Core/AuthorizationLedger.swift | cut -d: -f1)
if [[ -z "$sig_line" || "$grant_line" -le "$sig_line" ]]; then
  echo "FAIL the grant is not built after the signature check"; exit 1
fi
# 证据相关类型不出现在任何返回授权的签名里（除了 complete 的门槛参数）。
if grep -rn --include='*.swift' -E '(IdentityEvidence|EvidenceTicket).*->.*AuthorizationGrant' prototype \
     | grep -v 'evidence: EvidenceTicket? = nil) -> Result<AuthorizationGrant, AuthFailure>'; then
  echo "FAIL a function maps evidence to a grant"; exit 1
fi
echo "ok   static: the only grant is built in complete() after the signature check; evidence never maps to a grant"
