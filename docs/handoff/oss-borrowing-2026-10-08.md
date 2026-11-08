# 开源借鉴台账

2026-10-08。十六个开源项目逐项读了源码和许可，决定取什么、不取什么。这份是来源、固定提交和许可证明；画面见总稿 [WindowShade 设计系统](../design-drafts/WindowShade%20设计系统.html) 的「借鉴台账」一节，落地计划见 `~/.claude/plans/ethereal-forging-liskov.md`。

**许可总则**：GPL（Atoll、Peninsula、niri、PlayPort、DiPlay、LIVI）、AGPL（AirBattery）、无许可证（BLEUnlock、atv-core）只借思路，用 Swift 重写；BSD-3（Hyprland、mediaremote-adapter）、MIT（Loupe、Glance、lipflow、quietglass）可用代码，带上原作者版权声明；非商用的模型权重（ArcFace、LRS3、InsightFace）不进仓库。Alcove 闭源，只看公开行为。

**硬规则不变**：一个宿主一个协调器；状态来自数据；放行只走授权账；脸、挑战、头部动作只作证据，系统认证永远是出路；新读取先进 `tools/privacy/registry.json`；能耗不高于 1.0.15；默认关。

## 刘海与窗口管理

| 项目 | 固定提交 / 版本 | 许可 | 取 | 不取 |
|---|---|---|---|---|
| [Atoll](https://github.com/Ebullioscopic/Atoll) | 2026-10-08，4875★ | GPL-3.0 | 按音量 / 亮度键才开口（`MediaKeyInterceptor` 监听 type 14，到顶到底也开口）；锁屏让系统 HUD 显示（`SystemChangesObserver`）；浏览器下载看 `~/Downloads` 里的半成品文件（`DownloadManager`）；正在播放用 mediaremote-adapter 推送（`NowPlayingController`） | SIGSTOP / killall / launchctl 冻结系统 HUD、最高层 `CGSSpace`、锁屏小组件、`LiquidGlassBackground`、读 keychain 里的 LLM key、它的四段曲线刘海（我们 `bezelPath` 更准） |
| [Peninsula](https://github.com/Celve/Peninsula) | 2025-10-10，459★（停更） | GPL-3.0 | Dock 未读红点（`AXStatusLabel`）可上启动台和那一排的格子 | 假 24 点刘海、读通知中心私有库、替换 ⌘Tab |
| [Alcove](https://tryalcove.com/) | 1.7.2，闭源 | 只看行为 | 横扫一次只算一下、门槛调高、展开才切（1.6.6/1.6.15）；音量到顶到底也开口、不挡系统 HUD、个性化音量不触发；空闲降帧率（1.3.4）；在 Mission Control 和原生全屏时让开（1.6.5–1.6.13）；更正价格 $14.99 / macOS 15 | 锁屏小组件、假刘海、私有绘制和代码 |
| [niri](https://github.com/niri-wm/niri) | 2026-10-08，28267★（`YaLTeR/niri` 即此仓库） | GPL-3.0 | 松手速度只看最后 150 ms、松手补零位移样本（`swipe_tracker.rs`）；关掉刚开的列回到上一列和原视野、换焦点就忘（`scrolling.rs`）；拖到边卷轴跟着滚（30 点触发、100 ms 延迟、线性加到 1500/s） | 把工作区原样搬来 |
| [Hyprland](https://github.com/hyprwm/Hyprland) | 2026-10-06，38812★ | BSD-3 | 拖到另一扇上按指针相对中心的角度决定从哪边分（`DwindleAlgorithm` `smart_split`）；拖过一段距离才触发（`DragController` `drag_threshold`） | 贝塞尔曲线、Lua / IPC / 插件、模糊、special-workspace 暗层 |

## 身份、隐私、电量、静音

| 项目 | 固定提交 | 许可 | 取 | 不取 |
|---|---|---|---|---|
| [Loupe](https://github.com/mysk-research/loupe) | 2262efd，1554★ | MIT（名字/图标/图片保留） | 页面开着才实时更新、关掉就停（`LiveSignalProvider.stream()`）；JSON 导出（`ExportView`）；「合起来能看出什么」（`FingerprintNarrative`）；每个用途单独同意（`CollectionConsent`）；截图用假数据（`ScreenshotMode`） | 品牌；`AppInferenceEngine` 那种对本人的敏感猜测 |
| [Glance](https://github.com/jonnyoo/glance) | b97f521，1542★ | MIT（ArcFace 权重非商用） | 扫描每帧重查锁态、按帧号去重、不是本人清掉匹配、等 2 秒错脸才失败、2 秒内多唤醒算一次（`FaceUnlockCoordinator`）；均值模板 + 最近样本都过线、无亚军余量、旧模型版本排除、0.18 旁人线、0.3 跟脸容差（`FaceRecognitionPipeline`）；`IOHIDManager` 收空格（`SpaceKeyMonitor`）；清空字段再按 20 的 UTF-16 批打字（`KeystrokeInjector`） | 往没确认是登录框的地方打字；权重 |
| [BLEUnlock](https://github.com/ts1/BLEUnlock) | 2eeb35d，4469★ | 无 | 睡眠前切 `.regular` 激活、醒来 1 秒后切回让蓝牙能接着扫、唤醒 0.5 秒后先查锁态再解、锁屏时按 Esc 调登录框；手机不在被密码解开 10 秒内记「intruded」；`getMACFromUUID` 把 CoreBluetooth UUID 映射到真地址（读 `*.ledevices.paired.db`，要登记、可能要完全磁盘访问）；`SACLockScreenImmediate` 立即锁 | 只凭 RSSI 解锁；字符串拼 SQL；手动锁后走回自动解（我们更严） |
| [AirBattery](https://github.com/lihaoyun6/AirBattery) | 134e02f，2988★ | AGPL-3.0 | AirPods 连本机读左右耳盒：`system_profiler SPBluetoothDataType -json` 的 `device_batteryLevelLeft/Right/Case`（公开命令，连上才跑、之后少读）；附近 AirPods 读 Apple 厂商数据（29 字节，已为被动 RSSI 读）；iPhone 走标准 GATT 180F/2A19 + 2A24；iPhone/iPad/Watch 可走 libimobiledevice（LGPL，要先信任） | 它的代码、`logReader.sh` 刮系统日志、Nearcast 局域网共享、`BatteryStatusFlags==4` 当未充电、附带的 helper 二进制 |
| [lipflow](https://github.com/amywork777/lipflow) | e37453b，544★ | MIT（ESPnet Apache，LRS3 非商用） | 录制少于 12 帧或不到 40% 有脸就重录、松开后多录 0.4 秒、每 0.45 秒实时预览（`dictation.py`）；按住 0.25 秒内是点、0.35 秒内双击进免手持 60 秒、Esc 取消、按别的键取消（`ptt.py`）；相机懒开、45 秒空闲关、不自动用连续性相机（`camera.py`）；个人模型要在留出数据上赢过通用模型才留（`practice.py`） | LRS3 权重、云端 / 大模型整理、Whisper（用麦克风）、读输入框学纠正 |
| [quietglass](https://github.com/clintonimaroo/quietglass) | 6025c4d，56★ | MIT（SFace Apache） | 逐脸 IoU≥0.25 跟踪、0.65 秒过期；owner 是唯一脸或居中大脸；旁人正对（yaw<0.61、pitch<0.52）0.7 秒才算、0.35 秒覆盖、1.5 秒清、看不到脸不清（`CameraTracking`/`NearbyPresence`/`NearbyWarningPolicy`）；随机转头挑战、每步 0.25 秒、眼睛≥录入 0.78、10 秒超时、1.5 秒内接上丢失、匹配 3–8 向量中位≥0.50 最小≥0.35（`OwnerRecognitionPolicy`）；头部方向按屏幕存四元数、4° 粘滞、换 AirPod 重校（`DisplayHeadTracking`）；帧 SHA 变了才做文字识别、存标题单向摘要（`SensitiveText`/`FrameFingerprint`） | 模板存登录钥匙串（会备份）；关「认我」时给剩下的人清遮罩；靠 `sharingType=.none` 防录屏（实测 SCK 仍抓得到） |

## CarPlay 接收（身份走可插拔接口，只接正式授权）

| 项目 | 固定提交 | 许可 | 取（工程做法） | 不取 |
|---|---|---|---|---|
| [PlayPort](https://github.com/youcci/playport) | 9a0882d，256★ | GPL-3.0 | 蓝牙 RFCOMM iAP2 引导（UUID `…deca-fade…`）→ 交 Wi-Fi → AirPlay RTSP(7000) 收 H.264/HEVC + RTP 音频、直通不重编码；改分辨率重连；查看者打开时要关键帧；5 秒再邀请带冷却；两指 HID 回传（6 字节/指）。Mac 阻碍：系统 AirPlay 占 7000 要先关、要蓝牙 + 定位权限、只无线 | 它的代码、提取来的身份、CarPlay 商标 |
| [DiPlay](https://github.com/shihabal3amri/DiPlay) | 858a7ee（v0.2.15），6871★ | GPL-3.0（部分 AGPL / 图标另有许可） | 重连预算 2 秒×2ⁿ、≤30 秒、5 次、稳 60 秒清零（`WirelessStartupRetryBudget`）；设置改动等重连才生效（`PendingReconnect`）；缓冲音乐预发约 1:43（`mainBuffered`）；验收数「收到帧」和「画出帧」分开（`CONNECTION_RELIABILITY.md`） | 它的代码、提取来的身份、图标、车厂界面 |
| [LIVI](https://github.com/f-io/LIVI) | 3968d38，864★ | GPL-3.0 | CarPlay 画面留 view-area / safe-area 两套 inset 避开刘海；已连手机间切换不重连；AirPlay Pair-Verify 验过客户端签名、M4 后才装控制 key（和我们 strict 路径一致，和 atv-core 相反） | 它的代码；重刷固件的 LIVI Link 加密狗当成品；Mac 上没有有线路径 |
| [atv-core](https://github.com/corvofeng/atv-core) | 8a4ada2，235★ | 无（工作区声明 MIT，无 LICENSE 文件） | 遥控器按键表：5 返回、6 确认、7 电视键、14 播放/暂停、18 静音、19 电源（iOS 26/27 控制中心复用 18/19），`_hBtS` 1 按下 2 松开、松开才算；触控 `_hidT` 1000×1000、`_tPh` 1 开始 4 结束、<60 点 ≥150 滑；后台探测（`_x` 高位）1 秒、普通 2.5 秒、不开会话 3 秒断；音量标志 `_mcF` 0x0100 让 iPhone 音量键能调、GetVolume 返回 0 表示静音 | 不验 PV-M3、PIN 固定 1111 写日志、机器 UUID SHA 当私钥、SRP server 值固定、同 IP 新连接踢旧、播放键双击加 300 ms、电源键 `pmset displaysleepnow`（我们电源是收工不是睡眠） |

| [Mole](https://github.com/tw93/Mole) | 2026-10-11，main | GPL-3.0 | 启动台卸载的思路：App 本体 + 按 bundleID 扫用户域关联文件（偏好/应用支持/缓存/状态/容器/启动代理），共用数据保留，删除前逐文件复核 | 它的代码（Go）、直接删除（我们进废纸篓）、系统域提权路径 |

**mediaremote-adapter**（[ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)，BSD-3）：通过 `/usr/bin/perl … stream --micros` 拿所有播放器的推送更新，配合 Atoll 的用法。它依赖私有框架、绕了一个 Apple 授权，可能随系统更新失效，进隐私第三层登记，osascript 留作退路。

## C4：第一帧密钥仍无答案

iPhone 遥控器在 Pair-Setup 之后第一个加密帧用的密钥，这些项目都没有答案：atv-core（`session.rs#L527-531`、`#L310-313`）在答 PV-M1 时就装 ClientEncrypt-main，用 counter 0、帧头当 AAD 解第一帧——正是我们 `WS2CompanionCrypto.swift:169-170` 已经排除、手机拒绝的那个 key，失败也断开，和我们一样。PlayPort / DiPlay / LIVI 做的是 AirPlay / CarPlay 配对，不碰 Companion 协议。C4 继续当独立研究项，保住已经能用的 fresh Pair-Verify 路径。
