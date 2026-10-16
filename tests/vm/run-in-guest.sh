#!/bin/bash
# 在虚拟机里跑核心探针：每组一个进程，经 open 进图形会话；日志与收起记录放在 ~/wsqa-run 下。
# 用法：[WSQA_SETTINGS=autohide,stage-manager,display:1280x800@1] [WSQA_TIMEOUT_SCALE=3] [WSQA_SUITE_TIMEOUT=900] run-in-guest.sh 探针组…
#   WSQA_SETTINGS：跑之前在来宾里临时改的系统设置（逗号分隔），结束或被打断时一律还原：
#     autohide             程序坞自动隐藏（defaults write com.apple.dock autohide；V8（b））
#     stage-manager        台前调度（defaults write com.apple.WindowManager GloballyEnabled；V8（f）、R19／V10）
#     display:宽x高@缩放   显示模式，例如 display:1280x800@1（V11；用 vm-display-mode 小工具，只改本次登录会话）
#   WSQA_TIMEOUT_SCALE：把探针自己的等待上限放宽几倍（1–8，默认 3；宿主负载高时虚拟机慢），WSQA_SUITE_TIMEOUT：每组总时限（秒，默认 900）。
# 安全：只在虚拟机里改设置。改任何设置之前先检查 kern.hv_vmm_present（虚拟机里为 1），不是就整个退出；宿主机永远不会走到这里的改动分支。
scale=${WSQA_TIMEOUT_SCALE:-3}; limit=${WSQA_SUITE_TIMEOUT:-900}
settings=${WSQA_SETTINGS:-}

is_vm() { [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" = 1 ]; }

if [ -n "$settings" ] && ! is_vm; then
  echo "REFUSED: WSQA_SETTINGS=$settings but this is not a virtual machine (kern.hv_vmm_present != 1); nothing was changed" >&2
  exit 3
fi

cd "$HOME/wsqa-run" || exit 1
mkdir -p logs results saved shots && chmod 700 logs

wait_dock() { # 有界等待 Dock 重新起来
  local t0=$SECONDS
  while ! pgrep -x Dock >/dev/null && (( SECONDS - t0 < 30 )); do sleep 1; done
  sleep 3
  echo "INFO guest: Dock back after $((SECONDS - t0)) s"
}

display_tool() { # 经 open 在图形会话里跑小工具，输出读回来
  local out="$HOME/wsqa-run/results/display-tool.txt"; rm -f "$out"
  open -n -W --stdout "$out" --stderr "$out" ./VMDisplayMode.app --args "$@"
  cat "$out" 2>/dev/null
}

save_default() { # save_default 名字 域 键：只在还没存过时存下原值（崩溃后重跑不会把「已改过」的值当原值）
  [ -e "saved/$1" ] && return
  if v=$(defaults read "$2" "$3" 2>/dev/null); then echo "$v" > "saved/$1"; else echo ABSENT > "saved/$1"; fi
}

restore_default() { # restore_default 名字 域 键
  [ -e "saved/$1" ] || return 1
  if [ "$(cat "saved/$1")" = ABSENT ]; then defaults delete "$2" "$3" 2>/dev/null
  elif [ "$(cat "saved/$1")" = 1 ]; then defaults write "$2" "$3" -bool true
  else defaults write "$2" "$3" -bool false; fi
  rm -f "saved/$1"
}

restore_all() {
  is_vm || return 0
  local touched_dock=0 touched_wm=0
  restore_default autohide com.apple.dock autohide && touched_dock=1
  restore_default stage-manager com.apple.WindowManager GloballyEnabled && touched_wm=1
  if [ -e saved/display ]; then
    echo "INFO guest: restoring display mode $(cat saved/display)"
    display_tool set "$(cat saved/display)" && rm -f saved/display
  fi
  if (( touched_wm )); then killall cfprefsd WindowManager Dock 2>/dev/null; wait_dock
  elif (( touched_dock )); then killall Dock 2>/dev/null; wait_dock; fi
  if (( touched_dock || touched_wm )); then echo "INFO guest: settings restored"; fi
}

apply_settings() {
  local s dock=0 wm=0
  IFS=, read -ra list <<< "$settings"
  for s in "${list[@]}"; do
    case "$s" in
      autohide) save_default autohide com.apple.dock autohide; defaults write com.apple.dock autohide -bool true; dock=1 ;;
      stage-manager) save_default stage-manager com.apple.WindowManager GloballyEnabled
        defaults write com.apple.WindowManager GloballyEnabled -bool true; wm=1 ;;
      display:*)
        [ -e saved/display ] || display_tool current | head -1 > saved/display
        grep -Eq '^[0-9]+x[0-9]+@[12]$' saved/display || { echo "REFUSED: cannot read the current display mode" >&2; rm -f saved/display; return 5; }
        echo "INFO guest: display $(cat saved/display) -> ${s#display:}"
        display_tool set "${s#display:}" ;;
      *) echo "REFUSED: unknown setting $s" >&2; return 4 ;;
    esac
  done
  if (( wm )); then killall cfprefsd WindowManager Dock 2>/dev/null; wait_dock
  elif (( dock )); then killall Dock 2>/dev/null; wait_dock; fi
  echo "INFO guest: settings applied: $settings (autohide=$(defaults read com.apple.dock autohide 2>/dev/null || echo unset), stage-manager=$(defaults read com.apple.WindowManager GloballyEnabled 2>/dev/null || echo unset))"
}

# 上一次被打断时留下的改动先还原，再开始。
restore_all
trap 'restore_all' EXIT
trap 'exit 130' INT TERM
if [ -n "$settings" ]; then apply_settings || exit $?; fi

for suite in "$@"; do
  log="$HOME/wsqa-run/logs/$suite.log"; : > "$log"; chmod 600 "$log"
  out="$HOME/wsqa-run/results/$suite.txt"; rm -f "$out"
  t0=$SECONDS; timed_out=0
  echo "INFO guest: load $(sysctl -n vm.loadavg) before $suite"
  open -n -W --env WINDOWSHADE_LOG_PATH="$log" --env WINDOWSHADE_PROBE_ROOT="$HOME/wsqa-run" \
    --env WINDOWSHADE_PROBE_TIMEOUT_SCALE="$scale" --env PROBE_SHOTS="$HOME/wsqa-run/shots" \
    --stdout "$out" --stderr "$out" ./WindowShade.app \
    --args --glance-probe --fixture "$HOME/wsqa-run/GlanceFixture.app/Contents/MacOS/GlanceFixture" "--$suite" &
  opid=$!
  while kill -0 "$opid" 2>/dev/null; do
    if (( SECONDS - t0 > limit )); then
      timed_out=1; echo "TIMEOUT $suite after $((SECONDS - t0)) s (limit $limit s); stopping the probe"
      pkill -x WindowShade; pkill -x GlanceFixture; break
    fi
    sleep 2
  done
  wait "$opid" 2>/dev/null
  fails=$(grep -c '^FAIL' "$out"); verdict=$(grep '^verdict' "$out")
  echo "== $suite fails=$fails $verdict elapsed=$((SECONDS - t0))s timed_out=$timed_out"
  grep -E '^(FAIL|INFO (restore|glance|probe-wait|dock-scenarios)|TIMING|PASS fold-unmin|SKIP)' "$out" | cut -c1-220
done
