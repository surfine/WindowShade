import Cocoa

// 强制结束 WindowShade 之后，下次启动把窗口还回来（--kill-recovery，要手动跑）：
// v1.0.16 清单里“画中画、刘海没覆盖；没做过真的强制结束”。入口 exerciseKillRecovery(pid:)。
//
// 另起一份 WindowShade 当“这一次”：它把自己的临时 App 窗口放进侧拉（收在屏幕边外）、画中画、刘海，
// 说一声“好了”，就被 kill -9；再起一份不带探针参数的 WindowShade 当“下次启动”（真的走一遍启动），
// 看临时 App 的窗口回没回到原处、恢复记录清没清掉，然后正常退出它。三种状态各来一遍。
// 两份都只从 --stage-app 给的路径起，而且那必须就是探针自己这一份 stage 构建；绝不碰“应用程序”里的日常版。
//
// 前提（不满足就一份都不起，直接说为什么）：
// - 日常用的 WindowShade 已经退出：两份共用恢复记录，下次启动会把日常版收着的窗口也还回来；
// - 恢复记录里没有别的正在运行的 App 的窗口，屏幕外 WindowShade 的停车点上也没停着别的 App 的窗口
//   （下次启动会一起还回来，那就动了不是临时 App 的窗口）。
// 用法：tests/run-glance-probe.sh --kill-recovery --stage-app "$PWD/.build/duo-validation/WindowShade.app"

/// 读另一份 WindowShade 的输出（后台线程写，主线程读）。
final class GapOutputCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var text = ""
  func append(_ data: Data) {
    lock.lock()
    text += String(decoding: data, as: UTF8.self)
    lock.unlock()
  }
  var all: String {
    lock.lock()
    defer { lock.unlock() }
    return text
  }
  func line(startingWith prefix: String) -> String? {
    all.split(separator: "\n").first { $0.hasPrefix(prefix) }.map(String.init)
  }
}

