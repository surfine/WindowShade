# 隐私读取登记表

状态：提交主模型审定的合同 v1。当前行只证明源码存在这些读取，不证明网络、磁盘和双账户测试已通过。planned 行只在功能接通后出现，不能提前展示伪值。

## 数据结构

唯一数据源是 `privacy/registry.json`。每行包含稳定 id、label、三层 sensitivity（public/sensitive/private）、group、reads、purpose、destination、activation、toggle、status、verification、retention、log_policy。读取点另存 path、line、symbol、source、signal。源码行号用于定位，门禁使用路径+符号+原行的多重集合，移动行号不被误当新调用。这个表和工具为原创；没有复制 Loupe 的实现，因此不冒用其版权声明。以后真的引入 MIT 源文件，必须另附该文件原版权。

## 页面规则

页面从下面同一 JSON 生成。打开时取现有控制器的只读快照，不为了填一个值而启动摄像头、蓝牙读取、音频枚举或网络请求。值缺失显示“未读取”；权限不足显示“未授权”；失败显示“暂不可用”。不显示过期原值冒充当前值。private 值默认隐藏，由用户在未锁定的隐私页明确展开；再次锁屏清空。每项开关引用原设置键，不复制新开关。

不能继续使用“除了检查更新，都不离开这台 Mac”作为全局承诺：A2、D5、D6、语音和跨设备功能的数据去向不同。默认总说明改为“下面列出读取内容、用途和去向。你开启的连接可能把已提交的内容交给相应服务。”尚未上线的连接不展示为已开启。活动状态来自本机不代表后端助手不联网。

## 完整项目条目

