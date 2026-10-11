#!/bin/bash
# 纯 Swift SRP 的官方向量验证（离线；向量来自 NativeSRPTests.c 的机器提取）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/srp-tests
python3 - <<'PY'
# 向量提取与 C 源保持同源；提取脚本改动时这里会因长度断言失败。
import re, json
src = open('tools/probes/companion-pairing/NativeSRPTests.c').read()
def extract(name):
    match = re.search(r'static const uint8_t %s\[\](?:\s*=\s*)?\{(.*?)\};' % name, src, re.S)
    body = re.sub(r'"[^"]*"', '', match.group(1))
    return [int(x, 16) for x in re.findall(r'0x([0-9A-Fa-f]{2})', body)]
names = {'salt': 'salt', 'b': 'b', 'A': 'A', 'B': 'B', 'u': 'u', 'S': 'S',
         'K': 'k', 'M1': 'm1', 'M2': 'm2', 'v': 'v'}
data = {key: extract('srp_' + raw) for key, raw in names.items()}
data['user'] = list(b'alice'); data['pass'] = list(b'password123')
assert len(data['salt']) == 16 and len(data['b']) == 32
assert all(len(data[k]) == 384 for k in ('A', 'B', 'S', 'v'))
assert all(len(data[k]) == 64 for k in ('u', 'K', 'M1', 'M2'))
open('tests/WS2PureSRPVectors.json', 'w').write(
    json.dumps({k: ''.join('%02x' % b for b in v) for k, v in data.items()}, indent=1))
PY
swiftc -swift-version 6 -strict-concurrency=complete -module-cache-path "$PWD/.build/module-cache" \
  prototype/Support/WS2PureSRP.swift \
  tests/WS2PureSRPTests.swift \
  -framework CryptoKit -framework Security \
  -o .build/srp-tests/pure-srp
.build/srp-tests/pure-srp
