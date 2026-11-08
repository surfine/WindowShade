# CarPlay 无凭据实验：播放器与合成协议测试通过，接收尚未运行

2026-10-07（Asia/Taipei）。本轮用户没有 dongle、认证身份或服务。保留当前产品入口；没有接入长按、UI 或日常实例。

## 2026-10-10 转向：先求有——live 画面经外部接收器，MFi 模块真机可测

用户三条指示改变了路线：优先接 LIVI / PlayPort / DiPlay；以用户体验为本、可推翻旧决策；先求有再求好、这是前卫实验。据此**推翻「没有 Apple 签发身份就不做 live 入口」**的旧决策：

1. **App 侧 live 通路（已交付，默认关）**：`CarPlay.receiver.endpoint`（ws://…，用户自填，含接收器令牌）设了之后，长按刘海的全屏不再走合成动画，而是作为接收器的**前端**——`WS2CarPlayReceiverClient` 连接收器 WebSocket，`WS2CarPlayVideoDecoder` 用 avcC/hvcC + Annex B→AVCC 直接喂 `AVSampleBufferDisplayLayer`；触摸/方向键/回车/空格/s 映射成接收器的 touch/knob/media/siri JSON 回传。认证、iAP2、AirPlay 全在接收器进程里完成（GPL 隔离在进程边界外，App 全部原创 Swift，不读不存任何身份）。会话模型加了 `delegated` live 模式：本机无身份也可 live，退避/重连/关键帧/收画计数与直连同一套。全屏文案新增 live 相位：出画面前「等待 iPhone 的画面」，出画面后整屏只留视频，Esc/再长按回桌面不断开手机。
   - 测试：`tests/run-carplay-session-tests.sh`、`run-carplay-surface-tests.sh`、`run-carplay-receiver-tests.sh` 全绿（线协议按 PlayPort 固定源 9a0882d 的 Wire.kt/WebHub.kt 逐字节核对，VIDEO_CONFIG 记录从偏移 11 起、上游多带一个尾零字节也已对齐）。
   - 隐私登记：新增 `carplay-receiver`（URLSession×5），`CarPlay.receiver.endpoint` 读写归 `settings`×3；隐私页已重生成并过同步测试。默认关：开关和地址都不设就完全走旧路。
2. **iAP2/MFi 真机探针（已交付，隔离工具）**：`tools/carplay/iap2/` 原创 Swift 实现 iAP2 链路层（FF 55 marker、FF 5A 帧与 8 位补码校验、0x80 同步交换、session 10）、CSM（0x4040）、识别消息 0x1D00→01→02（无线参数表含组 17 蓝牙传输/组 24 Wi-Fi，按上游 IdentificationClient 参数 ID 逐项核对）、MFi 交换 0xAA00→05（证书放参数 0、对 iPhone 给的 32 字节摘要做 ECDSA-P256 输出 64 字节 r||s）。身份走用户自备目录（identity.pk8 + certificate.p7b，PKCS#8 解析只认 P-256 OID），加载时当场自检私钥/证书匹配；Apple 私钥外部表示是 04||X||Y||标量（标量在最后 32 字节），导入按同格式重组。离线测试（现场生成自签测试身份，不碰蓝牙）全绿；`bash tools/carplay/build-iap2-probe.sh` 编出 `.build/carplay-tests/iap2-probe`。
   - 真机跑法：iPhone 先与 Mac 配对（`iap2-probe --list` 找地址；iPhone 在蓝牙设置页等待），然后 `iap2-probe --identity-dir <dir> --address <addr>`，阶段日志在 stderr，`RESULT authenticated` 即 iPhone 认了这份身份。退出码区分：3 RFCOMM 打不开、4 通道被关、5 链路死、6 识别被拒、7 签名/挑战异常、8 MFi 拒绝、9 超时未完成。需要终端蓝牙权限。
   - 尚未真机执行：MFi 通过只证明身份被认，Wi-Fi 交接（0x5703 组 24 的 SSID/密码发送）与 AirPlay 会话是下一片。
