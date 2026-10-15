#!/bin/bash
# F08：收起／合盖 Metal 渲染管线——在飞帧空位、GPU 共享对象只建一次、page 金字塔按帧确认、
# 静图零拷贝纹理与旧路径逐字节一致（附 4800×2600 静图准备耗时）。需要本机 Metal。
# FOLD_BENCH=0 跳过耗时测量。本机没装 Metal 工具链时，可用 WINDOWSHADE_DUO_METALLIB 指向一份现成的 Duo.metallib。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/fold-renderer-tests .build/duo-metal
if xcrun -sdk macosx metal -mmacosx-version-min=14.0 -fmodules-cache-path="$(pwd)/.build/module-cache" \
  -c prototype/Effects/Duo.metal -o .build/duo-metal/Duo.air 2>/dev/null; then
  xcrun -sdk macosx metallib .build/duo-metal/Duo.air -o .build/duo-metal/Duo.metallib
elif [ -n "${WINDOWSHADE_DUO_METALLIB:-}" ]; then
  echo "note: Metal 工具链不可用，使用 $WINDOWSHADE_DUO_METALLIB"
  cp "$WINDOWSHADE_DUO_METALLIB" .build/duo-metal/Duo.metallib
elif [ -f .build/duo-metal/Duo.metallib ]; then
  echo "note: Metal 工具链不可用，沿用现有 .build/duo-metal/Duo.metallib"
else
  echo "FAIL: 编译不了 Duo.metal，也没有现成的 Duo.metallib（设 WINDOWSHADE_DUO_METALLIB）" >&2
  exit 1
fi
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/Effects/FoldPageKey.swift \
  prototype/Effects/FoldGPU.swift \
  tests/FoldRendererPipelineTests.swift \
  -o .build/fold-renderer-tests/fold-renderer
.build/fold-renderer-tests/fold-renderer
