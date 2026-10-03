# 第2份验证记录

本次环境为Linux、Swift 6.2.1、Node 22.16.0。实际版本输出见`validation/environment.json`。没有macOS SDK或实际外设；上传的Mac记录不是本次运行结果。以下记录只属于本次第2份，未把上一份的138个场景、377个断言重复计入。

## 实际编译、执行

从本包根目录执行：

```sh
bash tests/run-core.sh
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -typecheck contracts/Contracts.swift dependencies/FocusTimer.swift packages/T2/prototype/App/FocusTimerHost.swift
node film/scripts/check-timeline.mjs
python tests/check-schema.py --schema-dir /原repo/docs/handoff/reference/codex-app-server-schema-0.153.0
python tools/stage.py --repo /原repo --out /全新暂存目录
```

以上本次全部退出0；原始结果分别在`core-tests.txt`、`focus-host-typecheck.txt`、`film-timeline.json`、`codex-schema.json`、`staging.txt`。类型检查成功通常没有stdout；空文件不是错误输出被省略。

纯Swift代码编译使用Swift 6语言模式、完整严格并发检查、警告视为错误。**22个独立场景、86个断言通过**，覆盖共享租约、旧按键确认拒绝、期限与断连、远端准入、Codex分帧与状态边界。测试程序的拆包循环断言计入86，但未拆成多个独立场景。真实CLI未启动。

Codex记录共有9条合成出站消息：**8条载荷通过固定JSON schema验证，1条initialized通知通过结构断言**。其中两条是拒绝审批的返回值，没有允许执行的示例。消息本体和数字/字符串ID保留在`codex-outbound.ndjson`。schema验证不证明协议时序、端到端通信或授权正确。

`FocusTimerHost.swift`与合同和T1依赖一起通过Foundation类型检查。`FocusTimerCard.swift`是另一个AppKit文件，不能把host通过套用给card。

暂存脚本验证输入SHA256和唯一原文锚点，只向全新目录`/mnt/data/ws2-stage-part2-final`输出文件；不修改原repo。它不是完整工程复制，也不负责Xcode目标成员关系和宿主调用接线。part1合并时，合同文件只能保留一份。

## 语法检查与未执行的编译

5个Mac探针、S1信息气泡、T2宿主和卡片共8个Swift文件执行`swiftc -frontend -parse`，全部退出0，逐文件记录在`mac-source-parse.json`。**这是语法解析，不是加载macOS SDK的类型检查，更不是真机运行。**

`typescript-syntax.json`记录本机TypeScript对film/src的TS/TSX逐文件transpile语法检查，未见语法诊断。本机工具版本与工程锁定TypeScript版本分开记录。这次没有完成依赖解析和Remotion语义编译：npm依赖安装未完成，独立curl检查访问npm registry返回退出6（DNS无法解析），详见`npm-network-check.txt`。不得将语法检查写成`npm run typecheck`或Remotion render通过。

## 两条实际影片

本次用Chromium读取同一份确定性SVG画面，由Python按时间采样，交给ffmpeg编码。完整命令形状：

```sh
cd film
python scripts/render-offline.py --scale .5 --out out/WS2-animatic-landscape.mp4
python scripts/render-offline.py --portrait --scale .5 --out out/WS2-animatic-portrait.mp4
```

两条实际输出均为126.000秒、24fps、3024帧、H.264；横版960×540，竖版540×960，均无音轨。ffprobe原始结果在`media-probe.json`，逐秒渲染记录在`offline-render-*.txt`。这两条是离线动态分镜，**不是Remotion渲染成片**。Remotion源工程目标仍为60fps、7560帧、1920×1080/1080×1920。

时间线测试**186项断言通过**，包括章节长度、连续轮廓、静止段与重复定位的确定性。安排的静止段2370/7560帧约31.35%，不代表审美评分或全片像素验收。实际视频每章各抽一帧，共18帧，见`contact-landscape.jpg`和`contact-portrait.jpg`：标题可见、概念/待录标记可见，没有发现这18个位置的文字裁切；竖版主体偏小、留白较多，占位卡重复，均仍需后续素材与节奏调整。未逐帧人工观看两条全片，也未运行光流carry工具。

17项真机素材均未提供，保持未批准状态。没有配音、音乐、响度或音频授权验收。抽象图形不是解锁、CarPlay、后端真实执行或身份模型能力的证据。

## 尚未完成

没有整App构建、macOS探针实测、私有多触点ABI确认、BLE身份与心跳证明、遥控器音频、真实系统锁/解锁、人脸活体/误识率、跨设备配对加密、自动修改home、生产App接线、能耗测量或发行签名。对应未完项逐包写在`REMAINING.md`，不能因为探针或工作单已经交付就标为完成。