extension GlanceProbe {
  func exerciseKillRecovery(pid: pid_t) async throws {
    NotchController.probeSilence = true
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: "--victim"), index + 1 < arguments.count {
      try await gapRecoveryVictim(kind: arguments[index + 1], pid: pid)
      return
    }
    // 1. 只认 stage 构建：--stage-app 必须就是探针自己这一份，不在“应用程序”里，在 .build 下面。
    guard let stageIndex = arguments.firstIndex(of: "--stage-app"), stageIndex + 1 < arguments.count,
          let fixtureIndex = arguments.firstIndex(of: "--fixture"), fixtureIndex + 1 < arguments.count else {
      print("FAIL kill-recovery: pass --stage-app <.build/duo-validation/WindowShade.app>; nothing was started")
      return
    }
    let given = URL(fileURLWithPath: arguments[stageIndex + 1]).standardizedFileURL.resolvingSymlinksInPath()
    let mine = Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
    guard given.path == mine.path, !mine.pathComponents.contains("Applications"), mine.pathComponents.contains(".build"),
          let executable = Bundle.main.executableURL else {
      print("FAIL kill-recovery: --stage-app \(given.path) is not the stage build this probe runs from (\(mine.path)); nothing was started")
      return
    }
    // 2. 日常版得先退出。
    let others = gapOtherWindowShadeCopies()
    guard others.isEmpty else {
      print("FAIL kill-recovery: quit the everyday WindowShade first (running: \(others.map { "pid \($0.pid) \($0.path)" }.joined(separator: "; "))); both copies share the recovery records, so the next launch would move windows it holds. Nothing was started")
      return
    }
    // 3. 下次启动只能还临时 App 的窗口。
    if let blocker = gapRecoveryBlocker() {
      print("FAIL kill-recovery: \(blocker); the next launch would move windows that are not the fixture's. Nothing was started")
      return
    }
    let fixturePath = arguments[fixtureIndex + 1]
    for kind in ["slide-over", "pip", "notch"] {
      try await gapKillAndRelaunch(kind: kind, executable: executable, fixturePath: fixturePath)
      try await Task.sleep(nanoseconds: 1_000_000_000)
    }
  }

  /// 恢复记录或屏幕外停车点上有别的 App 的窗口：返回说明；没有返回 nil。
  private func gapRecoveryBlocker() -> String? {
    func alive(_ pid: Int) -> Bool { pid > 0 && pid <= Int(Int32.max) && kill(pid_t(pid), 0) == 0 }
    if let entries = try? DurableShadeJournal.application.load() {
      let live = entries.compactMap { ($0["pid"] as? NSNumber)?.intValue }.filter(alive)
      if !live.isEmpty { return "the fold recovery record still holds windows of running apps (pids \(live))" }
    }
    let directory = DurableShadeJournal.application.url.deletingLastPathComponent()
    let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    for url in urls where url.lastPathComponent.hasPrefix("SlideOver-") && url.pathExtension == "plist" {
      let entries = (try? DurableShadeJournal(url: url).load()) ?? []
      let live = entries.compactMap { ($0["pid"] as? NSNumber)?.intValue }.filter(alive)
      if !live.isEmpty { return "\(url.lastPathComponent) still holds windows of running apps (pids \(live))" }
    }
    let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let parked = list.filter { info in
      (info[kCGWindowLayer as String] as? Int) == 0 && cgWindowBounds(info).map { owner.isAtWindowShadeParkingSpot($0.origin) } == true
    }.map { ($0[kCGWindowOwnerName as String] as? String) ?? "?" }
    if !parked.isEmpty { return "windows of \(Set(parked).sorted()) are parked off screen where WindowShade parks folded windows" }
    return nil
  }

  /// 一种状态：起“这一次”、等它说好了、kill -9、看窗口留在外面；起“下次启动”、等窗口回来、记录清掉；正常退出它。
  private func gapKillAndRelaunch(kind: String, executable: URL, fixturePath: String) async throws {
    let victim = Process()
    victim.executableURL = executable
    victim.arguments = ["--glance-probe", "--fixture", fixturePath, "--kill-recovery", "--victim", kind]
    let pipe = Pipe()
    let output = GapOutputCollector()
    victim.standardOutput = pipe
    victim.standardError = pipe
    pipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if data.isEmpty { handle.readabilityHandler = nil } else { output.append(data) }
    }
    try victim.run()
    var fixturePID: pid_t = 0
    var nextLaunch: Process?
    defer {
      if victim.isRunning { kill(victim.processIdentifier, SIGKILL) }
      pipe.fileHandleForReading.readabilityHandler = nil
      if let next = nextLaunch, next.isRunning { kill(next.processIdentifier, SIGKILL) }
      if fixturePID > 0 { kill(fixturePID, SIGTERM) }
    }
    let ready = (try? await wait("\(kind): the first copy puts the window away", timeout: 40) {
      output.line(startingWith: "VICTIM READY") != nil || !victim.isRunning
    }) != nil
    guard ready, let line = output.line(startingWith: "VICTIM READY") else {
      print("FAIL kill-recovery \(kind): the first copy never said it was ready; its output:\n\(output.all.split(separator: "\n").suffix(8).joined(separator: "\n"))")
      return
    }
    // VICTIM READY fixture=<pid> id=<window> expect=x,y,w,h
    var fields: [String: String] = [:]
    for part in line.split(separator: " ") {
      let pair = part.split(separator: "=", maxSplits: 1)
      if pair.count == 2 { fields[String(pair[0])] = String(pair[1]) }
    }
    let numbers = (fields["expect"] ?? "").split(separator: ",").compactMap { Double($0) }
    guard let fixture = fields["fixture"].flatMap({ Int32($0) }), let window = fields["id"].flatMap({ UInt32($0) }),
          numbers.count == 4 else {
      print("FAIL kill-recovery \(kind): could not read the ready line: \(line)")
      return
    }
    fixturePID = fixture
    let windowID = CGWindowID(window)
    let expect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])

    // kill -9：来不及收尾。窗口应该还留在外面（收在屏幕边外、让开、藏起来），不然就没什么可测的。
    kill(victim.processIdentifier, SIGKILL)
    try await wait("\(kind): first copy gone", timeout: 3) { !victim.isRunning }
    try await Task.sleep(nanoseconds: 500_000_000)
    func isBack() -> Bool {
      guard windowIsOnScreenNow(windowID), let frame = bounds(windowID) else { return false }
      return gapVisibleWidth(frame) > 64 && gapAlpha(windowID) > 0.5
        && abs(frame.minX - expect.minX) < 12 && abs(frame.minY - expect.minY) < 12
    }
    let leftOut = !isBack()
    let records = gapRecoveryRecords(mentioning: windowID)
    print("INFO kill-recovery \(kind): after kill -9 the window is \(leftOut ? "still put away" : "already back") (\(bounds(windowID).map { "\($0)" } ?? "-") onscreen=\(windowIsOnScreenNow(windowID)) alpha=\(gapAlpha(windowID))); records: \(records.isEmpty ? "none" : records.joined(separator: ", "))")

    // 下次启动：真的走一遍启动（刘海不播报、不教）。
    let next = Process()
    next.executableURL = executable
    next.arguments = ["--no-teach"]
    next.standardOutput = FileHandle.nullDevice
    next.standardError = FileHandle.nullDevice
    try next.run()
    nextLaunch = next
    let launched = CACurrentMediaTime()
    let back = (try? await wait("\(kind): window back after the next launch", timeout: 20) { isBack() }) != nil
    let tookMs = Int((CACurrentMediaTime() - launched) * 1000)
    let cleared = (try? await wait("\(kind): recovery record cleared", timeout: 5) {
      self.gapRecoveryRecords(mentioning: windowID).isEmpty
    }) != nil
    print("\(leftOut && back && cleared ? "PASS" : "FAIL") kill-recovery \(kind): WindowShade force-quit with the window \(kind == "slide-over" ? "tucked past the screen edge" : kind == "pip" ? "in picture in picture" : "tucked into the notch"); the next launch puts it back at \(expect) (\(back ? "in \(tookMs) ms" : "not within 20 s"); now \(bounds(windowID).map { "\($0)" } ?? "-")) and clears its recovery record (\(cleared ? "cleared" : "left: \(gapRecoveryRecords(mentioning: windowID))"))")

    // 正常退出“下次启动”那一份（退出时它会把 Dock 的设置还原、收好一切）；退不掉才强制。
    _ = NSRunningApplication(processIdentifier: next.processIdentifier)?.terminate()
    let quit = (try? await wait("\(kind): next launch quits", timeout: 8) { !next.isRunning }) != nil
    if !quit {
      next.terminate()
      _ = try? await wait("\(kind): next launch stops", timeout: 3) { !next.isRunning }
      print("INFO kill-recovery \(kind): the next launch did not quit when asked; it was stopped (Dock settings are put back on the everyday copy's next start)")
    }
  }

  /// “这一次”那一份：把自己的临时 App 窗口放好，说一声，然后等着被 kill -9。
  /// 90 秒还没人来，就自己收尾退出（放回窗口、关掉临时 App），不把东西留在外面。
  private func gapRecoveryVictim(kind: String, pid: pid_t) async throws {
    guard let element = appWindows(pid: pid).first(where: { windowID(of: $0) == id }), let original = bounds(id) else {
      throw EffectError.unavailable("kill-recovery victim: no fixture window")
    }
    let expect: CGRect
    switch kind {
    case "slide-over":
      let slide = owner.slideOver
      slide.enter(element, id: id, pid: pid)
      guard let docked = slide.dockedFrame else { throw EffectError.unavailable("kill-recovery victim: slide over did not start") }
      try await wait("docked", timeout: 4) { self.bounds(self.id).map { self.closeTo($0, docked) } == true }
      slide.hide(velocity: .zero, reason: "kill-recovery")
      try await wait("tucked past the edge", timeout: 4) {
        slide.isHidden && self.bounds(self.id).map { self.gapVisibleWidth($0) <= 64 } == true
      }
      expect = docked
    case "pip":
      let pip = owner.pip
      pip.enter(element, id: id, pid: pid)
      try await wait("in picture in picture", timeout: 5) { pip.framesForProbe(self.id) > 3 && pip.panelFrameForProbe(self.id) != nil }
      try await wait("stepped aside", timeout: 4) { self.bounds(self.id).map { self.gapVisibleWidth($0) <= 64 } == true }
      expect = original
    case "notch":
      // 和日常版一样写真正的恢复记录（探针平时写在自己的那一份里），下次启动读的就是它。
      owner.recoveryJournalOverride = nil
      let notch = owner.notch
      notch.install()
      notch.tuck(element, id: id, pid: pid, landed: original, home: original, velocity: .zero)
      // 藏好的样子看收起用的哪一种：停到屏幕外、整扇透明，或者从屏幕上拿掉。
      try await wait("tucked into the notch", timeout: 6) {
        let away = !windowIsOnScreenNow(self.id) || self.gapAlpha(self.id) < 0.05
          || self.bounds(self.id).map { self.gapVisibleWidth($0) <= 64 } == true
        return notch.isTucked(self.id) && away
          && self.gapRecoveryRecords(mentioning: self.id).contains("RecoveryJournal.plist")
      }
      expect = original
    default:
      throw EffectError.unavailable("kill-recovery victim: unknown state \(kind)")
    }
    try await Task.sleep(nanoseconds: 300_000_000)
    print("VICTIM READY fixture=\(pid) id=\(id) expect=\(Int(expect.minX)),\(Int(expect.minY)),\(Int(expect.width)),\(Int(expect.height))")
    fflush(stdout)
    try await Task.sleep(nanoseconds: 90_000_000_000)
    throw EffectError.unavailable("kill-recovery victim: nobody stopped this copy within 90 s; putting things back")
  }
}
