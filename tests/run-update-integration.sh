#!/bin/bash
# 更新器的本地隔离验证（自检、状态迁移、换回）。要签名身份，先跑：
#     cd prototype && ./build.sh --stage
#
# 全程在临时目录里：看护用 --store 指到自己的 store，装着的“那一版”也在临时目录里；
# 不碰已装的 WindowShade、不联网、不动用户设置。
# 一处例外要说清楚：看护换回成功后会按路径把装好的那一版打开一次，而 App 没有 --store 参数，
# 所以那一份读的是你自己的 ~/Library/Application Support/WindowShade——它只会做产品本来也会做的事
# （没有任何更新记录时，清掉一份超过 7 天的过期备份），不会写别的。
# 不跑 Sparkle（那一步要 Sparkle 发布包里的 sign_update / generate_appcast，见 docs/update.md）。
#
# 验三件事：
#   1. 自检：WindowShade --self-check 返回 build=<n> ok；
#   2. 状态迁移：--self-check --write-sample-state / --read-state 写出并读回一份样例状态
#      （恢复日志 + 偏好 + 更新日志），读的一方认了就说明“换回后的旧版还读得懂”；
#   3. 换回（回退）：造一个“装上去的坏版”（build 17）+ 一份真备份 zip（build 16），
#      让看护 --restore 真换回来：装着的包要变回备份那一版、store 记 restored、refused 记下坏版；
#      再把备份的 SHA-256 改坏：要记 restoreFailed，且装着的坏版一动不动。
set -euo pipefail
cd "$(dirname "$0")/.."

APP=".build/duo-validation/WindowShade.app"
BIN="$APP/Contents/MacOS/WindowShade"
GUARD="$APP/Contents/Helpers/WindowShadeUpdateGuard.app/Contents/MacOS/WindowShadeUpdateGuard"
if [ ! -x "$BIN" ] || [ ! -x "$GUARD" ]; then
  echo "先跑：cd prototype && WINDOWSHADE_CODESIGN_IDENTITY=\"...\" ./build.sh --stage" >&2
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ws-update-integration.XXXXXX")"
passes=0
failures=0
ok()   { printf 'ok   %s\n' "$1"; passes=$((passes + 1)); }
bad()  { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
# 看护换回后会按路径打开装好的那一版：必须真的把它关掉——它是同一个 bundle id 的另一份
# WindowShade，留着会和用户那一份抢全局快捷键、多出一个菜单栏图标。
stop_launched_copy() {
  # 按目录名匹配，不按 $WORK 的全路径：macOS 上 /var 是指向 /private/var 的符号链接，
  # 而进程的命令行里是 /private/var/...，全路径匹配不上（这一条踩过）。
  # LaunchServices 也可能晚一拍才把 App 起起来，所以先等一会儿再杀。
  sleep 1
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pkill -f "ws-update-integration." 2>/dev/null || true
    pgrep -f "ws-update-integration." >/dev/null 2>&1 || break
    sleep 0.3
  done
  pkill -9 -f "ws-update-integration." 2>/dev/null || true
}
cleanup() {
  stop_launched_copy
  if [ -z "${WS_UPDATE_INT_KEEP:-}" ]; then rm -rf "$WORK"; fi
}
trap cleanup EXIT
echo "==> 临时目录：${WORK}（保留：WS_UPDATE_INT_KEEP=1）"

# ---- 1. 自检 ----

BUILD="$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
SELF="$(perl -e 'alarm 15; exec @ARGV' "$BIN" --self-check 2>&1 || true)"
if [ "$SELF" = "WindowShade self-check build=$BUILD ok" ]; then
  ok "自检：$SELF"
else
  bad "自检：得到「${SELF}」，应为「WindowShade self-check build=$BUILD ok」"
fi

# ---- 2. 状态迁移：写一份样例状态再读回来 ----

STATE="$WORK/state"
if perl -e 'alarm 30; exec @ARGV' "$BIN" --self-check --write-sample-state "$STATE" >"$WORK/write-state.log" 2>&1 \
   && grep -q "sample state written" "$WORK/write-state.log"; then
  ok "状态迁移：写出样例状态（恢复日志 + 偏好 + 更新日志）"
else
  bad "状态迁移：写出样例状态失败（$(tail -1 "$WORK/write-state.log")）"
fi
READ="$(perl -e 'alarm 30; exec @ARGV' "$BIN" --self-check --read-state "$STATE" 2>&1 || true)"
case "$READ" in
  *"read-state ok build=$BUILD"*) ok "状态迁移：读回来没问题（${READ}）" ;;
  *) bad "状态迁移：读回来有问题（${READ}）" ;;
esac

# ---- 3. 换回 ----

ZIP="$WORK/WindowShade-$VERSION-$BUILD.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
DR="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
if [ -n "$DR" ] && [ -f "$ZIP" ]; then
  ok "备份：真打包一份 zip（$(du -k "$ZIP" | cut -f1) KB），拿到签名要求"
else
  bad "备份：打包或取签名要求失败"
fi

# 造一个“已经装上来的坏版”：就是这一版，但 build 写成 17，再放一个记号文件，
# 换回成功的话它会随坏版一起被换走。
make_bad_installed() {
  local dir="$1"
  mkdir -p "$dir"
  ditto "$APP" "$dir/WindowShade.app"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion 17" "$dir/WindowShade.app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.0.17" "$dir/WindowShade.app/Contents/Info.plist"
  printf 'bad build 17\n' > "$dir/WindowShade.app/Contents/BAD-MARKER"
}

