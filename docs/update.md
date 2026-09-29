# 应用内更新：Sparkle 负责搬运，我们在前后把关

2026-09-29 第二次改版。第一版推荐自己写更新器（b），理由是 Sparkle 2（a）不管授权、不管坏包。Aaron 问：能不能用 Sparkle 处理边角情况，
同时做到不丢授权、坏包不会让人没了 App、引导他把 App 装好用起来。第一次改版给出了合起来的方案；这一版按对抗审查补上了两条能绕过关的路
（旧版在关跑完前死掉、Sparkle 续装已准备好的安装）、几处钩子时机和一个会让关永远找不到包的 bug。只是方案，没有改代码。

## 结论

- **能合，不用 fork。** 查新版、清单、EdDSA 验签、下载、解包、清隔离标记、gktool 预扫描、等 App 退出、原子交换、重新打开，全交给 Sparkle 2.10.0。
  我们只补三件它不管的事：
  - **授权**：安装前拿解开的新版和正在运行的这一版比“指定要求”（designated requirement，下称 DR），不一样就不装，改成手动安装并说清要重新授权。
  - **坏包**：他同意更新时先备份旧版、交出看护；安装前让新版试跑一次；装后看护盯着新版起来，起不来就换回。之后 7 天里连续崩两次也会自己换回，设置里还能“回到 1.0.16”。
  - **引导**：官网下载处写清三步，照顾到 14 和标准账户；App 第一次打开时，不在“应用程序”里就多一步“移到‘应用程序’”；更新前后什么都不弹，只在要他动手时开口。
- **界面必须自己实现 `SPUUserDriver`。** Sparkle 里能在安装前否决的只有两处，都在 user driver 上：第 1 阶段做完后的 `showReadyToInstallAndRelaunch:`，
  和续装时 stage 为 `.installing` 的 `showUpdateFoundWithAppcastItem:state:reply:`。两处都只回 `.install` 或 `.skip`，**绝不回 `.dismiss`**。
  `updaterShouldRelaunchApplication:` 返回 NO、`shouldPostponeRelaunch…` 不调 block、回 `.dismiss` 都拦不住：安装器准备好以后，App 一退出就会装。
  标准界面拿不到否决点，中文也用“您”“安装并重启应用”，不合文案规则。
- **`.skip` 只是请求，不是否决。** 取消消息是异步发的；消息没送到而安装器听到 App 退出，照样装。所以否决后要确认 Sparkle 的安装任务真的没了，
  超时就由我们 `SMJobRemove` 掉，再放行退出。
- **看护在他点“更新并重新打开”时就交出去，不等过关。** 关里任何一处崩溃（我们自己的代码、试跑时内存吃紧），旧版一死，Sparkle 可能装一个没过关的包，而且不重开。
  这时只有提前交出的看护在场：没装上就重开旧版，装上了就补做 DR 比对和试跑，不过就换回。
- **两个前提来自源码。**
  - delegate 和 user driver 都拿不到解开的 `.app` 在哪，只能去 Sparkle 的内部缓存目录找。锁定版本，升级跑集成测试；找不到就不装。
  - Sparkle 没有“换回上一版”，也拒绝降级；退出后安装失败不会重开旧版，重开新版后也不看它有没有起来。备份、看护、换回都得自己写。
- **跟第一版比，省掉的**：自定义清单、验签、下载、解压、交换、“旧进程收尾但不退出”和 `createsNewApplicationInstance`。
  Sparkle 让 App 正常退出，`applicationWillTerminate` 里的 `restoreAll()` 照常执行，也不会有两个 WindowShade 同时在跑。
- **多出来的成本**：接入二进制框架（构建、按顺序重签、测试编译都要改）；一个约三百行的看护小 App；依赖已弃用的 `SMJobSubmit`（Sparkle 自己也靠它）；
  安装包变大，大小待实测；新版在 7 天内不能以旧版读不懂的方式改写停车日志和偏好。
- **必须先处理的两件事。**
  - 停掉“同一版本重新发布”：Sparkle 按 `CFBundleVersion` 认版本，换包不升 build，已装旧包的人永远收不到。
  - 开发证书 2027-06-14 到期，2027 年 5 月前续期，流程见“发布流程”。
- 已经装了 1.0.15、1.0.16 的人不会收到任何通知（这两版不联网）。第一个带更新器的版本要靠官网和 README 一句话接住，之后在菜单里点一下就行。

## 核实过的事实

第一版和第一次改版核实过、至今成立的，加上这次对抗审查在 2.x 分支原文里确认的几条。

**不会碰到“仍要打开”。** App 自己下载的文件默认不带隔离标记（`LSFileQuarantineEnabled` 默认 false，
[Launch Services Keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html)）。
Sparkle 装之前还会递归清一遍 `com.apple.quarantine`，macOS 14.4 起再跑 `/usr/bin/gktool scan`，把第一次打开时的检查提前做掉
（[SUPlainInstaller.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Autoupdate/SUPlainInstaller.m)；本机 `man gktool` 写明用途是预热缓存）。
Apple 仍会在第一次打开时查已知恶意内容
（[Gatekeeper and runtime protection](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web)），
所以更新后最多看到一次“正在验证”。这是从文档推出来的，要在另一个用户账户上实测。

**授权跟着 DR 走。** macOS 把 DR 记进授权数据库，以后每次都检查这一版是否满足它
（[TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)）。v1.0.15 发布包的 DR：

```text
identifier "com.windowshade.prototype" and anchor apple generic
  and certificate leaf[subject.CN] = "Apple Development: <账号> (G3TN2MBQ2Q)"
  and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */
```

它认 bundle ID、Apple 签发和证书 CN，不认路径、文件内容和具体哪一张证书。嵌入 Sparkle 框架不改变主程序的 DR，发布关会再验一遍。
改用 Developer ID 时 DR 一定会变（它认 Team，即 `subject.OU`），那时所有人要手动装一次、重新授权一次。
残余风险：我们比的是“新版满足当前这一版的 DR、且 DR 字符串相同”，授权数据库里存的那条要求（csreq）读不到。当前这一版能用，说明它满足 csreq；
字符串相同时可以推出新版也满足，但没法直接验证。所以界面上不写“保证”。