|ID / 显示名|层级 / 状态|读取与用途|数据去向|时机与开关|
|---|---|---|---|---|
|`screen-shape` / 屏幕和刘海的形状|public / current|显示器编号、尺寸、菜单栏与安全区；把控件放在所属屏幕|内存；不发送|布局启用时；隐私页仅取现有快照；无独立开关，跟随刘海功能|
|`lock-state` / 是否锁屏|sensitive / current|锁定/未锁定/未知、当前控制台会话；阻止锁屏时显示或执行敏感动作|内存；不发送|会话通知与授权边界复核；安全边界不可单独关闭|
|`battery` / 配件电量|sensitive / current|已连接配件型号、电量、连接状态；显示现有配件状态|内存；不发送|现有活动来源；页面不再轮询；跟随实时活动；不新增重复开关|
|`recording-app` / 哪个 App 在录音|sensitive / current|音频进程标识、bundle ID、录音状态；录音活动提示，不读取录音内容|内存；不发送|现有来源激活时；实时活动|
|`window-ax` / 窗口的标题、位置和大小|private / current|AX 标题、窗口ID、角色、几何、所属进程；找到并收起或恢复目标窗口|内存；已收起窗口的恢复日志存本机|执行动作或既有缓存刷新；辅助功能授权；关闭功能停止新增读取|
|`key-position` / 按了哪个键|sensitive / current|键码、修饰键、按下/松开、点击/滚动位置；快捷键、惯用键和手势；不读输入文字|内存；不持久按键序列|功能启用且未锁定；既有惯用键/手势开关；一直用Mac时关闭相应钩子|
|`window-image` / 窗口的画面|private / current|授权目标窗口的像素帧与缩略图；动画、预览和窗口浏览|目标为仅内存；磁盘行为待P1-FS验证|只有可见动画/预览；屏幕录制授权；对应功能|
|`camera-frame` / 摄像头|private / current|临时视频帧、动作/是否有人结果；用户触发的眨眼转头；离席检测另按L1合同|只在内存；无主动上传；需真机文件检查|功能显式开启且当前状态允许；摄像头及对应功能；锁屏不自动重开一般摄像头源|
|`music` / 正在播放的歌|private / current|曲目、艺人、封面入口、进度、播放状态；显示音乐并控制本次暂停的播放器|进程间自动化；内存；不把标题写日志|通知触发，现有兜底计时不在本轮更改；实时活动/音乐控制和系统自动化授权|
|`notch-private` / 刘海的精确轮廓|public / current|bezelPath、轮廓和圆角数据；贴合硬件边缘|内存|显示变化时缓存；关闭自适应外形用公开安全区|
|`spaces-private` / 其他桌面和最小化窗口的画面|private / current|私有窗口/Space关系、位置和透明度，以及可用的窗口像素；已授权的跨桌面预览及窗口控制；枚举或控制调用不一定读取像素|内存；磁盘行为待验证|用户动作时；私有截图退回公开可用窗口/关闭预览|
|`hinge` / 屏幕开合的角度|sensitive / current|HID 铰链角度；桌面开合效果|内存|现有运动分档采样，锁屏按现有边界；桌面开合|
|`tilt` / 机身的倾斜|sensitive / current|加速度计样本、移动状态；桌面倾斜及铰链采样分档|内存|驱动推送，停用后拆回调；倾斜效果|
|`update` / 检查更新|sensitive / current|应用版本、Sparkle更新请求及服务端可见网络元数据；取得更新目录和下载|更新服务；实际主机从构建配置和P2流量核验|仅自动更新开关或用户检查更新；自动检查更新；关后仍可手动检查|
|`settings` / 设置|sensitive / current|本应用用户选择、已授权开关、模型槽位标识及被查询的系统偏好；保留选择和适应当前系统设置|本机偏好文件；不存临时审批票据|原控制器需要查询时；页面只读已有快照；各原有设置；重置只清本应用值|
|`recovery` / 恢复记录|private / current|收起窗口目标、标题和位置等恢复字段；崩溃后放回用户窗口|本机 RecoveryJournal.plist；恢复后的删减需单独核验|收起/恢复事务；无删除其他App数据行为|
|`diagnostics` / 运行记录|sensitive / current|固定事件码、技术状态、耗时；禁止窗口标题和提示词；排错与性能核验|本机专用目录0700/文件0600及一个备份|事件发生时；不开新轮询；开发路径覆盖受同样安全规则限制|
|`login-item` / 登录时自动启动|sensitive / current|本应用登录项状态；按用户选择启动|本机系统登录项服务|打开设置读取既有状态，修改时提交；既有登录时自动启动|
|`agent-hooks` / 编程助手的事件|private / planned|provider、session/turn/tool/request ID、进程身份、状态及最小摘要；A2把已选择助手的状态放到刘海|本机受保护IPC；不存完整hook输入；上游CLI自身可能联网|A2a/A2b用户启用后；先备份并合并配置；编程助手活动；撤销只删除本应用配置块|
|`conductor-ipc` / 指挥连接|private / planned|同账户对端凭据、项目/会话ID、单调序号、请求摘要；D5a/b绑定输入与本机助手会话|Swift本机IPC；默认不监听局域网；跨设备传输另列下行|显式绑定，锁屏/睡眠/撤销关闭控制；指挥模式及项目绑定|
|`cross-device` / 跨设备语音或控制|private / planned|已配对对端身份、按键或音频流及认证握手；明确选中的设备输入|可能经过本地网络/系统连续互通；实际路径须探针记录，不能称从不离开本机|显式选源并建立可信通道后；来源选择和连接撤销|
|`codex-server` / Codex 会话和审批|private / planned|model/list能力、thread/turn/item状态、服务端审批请求、最小输入文本；D6发送用户明确提交并显示真实回执|本机app-server；后续Codex服务调用可能上传用户提交给提供商|仅绑定会话；初次连接先snapshot；指挥模式/会话绑定；不读取任意历史全文|
|`speech-input` / 语音输入|private / planned|选定麦克风的音频、临时转写、所选识别器；生成草稿，用户再次按播放才提交|默认本机识别；不具备本机识别则停用并说明，云路径必须另获同意|D1/D4有真实录音回执后，最长60秒；麦克风来源；松手/取消即停止|
|`bluetooth-presence` / 随身设备是否在场|sensitive / planned|配对设备标识、明确连接/断开、被证实可读特征的请求回执、RSSI；L2给L1离席和返回候选；RSSI不作身份授权|内存；不持久轨迹；设备名称不算可信身份|功能开启且蓝牙能力探针通过；自动锁定/返回流程，停用拆监听|
|`face-identity` / 人脸特征与身份结果|private / planned|已登记模板、活体挑战结果、匹配结果；用户已批准的身份验证，Vision检测人脸不等于识别身份|模板仅保护存储；原帧不存；身份后端待F1/L3证明|身份功能实际可用且已启用时才显示本行；刷脸功能及删除登记；不标成Face ID|
|`unlock-secret` / 解锁凭据|private / planned|仅经用户明确建立的受保护系统凭据；拟定锁屏返回后端；尚未证明可安全实现|必须Keychain/现有保护服务；不进日志/JSON/助手上下文|后端探针通过后另行启用；当前不得采集；删除登记；无可用后端就不显示已支持|
|`private-contact` / 触控板和鼠标触点|sensitive / planned|设备句柄、触点ID、经实测换算的坐标/面积、帧时间；I2给I1d点击和I1c拖动判定|内存当前接触组；不录制长期手势轨迹|符号、ABI、单位、停止回调均验证后；输入增强；未知设备或ABI停用该路径|
|`remote-hid` / 遥控器按钮|sensitive / planned|I5a每设备HID page/usage、down/up、连接代次；I1e/I1f在模式内映射动作|内存；映射归属账本仅本机|启用且已绑定来源；断线取消所有按键；遥控器模式；退出恢复自己占用的映射|
|`remote-touch` / 遥控器触控区域|sensitive / planned|被探针证实的触控坐标与时间，不从普通键码臆造；指挥模式轨迹输入|仅当前轨迹；最多2048采样点|I5a坐标来源探针通过后；无坐标仅按钮；指挥模式|
|`hid-remapping` / 遥控器按键映射|sensitive / planned|hidutil当前映射和仅由本应用新增的条目；I5b避免系统动作与本应用重复响应|本机系统映射；归属记录不含输入历史|用户开启时保存/差分应用，撤销差分恢复；遥控器模式；不覆盖其他工具新增映射|
|`game-controller` / 手柄输入和反馈|sensitive / planned|已连接手柄ID、方向/按钮/触控输入、输出扳机阻力；I8复用同一动作与交互租约|输入内存，反馈发回选定手柄；不跨会话缓存指令|显式功能开启，锁屏/断线/抢占立刻清扳机；手柄输入；不抢全局无关控制器|
|`authorization-key` / 设备授权密钥|private / current|Secure Enclave 包裹的句柄、公钥、指纹集合状态摘要、一次性挑战及签名结果；不导出私钥；用途和目标绑定的一次性授权账|~/Library/Application Support/WindowShade/Authorization/ 下的 device-key.v1、.pub、.biometry 文件及内存；当前源码没有把句柄写入 Keychain|每次明确授权；锁屏等推进代次；删除登记；安全校验不可跳过|
|`agent-voice-proof` / 审批口令和声纹辅助证据|private / planned|一次随机口令的转写和辅助匹配结果；D1高风险挑战的辅助证据；不是allow权限|短期内存；绑定请求摘要、代次、挑战ID；不写完整音频日志|已展示审批且新确认后才挑战；不具备可靠声纹证明则用现有主身份路径|

