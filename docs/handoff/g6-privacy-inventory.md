# G6 隐私盘点

只盘点 `main`（`6cdf052`）上 App 实际的持久读写。不删数据、不改存储格式、不做迁移。登记表 `tools/privacy/registry.json` 没有加行、没有改 status。

「登记」指登记表里有没有点名这一项。`settings` 把本应用偏好收成一行，下面的键大多只被这一行笼统盖住。

## 恢复记录里的窗口标题

两处存同一份条目，字段含 `title`、`appName`、`bundleID`、`pid`、`id`、坐标、尺寸、`originalAlpha`、`displayID`、`spaceID`、`createdAt`、`updatedAt`、`schemaVersion`。

| 存储 | 谁写 | 谁读 | 存多久 | 怎么清 | 登记 |
| --- | --- | --- | --- | --- | --- |
| `~/Library/Application Support/WindowShade/RecoveryJournal.plist` | `Journal.saveShadeJournalEntries` → `DurableShadeJournal.save`。目录 `0700`，文件 `0600`。同 UID 的代码读得到 | `shadeJournalEntries` 优先读这份。`journalMatches` 用 pid、bundle、创建时间、窗口 ID。救援读坐标、尺寸、`hide`、`displayID`、`originalAlpha`、`appName`（只写进运行记录）。源码里没有读取者把 `title` 当身份 | 超过 14 天的条目由 `pruneShadeJournal` 删掉 | 条目变空时仍会把空数组写回这个文件。放回成功后的删减要另核 | `recovery`，current。去向只写了这个 plist |
| 偏好键 `ShadeJournalEntries` | 磁盘写入成功后，`saveShadeJournalEntries` 再写一份同样的数组 | 磁盘读失败时才用这份 | 与上面同一份内容，同样 14 天修剪 | 条目变空时 `removeObject` | `recovery` 没有点名这个键。`settings` 只笼统说本机偏好 |

标题还在两份里。匹配不靠标题。要不要从 schema 拿掉，由主模型定迁移。这次没删。

## 其它文件

| 路径 | 谁写 | 谁读 | 存多久 | 怎么清 | 登记 |
| --- | --- | --- | --- | --- | --- |
| `~/Library/Application Support/WindowShade/SlideOver-<pid>.plist` | `SlideOverRecovery.record`：窗口 ID、pid、进程启动时刻、框 | 同文件的恢复与 `clear` | 进程活着时那一份；没有 14 天修剪 | `clear` 拿掉对应 ID | 未点名。`recovery` 只写了 `RecoveryJournal.plist` |
| `~/Library/Logs/WindowShade/windowshade.log` 与 `.1` | `WindowShadeLogger` → `SecureLogFile`。目录 `0700`，文件 `0600`，满 5MB 轮转一份备份。同 UID 读得到。开发覆盖 `WINDOWSHADE_LOG_PATH` 仍走同一套校验 | 设置里「打开诊断日志」 | 当前文件加一份 `.1` | 写失败就停用，不退回 `/tmp`。没有在界面上提供清空 | `diagnostics`，current |
| `~/Library/Application Support/WindowShade/Authorization/` 下 `device-key.v1`、`.pub`、`.biometry` | `DeviceAuthorizationKey`。句柄是 Secure Enclave 包裹，源码写明没有放进 Keychain | 签名路径 | 登记期间保留 | 指纹集变化导致失效时删这三个文件 | `authorization-key`，current |
| `~/Library/Application Support/WindowShade/OwnedCodex-v1/{home,codex,tmp}` 与 `codex/config.toml` | 用户同意启动之后 `WS2LocalLaunchProfile.prepare`。配置固定只读、`cli_auth_credentials_store = "file"`、权限 `0600`。不改用户原来的 `~/.codex` | 下次 `revalidate` 核对这份配置没被改过 | 写下去就留着；再次准备发现被改过就拒绝，不覆盖 | 没有界面上的删除。和撤销配对、登出不是同一个动作 | `codex-server` 仍是 planned。写入路径已经在源码里 |
| `~/Library/Application Support/WindowShade/Update/`：`journal.json`、`refused.json`、`guard.pid`，以及 `Previous/` 备份记录 | `UpdateModels` / 看护 | 更新状态与拒绝过的版本 | 随更新过程留下 | 没有在这次盘点里改删除动作 | `update` 只写了联网检查，没有点名这些文件 |
| `~/Library/Application Support/Rectangle/RectangleConfig.json` | 不写。`RectangleImport` 只读 | 导入快捷键 | 用户自己的文件 | 不删 | 未点名。只读别人的配置 |

