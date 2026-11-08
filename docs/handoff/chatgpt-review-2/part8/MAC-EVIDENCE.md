# 第八份在这台 Mac 上实际跑出来的结果（2026-10-03）

环境：macOS 27.0（26A428）、Xcode SDK 27、Swift 6.4。命令在仓库根跑，证据在 `.build/` 与 `tests/part8/validation/`。

## 合入后跑通的

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| input（手柄 → 原生模型列表） | `python3 tests/part8/tests/run.py --repo . --suite input` | 33 场景 / 49 断言 |
| fold（原 Notch 收起证据） | 同上 `--suite fold` | 21 场景 / 49 断言 |
| flow（会话 + 选择模型，含真实子进程） | 同上 `--suite flow` | 6 场景 / 27 断言 |
| 构建边界 | `python3 tests/part8/tests/check-build.py --repo .` | Foundation 37 份类型检查 + 41 份语法检查 |
| 接线检查 | `python3 tests/part8/tests/check-wiring.py --repo .` | PASS：物理尝试绑定授权账、刘海用真实证据调用方、只读入口未被放宽 |
| 文件工具 | `python3 tests/part8/tests/test-tools.py` | 18 项 OK（含 macOS 符号链接与路径规范化两处修正） |
| 旧回归（part7 三套 + legacy 两批） | `tests/part7/tests/run.py`、`regressions.py` | part7 core 27/51、flow 18/145、native 3/14；part6 core 95/wire 11、part5 core 97、part4 188、part2 86、T1 32、手势全过；process 9/27 与 8/26；PROC04 0.117 秒 |
| 整 App | `cd prototype && ./build.sh --check` | 通过（含 Native C 模块） |
| AppKit 回归 | `bash tests/run-appkit-tests.sh all` | 八套全过（含 LEASE-H01…08） |
| 隐私门禁 | `tests/run-privacy-registry-check.sh` / `run-privacy-page-sync.sh` | 466 个词法点、页面数据同源 |

## 这一轮只有 Mac 才会暴露的问题（都已按证据处理）

1. **第八份的 `check-build.py` / `regressions.py` 仍按 `prototype/App/InteractionCoordinator.swift` 找文件**，
   而本仓库把共享仲裁放在 `Core/`。两个脚本都改成两边都能找到（沿用第七份runner已做的处理）。
2. **`tests/part8/tools/stage.py` 的符号链接链检查拒绝 macOS 的 `/var`**（Apple 自己的根级链接），
   整份工具测试在 Mac 上直接报错。按本仓库既有做法（`WS2AtomicConfiguration`、`WS2UnixSocket`）先规范化
   `/var`、`/tmp`、`/etc` 三个根级前缀，其余任何一段是符号链接仍然拒绝。
3. **同一脚本里 `package.resolve()` 与 `out.absolute()` 混用**：`/var` 与 `/private/var` 两种写法让
   “输出在输入内”的比较失配，`test_package_output` 因此不再被拒。全改成 `resolve()`。
4. **新代码要 `island.inputHandle(for:)`**（模型选择页在同一租约下路由输入）。单岛是 `NotchLeaseHub`，
   我给它加了这一个只读访问器：只有内容仍是当前挂载且租约 `isCurrent` 才返回句柄。
5. **`WS2FoldEvidenceAdapter` 在非隔离上下文读 `AuthorizationService.shared.lockState()`**（MainActor 事实），
   Swift 6 严格并发下编不过。照仓库既有写法用 `MainActor.assumeIsolated` 显式声明在主线程上读。
6. **隐私登记表**：窗口证据适配器新读了一处 `kAXMinimizedAttribute`，主模型逐点归类到 `window-ax`
   （只观察本次收起，不新存截图或标题），登记表 465 → 466 点。

## 仍然没做（以第八份 REMAINING 为准）

真实手柄与 GameController 签名、插拔/重映射/共存实测；AppKit 焦点与布局实测；真实 AX 收起/恢复；
完整 T3（强身份、用户 revision、run/effect 绑定、幂等恢复、跨重启 journal）；Touch ID 允许路径；
配对接收与原生 Remote；身份与系统锁；能耗与全菜单回归；影片、签名与发布。
本轮没有打开任何自动窗口效果：`WS2FocusWindowPort.admitted` 仍为 false。
