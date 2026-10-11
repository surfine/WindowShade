#!/bin/bash
# SRP 三方交叉验证：纯 Swift（WS2PureSRP）与探针 C 原生（WSNativeSRP.c + OpenSSL）各自当服务端，
# Python 参考客户端对各自的 (salt, B) 算 A/M1/K。两个实现都必须接受客户端证明，
# 且返回的会话密钥与客户端一致。没有本地 OpenSSL 时按 not_run 退出 78，不算失败。
set -uo pipefail
cd "$(dirname "$0")/.."
BASE=tools/probes/companion-pairing
OUT=.build/srp-tests/cross
OPENSSL_PREFIX=${WS_SRP_OPENSSL_PREFIX:-/opt/homebrew/opt/openssl@3}
mkdir -p "$OUT/module-cache"
if [[ ! -f "$OPENSSL_PREFIX/include/openssl/bn.h" ]]; then
  echo "SKIP srp cross-check: no OpenSSL at $OPENSSL_PREFIX (not_run)"
  exit 78
fi
echo "==> 编译 C 原生 SRP 与交叉执行器"
clang -std=c11 -O2 -I"$OPENSSL_PREFIX/include" -c "$BASE/WSNativeSRP.c" -o "$OUT/WSNativeSRP.o" || exit 1
swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -module-cache-path "$OUT/module-cache" -I "$BASE" \
  prototype/Support/WS2PureSRP.swift "$BASE/WS2NativeSRPPrimitive.swift" tests/WS2SRPCrossCheck.swift \
  "$OUT/WSNativeSRP.o" -L"$OPENSSL_PREFIX/lib" -lcrypto \
  -o "$OUT/srp-crosscheck" || exit 1

python3 - "$OUT/srp-crosscheck" <<'PY'
import hashlib, json, os, subprocess, sys

binary = sys.argv[1]
N = 0xFFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AAAC42DAD33170D04507A33A85521ABDF1CBA64ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6BF12FFA06D98A0864D87602733EC86A64521F2B18177B200CBBE117577A615D6C770988C0BAD946E208E24FA074E5AB3143DB5BFCE0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF
USER = b"Pair-Setup"

def h(parts):
    hasher = hashlib.sha512()
    for p in parts:
        hasher.update(p)
    return hasher.digest()

def strip_leading(value):
    return value.to_bytes(384, "big").lstrip(b"\x00")

def client(pin, salt, server_b):
    x = int.from_bytes(h([salt + h([USER + b":" + pin])]), "big")
    v = pow(5, x, N)
    a = int.from_bytes(os.urandom(32), "big")
    client_a = pow(5, a, N)
    u = int.from_bytes(h([client_a.to_bytes(384, "big"), server_b.to_bytes(384, "big")]), "big")
    k = int.from_bytes(h([N.to_bytes(384, "big"), (5).to_bytes(384, "big")]), "big")
    s = pow((server_b - k * v) % N, a + u * x, N)
    key = h([strip_leading(s)])
    m1 = h([bytes(x ^ y for x, y in zip(h([N.to_bytes(384, "big")]), h([b"\x05"]))),
            h([USER]), salt, strip_leading(client_a), strip_leading(server_b), key])
    return client_a, m1, key

pins = [b"111111", b"393939", b"0123456789", b"x" * 64]
failures = 0
for implementation in ("--pure", "--native"):
    for index, pin in enumerate(pins):
        process = subprocess.Popen([binary, implementation, "run", pin.decode()],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True)
        started = json.loads(process.stderr.readline().strip())
        salt = bytes.fromhex(started["salt"])
        server_b = int(started["B"], 16)
        client_a, m1, key = client(pin, salt, server_b)
        stdout, _ = process.communicate(f"{client_a:0768x},{m1.hex()}\n")
        result = json.loads(stdout.strip())
        agreed = result.get("K") == key.hex()
        accepted = result.get("accepted") is True
        print(f"{'ok  ' if agreed and accepted else 'FAIL'} {implementation} pin#{index} accepted={accepted} key-agrees={agreed}")
        if not (agreed and accepted):
            failures += 1
            print("     client key:", key.hex()[:24], "server:", str(result.get("K"))[:24], result.get("error", ""))
sys.exit(1 if failures else 0)
PY
status=$?
if [ $status -eq 0 ]; then echo "PASS srp cross-check (pure vs native vs python client)"; else echo "FAIL srp cross-check"; exit 1; fi
