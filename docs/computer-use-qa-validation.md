# Computer Use 工具实施与验收

2026-10-09：方法、CLI、八场景合同和项目入口已落地于独立分支 `codex/computer-use-qa`。没有改动产品源码、签名或发布；原工作区并行改动保持独立。

## 已验证

- Python 标准库工具：83 项离线检查通过，覆盖传输失败、旧截图、缺文件、哈希/AX 身份冲突、错误的通过结论、历史失败保留、会话停止、VM 互斥与清理边界。
- CounterFixture 使用 Swift 6、完整并发检查、警告视为错误编译成功；经 prepare 实际传入 VM、核对哈希并持续计数。
- 真实 CLI 完成收起、静态看一眼、取消、展开与清理；窗口位置、尺寸、身份和文本与本次基线一致。
- 动态预览中看见计数 217→317→507，但曾有截图超时与 AX 截断，本轮为 inconclusive；故障后的点击确实在 CLI 内被拒绝。受控恢复与视觉复核之后，清理通过。
- 从外置盘交付副本执行 verify，确认四个已测场景通过，未测项没有变绿。report 返回 2 表示仍有未测/失败，不是完整产品验收通过。

测试对象始终是历史签名 WindowShade 1.0.16（SHA256 `128b76bd47c4d3ea27220deb03f4d30256d4640fd844ba50bbc5ba0c7717e8f1`），来宾 macOS 26.6.2；没有把结果套到当前源码。单窗口、目标变更、多屏及真实硬件矩阵仍需针对候选构建执行。

## 实际运行记录

- [20261009T173952-939c09b4](</Volumes/TiPlus 7100/WindowShade-QA/evidence/computer-use-qa/20261009T173952-939c09b4/report-1791541852533221000.md>)：fold-companion=fail、restore=pass；cleanup=pass。
- [20261009T175511-f5cb6b23](</Volumes/TiPlus 7100/WindowShade-QA/evidence/computer-use-qa/20261009T175511-f5cb6b23/report-1791541852971869000.md>)：fold-companion=blocked；cleanup=pass。
- [20261009T180056-38310eec](</Volumes/TiPlus 7100/WindowShade-QA/evidence/computer-use-qa/20261009T180056-38310eec/report-1791541853339932000.md>)：fold-companion=pass、peek-static=blocked；cleanup=pass。
- [20261009T180537-8b806344](</Volumes/TiPlus 7100/WindowShade-QA/evidence/computer-use-qa/20261009T180537-8b806344/report-1791541853738987000.md>)：fold-companion=pass、peek-static=pass、peek-cancel=pass、restore=pass；cleanup=pass。
- [20261009T181007-61ccb18b](</Volumes/TiPlus 7100/WindowShade-QA/evidence/computer-use-qa/20261009T181007-61ccb18b/report-1791541854073982000.md>)：peek-live=blocked；cleanup=pass。
- [20261009T181327-fa8395b9](</Volumes/TiPlus 7100/WindowShade-QA/evidence/computer-use-qa/20261009T181327-fa8395b9/report-1791541854364794000.md>)：fold-companion=pass、peek-live=inconclusive、restore=pass、observation-failure=pass；cleanup=pass。

## 缺陷与边界

历史二进制在存在第二个 TextEdit 文档时走最小化路径，菜单计数增加但卷帘条没有出现。复现：保留两个 TextEdit 文档和 Finder，从 WindowShade 菜单收起当前文档；首份运行保留 before/after。仅确认该环境现象，未定位源码根因，不宣称当前工作区有同一缺陷。

动态预览会临时使原窗口可见，AX 的原几何和可见性不足以证明已经展开。因此 cleanup 必须有实际查看画面的 restore 复核，并重新核对 AX；故障恢复通道只允许新截图中原标题条区域的双击，不解除 HALTED，也不直接关闭窗口。

开发期发现并修复的工具问题也保留在运行记录：SSH 参数位置、move_cursor 不支持 capture_id、截图有效期、AX 完整等待、WindowServer 保留已关闭窗口编号、精确焦点确认与异步关闭核对。不能把这些工具阻塞写成产品失败。

## 交接

[主手册](computer-use-qa.md) 和 [工具入口](../tools/computer-use-qa/README.md) 是维护入口。六个公开基础命令另加 observe/act，均支持 --help。所有原始证据与运行报告保存在外置 QA 盘，不向仓库塞图片与二进制。

DeepSeek 负责传输层和离线测试初稿；主模型修正实际接口与验收边界、独立增加反例测试，并完成实机视觉复核。第二次委派达到轮次上限，后续测试与修正由主模型接手，未采信其完成声明。

所有本次测试窗口与会话已清理。VM 保留运行供复用；它的运行状态不属于产品通过证明。没有安装新的模型服务或创建后台自动化。
