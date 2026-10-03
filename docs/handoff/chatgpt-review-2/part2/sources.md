# 依据与版本边界

本次工程基线只有上传的round2 repo与part1，不声称检查了GitHub最新HEAD。固定协议以 `docs/handoff/reference/codex-app-server-schema-0.153.0/` 为准，macOS事实以同目录mac-facts-2026-10-03.md为准。

外部官方参考（本轮查询）：
- OpenAI app-server https://developers.openai.com/codex/app-server （当前重定向到 https://learn.chatgpt.com/docs/app-server ）；只作概念参考，字段由上传schema验证。
- Claude Code hooks https://code.claude.com/docs/en/hooks ；没有据网页推测Codex TOML的hook字段，也没有修改真实home。
- Remotion Series https://www.remotion.dev/docs/series ；OffthreadVideo https://www.remotion.dev/docs/offthreadvideo 。本工程固定4.0.484，不使用文档后来新增的OffthreadVideo durationInFrames属性。
- Apple GCDualSenseAdaptiveTrigger https://developer.apple.com/documentation/gamecontroller/gcdualsenseadaptivetrigger 。当前源码包未写完整GameController桥，已有Mac头文件记录不能顶替本轮编译。

shotcraft示例原样保留于film/reference；许可证见LICENSE-video-shotcraft。其它新增Swift、Python、JS/SVG为本次原创。未附字体文件、商业音频、人脸模板、私钥或密码。
