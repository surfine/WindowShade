# 实验 2：认出另一个 macOS 账号的主人后切换到那个账号（2026-10-31，macOS 27.0.1）

## 结论

**有限可行（带前提）。** 在 A 账号里“请求切到 B、让 B 的锁屏出现”只能靠私有 `login.framework` 函数，没有公开 API；老路 `CGSession -switchToUserID` 在 macOS 27 **已不存在**。B 已登录时，B 自己的 WindowShade 实例能在 B 的会话成为前台后做刷脸解锁（和普通锁屏同一条路）。B **没登录**时不可行：没有 B 的会话，我们的 App 没在跑，面前是登录窗口（本机还开着 FileVault）。

## 证据（`tools/user-switch-probe/run.sh`，只读，从不调用切换/锁屏函数）
```
path .../Menu Extras/User.menu/Contents/Resources/CGSession   missing
path .../Menu Extras/User.menu                                missing
login!SACSwitchToUser            present(not called)
login!SACSwitchToLoginWindow     present(not called)
login!SACLockScreenImmediate     present(not called)
login!SACScreenSaverStartNow / SACScreenSaverIsRunning / SACShieldWindowShowing  present
login!SACSwitchToUserID          absent
CGSCopySessionList / CGSSessionCopyAllSessionProperties  present (CoreGraphics, private)
session kCGSSessionOnConsoleKey {true}  kCGSSessionUserIDKey {501}  (用户名已脱敏)
accounts(uid>=500): 2  console_sessions: 1  filevault: FileVault is On.
```
- 本机 `man CGSession` 无手册；`Menu Extras` 目录里没有 `User.menu`。
- `CGSessionCopyCurrentDictionary`（公开）只描述**当前**会话；要列别的会话需要私有的 `CGSCopySessionList`。
- `SACSwitchToUser` 的参数签名我**没有验证**（没调用、没反汇编），不要凭印象写调用。

## 回答被问到的几点
- **A 能否请求“切到 B”？** 只有私有 `SACSwitchToUser`（与系统“快速用户切换”菜单同源）或界面脚本去点控制中心；公开 API 没有。是否需要特殊授权未测（测它就要真的切换，被禁止）。属于**待 Aaron 在场时的受控实测**。
- **B 的锁屏如何出现？** 由 `loginwindow` 管。切换后 A 的会话挂起，B 的会话（若在）变前台并显示 B 的锁屏/密码框；密码框由 loginwindow 画，不属于任何 App。
- **B 自己的 WindowShade 能否刷脸？** 能，前提：B 已登录且 App 在 B 会话里运行（登录项）、B 授权过相机、B 录过脸。B 的实例用公开的 `NSWorkspace.sessionDidBecomeActiveNotification` 知道自己成了前台，再走现有“锁屏上认你→代填密码”流程。A 不能替 B 认脸：两个账号的相机权限、人脸数据、钥匙串都互相隔离（设计上也应保持）。
- **B 没登录？** 没有会话、没有进程，只能是登录窗口；FileVault 开着时重启后第一次登录必须输密码（这是系统要求，不是我们能放行的）。结论：**不做**，交回系统。（Touch ID 在重启后首次登录不可用属 Apple 公开行为，本轮没有重新查证。）
- **A→B 的触发**：要先在 A 里认出“这是 B 的脸”。这需要在 A 的会话里存 B 的人脸模板——违反“只认本机账户的主人”的硬要求和账户隔离，需要 Aaron 明确定是否允许。

## 隐私与安全
- 在 A 里替 B 识别身份，等于 A 账号的进程持有 B 的生物特征：建议**不做**；改为“A 里只做‘切到登录窗口/锁屏’的便利，不认人”。
- 私有 API 调用可能随系统更新改签名；本机 macOS 27 上符号都在，但没有验证行为。

## 需要 Aaron 做的事
1. 决定是否允许 A 保存 B 的脸模板（建议否）。
2. 如要实测 `SACSwitchToUser`：在你在场、B 已登录、已存好工作的情况下，我写一个带 `--confirm-i-am-present` 的单次调用探针；那会真的切换会话，所以需要你点头，我这轮没做。

## 编译检查
`clang UserSwitchProbe.c -o OUT -w -framework CoreFoundation -framework ApplicationServices` exit 0；`bash -n run.sh` exit 0。