write_journal() {
  local store="$1" app_path="$2" backup="$3" sha="$4"
  mkdir -p "$store/Update" "$store/Previous"
  WS_JSON_APP="$app_path" WS_JSON_BACKUP="$backup" WS_JSON_SHA="$sha" WS_JSON_DR="$DR" \
  WS_JSON_FROM_BUILD="$BUILD" WS_JSON_FROM_VERSION="$VERSION" \
    python3 - "$store/Update/journal.json" <<'PY'
import json, os, sys
from datetime import datetime, timezone
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
journal = {
    "from": {"version": os.environ["WS_JSON_FROM_VERSION"], "build": os.environ["WS_JSON_FROM_BUILD"]},
    "to": {"version": "1.0.17", "build": "17"},
    "appPath": os.environ["WS_JSON_APP"],
    "oldDR": os.environ["WS_JSON_DR"],
    "backup": os.environ["WS_JSON_BACKUP"],
    "backupSHA256": os.environ["WS_JSON_SHA"],
    "permissionsBefore": {"accessibility": True, "screenRecording": True},
    "phase": "rollbackRequested",
    "startedAt": now,
    "oldPID": 0,
    "launches": [],
    "restoreReason": "userRequested",
}
with open(sys.argv[1], "w") as handle:
    json.dump(journal, handle, indent=2, sort_keys=True)
PY
}

journal_field() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],''))" "$1" "$2"; }
refused_builds() {
  python3 - "$1" <<'PY'
import json, sys
try:
    entries = json.load(open(sys.argv[1]))
except Exception:
    print("")
    raise SystemExit
print(" ".join(e.get("build", "") for e in entries))
PY
}

# 3a. 备份是好的：应当真换回来。
STORE="$WORK/store-restore"
make_bad_installed "$WORK/installed"
write_journal "$STORE" "$WORK/installed/WindowShade.app" "$ZIP" "$SHA"
if perl -e 'alarm 120; exec @ARGV' "$GUARD" --restore --store "$STORE" >"$WORK/restore.log" 2>&1; then :; fi
RESTORED_SELF="$(perl -e 'alarm 15; exec @ARGV' "$WORK/installed/WindowShade.app/Contents/MacOS/WindowShade" --self-check 2>&1 || true)"
if [ "$RESTORED_SELF" = "WindowShade self-check build=$BUILD ok" ]; then
  ok "换回：装着的包被换回备份那一版（${RESTORED_SELF}）"
else
  bad "换回：装着的包还是坏的（${RESTORED_SELF}）"
fi
if [ ! -e "$WORK/installed/WindowShade.app/Contents/BAD-MARKER" ]; then
  ok "换回：坏版连记号文件一起被换走"
else
  bad "换回：坏版还留在原地"
fi
PHASE="$(journal_field "$STORE/Update/journal.json" phase 2>/dev/null || echo "")"
if [ "$PHASE" = "restored" ]; then ok "换回：store 记下 phase=restored"; else bad "换回：store 里 phase=${PHASE}，应为 restored"; fi
if [ "$(refused_builds "$STORE/Update/refused.json")" = "17" ]; then
  ok "换回：refused.json 记下了坏版 build 17（不再提示这一版）"
else
  bad "换回：refused.json 里是「$(refused_builds "$STORE/Update/refused.json")」，应为 17"
fi
if grep -q "restored $VERSION" "$STORE/Update/guard.log" 2>/dev/null; then
  ok "换回：guard.log 记下 restored $VERSION"
else
  bad "换回：guard.log 里没有 restored 那一条"
fi

# 3b. 备份是坏的（SHA-256 对不上）：不许动装着的包，记 restoreFailed。
STORE_BAD="$WORK/store-badsha"
make_bad_installed "$WORK/installed2"
write_journal "$STORE_BAD" "$WORK/installed2/WindowShade.app" "$ZIP" "0000000000000000000000000000000000000000000000000000000000000000"
if perl -e 'alarm 120; exec @ARGV' "$GUARD" --restore --store "$STORE_BAD" >"$WORK/restore-bad.log" 2>&1; then :; fi
PHASE_BAD="$(journal_field "$STORE_BAD/Update/journal.json" phase 2>/dev/null || echo "")"
if [ "$PHASE_BAD" = "restoreFailed" ]; then
  ok "坏包：store 记下 phase=restoreFailed"
else
  bad "坏包：store 里 phase=${PHASE_BAD}，应为 restoreFailed"
fi
if [ -e "$WORK/installed2/WindowShade.app/Contents/BAD-MARKER" ]; then
  ok "坏包：装着的包一动不动（还是那一版）"
else
  bad "坏包：装着的包被动过"
fi
if [ -z "$(refused_builds "$STORE_BAD/Update/refused.json")" ]; then
  ok "坏包：refused.json 撤掉了那一条（没换回就不算拒绝过）"
else
  bad "坏包：refused.json 里还留着「$(refused_builds "$STORE_BAD/Update/refused.json")」"
fi
if [ -s "$STORE_BAD/Update/guard.log" ]; then ok "坏包：看护写了日志"; else bad "坏包：看护没写日志"; fi

# 收尾自己也要干净：看护换回后打开的那一份要关掉，不能留一个临时 WindowShade 在跑。
stop_launched_copy
if pgrep -f "ws-update-integration." >/dev/null 2>&1; then
  bad "收尾：临时目录里还有 WindowShade 在跑（同一个 bundle id，会和用户那一份抢快捷键）"
else
  ok "收尾：换回后打开的那一份已关掉，没留下第二个 WindowShade"
fi

echo
echo "PASS: 更新器本地隔离验证 —— 自检、状态迁移、换回（好备份真换回、坏备份不动装着的包）"
echo "$passes 通过 / $failures 失败"
[ "$failures" = "0" ] || exit 1
