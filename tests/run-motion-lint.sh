#!/bin/bash
# 启动台的位移（position、bounds、transform）一律走弹簧，不用 CATransaction.setAnimationDuration 的隐式动画。
# 只改透明度、颜色的过渡可以保留时长淡化，但要在同一行或上一行写 `// fade-only`。
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
for file in prototype/App/Launchpad*.swift; do
  # 取每一处 setAnimationDuration( 与它的上一行，上一行或本行没有 fade-only 就报。
  bad=$(awk -v f="$file" '
    /setAnimationDuration\(/ {
      if ($0 !~ /fade-only/ && prev !~ /fade-only/) printf "%s:%d: %s\n", f, NR, $0
    }
    { prev = $0 }
  ' "$file")
  if [ -n "$bad" ]; then
    echo "$bad"
    status=1
  fi
done

if [ "$status" -ne 0 ]; then
  echo "motion lint 失败：位移请用 Motion.spring / springTo，只淡透明度的才写 // fade-only"
  exit 1
fi
echo "motion lint 通过"
