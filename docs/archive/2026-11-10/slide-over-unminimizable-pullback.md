# 台前调度下不能最小化的窗口收起被拉回（已修，归档）

> 归档 2026-11-10：修复随 1.0.21（build 20261110.01，tag v1.0.21.1）发布，不再跟踪。仅作历史记录。

原登记（`docs/known-failures.md`，首次记录 2026-11-09）：

- 失败项：台前调度下不能最小化的窗口收起仍会被拉回。
- 环境 / 构建：本机 M5（macOS 27），台前调度开，`--restore-guard` 用的那种不给最小化的临时窗。
- 复现：`slide.hide` 走系统收起失败（补写一次仍收不起）→ 退回推到屏外的老路，窗口右边被系统钳在 255。
- 当时状态：侧拉收起现在优先交给系统收起（侧条卡片）；只有 App 自己不让最小化的窗口走老路，这种窗口在这一侧收不干净。真遇到再定：要么换边，要么按住不动只记日志。
- 修复：换边（`flipToFreeEdge`，`prototype/App/SlideOver.swift`）已实现并合入；探针 `--slide-over-unminimizable` 在 1.0.21 发布前的真机门禁 PASS（见 `docs/handoff/HANDOFF-1.0.21.1.md`（私有库） 第 2 节与 `docs/releases/v1.0.21.1-release-gate-runbook.md` 记账）。
- 关联探针：`--slide-over`（标准窗口）、`--slide-over-unminimizable`（不可最小化窗口）。