**开发证书一年一张。** 本机唯一的签名身份是 Apple Development，团队 `FVGLY6W6S4`，有效期 2026-06-14 到 2027-06-14，签名没有 Apple 安全时间戳。
“证书过期后已签名的版本仍能运行”这句 Apple 只写给了 Developer ID（[Certificates](https://developer.apple.com/support/certificates/)），
所以开发证书过期后会怎样按**未知**处理。续期后 CN 会不会变，Apple 没写，只能靠发布关拦。

**App 能替换自己，前提是同一个 Team。** 对签名的 App，同一 Team ID 的程序可以修改它的包，不经过“App 管理”授权
（[NSUpdateSecurityPolicy](https://developer.apple.com/documentation/bundleresources/information-property-list/nsupdatesecuritypolicy)）。
所以 Sparkle 的 `Autoupdate`、`Updater.app` 和我们的看护都必须用同一张证书重签；新旧两版 Team 不同时，新版替换自己会弹系统询问或直接失败。

**Sparkle 怎么认包**（[SUUpdateValidator.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SUUpdateValidator.m)、
[SUCodeSigningVerifier.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Autoupdate/SUCodeSigningVerifier.m)）：

- EdDSA 和“新版满足旧版的 DR”两项，过一项就装。EdDSA 通过时，新版的签名只需本身有效，不要求满足旧 DR，所以换了证书也会装，授权悄悄丢掉。
- 设了 `SUVerifyUpdateBeforeExtraction=YES` 时，解压前先验 EdDSA，解开后不再比 DR。所以 **DR 这一关只能我们自己做**。
- 换密钥的兜底只认 Developer ID 的 Team，Apple Development 签名永远过不了。
- Sparkle 自己的安装器和 App 之间也要校验连接，要求同一个 Team 的证书。
- 新版 `CFBundleVersion` 比旧版低就拒绝，所以“换回上一版”不能走 Sparkle。

**Sparkle 怎么装**（[AppInstaller.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Autoupdate/AppInstaller.m)、
[SUInstallerLauncher.m](https://github.com/sparkle-project/Sparkle/blob/2.x/InstallerLauncher/SUInstallerLauncher.m)、
[InstallerProgressAppController.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/InstallerProgress/InstallerProgressAppController.m)）：

1. 开始解包时用 `SMJobSubmit` 提交一个临时 launchd 任务，标签是 `<bundle id>-sparkle-updater`。App 可写时在用户域；不可写时改到系统域，弹管理员授权框。
2. **App 还开着时**做第 1 阶段：解压、验签、清隔离、对齐属主、登记 LaunchServices、gktool。解开的 App 放在
   `~/Library/Caches/com.windowshade.prototype/org.sparkle-project.Sparkle/Installation/<临时>/<临时>/WindowShade.app`，这是内部实现，不是 API
   （[SPULocalCacheDirectory.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SPULocalCacheDirectory.m)）。
3. 第 1 阶段做完、App 还在运行，就调用 `showReadyToInstallAndRelaunch:`
   （[SPUUIBasedUpdateDriver.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SPUUIBasedUpdateDriver.m)）。回 `.install` 就装；回 `.skip` 调用
   `cancelUpdate`，只记取消、不记跳过；回 `.dismiss` 只结束这次会话，App 退出时照样装
   （[SPUCoreBasedUpdateDriver.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SPUCoreBasedUpdateDriver.m)）。
4. **续装**：安装器已经准备好时再查一次，走的是 `showUpdateFoundWithAppcastItem:state:reply:`，`state.stage == .installing`。
   三种回复都进 `finishInstallationWithResponse`，不会再调用 ready-to-install；这里的 `.skip` 还会写 `SUSkippedVersion`
   （同一文件）。续装时 `shouldProceedWithUpdate` 也不调用（[SPUBasicUpdateDriver.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SPUBasicUpdateDriver.m)）。
5. **取消是异步的**：`cancelUpdate` 只是发出 `SPUCancelInstallation`；安装器收到才清理退出。`dismissUpdateInstallation` 只说明 App 这边的会话结束了
   （[SPUInstallerDriver.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SPUInstallerDriver.m)）。
6. **App 死掉时**：安装器听到 App 退出就记下；第 1 阶段已做完就直接装，没做完就等做完再装。重开只由 App 发出的 `SPUResumeInstallationToStage2` 决定，
   App 是崩掉的就不重开。连接断开时若还没决定完成安装，安装器会清理后退出。两者谁先到不确定，所以“崩了以后装没装”两种结局都要接。
7. 正常路径让 App 退出：发普通的退出事件，App 的收尾照常执行。
8. **App 退出后**：先试 `renamex_np(RENAME_SWAP)` 原子交换，失败时退回“挪开旧版、放进新版、再失败就挪回”。换下来的旧版随临时目录删掉。
   macOS 13 起，只有 `Autoupdate` 和新版的 Team 相同时才走原子交换和 gktool。
9. `Updater.app` 用 `NSWorkspace` 重开新版，不带参数，也不看它有没有起来。**第 8 步失败时直接退出，不重开**，他会看到 App 消失。
10. 这一段超过 0.7 秒时，Sparkle 会弹自己的进度窗（标题“Updating %@”，按钮“Cancel Update”），文字改不了。包小，大概看不到。

**`shouldProceedWithUpdate` 在“有新版本”之前调用**，不是在他点更新之后。返回 NO 走 abort，定时检查时他什么都看不到。所以它不能用来做需要他知道的判断。

**被系统挪走和只读卷。** App 从“下载”直接打开时，系统会把它挪到一个随机的只读路径里运行（App Translocation）。Apple DTS 说：
没有受支持的办法判断是不是被挪走，也拿不到原路径；用访达挪一下位置就会解除
（[App Translocation Notes](https://developer.apple.com/forums/thread/724969)）。Sparkle 的判断很简单：路径含 `/AppTranslocation/`，或
`statfs` 带 `MNT_RDONLY`，就拒绝更新（[SUHost.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SUHost.m)、SPUBasicUpdateDriver.m）。
定时检查碰到这种情况默认不出声（[Documentation](https://sparkle-project.org/documentation/)）。位置问题要我们自己查、自己教。

**后台活动规则。** App 退出后还在跑的 helper 和 launchd 任务都算后台活动，用户可以在“登录项与扩展”里关掉；
屏幕上看得见的进程不受限（[Managing ongoing background processes](https://developer.apple.com/documentation/appkit/managing-ongoing-background-processes-in-your-mac)）。
macOS 26 起，App 退出后它起的后台任务还在跑时，系统可能弹窗问
（[部署指南](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web)）。
有第三方报告说，macOS 27 关掉后台活动后，用 `SMJobSubmit` 起的安装器在宿主退出约 5 秒后被杀
（[Squirrel.Mac #336](https://github.com/Squirrel/Squirrel.Mac/issues/336)）。Sparkle 的安装器和我们的看护都是这样提交的，可能一起被杀。

**第一次打开被拦。** macOS 15 起不能再按住 Control 点“打开”绕过，只能去系统设置点“仍要打开”；14 上两种都行，对话框的按钮也不一样
（[Updates to runtime protection in macOS Sequoia](https://developer.apple.com/news/?id=saqachfa)）。按钮只在尝试打开后大约一小时内出现，
点过以后这个 App 记为例外（[mh40616](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)、
[102445](https://support.apple.com/en-us/102445)）。点“仍要打开”和打开辅助功能、屏幕录制的开关都要管理员身份，标准账户要输入管理员的名字和密码。
中文系统设置里的名字 14、15、26 叫“隐私与安全性”，27 叫“隐私与安全”
（Apple 中文页 [15](https://support.apple.com/zh-cn/guide/mac-help/mh40616/15.0/mac/15.0)、[27](https://support.apple.com/zh-cn/guide/mac-help/mh40616/27/mac/27)），
所以引导里写“隐私与安全”，各版本都对得上。本机 macOS 27.0 的 `CoreServicesUIAgent` 里有一组专给开发证书签名 App 的拦截文案，
标题大意是“供……用于个人测试目的”。我们的包会不会命中，只能实测。

## 分工

| 环节 | 谁做 | 怎么做 |
| --- | --- | --- |
| 按时检查 | Sparkle | `SUScheduledCheckInterval`，每天或每周；App 在哪里都照常检查，开发版不启动更新器 |
| 清单 | Sparkle | `https://windowshade.aaronlau.me/appcast.xml`，清单本身签名（`SURequireSignedFeed`） |
| 选版本 | Sparkle + 我们 | Sparkle 按版本、系统、芯片、分批推送挑；定时检查时我们用 `bestValidUpdateInAppcast:forUpdater:` 去掉 `refused.json` 里的版本 |
| 界面 | 我们 | 自己的 `SPUUserDriver`：菜单那一项和更新小窗 |
| 能不能一键更新 | 我们 | 打开小窗时判断位置、写权限、卷、空间、别的用户、`refused.json`；不能就说原因，不回 `.install` |
| 备份、写日志、交出看护 | 我们 | 他点“更新并重新打开”后、回 `.install` 前 |
| 下载、验 EdDSA、解压 | Sparkle | `SUVerifyUpdateBeforeExtraction=YES`：EdDSA 不过就不解开 |
| 清隔离、gktool、登记 | Sparkle | 第 1 阶段，App 还开着 |
| **安装前的关** | 我们 | `showReadyToInstallAndRelaunch:`，以及续装时 `.installing` 的 `showUpdateFound`：找到解开的 App，比 DR、试跑，过了才回 `.install` |
| 否决到底 | 我们 | 回 `.skip` 后确认 `<bundle id>-sparkle-updater` 任务没了，超时自己 `SMJobRemove` |
| 退出、交换、重开 | Sparkle | App 正常退出，原子交换，重开新版 |
| 装后看护 | 我们 | 旧版一退出就接手：没装上就开旧版；装了没过关的包就补关；新版起不来就换回 |
| 看护被杀的兜底 | 我们 | 每一版启动时先读更新日志，补完或换回；7 天内连续崩两次自己换回 |
| 回到上一版 | 我们 | 设置里 7 天内一键换回，用旧版自带的看护 |
| 位置引导 | 我们 | 第一次打开时多一步“移到‘应用程序’” |

## G1 不丢授权

1. **发布关**（发布前，见“发布流程”第 4 步）：把要发的 zip 解开，新版的 DR 字符串必须和上一版发布包的 DR **完全相同**。
   不同就停下，只有有意换证书时才走“换证书的一版”。
2. **安装前比 DR**（客户端，在安装前的关里）：
   - 取正在运行这一版的 DR：`SecCodeCopySelf` → `SecCodeCopyDesignatedRequirement`；
   - 对解开的新版做 `SecStaticCodeCheckValidityWithErrors`，参数是 `kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode`，要求用上面那个 DR；
   - 再取新版自己的 DR，`SecRequirementCopyString` 后和旧 DR 字符串逐字相同。
   前一项保证这一次授权不丢，后一项保证下一次更新也还能比。任一项不过就回 `.skip`，说“这一版要手动安装……”。
   这里默认不把证书过期算作失败（[considerExpiration](https://developer.apple.com/documentation/security/seccsflags/considerexpiration)），和授权数据库的判断一致。
3. **装后自查**：新版启动后，用 `SecCodeCheckValidity(self, 日志里的 oldDR)` 再确认一次，并比 DR 字符串。不过就记 `abnormal`，换回。
   正常流程下这一步不会失败，它接的是“关没跑成 Sparkle 就装了”那种情况。
4. **换证书的一版**（续期后 CN 变了，或改用 Developer ID）：清单里标成 `sparkle:informationalUpdate`，配 `belowVersion=<换证书后第一个 build>`。
   Sparkle 只给下载链接，不会一键跨过 DR 变化（[Publishing](https://sparkle-project.org/documentation/publishing/)）。
   EdDSA 密钥这一版不能同时换，Sparkle 规定两样一次只能换一样（[Documentation](https://sparkle-project.org/documentation/)）。
5. **授权还是丢了**（比如 macOS 自己的问题）：不换回，因为换回也找不回授权。新版启动时比较更新前记下的授权状态；少了哪一项，
   就打开欢迎窗口的授权那一步，换成“再打开一次这两项”那组文案。

## G2 不让人没了 App

### 更新日志

`~/Library/Application Support/WindowShade/Update/journal.json`，每次先写临时文件再原子改名。App、看护、新旧两版都读写它：

```json
{
  "from": { "version": "1.0.16", "build": 16 },
  "to":   { "version": "1.0.17", "build": 17 },
  "appPath": "/Applications/WindowShade.app",
  "oldDR": "identifier \"com.windowshade.prototype\" and anchor apple generic and …",
  "backup": "~/Library/Application Support/WindowShade/Previous/WindowShade-1.0.16-16.zip",
  "permissionsBefore": { "accessibility": true, "screenRecording": true },
  "phase": "started",
  "startedAt": "2026-10-06T10:00:00+08:00",
  "oldPID": 812,
  "launches": [ { "build": 17, "pid": 905, "cleanExit": false, "runSeconds": 0 } ]
}
```

`phase` 主线：`started`（已备份、已交出看护，交给 Sparkle 下载）→ `gating`（关在跑）→ `approved`（过关）→ `launched`（新版进了 `main`）→ `healthy`。
旁路：`cancelled`、`refused`、`installFailed`、`restoring`、`restored`、`rollbackRequested`。

同目录另有两个文件：

- `refused.json`：换回过或试跑没过的 build，每条带原因（`crashed`、`selfCheckFailed`、`drChanged`）。它是“拒绝过的版本”的唯一记录，
  不靠 Sparkle 的 `SUSkippedVersion`。
- `Previous/backup.json`：备份的版本号、build、DR、SHA-256，全部从备份里的 App 读出，不推算。“回到 x.y.z”用它。

### 能不能一键更新

定时检查照常做，App 在哪里都一样；有新版本时菜单那一项变成“更新到 1.0.17…”。他打开小窗时判断，不能一键更新就说原因、给能走通的那一步：

| 条件 | 不满足时 |
| --- | --- |
| 不在被系统挪走的路径里，卷不是只读的，在 `/Applications` 或 `~/Applications` 里 | “先把 WindowShade 移到‘应用程序’文件夹……”，按钮 **移到“应用程序”** |
| App 所在卷 `getattrlist` 报告 `VOL_CAP_INT_RENAME_SWAP`，且和 `~/Library/Caches` 在同一个卷 | 同上：多半是装在外接磁盘上 |
| App 所在文件夹和 App 本身当前用户都能写 | “要这台 Mac 的管理员来更新。”，按钮 **好** |
| 没有别的用户开着 WindowShade（按进程表查同一路径、不同 uid） | “这台 Mac 上还有别人开着 WindowShade……” |
| 磁盘剩余空间至少是安装包的 4 倍（备份、下载、解开、交换） | “Mac 上的空间不够……” |
| 这个 build 不在 `refused.json` 里 | 只有手动检查会看到它：“1.0.17 上次在这台 Mac 上没能正常打开……”，按钮 **再试一次** / 稍后再说 |

- 不走 Sparkle 的管理员授权：系统域安装时解开的 App 不在我们的缓存目录，关就看不到；以 root 装的包，用户级的看护也换不回。
  标准账户里“下载新版手动装”同样写不进 `/Applications`，所以不给“打开下载页”这条死路。
- 别的用户开着旧版时不更新：他的旧进程会从换过的包里懒加载 `Duo.metallib` 和本地化文件，可能崩。
- 这些判断不放进 `shouldProceedWithUpdate`：它在“有新版本”之前调用，返回 NO 会让定时检查永远不出声。

### 他点“更新并重新打开”之后

在 `showUpdateFound` 的回复处理里、回 `.install` 之前，按顺序做：

1. **再判断一次**上表。
2. **备份**：`ditto -c -k --keepParent` 把当前的 App 压成 zip，先写成 `Previous/….zip.partial`。压成 zip，系统就不会把它当成第二个 WindowShade 登记。
   写完立刻解到临时目录，`codesign --verify --strict` 并确认 DR 等于正在运行的这一版，过了才算备份成功；不过就不更新。
   旧的那份备份到 `approved` 才被替换，所以被关拦下或他取消时，“回到 1.0.16”那份还在。
3. **交出看护**：把正在运行这一版里的 `Contents/Helpers/WindowShadeUpdateGuard.app` 拷到 `Application Support/WindowShade/Update/`
   （换包时它不能在包里；用的是已知能跑的旧版里那一份），验签名和我们同一个 Team。先 `SMJobRemove` 同名标签，再用 `SMJobSubmit` 在用户域提交。
   任务字典照抄 Sparkle 的：`RunAtLoad`、`LaunchOnlyOnce`，不写 plist 文件，标签 `com.windowshade.prototype.update-guard`，参数是日志路径。
4. **写日志** `phase=started`，记下旧 DR、旧 pid、授权状态、开始时间。
5. 回 `.install`。

`stage` 是 `.downloaded` 时同样走这五步。`stage` 是 `.installing`（续装）时，先走这五步，再跑下面的安装前的关，过了才回 `.install`，否则回 `.skip`。
续装的 `.skip` 会写 `SUSkippedVersion`；这不影响判断，因为我们只认 `refused.json`，他手动检查时我们会绕过 Sparkle 的跳过记录再问一次。

`.dismiss`（“稍后再说”）只在 `stage` 是 `.notDownloaded` 或 `.downloaded` 时用：这时安装器还没起来，不会装。

### 安装前的关

Sparkle 调用 `showReadyToInstallAndRelaunch:`（或续装时进入上一节）时跑，写 `phase=gating`，整个过程几秒：

1. **找到解开的 App**：在 `…/org.sparkle-project.Sparkle/Installation/` 下，只看**创建时间**晚于 `startedAt` 的第一层临时目录，
   往里找 `CFBundleIdentifier` 等于我们的、`CFBundleVersion` 等于这次版本的 `.app`，必须正好一个。
   不看 `.app` 的修改时间：解包保留归档里的时间，也就是构建时间，一定早于 `startedAt`。
   找不到或不止一个就否决。这样 Sparkle 改了目录结构时，结果是“不装”，不是“不检查就装”。
2. **不在 `refused.json` 里**，位置和上表仍然成立（续装时这一步是第一次做）。
3. **比 DR**：见 G1 第 2 步。
4. **看系统版本**：新版的 `LSMinimumSystemVersion` 不高于本机。
5. **试跑**：以超时 10 秒运行 `WindowShade.app/Contents/MacOS/WindowShade --self-check`，要求返回 0，输出里带上这次的 build 号。
   Sparkle 已经清掉隔离标记，直接运行没有障碍。超时重试一次；返回非零、框架缺失才记进 `refused.json`，偶发的超时只是这次不装。
   `--self-check` 是长期约定，每一版都得支持：写在 `main.swift` 最前面，不建窗口，不碰授权，不联网，不写文件；
   只让系统加载全部链接的框架（包括 Sparkle 和 `libswift_Concurrency`），载入 `Duo.metallib`，读一遍资源，就退出。
6. **放行**：备份从 `.partial` 改成正式名并更新 `backup.json`，写 `phase=approved`，回 `.install`。Sparkle 让 App 正常退出，交换，重开新版。

**否决**：回 `.skip`，写 `refused` 或 `cancelled`，然后确认 Sparkle 真的停了：

1. 等 `dismissUpdateInstallation`；
2. 查用户域里 `<bundle id>-sparkle-updater` 任务还在不在（`SMJobCopyDictionary`），最多等 5 秒；
3. 还在就 `SMJobRemove` 这个标签（同一用户域，我们删得掉），再查一次；
4. 确认没了，才 `SMJobRemove` 看护、删掉 `.partial` 备份、放行挂起的退出。

第 1 步不过只说“没能更新到 1.0.17，稍后再试。”；DR 不对说“这一版要手动安装……”；试跑没过说“1.0.17 在这台 Mac 上没能正常打开，所以没有更新。”。

### 退出请求

`applicationShouldTerminate`：

- **下载中**：调用下载的取消 block，写 `cancelled`，立即 `.terminateNow`。不挡注销和关机。
- **解包开始到结论**（几秒）：`.terminateLater`。安装器第 1 阶段做完后，App 一退出它就会装，所以这时的退出先记下，到关那一步直接否决、确认 Sparkle 停了，再放行。
- **`approved` 之后**：这是 Sparkle 发起的退出，`.terminateNow`。

这只防得住正常退出。崩溃、SIGKILL、强制退出由看护接。

### 看护

`prototype/UpdateGuard/`，一个不带 Dock 图标的小 App（`LSUIElement`），约三百行，用我们的证书签名。它在 `started` 就已经在跑，做完立刻退出：

1. **旧版还开着**：盯旧 pid（kqueue `NOTE_EXIT`），同时读日志。日志变成 `cancelled` 或 `refused`、旧版干净退出，它就退出。
2. **旧版退出了**：从这一刻起显示和 WindowShade 相同的菜单栏图标，直到交给新版或旧版为止。屏幕上看得见的进程不受后台活动限制，菜单栏图标也不会空出来。
   然后按退出时的 `phase` 分：
   - **`started`、`gating`（关还没跑完）**：旧版是崩掉的，或者我们自己的代码崩了。等 `<bundle id>-sparkle-updater` 任务结束，最多 120 秒。
     - 已装 App 的版本没变：Sparkle 没装。写 `installFailed`，打开旧版。
     - 版本变了：这是**没过关的安装**。对已装的新版补做 DR 比对和试跑（规则同关）；过了按下面 `approved` 继续，不过就换回。
   - **`approved`**：等已装 App 的 `CFBundleVersion` 变成新版，同时看安装任务还在不在，最多 120 秒。
     任务没了、版本也没变，是交换失败：写 `installFailed`，打开旧版。
3. **等新版起来**：新版 pid 20 秒还没出现在日志里，说明 Sparkle 没重开，看护自己打开。
4. **等 `healthy`**，最多 60 秒。下面几种情况换回：
   - 新版被信号结束，或退出时没写 `cleanExit`；
   - 新版写了 `abnormal`；
   - 60 秒到了。卡住的新版先发 SIGTERM，5 秒后 SIGKILL；它收起的窗口由旧版启动时的停车日志救回。
   新版写了 `cleanExit` 才退出的（他自己按了退出、授权后系统要求重新打开、`--after-move` 重开），不算失败；之后又出现同一版的新 pid 就接着盯，没出现就退出，
   剩下的由新版下次启动接着判断。
5. **换回**：
   - 先写 `refused.json` 和 `phase=restoring`，再动文件。否则交换后、写日志前掉电，旧版会把日志当成“没装上”安静清掉，坏版本还会被再次提醒。
   - 把备份解到和 App 同一个卷的临时目录（`url(for: .itemReplacementDirectory, …, appropriateFor:)`），核对 SHA-256，确认 DR 等于 `oldDR`（换回也不能丢授权）；
   - `renamex_np(RENAME_SWAP)` 换回，删掉换下来的坏版，写 `restored`，打开旧版。
6. 拿到 `healthy` 就写完日志、收起图标、退出。

看护打开 App 一律按 `appPath` 这个 URL（`NSWorkspace.openApplication(at:)`），不按 bundle ID：“下载”里的原件、缓存里解开的副本、换回用的临时副本，
同一个 bundle ID 都可能被 LaunchServices 选中。换回的代码在 `prototype/Update/UpdateRestore.swift`，App 和看护编译同一份。

### 新版启动

在 `main.swift` 里，`--self-check` 之后、`NSApplication` 之前，先读更新日志：

- **我是 `to` 那一版**：在 `launches` 里记一条，写 `launched`。
  - 日志停在 `started` 或 `gating`，而看护不在：关没跑完就被装上了，看护也没了。这时 DR 自查必做，不过就交给旧版的看护换回。
  - 看护不在、这个 build 已经有一次启动没走到 `healthy`：直接交给旧版的看护换回，不再往下跑。所以新版只要能跑到 `main`，就能换回。
  - 否则照常启动。启动完成、稳定运行 10 秒后做 G1 第 3 步的自查：过了写 `healthy`，不过写 `abnormal` 并退出。
  - 写 `healthy` 后 `SMJobRemove` 看护任务，比较 `permissionsBefore`，少了就走 G1 第 5 步。
- **我是 `from` 那一版**：
  - 读到 `restored` 或 `installFailed`：说一次对应的话，然后清掉。
  - 读到 `restoring`：换回做到一半，由这一版用自带的 `UpdateRestore` 补完（它本来就是旧版），再说一次。
  - 读到 `started`、`gating`、`approved`、`cancelled`，而我还在、看护也不在：这次没装上，安静地清掉。
- `healthy` 只看 App 是否正常启动、稳定运行，不看授权：没授权的人也能写 `healthy`。授权另走 G1 第 5 步。

“交给旧版的看护换回”，指用 `Update/` 里那份从旧版拷出来的看护，带 `--restore` 提交。发起回退的代码来自已知能跑的那一版；那份不在时才用新版自带的 `UpdateRestore`。

### 写了 `healthy` 以后又崩

`healthy` 只要求空闲 10 秒稳定，而 WindowShade 的高风险路径（收起窗口、看一眼、事件监听）都要他动手才触发，多数坏包能过这 10 秒。
第二次启动（比如登录时）必崩的包，他连设置里的“回到 1.0.16”都够不着。所以更新后 7 天内：

- `main` 里、`NSApplication` 之前，在 `launches` 记下这次启动；`applicationWillTerminate` 写 `cleanExit`，运行满 30 分钟也记为正常。
- `to` 这一版**连续两次**既没 `cleanExit` 也没跑满 30 分钟，第三次启动时就在 `main` 里交给旧版的看护换回，不经过界面。旧版启动后说一次“已经换回”。

### 回到上一版

更新成功后 7 天内，设置里有“回到 1.0.16”（版本号读 `backup.json`）。点了以后：写 `rollbackRequested`，提交旧版的看护，App 正常退出；
看护按上面第 5 步换回，把 1.0.17 记进 `refused.json`，打开 1.0.16。以后出了更大版本号的修复版，照常提醒。
他自己要的换回不再弹话。7 天后，或者下一次更新成功时，删掉旧备份。

### 换回以后旧版要读得懂

停车日志在 `prototype/Recovery/Journal.swift`，带 `schemaVersion: 3`，UserDefaults 也新旧共用。新版改了格式，换回后的旧版可能救不回收起的窗口，
那也是“没了能用的 App”。所以定为硬约束：

- 新版不得以上一版读不懂的方式改写停车日志和偏好。要改格式就双写，旧格式至少保留到再下一版。
- 发布关加一项：上一版读得懂这一版写下的状态（见“发布流程”第 4.9 步）。

## G3 引导

### 官网：点“下载 Mac 版”后在原地展开三步

- 现在按钮链到 GitHub Releases 页（`site/scripts/chrome.mjs:6`），那一页还列着“Source code (zip)”，新人容易点错。
  改成直接下载 App 的 zip：官网构建时按 `Info.plist` 的版本号拼出直链。
- 页面不跳走，在按钮下方展开下面的内容；“怎么装？”那条问答改成指向这里（`site/scripts/content.mjs` 223、437 行）。
- 每一步配一张实拍的裁切截图，圈出按钮。截图在干净的测试账户上拍，系统取 14、15、26、27，中英文、浅色深色各一套。
- 版本、大小、系统要求、SHA-256、源代码链接放在按钮旁边。
- README 和 README_CN 的“下载”一节换成同样的三步。

| | 中文 | English |
| --- | --- | --- |
| 标题 | 三步装好 | Install in three steps |
| 1 | 把 WindowShade 拖进“应用程序”文件夹。 | Drag WindowShade into your Applications folder. |
| 2 | 双击打开它。系统说没能打开时，先关掉这个提示。 | Open it. When macOS says it can’t open it, close that message. |
| 3 | 打开“系统设置”→“隐私与安全”，往下翻，点“仍要打开”，再按提示输入密码。 | Open System Settings → Privacy & Security, scroll down, click Open Anyway, then enter your password when asked. |
| 尾句 | WindowShade 还没交给 Apple 检查（这一步叫公证），所以第一次打开时系统会拦一下。以后在菜单里就能更新。 | WindowShade isn’t notarized by Apple yet, so macOS stops it the first time. After that, you update it from the menu. |
| 已有旧版 | 已经装了旧版：把新版拖进“应用程序”，选“替换”。辅助功能和屏幕录制不用重新打开。 | Already have an older version? Drag the new one into Applications and choose Replace. Accessibility and Screen Recording stay on. |
| 装不上（折叠） | 没看到“仍要打开”：先双击 WindowShade，再回来找。系统说“已损坏”：用 Safari 重新下载，双击解开压缩包。用的是标准账户：“仍要打开”和授权都要管理员输入名字和密码。 | No Open Anyway button? Open WindowShade once, then look again. “Damaged”? Download again in Safari and double-click the ZIP. On a standard account, an administrator needs to enter their name and password. |

- 第 2 步不点名按钮：14 上的对话框和 15 以后不一样。14 上按住 Control 点“打开”也行，但不写进三步，免得分叉。
- “已有旧版”那句只对发布关放行的版本成立（DR 与上一版逐字相同），第一个带更新器的版本一定满足。1.0.15、1.0.16 不联网，只能靠这句接住。
- 不写终端命令、`xattr`，也不教人关掉安全检查。
- 不提供 Homebrew：官方 cask 从 2026 年 9 月起不收过不了 Gatekeeper 的包（[Homebrew 5.0.0](https://brew.sh/2025/11/12/homebrew-5.0.0/)、
  [Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)），自建 tap 要删隔离标记，正是 Homebrew 在收紧的做法。
- 首次下载保持 zip，和 Sparkle 用同一个包。
- 接入 Sparkle 后包里有了符号链接，用不保留符号链接的第三方工具解压，会得到“已损坏”。所以写“双击解开”，并列为实测项。

### App 第一次打开：需要时多一步“移到‘应用程序’”

**什么时候出现**：不满足“能不能一键更新”表里前两行，即路径含 `/AppTranslocation/`、卷只读、不在 `/Applications` 或 `~/Applications`、或不在系统卷上。
这一步排在欢迎窗口三步前面，用同一个舞台，动画是图标落进“应用程序”文件夹；欢迎窗口本身还是三步。
授权和“登录时打开”都放在移好之后：否则登录项会指向“下载”。

| 元素 | 文案 |
| --- | --- |
| 标题 | 放进“应用程序”文件夹 |
| 导语 | Mac 上的 App 都放在这里。放进去以后，才能在菜单里更新 WindowShade。 |
| 按钮 | **移到“应用程序”**（默认）/ 跳过 |
| 那里已有旧版 | 副句：“应用程序”里的 WindowShade 1.0.14 会换成这一版。 |
| 那里已有同版或更新的版本 | “应用程序”里已经有 WindowShade 1.0.17。按钮：**打开它** |
| 没能移过去 | 没能移过去。把 WindowShade 拖进“应用程序”文件夹，再从那里打开它。按钮：**在访达中显示** |

点“移到‘应用程序’”后做四件事：

1. **复制**：复制正在运行的这份（`Bundle.main.bundleURL`，被系统挪走时也读得到）。先复制到目标卷的临时目录，清掉 `com.apple.quarantine`，
   验签名和 DR 与自己相同，再改名放进去。目标是 `/Applications`，写不进去（标准账户）就放 `~/Applications`，没有就建一个。两处都能一键更新。
2. **替换旧版**：目标处有旧版且正在运行时，先请它退出；用 `renamex_np` 换掉，换下来的旧版移到废纸篓。
3. **重新打开**：从新位置打开，参数 `--after-move`，当前进程退出；新进程的欢迎窗口从第 1 步接着走。
4. **原件不动**：“下载”里的那份原件先不动。
   - 被系统挪走时，拿不到原路径（DTS 说没有受支持的办法）；
   - 碰“下载”文件夹可能触发系统的“访问‘下载’文件夹”询问，那比留一份原件更糟。
   - 列为实测项：挪原件不会触发询问的话，再改成把原件移到废纸篓。
   - 他以后误开原件时，这一步会说“‘应用程序’里已经有 WindowShade 1.0.17”，并替他打开那一份。

点“跳过”后不再追问。定时检查照常，有新版本时菜单那一项照样变成“更新到 1.0.17…”，点开后落到“先把 WindowShade 移到‘应用程序’文件夹……”，
按钮同样是“移到‘应用程序’”。不在“应用程序”里不会变成永远不出声。
这合 direction.md 的“点提示就替他做成那一下”。不接 LetsMove 库，只借它的流程（[PFMoveApplication.m](https://github.com/potionfactory/LetsMove/blob/master/PFMoveApplication.m)）。

### 授权那一步和更新怎么接

- 欢迎窗口不问更新的事。
- Info.plist 显式写 `SUEnableAutomaticChecks`，delegate 的 `updaterShouldPromptForPermissionToCheckForUpdates:` 返回 NO：Sparkle 不会在第二次启动时弹窗问。
- 当前用户是标准账户时，授权页导语下多一句：“打开这两项时，要输入管理员的名字和密码。”
- 授权页（第 3 步）同时是“更新后授权不在了”时的落点：

| 情况 | 标题 | 导语 |
| --- | --- | --- |
| 更新或手动装了新版后缺授权 | 再打开一次这两项 | 装好新版本后，系统要你重新打开辅助功能和屏幕录制。 |
| 从系统设置回来 10 秒还是没授权（常驻小字） | — | 开关开着却没用？在列表里选中 WindowShade，点“−”删掉，再回来点“去授权”。 |

- 更新后第一次启动不重放欢迎窗口：“看过引导”存在 UserDefaults 里，跟着 bundle ID 走，替换 App 不影响它。

### 更新前后他看到什么

有新版本不算“卡住”：刘海不开口，不弹窗，不加红点，只是菜单里那一项换个说法。

1. 菜单栏菜单和应用菜单里“检查更新…”变成“更新到 1.0.17…”。
2. 点它，打开更新小窗：版本、改动最多三条、“更新前，窗口会先恢复原样。”，按钮“更新并重新打开 / 稍后再说 / 跳过这一版”。
   不能一键更新时，按钮换成对应的那一个。
3. 点“更新并重新打开”后，小窗里依次显示：
   - 正在下载…（4 MB 级别，几秒）；
   - 正在准备…（解压、Sparkle 第 1 阶段、我们的关，几秒）；
   - 正在重新打开…
4. 收起、收进刘海的窗口恢复原样。菜单栏图标由看护接着显示，新版起来后交回，不会空出来。系统可能显示一次自己的“正在验证”。
5. 之后什么都不弹。设置里“当前版本 1.0.17”那一行，7 天内多出“看更新记录”和“回到 1.0.16”。

只有下面几种情况会开口，而且都在更新小窗或授权页里：没装上、换回了、这一版要手动装、缺授权、要他先做一步（移位置、找管理员、腾空间）。

## Sparkle 的接法

### Info.plist

| 键 | 值 | 为什么 |
| --- | --- | --- |
| `SUFeedURL` | `https://windowshade.aaronlau.me/appcast.xml` | 官网是 Cloudflare Pages 静态站；开发版不写，更新器就不启动 |
| `SUPublicEDKey` | `generate_keys` 生成的公钥 | EdDSA 必填 |
| `SUVerifyUpdateBeforeExtraction` | YES | EdDSA 不过就不解开；DR 由我们的关来比 |
| `SURequireSignedFeed` | YES | 清单被改也不认（2.9 起）；签法接入时照文档核对 |
| `SUEnableAutomaticChecks` | 按“要 Aaron 定的”第 1 条 | 显式写上，Sparkle 就不会自己弹窗问 |
| `SUScheduledCheckInterval` | 86400 | 设置里可改为每周 |
| `SUAllowsAutomaticUpdates`、`SUAutomaticallyUpdate` | NO | 没有“退出时静默装”这条绕过关的路；静默安装可能发生在注销时，那时没人看着 |
| `SUEnableSystemProfiling` | NO | 不发系统信息 |

不需要 `SUEnableInstallerLauncherService` 等 XPC 键：App 没开沙盒，默认都是 NO（[Sandboxing](https://sparkle-project.org/documentation/sandboxing/)）。

### 自己的 `SPUUserDriver`（`prototype/Update/SparkleBridge.swift`）

16 个必选方法，全部列出（[SPUUserDriver.h](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SPUUserDriver.h)）。带 acknowledgement 的必须调用，否则 Sparkle 的会话不会结束：

| 方法 | 我们做什么 |
| --- | --- |
| `showUpdatePermissionRequest:reply:` | 不出界面，按设置应答（理论上不会被调用） |
| `showUserInitiatedUpdateCheckWithCancellation:` | 小窗显示“正在检查…” |
| `showUpdateFoundWithAppcastItem:state:reply:` | 定时检查：只改菜单那一项，`reply` 留到他打开小窗时再给；手动检查：直接打开小窗。`.installing` 时先过关。`informationOnlyUpdate` 的条目显示“这一版要手动安装……” |
| `showUpdateReleaseNotesWithDownloadData:` | 不用（改动说明写在清单的 `<description>` 里），不出界面 |
| `showUpdateReleaseNotesFailedToDownloadWithError:` | 不出界面 |
| `showUpdateNotFoundWithError:acknowledgement:` | 手动检查时显示“已经是最新版本。”；立即应答 |
| `showUpdaterError:acknowledgement:` | 手动检查时按错误码映射到我们的句子；定时检查只写日志；立即应答 |
| `showDownloadInitiatedWithCancellation:` | “正在下载…”；取消 block 留给退出请求用 |
| `showDownloadDidReceiveExpectedContentLength:`、`showDownloadDidReceiveDataOfLength:` | 进度 |
| `showDownloadDidStartExtractingUpdate`、`showExtractionReceivedProgress:` | “正在准备…”；从这里起退出请求先挂起 |
| `showReadyToInstallAndRelaunch:` | **安装前的关**，只回 `.install` 或 `.skip` |
| `showInstallingUpdateWithApplicationTerminated:retryTerminatingApplication:` | “正在重新打开…”；App 没退出时调用重试 |
| `showUpdateInstalledAndRelaunched:acknowledgement:` | 不出界面，立即应答 |
| `showUpdateInFocus` | 把小窗提到前面 |
| `dismissUpdateInstallation` | 关小窗；否决时接着确认安装任务没了 |

### `SPUUpdaterDelegate`

| 方法 | 用法 |
| --- | --- |
| `feedURLStringForUpdater:` | 平时用官网；上次因网络出错失败时，换成 GitHub Release 附件里的同一份 `appcast.xml`（清单签了名，放哪里都一样） |
| `updaterShouldPromptForPermissionToCheckForUpdates:` | NO |
| `bestValidUpdateInAppcast:forUpdater:` | 定时检查时，最好的那一版在 `refused.json` 里就返回 `SUAppcastItem.emptyAppcastItem`；手动检查（我们发起前记一个标记）不过滤 |
| `updater:shouldProceedWithUpdate:updateCheck:error:` | 返回 YES，只写日志。它在“有新版本”之前调用、续装时不调用，不能当关 |
| `updater:willInstallUpdate:` | 写日志 |
| `updater:didAbortWithError:`、`updater:didFinishUpdateCycleForUpdateCheck:error:` | 复原菜单那一项，写日志 |
| `allowedChannelsForUpdater:` | 设置里没有入口；Aaron 自己用 `defaults write` 打开 `beta` 频道，先用一版再推给所有人 |

**有意不用的钩子**：
- `updaterShouldRelaunchApplication:` 和 `updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:`：拦不住，退出时照样装。
- `updater:willInstallUpdateOnQuit:immediateInstallationBlock:`：只用于静默自动更新，我们关掉了。

`SPUUpdater` 上设 `userAgentString = "WindowShade/1.0.17"`，`sendsSystemProfile = false`。

## 会改的文件

| 文件 | 改什么 |
| --- | --- |
| `prototype/Update/UpdateController.swift`（新） | 状态、设置读写、菜单文字、“能不能一键更新”；不依赖 Sparkle |
| `prototype/Update/SparkleBridge.swift`（新） | 整个文件包在 `#if canImport(Sparkle)` 里：`SPUUpdater`、delegate、`SPUUserDriver`，只转发给别的文件 |
| `prototype/Update/UpdateGate.swift`（新） | 找解开的 App、比 DR、试跑、备份、交出看护、否决后确认安装任务没了 |
| `prototype/Update/UpdateJournal.swift`（新） | 更新日志、`refused.json`、`backup.json`、启动时的恢复规则、连续崩溃计数；看护也编译它 |
| `prototype/Update/UpdateRestore.swift`（新） | 解备份、验 DR、交换、打开；看护也编译它 |
| `prototype/Update/InstallLocation.swift`（新） | 判断位置和卷，移到“应用程序” |
| `prototype/Update/UpdateWindow.swift`（新） | 更新小窗 |
| `prototype/UpdateGuard/main.swift`（新） | 看护小 App，单独编译，不进主程序 |
| `prototype/main.swift` | 最前面处理 `--self-check`；接着读更新日志、记启动 |
| `prototype/WindowShade.swift` | 加 `applicationShouldTerminate`（按上面三段）；`applicationWillTerminate` 写 `cleanExit`；稳定 10 秒后写 `healthy` |
| `prototype/Recovery/Journal.swift` | 不改格式；加注释写明双写约束 |
| `prototype/App/MenuBarController.swift`、`prototype/App/StandardMenu.swift` | “关于 WindowShade”下面加“检查更新…” |
| `prototype/App/Preferences.swift` | “权限与启动”页“启动”下面加“更新”一组 |
| `prototype/App/Welcome.swift`、`docs/welcome.md` | 需要时的“放进‘应用程序’文件夹”一步；标准账户那一句；授权页的更新后文案 |
| `prototype/Info.plist` | 上表的 `SU*` 键（`SUFeedURL` 由 `build.sh --stage` 写入） |
| `prototype/build.sh` | 见下一节 |
| `scripts/fetch-sparkle.sh`（新） | 下载固定版本 2.10.0 的 `Sparkle-2.10.0.tar.xz`，核对写死的 SHA-256（接入时填），解到 `.build/sparkle/2.10.0/`，包括框架和 `generate_keys`、`sign_update` |
| `scripts/release-gate.sh`（新） | 发布关，见“发布流程” |
| `scripts/make-appcast.sh`（新） | `sign_update` 签 zip，写 `site/public/appcast.xml` 的新条目，再给清单签名 |
| `site/public/appcast.xml`（新）、`site/scripts/build.mjs`、`site/scripts/check.mjs` | 发布清单；`_headers` 给 `/appcast.xml` 加 `Cache-Control: public, max-age=300`；检查版本、系统要求、芯片和 Info.plist 一致 |
| `site/scripts/chrome.mjs`、`site/scripts/content.mjs` | 直链下载、三步安装、“已有旧版”那句、问答“会联网吗？” |
| `README.md`、`README_CN.md` | 三步安装和“已有旧版”那句；“隐私与安全性”改成“隐私与安全” |
| `docs/copy-guide.md` | 固定词汇，见“文案” |
| `DEVELOPMENT.md` | 发布流程、密钥、续期、升级 Sparkle；模块结构里加 `Update/`、`UpdateGuard/` |
| `tests/UpdateTests.swift`、`tests/run-update-tests.sh`、`tests/run-update-integration.sh`（新） | 见“验收” |

Sparkle 框架不放进仓库：每次升级都会让 git 历史多出几 MB 二进制；靠固定版本和 SHA-256 保证每次拿到同一份。
接入 Sparkle 的只有 `SparkleBridge.swift`，其余逻辑都不依赖它，现有编整套生产源码的测试脚本不用加框架路径。这一点要实测。
日常 `./build.sh` 出来的开发版不写 `SUFeedURL`，更新器不启动，不会被线上版本换掉。

## build.sh 怎么改

1. **拿框架**：`--check` 以外的模式都先跑 `scripts/fetch-sparkle.sh`（已有就跳过）。`--check` 找得到框架就带 `-F`，找不到就靠 `canImport` 跳过。
2. **收集源文件**：`collect_sources` 加 `-path ./UpdateGuard -prune`。
3. **编译主程序**：加 `-F "$SPARKLE_DIR" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks`，另加 `-framework Security`。
4. **编译看护**：
   ```sh
   swiftc -target "$ARCH-apple-macosx14.0" -O -o "$WORK/WindowShadeUpdateGuard" \
     "$WORK/UpdateGuard/main.swift" "$WORK/Update/UpdateJournal.swift" "$WORK/Update/UpdateRestore.swift" \
     -framework Foundation -framework AppKit -framework Security -framework ServiceManagement
   ```
   包成 `WindowShadeUpdateGuard.app`（`LSUIElement=YES`，带菜单栏图标资源），放进 `Contents/Helpers/`，这是 Apple 给辅助程序定的位置
   （[Placing content in a bundle](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle)）。
5. **放框架**：`ditto` 放进 `Contents/Frameworks/Sparkle.framework`（`ditto` 保留符号链接），然后：
   - 删掉 `Versions/B/XPCServices`；
   - 只留发布架构（`lipo -thin`）和 `en`、`zh_CN` 两个 lproj；
   - 记下前后大小，写进发布说明的草稿。
6. **签名**：从里往外逐个签，全部用同一个身份，不用 `--deep`（[Sandboxing](https://sparkle-project.org/documentation/sandboxing/)、
   [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)）：
   ```sh
   FW="$APP/Contents/Frameworks/Sparkle.framework"
   codesign -f -s "$IDENTITY" -o runtime "$FW/Versions/B/Autoupdate"
   codesign -f -s "$IDENTITY" -o runtime "$FW/Versions/B/Updater.app"
   codesign -f -s "$IDENTITY" -o runtime "$FW"
   codesign -f -s "$IDENTITY" -o runtime -i com.windowshade.prototype.update-guard \
     "$APP/Contents/Helpers/WindowShadeUpdateGuard.app"
   codesign -f -s "$IDENTITY" "$APP"          # 主程序照旧：不加新标志，标识符不变
   codesign --verify --deep --strict "$APP"
   ```
   现在只签最外层（第 166 行），要改成上面这样。主程序不加 hardened runtime：DR 不受影响，但这次不改已经发出去的行为。
7. **`--stage` 额外检查**：写入 `SUFeedURL`；`otool -L` 确认链接了 Sparkle；`codesign -dv` 确认几处嵌套代码的 TeamIdentifier 相同；
   `Info.plist` 里的 `SUPublicEDKey` 要等于仓库里记下的那个。

## 发布流程（写进 DEVELOPMENT.md）

1. **每个公开的包都升 `CFBundleVersion`。** 删掉“同一版本重新发布”一节：不再移动已发布的 tag，不再 `--clobber`。换包就升一个小版本。
2. `./build.sh --stage`，跑回归检查。
3. 打包：仍用 `ditto -c -k --sequesterRsrc --keepParent`，它保留框架里的符号链接。
4. **发布关** `scripts/release-gate.sh dist/WindowShade-v<版本>.zip`。检查的是要发出去的这个 zip，不是构建目录；有一项不过就停下：
   1. 用 `gh release download` 取上一版发布包，读出它的 DR。
   2. 把新 zip 解到临时目录，里面只有一个 `WindowShade.app`，`codesign --verify --deep --strict` 通过。
   3. 新版的 DR 和上一版逐字相同，`codesign --verify -R="=<上一版 DR>"` 通过。只有加了 `--cert-change` 才允许不同，这时这一版必须走“换证书的一版”。
   4. `--self-check` 返回 0，输出里有这次的 build 号。
   5. `CFBundleVersion` 大于上一版。
   6. `LSMinimumSystemVersion` 和清单的 `minimumSystemVersion` 按版本号比相等（先补齐成三段再比：`14.0` 和 `14.0.0` 相等）。系统版本不够的话 App 根本打不开，我们的代码一行都跑不到。
   7. `lipo -archs` 和清单里的 `hardwareRequirements` 一致：只发 arm64 时必须写上，否则 Intel Mac 会收到一个打不开的版本。
   8. 链接了 Sparkle，`SUPublicEDKey`、`SUFeedURL` 没变，`Contents/Helpers/WindowShadeUpdateGuard.app` 在且签名同 Team。
   9. **上一版读得懂这一版的状态**：新版 `--self-check --write-sample-state <目录>` 写一份停车日志和偏好，上一版 `--self-check --read-state <目录>` 返回 0。
      第一个带更新器的版本起支持这两个参数。
5. `gh release create` 上传 zip 和 `.sha256`，再 `curl -L` 下载回来，核对 SHA-256。
6. `scripts/make-appcast.sh <版本>`：`sign_update` 签 zip，把新条目写进 `site/public/appcast.xml`（保留最近三条），再给整个清单签名。
   改动说明取自 `docs/releases/v<版本>.md` 开头最多三行，直接写进 `<description>`。然后 `npm run deploy`（它会先 build 和 check），
   最后 `curl` 一次线上的清单。顺序是先上传包、后发清单；反过来的话，他会先看到新版本却下载不到。
7. **先走测试频道**：条目先带 `<sparkle:channel>beta</sparkle:channel>` 发一次，Aaron 自己装上用一天，再去掉频道标记重发清单。
8. **分批推送**：条目带 `sparkle:phasedRolloutInterval` 86400，定时检查分 7 天推完，手动检查不受限
   （[Publishing](https://sparkle-project.org/documentation/publishing/)）。有坏包时，第一天只会碰到约七分之一的人。
9. **撤回一版**：从清单删掉那一条再部署。已经装上的人用“回到 1.0.16”，或者等更大版本号的修复版。

条目的样子（写法接入时照 Publishing 文档核对）：

```xml
<item>
  <title>1.0.17</title>
  <pubDate>Tue, 06 Oct 2026 10:00:00 +0800</pubDate>
  <sparkle:version>17</sparkle:version>
  <sparkle:shortVersionString>1.0.17</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
  <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
  <sparkle:phasedRolloutInterval>86400</sparkle:phasedRolloutInterval>
  <description><![CDATA[一句话写这一版改了什么]]></description>
  <enclosure url="https://github.com/surfine/WindowShade/releases/download/v1.0.17/WindowShade-v1.0.17.zip"
             length="…" type="application/octet-stream" sparkle:edSignature="…"/>
</item>
```

**EdDSA 密钥**：`generate_keys` 只跑一次，私钥存登录钥匙串，另导出一份加密的离线备份，永不进仓库。私钥丢了，Sparkle 在 Apple Development 签名下没有兜底，
所有人要手动装一次带新公钥的版本。换密钥要单独发一版，这一版证书不能同时换。

**证书续期**（2027 年 5 月前做）：
1. 在同一个账号下申请新的 Apple Development 证书。钥匙串里两张同名证书会让 `codesign` 报身份不唯一，
   `WINDOWSHADE_CODESIGN_IDENTITY` 改用新证书的 SHA-1。
2. `--stage` 后跑发布关。DR 逐字相同，就照常发；不同，就按“换证书的一版”发：
   - 清单里的 `informationalUpdate` 配 `belowVersion`；
   - 发布说明写明要手动安装、重新授权；
   - README 的三步不变，“已有旧版”那句这一版要改成“要重新打开辅助功能和屏幕录制”。
3. 确认新证书发的第一版在测试账户上授权还在，再删旧证书。

**升级 Sparkle**：
1. 改 `fetch-sparkle.sh` 里的版本号和 SHA-256。
2. 读发布说明，留意安装器、缓存目录、续装和取消流程的改动。
3. 跑 `tests/run-update-integration.sh`。关找不到解开的 App 时，结果是“不装”，但这样发出去就等于没法更新，所以不过不发。

## 设置

“权限与启动”页，“启动”下面加一组“更新”：

- **自动检查更新**：开关。说明：“有新版本时在菜单里告诉你，不会自己装。”
- **检查频率**：每天 / 每周，默认每天。自动检查关着时不可选。
- **当前版本 1.0.17**，旁边一个按钮 **检查更新**；结果就写在这一行。
- 更新后 7 天内，这一行下面多两项：
  - 链接 **看更新记录**；
  - **回到 1.0.16**，说明“新版本用着不对，可以换回刚才那一版。”

## 隐私：检查时发出什么

现在的 WindowShade 不联网，更新检查会是它第一个网络请求：

- **检查**：一次 HTTPS GET，发往 windowshade.aaronlau.me。网络出错时，下次改发 github.com。
  - User-Agent 只写 `WindowShade/1.0.17`，去掉 Sparkle 默认附带的 Sparkle 版本；
  - 不发系统信息，没有查询参数，没有安装编号；
  - 分批推送的分组号在本机随机生成，不发出去。
  - 服务器能看到的只有网络地址和版本号。
- **下载**：发往 GitHub 和它跳转到的下载服务器，同样不带我们的标识。Sparkle 下载用系统默认的网络会话，
  系统可能在本机缓存里留下这些请求的记录，这一点改不了。
- **不发的**：窗口画面、窗口标题、使用记录、崩溃计数。没有安装编号，也就数不出有多少人在用；这是有意的。
- **关掉自动检查**：关掉“自动检查更新”后，只在他点“检查更新…”时联网。
- **官网**：官网“你的窗口，只留在你的 Mac 上”仍然成立，问答里加一条“会联网吗？”。

## 文案

| 场景 | 文案 |
| --- | --- |
| 菜单，平时 | 检查更新… |
| 菜单，有新版本 | 更新到 1.0.17… |
| 更新小窗 | 标题“WindowShade 1.0.17”；“你现在用的是 1.0.16。”；改动最多三条；链接“看完整更新记录” |
| 小窗里的提醒 | 更新前，窗口会先恢复原样。 |
| 小窗按钮 | **更新并重新打开** / 稍后再说 / 跳过这一版 |
| 进行中 | 正在检查… / 正在下载… / 正在准备… / 正在重新打开… |
| 手动检查，没有新版本 | 已经是最新版本。 |
| 手动检查失败 | 没能检查更新，稍后再试。 |
| 下载、验签失败，或关找不到解开的 App | 没能更新到 1.0.17，稍后再试。 |
| 空间不够 | Mac 上的空间不够，没能更新。 |
| 试跑没过 | 1.0.17 在这台 Mac 上没能正常打开，所以没有更新。 |
| 手动检查到上次没过的版本 | 1.0.17 上次在这台 Mac 上没能正常打开。按钮：**再试一次** / 稍后再说 |
| DR 变了或 `informationalUpdate` | 这一版要手动安装。装好后，要重新打开辅助功能和屏幕录制。按钮：**打开下载页** |
| 不在“应用程序”里（含被系统挪走、只读卷、外接磁盘） | 先把 WindowShade 移到“应用程序”文件夹，才能更新。按钮：**移到“应用程序”** |
| 当前账户写不进去 | 要这台 Mac 的管理员来更新。按钮：**好** |
| 别的用户开着 | 这台 Mac 上还有别人开着 WindowShade，等他退出后再更新。按钮：**好** |
| 退出后没装上 | 没能更新到 1.0.17，还在用 1.0.16。 |
| 新版没起来或连续崩溃，已换回 | 1.0.17 没能正常打开，已经换回 1.0.16。按钮：**好** / 反馈问题 |
| 标准账户，授权页 | 打开这两项时，要输入管理员的名字和密码。 |

- “打开下载页”固定打开官网下载处，不用清单里的地址。
- “反馈问题”打开 GitHub Issues 的新建页，不附带任何数据。
- “好”只用在纯告知的话上。
- 不写“这一版不会再提醒你”：手动检查仍会列出它。界面上也不写“保证不丢授权”（copy-guide 第 6 条）。

`docs/copy-guide.md` 固定词汇加：

| 概念 | 用词 | 不要用 |
| --- | --- | --- |
| 找新版本 | **检查更新…**（菜单）/ **检查更新**（设置里的按钮） | 检查升级、Check for Updates |
| 有新版本时菜单那一项 | **更新到 1.0.17…** | 新版本可用！、立即升级 |
| 装新版本 | **更新并重新打开**；暂时不装 **稍后再说**；不要这一版 **跳过这一版**；上次没过的再装 **再试一次** | 安装并重启、以后提醒我、强制更新 |
| 换回上一版 | **回到 1.0.16** | 回滚、降级、rollback |
| 设置 | **自动检查更新**；**检查频率：每天 / 每周** | 自动升级、更新通道 |
| 把 App 放进“应用程序”文件夹 | 标题 **放进“应用程序”文件夹**；按钮 **移到“应用程序”** | 安装到应用程序目录、迁移、Move to Applications |
| 系统第一次拦下时的面板和按钮 | 照抄系统：**隐私与安全**、**仍要打开** | 绕过、关闭 Gatekeeper、信任开发者、隐私与安全性 |
| 公证 | 第一次出现时写 **交给 Apple 检查（这一步叫公证）** | notarize、Apple 认证 |
| 每一版改了什么 | **更新记录** | 发行说明、changelog、新功能介绍 |
| 需要管理员 | **这台 Mac 的管理员**；**管理员的名字和密码** | 管理员权限、提权、sudo |

## 出错时谁来接

| 情况 | 谁接 | 结果 |
| --- | --- | --- |
| 定时检查连不上 | Sparkle | 不出声，下次再查；下次改查 GitHub 上的同一份清单 |
| 手动检查连不上 | Sparkle → 我们的界面 | “没能检查更新，稍后再试。” |
| 清单被篡改 | Sparkle（签名清单） | 不认；手动检查时同上 |
| 下载中断、包被改、EdDSA 不对 | Sparkle | 不解开；“没能更新到 1.0.17，稍后再试。” |
| 发版时误用了别的证书 | 发布关 | 发不出去 |
| 误用别的证书的包漏发了 | 安装前的关（DR） | 不装，说“这一版要手动安装……”，授权不动 |
| 有意换证书 | 清单 `informationalUpdate` | 只给下载页，说清要重新授权 |
| 只有 EdDSA 私钥泄露 | 安装前的关 | 对方没有证书私钥，DR 过不了，不装 |
| 包里缺框架、系统版本不够、一启动就崩 | 发布关试跑；漏发了由安装前的试跑拦下 | 不装，记为坏版本 |
| 试跑偶发超时 | 关 | 重试一次；仍超时只是这次不装，不记坏版本 |
| 续装已准备好的安装 | `showUpdateFound`（`.installing`）里的同一道关 | 过了才装，不过回 `.skip` |
| 回了 `.skip` 但取消消息没送到 | 否决到底 | 确认安装任务没了，超时 `SMJobRemove`，再放行退出 |
| 关跑到一半时他点退出、注销 | `applicationShouldTerminate` | 下载中：取消并立即退出；解包到结论：挂起，否决后再放行 |
| 关跑完前旧版崩了（含我们的代码崩、试跑时内存吃紧） | 已交出的看护 | 没装上就开旧版；装上了就补 DR 和试跑，不过就换回 |
| 试跑能过、正常启动后才崩 | 看护 | 换回，旧版说一次，记为坏版本 |
| 新版卡住不动 | 看护（60 秒） | 结束新版，换回；它收起的窗口由旧版启动时救回 |
| 新版自己干净退出（他按了退出、授权后重开、移位置后重开） | 看护看 `cleanExit` | 不算失败，接着盯或交给新版下次启动 |
| 写了 `healthy` 后第二次启动才崩 | 新版 `main` 里的连续崩溃计数 | 7 天内连续两次没正常结束，交给旧版的看护换回 |
| 新版能用但有毛病 | 他自己 | 设置里“回到 1.0.16”；我们撤回清单、发修复版 |
| Sparkle 退出后交换失败 | Sparkle 保住旧版；看护开旧版 | “没能更新到 1.0.17，还在用 1.0.16。” |
| Sparkle 没重开新版 | 看护（20 秒） | 按路径打开 |
| 看护换回到一半掉电 | 日志先写 `restoring` 和 `refused.json` 再交换 | 旧版启动时补完；坏版本不再被定时提醒 |
| 看护被杀（注销、关机、后台活动被关） | 下一次启动的那一版 | 按日志补完或换回；新版第二次没走到 `healthy` 就交给旧版的看护换回 |
| 看护和 Sparkle 安装器一起被杀 | 他再打开 WindowShade | 交换是原子的，`/Applications` 里总有一版；打开的那一版按日志收尾 |
| 看护被杀，同时新版连 `main` 都进不去 | 没有自动兜底 | 只能重新下载；官网始终留着上一版。靠发布关、安装前试跑、测试频道和分批推送把概率压低 |
| 新旧两版 Team 不同时新版要换回自己 | 不会发生 | 换 Team 必然 DR 变，发布关和安装前的关都会拦；换证书的一版只给下载页 |
| 被系统挪走、只读卷、外接磁盘、不在“应用程序”里 | 小窗 | 不更新，引导“移到‘应用程序’” |
| 标准账户，App 在 `/Applications` | 小窗 | 不走管理员授权，“要这台 Mac 的管理员来更新。” |
| 别的用户开着 WindowShade | 小窗 | 等他退出后再更新 |
| 空间不够 | 小窗 | 不更新 |
| Sparkle 拒绝降级 | 我们的换回 | 换回不经过 Sparkle |
| 换回过的版本又出现在清单里 | `bestValidUpdateInAppcast` | 定时检查不提醒；手动检查说明原因、可以再试；更大版本号的照常提醒 |
| Sparkle 升级后改了缓存目录 | 关找不到解开的 App | 不装；升级时的集成测试先拦住 |
| 换回后旧版读不懂新版写的状态 | 发布关 4.9 和双写约束 | 发不出去 |
| 更新后授权少了 | 新版启动时比较 | 不换回；打开授权页，用“再打开一次这两项” |
| 更新前收起、收进刘海的窗口 | `applicationWillTerminate` 的 `restoreAll()`；崩溃时由停车日志兜底 | 恢复原样 |
| 开发证书过期 | 我们 | 2027 年 5 月前续期；过期后的行为未知 |

## 验收

**纯逻辑测试**（`tests/run-update-tests.sh`，不联网、不链接 Sparkle、不动已装的 App）：
- 日志每个 `phase` 下“我是新版 / 我是旧版 / 看护在不在”的恢复决定；看护的决策表（输入：旧 pid 退出时的 phase、版本、pid、`cleanExit`、`healthy`、超时 → 动作）。
- 连续崩溃计数：两次不干净结束才换回；一次干净退出或跑满 30 分钟就清零；7 天后不再计。
- 位置和卷判断：路径含 `/AppTranslocation/`、只读卷、不在“应用程序”里、不可写、不支持 RENAME_SWAP、和缓存不在同一卷。
- 在假的缓存目录树里找解开的 App：零个、一个、两个、版本不对、第一层目录创建时间太早。**`.app` 的修改时间一律设成比 `startedAt` 早**，照实际解包的样子。
- 用临时签名的假 App 测 DR：相同通过，不同拒绝，只“满足”但字符串不同也拒绝。
- 在临时目录里测备份（`.partial` 到 `approved` 才替换、校验不过就不更新）、交换、换回（先写 `restoring` 再交换）、SHA-256 不对时拒绝换回。
- `refused.json` 的过滤：定时检查过滤，手动检查不过滤。
- 版本号规范化比较：`14.0` 等于 `14.0.0`。

**集成测试**（`tests/run-update-integration.sh`，发布机上跑，要签名身份和 Sparkle 工具；升级 Sparkle 时必跑）：
- 用测试 bundle ID 和测试密钥构建 N、N+1 两版，本机提供清单。本机测试清单要满足 Sparkle 的哪些要求，接入时核对。
- 逐项确认：
  - `showReadyToInstallAndRelaunch:` 一定被调用，关能找到解开的 App；
  - 回 `.skip` 后安装任务消失，App 退出，已装的包没变；
  - 让 `.skip` 的取消不生效（测试版里跳过 `cancelUpdate`），否决到底会 `SMJobRemove` 掉安装任务，已装的包没变；
  - 回 `.install` 后装上，看护拿到 `healthy` 就退出；
  - 在关里 `kill -9` 旧版：两种结局（装了 / 没装）都能被看护接住，最后开着的是过关的那一版；
  - 第 1 阶段做完后不回复、重开 App 再检查，走续装路径，关照样跑；
  - 装一个启动 3 秒后崩的测试版，会被换回；
  - 装一个卡住的测试版，60 秒后被换回；
  - 装一个第二次启动才崩的测试版，第三次启动时被换回；
  - 新版起来后自己退出（写 `cleanExit`），不被换回；
  - 在 `.install` 后给 App 包加 `uchg`，让交换失败，看护会打开旧版。

**另一个用户账户上的真机测试**（第一次应用内更新之前做；系统取 14、15、26、27）：

1. 用 Safari 和 Chrome 各下载一次、打开，截下实际出现的对话框。27 上重点看会不会出现“供……用于个人测试目的”，显示的是谁的名字。
2. 从“下载”打开时出现“放进‘应用程序’文件夹”；移过去后：
   - 从“应用程序”重新打开，系统不再拦；
   - 授权和登录项都指向 `/Applications`；
   - 看系统会不会询问访问“下载”文件夹，决定能不能把原件移到废纸篓。
3. 标准账户：点“仍要打开”和打开授权时要管理员的名字和密码；移到 `~/Applications` 后能一键更新；`/Applications` 里的 App 显示“要这台 Mac 的管理员来更新。”。
4. 从 1.0.16 拖入替换成第一个带更新器的版本，授权还在。
5. 从 N 更新到 N+1，确认以下几点：
   - 辅助功能和屏幕录制仍然有效，没有出现“仍要打开”；
   - 系统的“正在验证”最多出现一次；
   - 登录项仍有效，菜单栏只有一个图标且没有空出来，收起的窗口都恢复了；
   - 看 Sparkle 的进度窗出不出现；
   - 看会不会冒出“已添加后台项目”或“已添加登录项”的通知；
   - 看屏幕录制的定期询问会不会出现。
6. 看护换回时，“App 管理”会不会拦（它和 App 同一个 Team，按文档应该不拦）。
7. 在 27 上关掉 WindowShade 的后台活动：Sparkle 能不能装完；看护显示菜单栏图标后能不能活到新版记 `healthy`；在 26 上看会不会弹后台任务窗。
8. 中断：强退旧版（下载中、关跑到一半、交换前）；强退看护；更新中途注销；换回中途强退看护。下次打开都能收尾。
9. 快速切换用户：另一个账户开着 WindowShade 时，这个账户不更新。
10. 用另一张证书签一个包，模拟换证书：关拦下并提示手动安装；手动装上后，授权页的“再打开一次这两项”和“−”那句能带他把授权找回来。
11. 用“归档实用工具”和一个第三方解压工具分别解开 zip，看签名是否完整。
12. 实测装进 Sparkle 后安装包的大小。

## 剩下的风险

- **看护被杀，同时新版连 `main` 都进不去**：没有自动兜底，只能重新下载。
  靠这几样压低概率：发布关试跑发出去的 zip、安装前在他的 Mac 上再试跑一次、编译目标 14.0 由编译器查 API 版本、测试频道、分批推送。
- **看护和 Sparkle 安装器一起被杀**：两者都是 `SMJobSubmit` 提交的，macOS 27 关掉后台活动时可能一起被杀。交换是原子的，`/Applications` 里总有一版，
  但没人重开，他会看到 App 消失，要自己再打开。看护显示菜单栏图标是为了算“看得见”，能不能躲过要实测。
  没选 `SMAppService.agent`：它能活过注销和掉电，但会出“已添加后台项目”通知，和 direction.md 的“只在卡住时开口”冲突。
- **依赖 Sparkle 的内部缓存目录和续装、取消流程**：锁定版本，升级跑集成测试，找不到就不装。
- **`SMJobSubmit` 已被 Apple 标为弃用**（[文档](https://developer.apple.com/documentation/servicemanagement/smjobsubmit(_:_:_:_:))）：Sparkle 至今靠它，我们和它同进退。
- **DR 只能间接证明授权不丢**：授权数据库里存的要求读不到，见“核实过的事实”。
- **Sparkle 自己的进度窗**文字是英文或它的翻译，不合文案规则；只在交换超过 0.7 秒时出现。
- **开发证书**：可能被吊销，过期后的行为未知，macOS 27 可能对它显示“个人测试”。长期解法是 Developer ID 加公证，
  到时用 `informationalUpdate` 引导所有人手动装一次、重新授权一次。
- **EdDSA 私钥和证书私钥同时泄露**：不在这次范围内。

## 实现和上文不一样的地方（2026-09-29）

上文是设计；落地时下面几处改了，以这里为准。

- **文件位置**：没有 `prototype/Update/` 和 `prototype/UpdateGuard/`。App 一侧是 `prototype/App/Updater*.swift`
  （`UpdaterSparkle.swift` 是唯一接 Sparkle 的一层，`UpdaterSystem.swift` 放 DR、备份、换回、launchd），纯逻辑是 `prototype/Core/Update*.swift`，
  看护是 `prototype/Watchdog/`（`main.swift` 和它自己的一份菜单栏图标 `GuardIcon.swift`）。看护编 `Watchdog/*.swift` 加
  `Core/Update*.swift`、`App/UpdaterSystem.swift`、`App/UpdaterCopy.swift`，不编 App 里别的文件。测试是 `tests/UpdateTests.swift`。
- **Sparkle 放进了仓库**：`prototype/Vendor/Sparkle.framework`（2.10.0，核对过 SHA-256，已删 XPCServices，约 2.6 MB），没有 `scripts/fetch-sparkle.sh`。
  嵌入时除了 XPCServices，还删 `Headers`、`PrivateHeaders`、`Modules`；本地化留 `Base`、`en`、`zh_CN` 三份。升级流程写在 DEVELOPMENT.md。
- **看护等旧版**：第一段（旧版还开着）用 DispatchSource 的进程源（即 kqueue `NOTE_EXIT`）等旧 pid，用 `Update/` 目录的文件源等日志变化，
  不轮询；后面几段各有上限（最多约三分钟），仍每 0.5 秒看一次安装任务和日志。
- **否决后看护不自己走**：旧版还开着时，日志变成 `cancelled` 或 `refused`，看护不退出；App 确认 Sparkle 的安装任务没了才 `SMJobRemove` 它，
  删不掉就一直留着。旧版在 `cancelled` / `refused` 时退出，看护照样等安装任务结束：没装上就安静退出（他自己退的，不重开旧版），
  顺手丢掉 `.partial`、放回另存的日志；装上了，`refused` 直接换回，`cancelled` 补做 DR 比对和试跑，不过就换回。
- **补关不盖新版的状态**：看护补完关只把 `started`、`gating`、`cancelled` 改成 `approved`；新版同时写下的 `launched`、`healthy` 不动。
  新版在 `launched` 或 `approved` 时都会做 10 秒后的自查、写 `healthy`。补关里只有“通过”和“试跑偶发超时”放行，其余结论都换回。
- **换回没做成**：加了终态 `restoreFailed`（备份缺失、SHA-256 或 DR 不对、交换失败）。撤掉 `refused.json` 里这一条，打开装着的那一版；
  它读到 `restoreFailed` 就照常运行，说一次“没能换回 1.0.16，还在用 1.0.17。”（按钮 **好** / 反馈问题），然后清掉日志和备份。
  新版在 `main` 里要交出去换回之前，先看备份文件在、名字对得上 from 那一版；不对就直接走这条，不交出去，免得“启动→退出”循环。
- **位置判断拆成两行**：“不在‘应用程序’里（含被系统挪走、只读卷）”给 **移到“应用程序”**；在“应用程序”里但卷不支持交换、或和缓存不在同一个卷
  （home 在外接磁盘上），移过去也没用，所以不进欢迎窗口，更新小窗说“这台 Mac 上没法在菜单里更新 WindowShade。到下载页下载新版，
  拖进“应用程序”文件夹替换原来那一份。”，按钮 **打开下载页** / 稍后再说。
- **移到“应用程序”的两条保护**：那里已有的一份不比自己旧，就打开它，不移（欢迎窗口和更新小窗都这样）；那里已有的包签名要求和自己不同，不替换，
  按“没能移过去”处理。标准账户放进 `~/Applications` 时，`/Applications` 里的旧版不动，副句也不说“会换成这一版”。
- **签名变了而换回**：旧版说的是“这一版要手动安装。装好后，要重新打开辅助功能和屏幕录制。”（按钮 **打开下载页** / 稍后再说），
  不说“没能正常打开”。
- **下载中退出**：Sparkle 的安装任务已经提交（解包已开始、消息还没到）时，按“解包到结论”那一段处理：挂起退出、否决、确认任务没了再放行。
- **Sparkle 在关里或过关后报错、收掉会话**：不再停在 gating / approved。关里的直接按否决收尾；过关后的每 3 秒看一次安装任务，没了、
  或 30 秒还没让 App 退出，就删掉任务、按否决收尾，说“没能更新到 1.0.17，稍后再试。”。
- **落盘**：更新日志、`refused.json`、`backup.json` 每次写都 `F_FULLFSYNC` 后再改名、再同步目录，“先写 restoring 再交换”在掉电后也成立。
- **`--write-sample-state` / `--read-state` 已实现**（`App/UpdaterLaunch.swift`）：样例是停车日志（照 `Recovery/Journal.swift` 的字段）、
  这一版偏好的快照、一份更新日志；读的一方检查救回窗口要用的字段、`schemaVersion` 不超过自己认得的、偏好同名键的类型没变。
  只碰给定目录，偏好只读。改停车日志字段时要同步那里的样例。
- **`--stage`**：多了两项。`main.swift`、`WindowShade.swift` 里没接齐更新器入口时打警告（不停下，别的验证也用 `--stage`），这样的包不能发布；
  接齐了就试跑 `--self-check`，5 秒内返回 0 且输出 `build=N`，否则停下。
- **还没写的**：`scripts/release-gate.sh`、`scripts/make-appcast.sh`、`tests/run-update-integration.sh`、`site/public/appcast.xml`。
  发布关和清单先按 DEVELOPMENT.md 手动做。
- **接线由协调者做**（这些文件不归更新器这一批改）：`main.swift` 的 `UpdateLaunch.handleEarlyArguments()` 和 `UpdateLaunch.recordLaunch()`，
  `WindowShade.swift` 的 `start()`、`applicationShouldTerminate()`、`applicationWillTerminate()`，菜单、设置、欢迎窗口。
  前两处是发布阻断项。

## 已定（Aaron，2026-09-29）

1. “自动检查更新”默认开，设置里能关。
2. 第一次打开时不在“应用程序”里：替他移过去（问一句“移到‘应用程序’”，点了就移并重新打开）。
3. 不做 Developer ID 和公证，实测出问题也不做；遇到“个人测试”一类提示或看护、安装器被系统杀掉时，退回“手动下载安装”的路径并在官网写清楚。
4. 我先定的两件（Aaron 可改）：测试频道只给 Aaron 自己用（`defaults write` 打开）；看护在旧版退出后显示菜单栏图标，不走 `SMAppService.agent`。

## 出处

- **Sparkle 源码**（2.x 分支）：
  - 认包：[SUUpdateValidator.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SUUpdateValidator.m)、
    [SUCodeSigningVerifier.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Autoupdate/SUCodeSigningVerifier.m)
  - 安装器：[AppInstaller.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Autoupdate/AppInstaller.m)、
    [SUPlainInstaller.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Autoupdate/SUPlainInstaller.m)、
    [SUFileManager.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SUFileManager.m)、
    [SUInstallerLauncher.m](https://github.com/sparkle-project/Sparkle/blob/2.x/InstallerLauncher/SUInstallerLauncher.m)、
    [InstallerProgressAppController.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/InstallerProgress/InstallerProgressAppController.m)、
    [ShowInstallerProgress.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/InstallerProgress/ShowInstallerProgress.m)
  - 更新流程：[SPUInstallerDriver.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SPUInstallerDriver.m)、
    [SPUCoreBasedUpdateDriver.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SPUCoreBasedUpdateDriver.m)、
    [SPUUIBasedUpdateDriver.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SPUUIBasedUpdateDriver.m)、
    [SPUBasicUpdateDriver.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SPUBasicUpdateDriver.m)
  - 接口：[SPUUserDriver.h](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SPUUserDriver.h)、
    [SPUUpdaterDelegate.h](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SPUUpdaterDelegate.h)
  - 其它：[SUHost.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SUHost.m)、
    [SPULocalCacheDirectory.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SPULocalCacheDirectory.m)、
    [zh_CN Sparkle.strings](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/zh_CN.lproj/Sparkle.strings)
- **Sparkle 文档与发布**：[Documentation](https://sparkle-project.org/documentation/)、[Customization](https://sparkle-project.org/documentation/customization/)、
  [Publishing](https://sparkle-project.org/documentation/publishing/)、[Sandboxing](https://sparkle-project.org/documentation/sandboxing/)、
  [Custom UIs](https://sparkle-project.org/documentation/custom-user-interfaces/)、[2.10.0 发布说明](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0)
- **Apple**：
  - 签名与授权：[TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)、
    [Certificates](https://developer.apple.com/support/certificates/)、
    [NSUpdateSecurityPolicy](https://developer.apple.com/documentation/bundleresources/information-property-list/nsupdatesecuritypolicy)、
    [considerExpiration](https://developer.apple.com/documentation/security/seccsflags/considerexpiration)、
    [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)
  - Gatekeeper 与首次打开：[Launch Services Keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html)、
    [Gatekeeper and runtime protection](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web)、
    [Updates to runtime protection in macOS Sequoia](https://developer.apple.com/news/?id=saqachfa)、
    [mh40616](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)、
    [102445](https://support.apple.com/en-us/102445)、
    [App Translocation Notes](https://developer.apple.com/forums/thread/724969)
  - 后台活动：[Managing ongoing background processes](https://developer.apple.com/documentation/appkit/managing-ongoing-background-processes-in-your-mac)、
    [登录项与后台任务（部署指南）](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web)、
    [SMJobSubmit](https://developer.apple.com/documentation/servicemanagement/smjobsubmit(_:_:_:_:))
  - 包结构：[Placing content in a bundle](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle)
- **其它**：[Squirrel.Mac #336](https://github.com/Squirrel/Squirrel.Mac/issues/336)、[LetsMove](https://github.com/potionfactory/LetsMove)、
  [Homebrew 5.0.0](https://brew.sh/2025/11/12/homebrew-5.0.0/)、[Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)
- **本机只读检查**（2026-09-29）：
  - `codesign -dvvv --requirements -` 读 v1.0.15 发布包；
  - `openssl x509 -dates` 读证书有效期；
  - `spctl -a -vv` 的结果是 rejected；
  - 读了 `CoreServicesUIAgent`、`SecurityPrivacyExtension.appex` 的本地化表；
  - 读了 `man gktool`，以及 `prototype/build.sh`、`prototype/Info.plist`、`prototype/Recovery/Journal.swift` 的格式版本。
- **这次复核**（2026-09-29，WebFetch 读 2.x 原文）：续装走 `showUpdateFound` 的 `.installing` 分支、三种回复都进 `finishInstallationWithResponse`、`.skip` 写跳过记录；
  安装器在 App 退出后按第 1 阶段是否完成决定装，`_shouldRelaunch` 只由 `SPUResumeInstallationToStage2` 设置，取消消息触发清理退出。