`WS2KeychainPeerStorage`（服务由调用方传入，账户 `companion-peer-snapshot-v1`）在 `prototype/` 里没有构造点。`SecItem*` 调用已挂在 planned 的 `pair-verify-identity`。按 D09，未指定设备前不写 Keychain。

## 偏好键

谁写谁读都是对应的设置或启动路径，存在本应用的 `UserDefaults`。没有找到统一的「重置只清本应用值」实现；登记表 `settings` 那句「重置只清本应用值」没有对上一个清除入口。关掉功能不会自动删掉已写入的值。

| 键 | 内容 | 登记 |
| --- | --- | --- |
| `Notch.enabled` `Notch.changeAlerts` `Notch.teach` `Notch.coach` | 刘海开关、变化提醒、教学、教练进度 | `settings` |
| `Notch.deviceBattery.enabled` `DeviceBattery.alerted.v1` | 电量提醒开关；已提醒过的档位 | `settings`。电量读数本身在 `battery` |
| `Notch.activitiesEnabled` `Notch.activities.musicEnabled` | 实时活动、音乐 | `settings` |
| `Notch.habits` `Notch.habitsDeviceChecked` | 习惯 | `settings` |
| `GlanceEnabled` | 看一眼 | `settings` |
| `TrackpadGesturesEnabled` | 标题栏手势 | `settings` |
| `Dock.clickToHide` `Dock.lockDisplay` `Dock.lockDisplayID` `Dock.swipeGestures` | Dock | `settings`。`Dock.lockDisplayID` 是显示器编号 |
| `DockMineffectSessionActive` `DockMineffectHadOriginal` `DockMineffectOriginal` | 最小化效果的原值 | `settings` |
| `Launchpad.layout` | 启动台排布 | `settings` |
| `MissionControl.keys` | 调度中心按键 | `settings` |
| `SplitView.divider` | 分屏 | `settings` |
| `SlideOver.allDesktopsTipShown` | 侧拉提示是否出过 | `settings` |
| `Switcher.trigger` `SwitcherOrigin` | 窗口切换 | `settings` |
| `ShadeAppearanceMode` `ShadeFloatingOnTop` `ShadeTranslucency` `ShadeTranslucent` `ShadeTitlebarDoubleClickEnabled` `ShadeSoundEnabled` `ShadeFoldSound` `ShadeUnfoldSound` `ShadeSoundMigrationVersion` `ShadeOnboardingShown` `Arrange.gap` | 收起外观、置顶、声音、引导、间隙 | `settings`。`ShadeTranslucent` 是旧键 |
| `WindowShade.Settings.LastViewedSection` | 上次打开的设置页 | `settings` |
| `lockOverlay.enabled` | 锁屏遮罩 | `settings` |
| `WS2.focus.preset` `WS2.focus.tuckChat` | 番茄钟时长与收起聊天 | `focus-preferences`，current |
| `WindowBrowserAppearanceStyle` `WindowBrowserDockEnabled` `WindowBrowserKeyboardPanelEnabled` `WindowBrowserLivePreviewEnabled` `WindowBrowserExcludedBundleIDs` `WindowBrowserHotKeyCode` `WindowBrowserHotKeyModifiers` `WindowBrowserPreferredStyle` `WindowBrowserFirstRunHintShown` | 窗口浏览。排除名单是 bundle ID | `settings` |
| `GlobalShortcut.<case>` `GlobalShortcut.numberedExpand` `GlobalShortcut.directionKeys` | 每个快捷键一条；方向键是一条记录 | `settings` |
| `InstallHistory` | 新装还是升级，一个整数 | `settings` |
| `ShadeDebugWindowDump` | 布尔。打开时 `dumpWindow` 写运行记录，标题写成 `[redacted]` | `settings` |
| `SUEnableAutomaticChecks` `SUScheduledCheckInterval` `WindowShadeUpdateChannel` `WindowShadeUpdateUseFallbackFeed` `WindowShadeMoveToApplicationsDeclined` | 与 Sparkle 同名的检查开关和间隔；频道、备用源、欢迎窗口是否跳过 | `update` 覆盖检查更新。频道键没有设置入口 |
| `ShadeJournalEntries` | 见上表，含窗口标题 | 见上表 |

