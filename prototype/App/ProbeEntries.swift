import Cocoa

/// 别的改动包各自在新文件里写的真机探针，入口统一是 `func exercise<名字>(pid: pid_t) async throws`
/// （写成 GlanceProbe 的扩展，不能是 private / fileprivate）。GlanceProbe.swift 按命令行参数直接调用：
/// --strip-peek → exerciseStripPeek，--browser-more → exerciseBrowserMore，--dock-gestures → exerciseDockGestures。
/// 调用前已经 adoptFixture(pid:)，keepFixtureInFront、ensureFixtureAt 这几道保护可以直接用。
///
/// 下面的协议把三个入口的签名钉死（参数标签、async throws）：对不上，GlanceProbe 的一致性声明编译不过。
@MainActor protocol PendingProbeEntries {
  func exerciseStripPeek(pid: pid_t) async throws
  func exerciseBrowserMore(pid: pid_t) async throws
  func exerciseDockGestures(pid: pid_t) async throws
}

extension GlanceProbe: PendingProbeEntries {}