## 构建门禁

已登记 453 个保守词法命中，覆盖 91 个 Swift 文件。数量包括声明和注释里的符号，不能当成实际执行次数。完整逐点清单在 JSON 的 sites。新增命中必须失败，主模型逐点归类后才改表；执行模型不得运行自动“接受全部”更新。

```sh
python3 contracts/privacy/check-registry.py --repo "$REPO"
```
退出 0 且含 `PASS privacy-registry`。任何 `UNREGISTERED` 退出 1。此检查补充代码审查，不能发现任意拼接出的 dlsym、封装后的数据流或第三方二进制联网。每个 planned 读取点上线时，必须补静态位置和运行去向证据；表不是免审名单。

## 日志修复

`prototype/Support/Diagnostics.swift:5–68` 整段 logger 替换为 `privacy/WindowShadeLogger.replacement.swift.txt`。前锚点为 `import Cocoa`，后锚点为 `func wlog(_ s: String) {`；保留 `wlog` 包装与后面 MainThreadActivity 等全部代码。新增 `prototype/Support/SecureLogFile.swift`，内容取同目录完整实现。默认路径改为 `~/Library/Logs/WindowShade/windowshade.log`；仅专用目录改0700，文件0600。每条上限16KiB，文件5MiB、一个备份，保留旧队列。

打开每一级目录使用 NOFOLLOW 并核对所有者。最后文件必须是本用户普通文件、只有一个硬链接；以 append 打开，不截断目标。轮转只在持有的目录描述符下执行，核对当前 inode，拒绝不安全备份。Darwin 分支用空 extended ACL 清掉额外权限再 chmod。签名已查 Apple 头文件和手册，但本轮没有 macOS SDK；不能把 Linux 通过写成 Mac ACL 通过。

