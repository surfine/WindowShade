# docs/archive

一次性调查、旧版验收记录与已完成的进度日志放这里。

- 路径：`docs/archive/<归档日期>/<文件名>`。
- 每个文件开头写归档日期、原版本、是否仍有效；不再维护的内容明确写“仅作历史记录”。
- 现行规则不放这里：测试见 [../testing.md](../testing.md)，修缺陷流程见 [../fix-process.md](../fix-process.md)，已知失败见 [../known-failures.md](../known-failures.md)。

## 目录

- `2026-11-11/update-design-2026-09-29.md`：应用内更新的设计稿，被 [../update.md](../update.md) 取代。
- `2026-11-11/releases/`：1.0.16–1.0.21.1 已发布版本的发布关 runbook、验收清单、计划和 appcast 草稿。`tests/vm/run-updater-phase3-1018.sh` 读其中的 `appcast-item-1.0.18.xml`，移动它时要同步改脚本。
