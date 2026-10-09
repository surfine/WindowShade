#!/bin/bash
# 正在播放的真实波形（NP-6）：频带、dB 映射、起落（纯逻辑），以及什么时候建、拆 tap（假 tap、假授权，不碰 CoreAudio、不弹窗）。
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/.build/audio-level-tests"
mkdir -p "$out"
flags=(-swift-version 6 -strict-concurrency=complete -warnings-as-errors -O)
swiftc "${flags[@]}" "$root/prototype/Core/AudioLevelBands.swift" "$root/tests/AudioLevelBandsTests.swift" -o "$out/bands"
"$out/bands"
swiftc "${flags[@]}" -target arm64-apple-macosx14.0 "$root/prototype/Core/AudioLevelBands.swift" "$root/prototype/App/AudioLevelTap.swift" \
  "$root/tests/AudioLevelControllerTests.swift" -o "$out/controller"
"$out/controller"