开发环境变量 `WINDOWSHADE_LOG_PATH` 保留，但必须指向现存、专用、受保护且没有符号链接的父目录。共享 `/tmp` 不合格就停用持久日志，不回退、不申请提权、不删除未知文件。父路径不符合限制导致日志不可用时，应在诊断页显示固定状态“运行记录未写入”；本轮未接诊断 UI。若用户主目录/Logs 有自定义链接，先由主模型选定真实受保护目录，不自行放宽检查。

旧 `/tmp/windowshade.log` 与 `.1` 不自动迁移，也不声称已经清除历史泄露。P1 验收由 Aaron 确认旧日志文件所有者和内容后单独删除；不可对任意 `/tmp/windowshade.log` 直接 chmod 或跟随链接。

### 12 处精确替换

复核结果是11处写入标题正文，另1处只写标题长度。仍把这12处一并清理，但不把长度日志描述成正文泄露。`TrackpadGestures.swift` 的 `choice.title` 是动作菜单标签，不能仅凭名字就归为窗口标题。

#### 1. `prototype/PinnedPreview.swift:928` (window-title-content)

原文：
```swift
wlog("pin-preview: start id=\(id) app=\(appName) title=\(title) frame=\(format(frame))")
```
替换为：
```swift
wlog("pin-preview: start id=\(id) frame=\(format(frame))")
```

#### 2. `prototype/App/FoldExit.swift:63` (window-title-content)

原文：
```swift
wlog("quicklook: reopened via Finder Space fallback id=\(id) title=\(state.title)")
```
替换为：
```swift
wlog("quicklook: reopened via Finder Space fallback id=\(id)")
```

#### 3. `prototype/App/FoldExit.swift:65` (window-title-content)

原文：
```swift
wlog("quicklook: reopen unavailable id=\(id) title=\(state.title)")
```
替换为：
```swift
wlog("quicklook: reopen unavailable id=\(id)")
```

#### 4. `prototype/App/FoldExit.swift:251` (window-title-content)

原文：
```swift
wlog("quicklook fullscreen: reopen via Finder Space id=\(id) title=\(state.title)")
```
替换为：
```swift
wlog("quicklook fullscreen: reopen via Finder Space id=\(id)")
```

#### 5. `prototype/App/FoldExit.swift:254` (window-title-content)

原文：
```swift
wlog("quicklook fullscreen: reopen unavailable id=\(id) title=\(state.title)")
```
替换为：
```swift
wlog("quicklook fullscreen: reopen unavailable id=\(id)")
```

#### 6. `prototype/App/ShadeController.swift:272` (window-title-content)

原文：
```swift
wlog("quicklook: no direct reopen URL; will use Finder Space fallback title=\(title)")
```
替换为：
```swift
wlog("quicklook: no direct reopen URL; will use Finder Space fallback")
```

#### 7. `prototype/App/ShadeController.swift:512` (window-title-content)

原文：
```swift
wlog("    classic finalBarH=\(Int(barH)) appTitle=\"\(appName)\" windowTitle=\"\(title)\"")
```
替换为：
```swift
wlog("    classic finalBarH=\(Int(barH))")
```

#### 8. `prototype/App/ShadeController.swift:527` (window-title-content)

原文：
```swift
wlog("    proxy finalBarH=\(Int(barH)) canResize=\(canProxyResize) windowManagement=\(windowManagementCapability) appTitle=\"\(appName)\" windowTitle=\"\(title)\" preview=-")
```
替换为：
```swift
wlog("    proxy finalBarH=\(Int(barH)) canResize=\(canProxyResize) windowManagement=\(windowManagementCapability) preview=-")
```

#### 9. `prototype/App/ShadeController.swift:543` (window-title-content)

原文：
```swift
wlog("    proxy immediate finalBarH=\(Int(barH)) canResize=\(canProxyResize) windowManagement=\(windowManagementCapability) appTitle=\"\(appName)\" windowTitle=\"\(title)\" preview=\(quickPreview == nil ? "-" : "quick") capture=\(options.capturePreview)")
```
替换为：
```swift
wlog("    proxy immediate finalBarH=\(Int(barH)) canResize=\(canProxyResize) windowManagement=\(windowManagementCapability) preview=\(quickPreview == nil ? "-" : "quick") capture=\(options.capturePreview)")
```

#### 10. `prototype/App/ShadeController.swift:570` (window-title-content)

