> 历史归档：记录的是 2026-09-13 的判断与进度，不代表当前缺陷或执行指令。后续实现以 Git 历史、现行文档和 [1.0.15 发布说明](../../../releases/v1.0.15.md) 为准。

# WindowShade v1.0.11 包装与发布 — 完成

用户授权：更新 GitHub README、参考 AI System 6 包装项目并实际发版，保留历史上的有益元素。已阅读参考项目 README 与项目规则、当前 native 变更和最新用户验收记录。用户当前授权涵盖此次提交与公开发布。

- 提交并推送 `3cacffaee1844f5f3a370e2e4d4b275319a92ab6`，包含此前 35 个本地提交及已完成的原生 UI、裁切和网站工作。main 与 v1.0.11 的远程解引用均匹配。
- 中英文 README 重写：Make room. Keep your place. / 暂时让开，位置还在。保留 GIF、明暗真实设置图、快捷键、恢复机制、原设计笔记与历史发布说明；纠正单击展开及签名必然保留权限的绝对说法。
- GitHub About、官网入口和 topics 已更新。README 实际 GitHub 渲染和全部文章图片加载已检查。
- 历史正文原笔记保留，仅添加已核实年代和出处修正提示。明确独立实现而非历史同名代码延续。
- 版本 1.0.11 / build 11，arm64；build.sh 从源 Info.plist 同步两项版本，在签名前完成；沿用现有 Apple Development 证书，隔离 --stage 构建，不替换日常 app。发布文档同步此流程。
- 优化构建与 Metal 编译、Duo 核心/帧/集成检查、纸面组件检查、签名原生 fixture 折叠/恢复/准备期取消/拖动恢复/同步取消全部通过。构建保留已知 stopCapture API 警告。
- 签名验证、zip 解压后的版本/架构/签名验证通过。spctl 拒绝，README/Release 明确 Apple Development 签名但未公证，不声称 Developer ID 或 notarized。
- Release 已公开并设为 latest：https://github.com/surfine/WindowShade/releases/tag/v1.0.11 。附件 ZIP 3,170,463 bytes，SHA256 `57577c82e6d84b95808300ef1d065f21934f0a11dc13bda991b98d64d069697f`。GitHub 回下载与 checksum 校验通过。
- 官网版本截图说明与 Apple Silicon 下载边界已同步部署：https://39afb532.windowshade.pages.dev 。生产中英文首页与变更许可资产哈希吻合，27 资产构建检查通过，site/deployment.json 已提交。
- 未提交既有 AGENTS.md、CLAUDE.md、docs/reviews/、docs/tasks/，未改 AI System 6。历史任务中“尚未发布”的状态由此发布记录覆盖。无剩余发布工作。
