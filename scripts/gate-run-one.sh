#!/bin/bash
# 门禁内部用：跑一条命令，带硬超时，把退出码和耗时写到状态文件。
# 用法：gate-run-one.sh <超时秒> <日志> <状态文件> <命令…>
# 状态文件两列：退出码、耗时秒。超时按 124 记（和 GNU timeout 一致）。
set -u
timeout_s="$1"
log="$2"
status="$3"
shift 3

start=$(date +%s)
# 命令放进自己的进程组（perl setpgrp 后 exec，pid 不变），超时时整组一起杀，
# 否则只杀掉 bash，swiftc 和测试二进制会继续跑。macOS 没有 setsid，perl 是系统自带的。
perl -e 'setpgrp(0, 0) or die "setpgrp: $!"; exec @ARGV or die "exec: $!"' -- "$@" >"$log" 2>&1 &
pid=$!
(
  sleep "$timeout_s"
  kill -TERM -- "-$pid" 2>/dev/null
  sleep 5
  kill -KILL -- "-$pid" 2>/dev/null
) >/dev/null 2>&1 &
watcher=$!

wait "$pid"
rc=$?
pkill -P "$watcher" 2>/dev/null
kill "$watcher" 2>/dev/null
wait "$watcher" 2>/dev/null
end=$(date +%s)
elapsed=$((end - start))

# 被看门狗终止的结果统一成 124（命令自己返回 143 的极少，接受这点误差）。
if [ "$rc" -eq 143 ] && [ "$elapsed" -ge "$timeout_s" ]; then
  rc=124
fi
printf '%s\t%s\n' "$rc" "$elapsed" >"$status"