系统偏好只读、不写：`AppleActionOnDoubleClick`，以及 `com.apple.symbolichotkeys` 里的 `AppleSymbolicHotKeys`。

## 日志与诊断尾

运行记录写 App 名、窗口 ID、坐标、角色、耗时。`dumpWindow` 不写窗口标题。恢复日志里的 `title` 不进 `wlog` 那几行（那几行写的是 `appName`）。

`WS2DiagnosticTail`：只有用户打开诊断时才留助手 stderr，最多 65536 字节，在内存里。`clear()` 丢掉这段字节，注释写明这不是密码学擦除，也不自动落盘、不上传。`codex-server` 仍是 planned，没有单独一行写这段尾部。

## 漏登清单

词法检查 `python3 tools/privacy/check-registry.py --repo .` 在这份 `main` 上已经失败。下面这些行不在登记表的 `sites` 里。这次不补登，留给主模型决定要不要登记：

```
UNREGISTERED prototype/App/GlobalShortcuts.swift: UserDefaults | nonisolated(unsafe) static var defaults: UserDefaults = .standard
UNREGISTERED prototype/App/UpdaterSystem.swift: SMAppService | /// 换成 SMAppService 会改变看护的生命周期，要另立工单；这里只把弃用调用收在一处，经协议转发，
UNREGISTERED prototype/Capture/ShareableContentCache.swift: SCShareableContent | /// SCShareableContent 没标 Sendable，只用这个本文件私有的壳子跨这一次边界，不对整个类型担保。
UNREGISTERED prototype/Capture/ShareableContentCache.swift: SCShareableContent | let content: SCShareableContent
UNREGISTERED prototype/Capture/ShareableContentCache.swift: SCShareableContent | ShareableSnapshot(content: try await SCShareableContent.current)
UNREGISTERED prototype/Support/SendableSystemHandles.swift: SCShareableContent | extension SCShareableContent: @retroactive @unchecked Sendable {}
UNREGISTERED prototype/Support/SendableSystemHandles.swift: SCStream | extension SCStream: @retroactive @unchecked Sendable {}
UNREGISTERED prototype/Support/SendableSystemHandles.swift: SCStream | /// 过滤器在本 App 里建好后只读不改（不设 includeMenuBar 之类的可写属性），只交给 SCStream / 截图接口使用。
```

内容上没有点名、这次也没有改登记状态的：

- 偏好副本 `ShadeJournalEntries`（含窗口标题）
- `SlideOver-<pid>.plist`
- `Update/journal.json`、`refused.json`、`guard.pid`、`Previous/`
- `OwnedCodex-v1` 与 `config.toml`（`codex-server` 仍是 planned）
- 诊断用的 stderr 尾部（只在内存）
- 只读的 Rectangle 配置

## 页面

D12：planned 行进入设置里的隐私页，灰色，值固定「还没读」，不取快照。声纹 `agent-voice-proof` 保持 planned。没有把任何 planned 改成 current。
