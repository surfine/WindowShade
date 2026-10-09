#!/bin/bash
# CarPlay 接收端会话生命周期纯逻辑（合成事件，无传输、无凭据）。
set -euo pipefail
exec bash "$(dirname "$0")/../tools/carplay/test-session.sh"