3. **PlayPort 后端照旧**：固定 9a0882d 的无凭据验证（17 JVM 合成测试）不变；`check-playport.sh`/`test-session.sh` 可复现。live 通路对接的是它的 WebSocket（8080，`?token=`），实跑时由用户自己起服务、自己提供身份——App 不碰。

## 固定对象与实际证据（2026-10-07 原文）

研究对象为 [PlayPort](https://github.com/youcci/playport/tree/9a0882dd0ffe48e467b59d58b12d81391df55ade)，SHA `9a0882dd0ffe48e467b59d58b12d81391df55ade`。真实 checkout 在忽略目录 `.build/research/playport`，detached HEAD，tracked 状态干净。GPL 源码没有进入 MIT 主应用或被 vendor。

本机 Node `v24.14.1`。按上游 package-lock 执行 `npm ci --ignore-scripts --no-audit --no-fund`，安装 17 个包，无全局安装。上游 `npm test` 通过：真实 InputController 的键盘隔离、原生控件、横竖屏坐标、多触点和释放。`npm run build` 通过：TypeScript 和 Vite 8.3.1，11 个模块；输出 HTML 16.59 kB、CSS 20.75 kB、JS 30.39 kB。这些只是未签名浏览器产物，不是 CarPlay 已接通的证据。

最初本机无 Java Runtime；本轮已自主补齐**仓库本地工具链**，不再将 JDK 作为用户阻断：官方 Temurin 21.0.12.1+1 下载到 `.build/tools/jdk21`，SHA256 `3623232f33a9c3baadf304480b2535f9a3cba8a58d42ecbb438ba267315d9998` 与官方 GitHub release asset digest 相符。Gradle 9.5.0 按上游 wrapper 校验下载，缓存隔离到 `.build/tools/gradle-home`。上游 `gradle-daemon-jvm.properties` 另指定 JVM 25，因此 Gradle 自动下载 Temurin 25.0.3+9 到同一忽略目录；没有修改上游配置或全局 Java。

协议模块实际编译成功，三组合成测试 **17 passed / 0 failed / 0 skipped**：Iap2ProtocolTest 10、CarPlaySizeTest 3、LocalMfiAuthenticationClientTest 4。后者现场生成自签测试材料，未加载或获取真实附件身份。未执行 server 的真实 MfiIdentityTest，也未启动服务。不能将这17项写成全上游96项通过。

本机回执：`.build/carplay-tests/playport-jvm-check.log`（最终 exit 0，BUILD SUCCESSFUL），JUnit XML 在 `.build/research/playport/protocol/build/test-results/test/`。早期 `playport-check.log` 的缺 JDK 结果已由本次成功证据取代。独立 Swift 会话测试通过，无全 App 构建。

## 可复现入口

在仓库根目录运行：

```sh
# 首次下载固定上游与前端依赖，需要网络；不启动任何服务
bash tools/carplay/check-playport.sh --prepare
# 可选：安装固定校验和的官方JDK到.build，Mac ARM64专用
bash tools/carplay/prepare-jdk21.sh
# 首次解析Gradle依赖；仍只跑指定无凭据测试
bash tools/carplay/check-playport.sh --resolve-jvm
# 已准备目录的本地检查；Gradle 使用 offline，只跑指定合成测试
bash tools/carplay/check-playport.sh --check
bash tools/carplay/test-session.sh
```

脚本拒绝错误 SHA、修改过的上游 tracked 文件以及含 `identity/offline-mfi` 的 checkout。未下载 Gradle/JVM 依赖的环境可用上面的显式准备步骤补齐；也支持用户指定 JAVA_HOME。脚本不包含 `:server:run`、蓝牙配对、mDNS 广播、凭据获取或手机连接。保存日志可用普通输出重定向，不会输出身份或 Wi-Fi 密码。

## WindowShade 适配边界

新增 `WS2CarPlaySession` 仅为自主实现的纯状态契约，尚无运行时调用点：每次连接分配独立 ticket；迟到的旧 session end/ready 不能清除新会话；断开使 ticket 失效；退出全屏只返回桌面，保留连接；缺身份停在 missingIdentity，不产生 ready。身份走可插拔接口 `WS2CarPlayAccessoryIdentity`：只接受来源为 Apple 签发的身份，提取出来的或来源不明的一律拒绝，仓库里不放任何提取的身份；接口只看来源，真正的校验归未来适配器，不能由 UI 勾选冒充通过。没有身份时会话只跑合成模式（2026-10-08 起 `failed` 状态由 `waitingToReconnect` / `gaveUp` 取代）。

测试覆盖缺身份、旧会话结束不清新会话、断开后的迟到事件、失败后的迟到 ready、退出全屏与断开的差别。上游 `CarPlayServer.onSessionEnded` 的旧会话事件仍会无条件结束麦克风并广播离线；本轮未改 GPL checkout。将来接线必须在媒体清理与 UI 通知之前匹配 ticket，仅加 WS 状态模型不能修好上游内部副作用。

## 下一步与真实阻断

无凭据构建与三组合成协议测试已完成。下一步由用户提供可使用的外部认证身份或服务，另行进入真实接收实验。PlayPort 无 dongle 但仍需认证身份；没有身份只能交付当前构建与适配契约。不得把 DiPlay APK 中实验性恢复身份当开源代码许可的一部分写入 WindowShade。

有身份后的第一片保持 PlayPort 独立播放器，验证一台 iPhone、H.264、真实画面/音频/点击及断线恢复，再接宿主 Esc 返回桌面。PlayPort 默认 Esc 是 CarPlay Back，宿主返回桌面应另行截获。Siri/通话、锁屏睡眠恢复、旧会话晚到、麦克风拒绝均尚未实测。LIVI 的硬件认证路径与 DiPlay 的 Android/BYD UI 不进入本次交付。

## 会话规则与测试矩阵（2026-10-08，合成事件，无真机）

入口是长按刘海；CarPlay 画面保持抽象，不画车机界面。`WS2CarPlaySession` 不开传输、不起计时器，时间由适配器传入：

- 全屏分辨率在会话开始时固定；改它或任何设置，只在下次重连生效。
- 每次显示 CarPlay 画面（长按）只向手机请求一个关键帧。
- 重连等待 2 s × 2^n，封顶 30 s，最多 5 次（2、4、8、16、30 s），第 5 次再失败就放弃，等用户重新连接；连接稳定满 60 s 清零重连计数。
- 两套边距：可视区是手机铺画面的范围，安全区在其内，保证内容躲开刘海。
- 收到的帧数和画出的帧数分开记，验收拿两者对比（画出只在画面显示时累计）。
- 离开回到桌面，每个窗口留在原处：会话不持有任何窗口状态，也不因此断开手机。

| 场景 | 预期 | 测试（`bash tests/run-carplay-session-tests.sh`） |
| --- | --- | --- |
| 退避序列 | 2、4、8、16、30 s 后放弃 | backoff 2,4,8,16,30 then stop |
| 稳定清零 | 59.9 s 不清，60 s 清零 | 59.9 s / 60 s of stability |
| 串流中改分辨率 | 当前会话不变，重连后生效 | running session keeps its resolution |
| 显示画面 | 每次一个关键帧 | showing requests one keyframe |
| 收与画 | 两个计数互不影响 | received and drawn move independently |
| 无身份 | 只能合成，要求 live 被拒 | live without identity is refused |
| 验收：冷启动 | 合成连上、首次显示请求关键帧、首秒收画一致 | cold start |
| 验收：反复重连 | 稳定后掉线永远只等 2 s；快速闪断 5 次后放弃 | repeated reconnect |
| 验收：长时间播放 | 1 小时 108000 帧收画一致，无多余关键帧或重连 | long playback |

## Mac 上已知的阻断

- 系统自带的 AirPlay 接收器占着 7000 端口，接收端要么让用户关掉它，要么换端口并如实告知。
- 需要蓝牙权限。
- 取 Wi-Fi 名称要定位权限；Wi-Fi 密码会交给手机，要在界面里说清。
- 只有无线：Mac 上没有有线 CarPlay。
- 没有 Apple 签发的配件身份前，一切只在合成模式下验证。
