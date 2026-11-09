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
| 蓝牙在场：连着时不再每 5 秒送探针回执 | 任意构建（11-06 起） | `WS2BluetoothPresenceSource` 改成通知驱动后，只在连上那一次送 `readStarted/readSucceeded`；5 秒保底只读 `isConnected()` | 2026-11-06 | 眼下无影响：`PresenceLock` 里靠探针回执续上 `cancelCountdown` 的分支只在 `cameraEnabled` 打开时才走，这个开关目前没有入口。将来打开相机在场（或“回来自动解锁”的 RSSI 判定）时，要在那段时间重新周期送探针 / RSSI | 2026-11-06 | `run-presence-bluetooth-source-tests.sh` |
| 台前调度下不能最小化的窗口收起仍会被拉回 | 本机 M5（macOS 27），台前调度开，`--restore-guard` 用的那种不给最小化的临时窗 | `slide.hide` 走系统收起失败（补写一次仍收不起）→ 退回推到屏外的老路，窗口右边被系统钳在 255 | 2026-11-09 | 侧拉收起现在优先交给系统收起（侧条卡片）；只有 App 自己不让最小化的窗口走老路，这种窗口在这一侧收不干净。真遇到再定：要么换边，要么按住不动只记日志 | 2026-11-09 | `--slide-over`（标准窗口）、`--restore-guard`（不可最小化窗口） |

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
