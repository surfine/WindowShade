# 已知失败与已知限制

登记原则：**只登记已经复现过、并且当前决定暂不处理的问题**。每项都要写清环境、复现方式、为什么暂不修、下次什么时候再看。
“下次”到了没有结论，就重新评估：修掉、改登记、或者删掉。

| 失败项 | 环境 / 构建 | 复现 | 首次记录 | 当前状态 | 最后核对 | 关联探针 |
|---|---|---|---|---|---|---|
| `run-part6-readiness.sh` 返回 2 | 本机，任意构建 | `bash tests/run-part6-readiness.sh` | 2026-11-02 | 预期 BLOCKED：真机与设备证据未补齐；不是回归 | 2026-11-02 | `readiness.py` |
| 虚拟机 `browser-more` 偶发超时 | wsqa-manual（macOS 26，2–4 核） | 跑 `tests/vm/run-core-probes.sh`，其中一组在不同步骤等满 5 秒 | 2026-10-16 | 重跑一次；仍失败记 `inconclusive`，不判回归 | 2026-11-02 | `run-core-probes.sh` |
| 页面探针写死开发证书 | 其余机器 | 6 个 `*page-probe.sh` 默认 `Apple Development: openkams@gmail.com (G3TN2MBQ2Q)` | 2026-11-02 | 用 `WINDOWSHADE_CODESIGN_IDENTITY` 覆盖；没有该证书的机器跑不了 | 2026-11-02 | `run-*-page-probe.sh` |
| 更新自检与 `Duo.metallib` 耦合 | 任意构建 | `UpdaterLaunch.selfCheck` 要求 bundle 里有 `Duo.metallib` | 2026-11-02 | 资源还在，暂不触发；若清理 Metal 效果，必须同步改自检，否则每次更新被否决 | 2026-11-02 | `run-update-integration.sh` |
| 声纹模型缺失时产物不同 | 干净检出、没有 `../WindowShade-models` | `build.sh --check` 跳过 `SpeakerEmbedding.mlpackage` | 2026-11-02 | 不阻塞编译；发版前必须确认包内有 `SpeakerEmbedding.mlmodelc` | 2026-11-02 | `build.sh` / 发布关 |
| AppKit 套件依赖 `rg` | 干净 macOS | 没有 `rg` 时套件发现为空 | 2026-11-02 | 预检会提示；装 `ripgrep` 后重跑 | 2026-11-02 | `run-appkit-tests.sh` |
| 1.0.20 未跑虚拟机回归 | 发布机 | `tests/vm/run-core-probes.sh` 未在 wsqa-15 / wsqa-manual 上执行 | 2026-11-02 | 按发布决定跳过；1.0.21 补两台各一轮 | 2026-11-02 | `tests/vm/run-core-probes.sh` |
| 跨桌面携带依赖 SkyLight 内部符号 | 任意构建 | `SLSPerformAsynchronousBridgedWindowManagementOperation` 或 `SLSBridgedMoveWindowsToManagedSpaceOperation` 缺失 | 2026-11-02 | 静默回退到“窗口留在原桌面”，日志 `method=fallback`；每个 macOS 大版本复核一次 | 2026-11-02 | `run-bridged-space-move-tests.sh` |
| `release-gate.sh` 默认联网取上一版 | 离线 | 不传 `--previous` 时调用 `gh release download` | 2026-11-02 | 离线门禁显式传 `--previous <zip>`；`local-gate.sh release` 已强制 | 2026-11-02 | `scripts/release-gate.sh` |
| `--restore-guard`：另一扇收起的窗被带回来 | 本机 M5（macOS 27），签名 stage 构建 | `bash tests/run-glance-probe.sh --restore-guard` → `FAIL restore-guard: the other window came back (still folded=true visible=true)` | 2026-11-06 | 11-05 改动前的 3cb3ba32 同样失败，不是本轮回归；待单独查「叫回前台后 App 把窗都摆出来」这条路 | 2026-11-06 | `--restore-guard` |
| `--notch`：收进刘海 5 秒内没离屏 | 本机 M5（macOS 27），签名 stage 构建 | `bash tests/run-glance-probe.sh --notch` → `verdict: FAIL timeout: tucked away after 5.0 s` | 2026-11-06 | 3cb3ba32 同样失败，不是本轮回归；前两项（甩向刘海、落点小岛）通过 | 2026-11-06 | `--notch` |
| `--split`：左右半屏后中间没出把手 | 本机 M5（macOS 27），签名 stage 构建 | `bash tests/run-glance-probe.sh --split` → `FAIL split: two windows filling the screen side by side get a bar in the middle (seams=0 at -1)`，`verdict: FAIL timeout: snapped to a third after 3.0 s` | 2026-11-06 | 37b24c3d 之上只加 --hold 探针的构建同样失败，逐行相同，不是 WindowStateHub 的回归；疑为探针 `refresh()` 后立刻读缝（扫描是异步的），待单独查 | 2026-11-06 | `--split` |
| `--pip`：收尾时两扇窗 4 秒内没都回来 | 本机 M5（macOS 27），签名 stage 构建 | `bash tests/run-glance-probe.sh --pip` → 前 8 项 PASS，`verdict: FAIL timeout: both back after 4.0 s` | 2026-11-06 | 改动前构建同样失败，不是本轮回归 | 2026-11-06 | `--pip` |
| `--slide-over-desktops`：临时窗挪不到另一张桌面 | 本机 M5（macOS 27），签名 stage 构建 | `bash tests/run-glance-probe.sh --slide-over-desktops` → `verdict: FAIL timeout: window on another desktop after 6.0 s` | 2026-11-06 | 改动前构建同样失败；同一台机器 `--slide-over-spaces --other-space` 能挪过去，差别待查 | 2026-11-06 | `--slide-over-desktops` |
| 默认看一眼流程：看一眼时真窗口冒出来 | 本机 M5（macOS 27），签名 stage 构建 | 不带专项参数跑 `tests/run-glance-probe.sh`（11-06 之前 `--slide-over-border` 没接进调度，也会落到这里）→ `verdict: FAIL real window came back during glance` | 2026-11-06 | 改动前构建同样失败，不是本轮回归 | 2026-11-06 | 默认流程 |
| 蓝牙在场：连着时不再每 5 秒送探针回执 | 任意构建（11-06 起） | `WS2BluetoothPresenceSource` 改成通知驱动后，只在连上那一次送 `readStarted/readSucceeded`；5 秒保底只读 `isConnected()` | 2026-11-06 | 眼下无影响：`PresenceLock` 里靠探针回执续上 `cancelCountdown` 的分支只在 `cameraEnabled` 打开时才走，这个开关目前没有入口。将来打开相机在场（或“回来自动解锁”的 RSSI 判定）时，要在那段时间重新周期送探针 / RSSI | 2026-11-06 | `run-presence-bluetooth-source-tests.sh` |

## 登记模板

```text
失败项：
环境 / 构建：
复现：
首次记录：
当前状态：
最后核对：
下次再看：
关联探针 / 证据：
```

## 不登记在这里的东西

- 一次性的性能热点调查 → `docs/perf-ledger.md`。
- 还没复现的猜测 → 先写进 issue 或当次修复记录，不占台账。
- 已被后续版本修掉的问题 → 删掉，或移进 `docs/archive/` 并在归档头写清版本。
