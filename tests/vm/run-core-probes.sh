#!/bin/bash
# 在另外两个支持的 macOS 版本的虚拟机里跑核心探针（支持政策见 DEVELOPMENT.md「支持的系统版本」）。
# 用法：tests/vm/run-core-probes.sh lume@<虚拟机地址> [探针组…]
# 先 cd prototype && ./build.sh --stage；虚拟机用外置 QA 盘的 Lume（RUNBOOK.md），客体里已授权辅助功能与屏幕录制、
# 已放好本机的 SSH 公钥。把签名构建与临时 App 用 ditto 打包传进去（不破坏签名），在客体的图形会话里逐组跑。
set -euo pipefail
cd "$(dirname "$0")/../.."
host=${1:?usage: run-core-probes.sh lume@<vm-ip> [suites...]}; shift || true
suites=("$@"); [ ${#suites[@]} -gt 0 ] || suites=(fold-timing restore-guard fold-unminimizable orphan wins browser-more)
# 临时 App 由本机任何一次 tests/run-glance-probe.sh 编出来。
[ -d .build/glance-tests/GlanceFixture.app ] || { echo "先在本机跑一次 tests/run-glance-probe.sh 编出临时 App" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
ditto -c -k --keepParent .build/duo-validation/WindowShade.app "$tmp/ws.zip"
ditto -c -k --keepParent .build/glance-tests/GlanceFixture.app "$tmp/fx.zip"
scp -q -o BatchMode=yes "$tmp/ws.zip" "$tmp/fx.zip" tests/vm/run-in-guest.sh "$host:/tmp/"
ssh -o BatchMode=yes "$host" "mkdir -p ~/wsqa-run && cd ~/wsqa-run && rm -rf WindowShade.app GlanceFixture.app \
  && ditto -x -k /tmp/ws.zip . && ditto -x -k /tmp/fx.zip . && cp /tmp/run-in-guest.sh . && chmod +x run-in-guest.sh \
  && codesign --verify --deep --strict WindowShade.app && echo \"guest macOS \$(sw_vers -productVersion)\" \
  && ./run-in-guest.sh ${suites[*]}"
