import Cocoa

/// 别的改动包各自在新文件里写的真机探针，入口统一是 `func exercise<名字>(pid: pid_t) async throws`
/// （写成 GlanceProbe 的扩展，不能是 private / fileprivate）。GlanceProbe.swift 按命令行参数直接调用：
/// --strip-peek → exerciseStripPeek，--browser-more → exerciseBrowserMore，--dock-gestures → exerciseDockGestures。
/// 调用前已经 adoptFixture(pid:)，keepFixtureInFront、ensureFixtureAt 这几道保护可以直接用。
///
/// 某个还没写的时候，下面的默认实现顶上：整个 App 照样编译得过，跑到那个参数就报“还没写”（算失败，不算通过）。
/// 写好以后，GlanceProbe 自己的同名方法优先，默认实现不再起作用：不用回来改这里，也不用改调度那几行。
/// 签名要一字不差（参数标签、async throws）；对不上时默认实现照样顶着，跑的时候就会看到“还没写”。
@MainActor protocol PendingProbeEntries {
  func exerciseStripPeek(pid: pid_t) async throws
  func exerciseBrowserMore(pid: pid_t) async throws
  func exerciseDockGestures(pid: pid_t) async throws
}

extension PendingProbeEntries {
  func exerciseStripPeek(pid: pid_t) async throws {
    throw EffectError.unavailable("--strip-peek: exerciseStripPeek(pid:) has not been written yet")
  }

  func exerciseBrowserMore(pid: pid_t) async throws {
    throw EffectError.unavailable("--browser-more: exerciseBrowserMore(pid:) has not been written yet")
  }

  func exerciseDockGestures(pid: pid_t) async throws {
    throw EffectError.unavailable("--dock-gestures: exerciseDockGestures(pid:) has not been written yet")
  }
}

extension GlanceProbe: PendingProbeEntries {}
