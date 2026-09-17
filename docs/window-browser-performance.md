# 窗口浏览性能：本轮实测、设计预算与未达项

本文只记录实际执行的测量。区分“本次实测”“设计预算”“仍未验证”，不把设计目标
写成已达到的宣传数据。

## 环境

| 项目 | 值 |
| --- | --- |
| 机型 | MacBook Air（Mac17,4，Apple M5，10 核，24 GB 内存） |
| 系统 | macOS 27.0（Build 26A428） |
| 工具链 | Xcode 26.6（17F113） |
| SDK | macOS SDK 26.5（含公开 AppKit 玻璃 API） |
| 构建 | `swiftc -O -target arm64-apple-macosx14.0`，同一进程内渲染离屏组件 |
| 数据 | 确定性内置记录；不打开、不操作任何真实窗口 |

测量口径：同一进程内对同一操作重复取样，先预热（≥10% 次），再报告 p50/p95。
这是**扣除输入与人为意图延迟后的处理时间**，不是端到端悬停延迟。

## 本次实测：改版前后对照

原始输出：[`.build/window-browser-perf/2026-09-18-before-after.txt`](../.build/window-browser-perf/2026-09-18-before-after.txt)
（基线为新 Worktree 中的 `05e5472`，同一台机器、同一天、同一脚本、同一组数据。）

### 冷启动：新建内容视图 + 第一次数据填充与布局

| 窗口数 | 基线 p50 / p95 | 本轮 p50 / p95 | 变化 |
| --- | --- | --- | --- |
| 1 | 3.4 / 4.3 ms | 6.4 / 7.4 ms | +88%（复用容器与玻璃/材质层的建立成本） |
| 3 | 6.1 / 6.3 ms | 10.2 / 11.1 ms | +67% |
| 8 | 12.5 / 13.0 ms | 15.9 / 16.7 ms | +27% |
| 120 | 200.4 / 248.6 ms | 17.8 / 19.7 ms | **−91%**（不再为每条记录立即创建整棵视图树） |

### 暖刷新：同一批数据再次 update + layout

| 窗口数 | 基线 p50 / p95 | 本轮 p50 / p95 | 说明 |
| --- | --- | --- | --- |
| 1 | 0.007 / 0.009 ms | 0.84 / 0.88 ms | 基线在内容签名未变时几乎不做工作；本轮仍重算布局计划 |
| 3 | 0.012 / 0.014 ms | 1.57 / 1.67 ms | 同上，本轮的刷新路径包含动作/状态重算与集合视图布局 |
| 8 | 0.020 / 0.022 ms | 0.62 / 0.64 ms | 列表模式 |
| 120 | 0.231 / 0.250 ms | 0.86 / 0.93 ms | 列表模式，视图复用以外的成本稳定 |

结论：本轮的刷新路径成本比基线高，但**全部落在 4 ms p95 的主线程预算内**；换来的是
120 条记录冷启动从 200 ms 降到 18 ms，以及“滚动/开关不随访问次数线性增长”。

### 面板几何计算

| 场景 | p50 / p95 | 说明 |
| --- | --- | --- |
| 1/3/8/20/120 个窗口 | < 0.001 / 0.001 ms | 纯值计算，2000 次取样 |

### 实机只读探针（1.0.13 已安装构建）

| 样本 | 实测 |
| --- | --- |
| 全部运行应用的窗口发现（15 个应用、17 个窗口、0 失败） | 371 ms，最慢应用 42 ms |
| 主线程最大停顿（同一轮） | 6 ms |
| 按完整身份解析 identity / geometry / capabilities | 各 0 ms |

命令：`prototype/WindowShade.app/Contents/MacOS/WindowShade --window-browser-catalog-probe`
（只读，不操作用户窗口）。

### 首屏文本与缓存路径

自动化回归内的同机测量（`tests/run-window-browser-tests.sh` 每次运行都会重新打印）：

| 样本 | 实测 |
| --- | --- |
| 50 个已管理窗口：目录发布 + 稳定排序 + 面板几何 | 0.9–4.2 ms |
| 200 个已管理窗口：同一路径 | 3.0–16.5 ms |

## 设计预算与达成情况

| 项目 | 预算 | 本轮结果 |
| --- | --- | --- |
| 主线程局部 UI 更新 | p95 < 4 ms | 达成（实测 p95 0.64–1.67 ms） |
| 首屏文本/缓存可见 | p95 < 50 ms（含硬件与样本说明） | 达成（纯数据路径 200 窗口 p95 ≈ 16.5 ms，不含截图与意图延迟） |
| 静态缩略图缓存 | 24 MiB 起 | 保留 24 MiB；新增 `cachedCostBytes`、视图侧 `cachedThumbnailBytes` 诊断 |
| 物理截图并发 | 同时最多 2 路 | 达成，且有 T01–T09 断言覆盖 |
| 普通实时预览 | 最多新增 1 路 | 达成（借用固定预览不新建流） |
| 功能关闭 | 不新增截图/实时流/周期 AX 枚举/持续绘制 | 达成（`--window-browser-idle-probe` 与 `stop()` 路径保留） |
| 连续开关与滚动 | 对象数量与 footprint 趋于稳定 | 达成（100 轮开关回归 + 200 条滚动后视图图像有界） |

## 仍未验证

- **端到端悬停延迟**：需要真实 Dock 悬停、辅助功能授权与真实截图，本机未在带授权
  的新构建上运行，因此没有 p95 端到端数字。
- **单元视图的实际创建数量**：离屏回归里 AppKit 不会为不可见条目创建复用单元，
  因此自动化只能断言“视图侧图像字节有界”；“只创建可见单元”的证据来自冷启动
  对照（120 条 18 ms vs 200 ms）与实机滚动步骤，缺少逐单元计数的实机采样。
- **WindowServer / 能耗**：本轮没有做 WindowServer CPU、能耗与 60/120 Hz 掉帧的
  实机采样。
- **真实进程 footprint**：只测了视图侧图像引用字节与服务缓存字节，没有用
  `phys_footprint` 采样长时间会话。
- **多显示器与混合缩放**：只有纯几何测试覆盖，缺少第二块显示器的实机样本。

## 运行时会话的计数（§17.1）

关闭面板或退出功能时，`/tmp/windowshade.log`（5 MB 自动轮转）会写一条
`perf-summary:` 记录，包含：物理截图启动/投递数、queued 取消数与占比、过期结果数
与占比、重复完成、停滞降级批次、仍在运行与排队的截图数、缓存条目与字节数、
逻辑 AX 发现请求数与真实 AX 调用数、Dock 检测次数、被丢弃的过期检测结果数、
当前检测排队长度。阶段耗时另有 `perf: input-arrival / intent-delay-end /
first-panel-show / first-catalog-publish / first-new-screenshot / live-first-frame /
action-submit-* / action-verified-* / panel-resources-released`。

单帧更新耗时不在运行时逐帧记录（避免日志本身影响帧率），由本文的离屏
`content.update+layout` 测量代表。

## 复现方式

```sh
# 纯逻辑回归（每次都会打印 50/200 窗口的首屏耗时）
bash tests/run-window-browser-tests.sh

# 前后对照（需要先取出基线 worktree）
git worktree add /tmp/ws-baseline 05e5472370e199e92b147f1e0af72175c6429288
/tmp/run-perf.sh    # 脚本内容见 .build/window-browser-perf/ 同目录说明

# 真实组件截图（隔离构建，不停止正在运行的应用）
cd prototype && ./build.sh --stage
cd .. && .build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade \
  --window-browser-shots .build/window-browser-shots
```