原文：
```swift
wlog("    proxy pre-hide-capture finalBarH=\(Int(barH)) canResize=\(canProxyResize) windowManagement=\(windowManagementCapability) appTitle=\"\(appName)\" windowTitle=\"\(title)\" preview=\(capturedImage == nil ? "-" : "sck")")
```
替换为：
```swift
wlog("    proxy pre-hide-capture finalBarH=\(Int(barH)) canResize=\(canProxyResize) windowManagement=\(windowManagementCapability) preview=\(capturedImage == nil ? "-" : "sck")")
```

#### 11. `prototype/Window/AXHelpers.swift:247` (window-title-content)

原文：
```swift
wlog("--- WINDOW role=\(axRole(win) ?? "?") title=\(axTitle(win)) pos=(\(Int(pos.x)),\(Int(pos.y))) size=(\(Int(size.width))x\(Int(size.height)))")
```
替换为：
```swift
wlog("ax-window: diagnostic title=[redacted]")
```

#### 12. `prototype/App/Notch.swift:1164` (title-length-only)

原文：
```swift
wlog("notch: title changed id=\(id) → \(thumbnail != nil ? "thumbnail dot" : decision == .alert ? "alert" : "mark") (\(title.count) chars)")
```
替换为：
```swift
wlog("notch: title changed id=\(id) → \(thumbnail != nil ? "thumbnail dot" : decision == .alert ? "alert" : "mark")")
```

### 安全生成补丁副本

```sh
python3 contracts/privacy/patch-logs.py --repo "$REPO"
python3 contracts/privacy/patch-logs.py --repo "$REPO" --output "$NEW_EMPTY_PATH"
```
预期退出0并含 `PASS log-patch: 12 exact replacements`。源码指纹不匹配、锚点重复或输出目录已存在时停止。脚本不会修改输入仓库；主模型审查副本 diff 后才合并。独立测试运行 `bash contracts/privacy/run-secure-log-tests.sh`。

## P1/P2 验收记录（本轮没有实际 Mac 记录）

|测试|执行方式|通过标准|当前状态|
|---|---|---|---|
|权限与ACL|Mac上跑日志套件，`ls -ldeO` 看目录/日志/备份；用另一标准账户读取|目录0700，文件0600，空extended ACL，另一账户拒绝|待Mac|
|真实标题不落盘|测试窗口标题设为唯一随机串，收起/预览/全屏/恢复后搜索日志|仅搜索该自造串；主日志和备份都无命中|待Mac|
|旧日志|只读检查历史tmp日志的所有者/链接，用户确认后移除本应用遗留|未擅自操作其他人的文件|待用户确认|
|联网|P2原规范开/关更新各一天，记录各PID进程树及目的地址|区分WindowShade/助手/跨设备；不能只看主进程|未执行|
|恢复记录|收起再恢复，比较RecoveryJournal字段和删除时机|只删已恢复归属记录，不删他人窗口状态|未执行|
|画面/语音/相机|在用户同意的测试账户用fs_usage检查；所有探针只写合成样本ID|无原帧、真实文本、音频落盘；停止后设备闲置|未执行|
|门禁负例|临时副本新增一条未登记URLSession调用，再运行门禁|退出1；删除负例恢复0|见VALIDATION|

## 来源

内部依据：`docs/privacy-page.md`、`docs/blueprint.md`、`docs/handoff/deepseek-menu-agents.md`、`docs/handoff/deepseek-conductor.md`、`docs/handoff/deepseek-dynamic-lock.md`、`docs/handoff/deepseek-input.md`及 JSON 逐点源码清单。外部依据见 `../sources.md` 的 Apple open(2)、acl_set_fd(3)、acl_get_entry(3) 和 Libc ACL 声明。没有复制外部实现代码。

## 授权存储的源码更正

`prototype/App/DeviceAuthorizationKey.swift:4–10、44–55、72–83、86–126` 明确使用 Secure Enclave `dataRepresentation`，在授权目录保存包裹句柄、公钥与指纹集合状态摘要。代码注释报告当前签名条件下 data-protection Keychain 写入失败；这是交接源码的说明，本轮没有重跑该 Mac 探针。不能把本应用“使用受保护签名”写成“所有授权数据已存入 Keychain”，也不能把该包裹句柄叫作裸私钥。现有文件写入采用 atomic 后 chmod；本份日志补丁不修改授权文件存储，不代表其 ACL、链接或多账户攻击路径已验收。相关验证归 P1-KEY。
