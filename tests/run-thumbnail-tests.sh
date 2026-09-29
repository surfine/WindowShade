#!/bin/bash
# 缩略图的几何与透明度设置（纯逻辑，不操作任何窗口）。真机上的收起、看一眼、展开、整理见 --thumbnail 探针。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/thumbnail-tests
swiftc prototype/Core/ThumbnailLayout.swift prototype/Core/ShadeTranslucency.swift tests/ThumbnailLayoutTests.swift \
  -o .build/thumbnail-tests/layout
.build/thumbnail-tests/layout
