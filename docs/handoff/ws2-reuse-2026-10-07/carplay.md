# CarPlay 无凭据实验：播放器与合成协议测试通过，接收尚未运行

2026-10-07（Asia/Taipei）。本轮用户没有 dongle、认证身份或服务。保留当前产品入口；没有接入长按、UI 或日常实例。

## 固定对象与实际证据

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

新增 `WS2CarPlaySession` 仅为自主实现的纯状态契约，尚无运行时调用点：每次连接分配独立 ticket；迟到的旧 session end/ready 不能清除新会话；断开使 ticket 失效；退出全屏只返回桌面，保留连接；缺身份停在 missingIdentity，不产生 ready。`identityAvailable` 是未来适配器验证结果，不是认证实现，不能由 UI 勾选冒充通过。

测试覆盖缺身份、旧会话结束不清新会话、断开后的迟到事件、失败后的迟到 ready、退出全屏与断开的差别。上游 `CarPlayServer.onSessionEnded` 的旧会话事件仍会无条件结束麦克风并广播离线；本轮未改 GPL checkout。将来接线必须在媒体清理与 UI 通知之前匹配 ticket，仅加 WS 状态模型不能修好上游内部副作用。

## 下一步与真实阻断

无凭据构建与三组合成协议测试已完成。下一步由用户提供可使用的外部认证身份或服务，另行进入真实接收实验。PlayPort 无 dongle 但仍需认证身份；没有身份只能交付当前构建与适配契约。不得把 DiPlay APK 中实验性恢复身份当开源代码许可的一部分写入 WindowShade。

有身份后的第一片保持 PlayPort 独立播放器，验证一台 iPhone、H.264、真实画面/音频/点击及断线恢复，再接宿主 Esc 返回桌面。PlayPort 默认 Esc 是 CarPlay Back，宿主返回桌面应另行截获。Siri/通话、锁屏睡眠恢复、旧会话晚到、麦克风拒绝均尚未实测。LIVI 的硬件认证路径与 DiPlay 的 Android/BYD UI 不进入本次交付。
