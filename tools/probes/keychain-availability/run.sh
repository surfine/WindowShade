#!/bin/bash
# 钥匙串可用性探针（ID-14）：三种构建各跑一遍。只用于本地探针，不改 prototype/build.sh。
#   bash tools/probes/keychain-availability/run.sh              三种都跑
#   bash tools/probes/keychain-availability/run.sh adhoc        只跑某一种（unsigned | adhoc | developer）
# 第三种需要本机已有 Apple Development 证书；没有就记 not_run。
set -uo pipefail
cd "$(dirname "$0")/../../.."
WORK=".build/keychain-availability-probe"
rm -rf "$WORK"
mkdir -p "$WORK"
SRC=(tools/probes/keychain-availability/main.swift prototype/App/FaceTemplateKeychainStore.swift prototype/Core/FaceTemplateSet.swift prototype/Core/FaceScanGuard.swift prototype/Core/SessionLockState.swift)
ONLY="${1:-all}"

find_developer_identity() {
  if [ -n "${WINDOWSHADE_CODESIGN_IDENTITY:-}" ]; then
    echo "$WINDOWSHADE_CODESIGN_IDENTITY"
    return
  fi
  security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -n 1
}

# $1 = 模式名；输出 .app 路径到标准输出
build_app() {
  local out="$WORK/$1/KeychainProbe.app"
  mkdir -p "$out/Contents/MacOS"
  cp "$(dirname "$0")/Info.plist" "$out/Contents/Info.plist"
  swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    -target arm64-apple-macosx14.0 "${SRC[@]}" -o "$out/Contents/MacOS/KeychainProbe" || return 1
  echo "$out"
}

run_mode() {
  local name="$1" app="$2"
  echo "== $name: $(codesign -dv "$app" 2>&1 | grep -E '^(Signature|Identifier|Authority)=' | tr '\n' ' ')"
  "$app/Contents/MacOS/KeychainProbe" "--mode=$name"
  echo "exit=$?"
}

if [ "$ONLY" = all ] || [ "$ONLY" = unsigned ]; then
  if app=$(build_app unsigned); then
    # arm64 链接器会自动 ad-hoc 签名；这里去掉签名，得到真正的未签名构建。
    codesign --remove-signature "$app/Contents/MacOS/KeychainProbe" 2>/dev/null
    run_mode unsigned "$app" 2>&1
  else
    echo "== unsigned: build_failed"
  fi
fi

if [ "$ONLY" = all ] || [ "$ONLY" = adhoc ]; then
  if app=$(build_app adhoc); then
    codesign --force --sign - "$app" && run_mode adhoc "$app" 2>&1
  else
    echo "== adhoc: build_failed"
  fi
fi

if [ "$ONLY" = all ] || [ "$ONLY" = developer ]; then
  identity="$(find_developer_identity)"
  if [ -z "$identity" ]; then
    echo "== developer: not_run（本机没有 Apple Development 证书）"
  elif app=$(build_app developer); then
    codesign --force --sign "$identity" "$app" && run_mode developer "$app" 2>&1
  else
    echo "== developer: build_failed"
  fi
fi
