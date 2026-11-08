# 第七份在这台 Mac 上实际跑出来的结果（2026-10-03）

环境：macOS 27.0（26A428）、Xcode SDK 27、Swift 6.4、`/opt/homebrew/bin/codex` = codex-cli 0.153.0。
命令都在仓库根跑；证据在 `.build/` 与 `tests/part7/validation/`。

## 合入后跑通的

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 第七份 core | `python3 tests/part7/tests/run.py --repo . --suite core` | 27 场景 / 51 断言 |
| 第七份 native | 同上 `--suite native` | 3 场景 / 14 断言（真实 Python 子进程、进程组、fd 边界） |
| 第七份 flow | 同上 `--suite flow` | 18 场景 / 145 断言（受控假后端，覆盖 config/account/thread/turn/中断/登出） |
| 旧回归（foundation） | `python3 tests/part7/tests/regressions.py --repo . --history docs/handoff/chatgpt-review-2 --batch foundation` | part6 core 95、part6 wire 11、part5 core 97、part4 188、part2 86、T1 32、手势全过 |
| 旧回归（process） | 同上 `--batch process` | part5 8/26、part6 9/27、PROC04 OBSERVED_PASS 0.097 秒 |
| 构建边界 | `python3 tests/part7/tests/check-build.py --repo .` | Foundation 33 份类型检查、38 份语法检查通过 |
| 整 App | `cd prototype && ./build.sh --check` | 通过（含 Native C 模块、Metal、MetalKit、GameController） |
| AppKit 回归 | `bash tests/run-appkit-tests.sh all` | 八套全过（含 LEASE-H01…08） |
| 隐私门禁 | `tests/run-privacy-registry-check.sh` / `run-privacy-page-sync.sh` | 465 个词法点、页面数据同源 |

## 真实 CLI 驱动 LaunchController（工单 01 第三步）

`bash tests/run-owned-codex-controller.sh`：隔离 profile（独立 HOME/CODEX_HOME/TMPDIR + 写好的
`config.toml`），不打开登录页、不发任何有副作用的命令。实际顺序：

```
stage: checking version / config / account
stage: phase→connecting
stage: phase→checkingConfig              # config/read 投影通过
stage: phase=signedOut  "需要登录 ChatGPT"
models = ["gpt-5.2","gpt-5.5","gpt-5.6-luna","gpt-5.6-sol","gpt-5.6-terra"]
SIGNED_OUT: 隔离 profile 里没有可用账号；真实查询需要用户先登录。
PASS owned Codex real controller: 版本、独立配置与账号边界走通（未登录，未发送查询）
```

也就是说：版本核对、独立配置、`config/read` 投影核对、模型目录都对真实 0.153.0 成立；
真正的查询要么用户在隔离 profile 里登录，要么用主 profile（会动到用户账号状态），本轮都没做。

## 这一轮只有 Mac 才会暴露的问题（都已按证据修）

1. **`posix_spawn_file_actions_addchdir_np` 在 SDK 26+ 弃用**：`-Werror` 直接编译失败。改成
   `__builtin_available(macOS 26, *)` 选 `posix_spawn_file_actions_addchdir`，旧系统走 `_np`
   并用 pragma 明确接受弃用（部署目标 14，两条路都要能编）。
2. **leader 退出后 `getpgid()` 在 macOS 上 ESRCH**（Linux 的僵尸还锚着 PID）：原生监督端口原来靠它
   取组号，于是既不终止进程组也永不回收。改为 spawn 成功时核对并记下组号（核对失败先杀再回收），之后只用记下的值。
3. **空进程组的 `kill(-pgid)` 在 macOS 回 EPERM**（Linux 回 ESRCH）：原实现把它当监督失败 → 不回收 →
   版本预检的 `onReaped` 永不触发，`flow` 整套卡死。改为用 0 号信号探一次，确认组内已无成员就照常回收。
4. **Swift 6：异步上下文不能迭代 `NSEnumerator`**（FlowTests 收集出站帧那段），先落成数组再筛。
5. **隔离 profile 的 PATH 限死成 `/usr/bin:/bin:/usr/sbin:/sbin`**：codex 是 `#!/usr/bin/env node`
   脚本、node 在 `/usr/local/bin`，真实 CLI 直接 127 退出，还会被误读成“版本不对”。改为沿用 App 自己的 PATH。
6. **真实的 `config/read` 总会投影一个 `hooks` 对象**（事件名齐全、数组为空）：旧检查把任何非空对象
   当成“配了钩子”而拒绝。改为逐事件核对：空数组/null 放行，真有条目或形状不对才拒绝。
7. （第五、六份已记）CryptoKit Ed25519 随机化签名、按线程屏蔽 SIGPIPE 无效、初始化期就发通知、
   codex 是 node 脚本需要 PATH——同属“只在 Mac 才会暴露”。

## 仍然没做

真实账号登录后的查询、Touch ID 允许路径、原生界面（布局/输入法/焦点）实测、Mac `waitid` 与
脱离组子孙的全树安全、配对/设备/窗口/能耗/影片、签名与发布。`COMPLETION-CONTRACT.md` 的 A/B/C
三张表没有被本轮改写成完成。
