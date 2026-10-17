import Cocoa
import QuartzCore

/// 规格 E3（2026-10-17 改做法）：卡顿表的显示链接一端。只在探针量一次交互的期间存在：
/// `start` 建链、等它先走两帧，`stop` 立刻 invalidate；平时没有任何对象、不起显示链接，产品路径零开销。
/// 时间戳是显示链接每一帧给的 `timestamp`（垂直同步时刻），回调在主线程 run loop 上——
/// 所以量到的是「主线程在交互期间有没有按时让出每一帧」：主线程被堵，回调就漏帧，帧间隔变长。
/// 纯 GPU／窗口服务器那一侧的掉帧不在这里（那要 Instruments），这里只管我们自己代码造成的卡。
@MainActor
final class HitchRecorder: NSObject {
  private let screen: NSScreen
  private var link: CADisplayLink?
  private var timestamps: [Double] = []
  /// 显示器的实际最高刷新率：ProMotion 120、普通外接屏与虚拟机多为 60。
  let refreshHz: Double

  init(screen: NSScreen) {
    self.screen = screen
    refreshHz = Double(max(1, screen.maximumFramesPerSecond))
  }

  /// 起链并等它先给出两帧（最多 0.5 秒），之后再触发交互：触发调用本身同步卡住主线程的那段才会落进帧间隔里。
  func start() async {
    stopLink()
    timestamps.removeAll(keepingCapacity: true)
    let created = screen.displayLink(target: self, selector: #selector(tick(_:)))
    // ProMotion 屏没人要高帧率时会降频；按满帧率要，预期间隔才和 refreshHz 对得上。
    let hz = Float(refreshHz)
    created.preferredFrameRateRange = CAFrameRateRange(minimum: hz, maximum: hz, preferred: hz)
    created.add(to: .main, forMode: .common)
    link = created
    let deadline = CACurrentMediaTime() + 0.5
    while timestamps.count < 2, CACurrentMediaTime() < deadline {
      try? await Task.sleep(for: .milliseconds(4), clock: .suspending)
    }
  }

  /// 停链，交回这次交互的时间戳。
  func stop() -> [Double] {
    stopLink()
    let out = timestamps
    timestamps.removeAll()
    return out
  }

  private func stopLink() {
    link?.invalidate()
    link = nil
  }

  @objc private func tick(_ sender: CADisplayLink) {
    timestamps.append(sender.timestamp)
  }

  /// 是否在虚拟机里（kern.hv_vmm_present = 1）。
  nonisolated static var isVirtualMachine: Bool {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    return sysctlbyname("kern.hv_vmm_present", &value, &size, nil, 0) == 0 && value == 1
  }
}

extension GlanceProbe {
  /// `--hitch`：在临时窗口上各做 N 次（`--hitch-rounds N`，默认 20）收起／展开、窗口浏览开／关、看一眼出现／收回，
  /// 每次交互单独量帧间隔，按类合并后打印 `HITCH <kind> …` 并按预算判 PASS／FAIL（见 Core/HitchMeter.swift）。
  /// 只动临时窗口和 WindowShade 自己的面板；窗口浏览或看一眼在设置里关着时那一类 SKIP，不改设置。
  func hitch(element: AXUIElement) async throws {
    let previousVolume = shadeSounds.volume
    shadeSounds.volume = 0
    defer { shadeSounds.volume = previousVolume }
    let args = CommandLine.arguments
    let rounds = args.firstIndex(of: "--hitch-rounds")
      .flatMap { args.indices.contains($0 + 1) ? Int(args[$0 + 1]) : nil }
      .map { max(1, $0) } ?? 20

    let screen = fixtureScreen() ?? NSScreen.main
    guard let screen else { throw EffectError.unavailable("hitch: no screen") }
    let recorder = HitchRecorder(screen: screen)
    let vm = HitchRecorder.isVirtualMachine
    let budget: HitchMeter.Budget = vm ? .virtualMachine : .hardware
    let animatedInVM = args.contains("--animated")
    print(String(format: "INFO hitch: %d rounds per kind, refresh %.0f Hz (%@), %@, budget %@",
      rounds, recorder.refreshHz, screen.localizedName, vm ? "virtual machine" : "hardware",
      vm ? "VM: ratio INFO only, worst < 500 ms" : "ratio < 5 ms/s and worst < 100 ms"))
    fflush(stdout)

    func measure(_ body: () async throws -> Void) async throws -> [Double] {
      await recorder.start()
      do { try await body() } catch { _ = recorder.stop(); throw error }
      return recorder.stop()
    }
    /// 状态先翻、动画后到：判定条件成立后再量一小段尾巴，盖住剩下的动画。
    func tail(_ ms: Int) async throws { try await Task.sleep(for: .milliseconds(ms), clock: .suspending) }

    var results: [(kind: String, runs: [[Double]])] = []

    // 收起／展开。每轮之间要等够：展开之后产品还会在 80／250／550／1100 ms 各补一次几何与前台，
    // 下一次收起若在那之前开始，会和这些补丁抢主线程（也会把它们量进下一次收起里）。
    // 一轮超时不整组中止：打印当时的状态、设法展开复原，记一次失败接着下一轮；连续 2 轮失败才放弃这一类。
    var folds: [[Double]] = [], unfolds: [[Double]] = []
    var foldFailures: [String] = []
    var consecutive = 0
    var hides: [String: Int] = [:]
    let foldLimit = 10.0, unfoldLimit = 10.0
    for round in 1...rounds {
      await ShareableContentCache.shared.prefetch()
      do {
        let started = CACurrentMediaTime()
        let fold = try await measure {
          owner.shade(element, id)
          try await wait("hitch fold \(round)", timeout: foldLimit) {
            self.owner.shaded[self.id]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
              && self.owner.duoController.windowEffects.activeCount == 0
          }
          try await tail(150)
        }
        if let hide = owner.shaded[id]?.hide { hides["\(hide)", default: 0] += 1 }
        try await Task.sleep(for: .milliseconds(500), clock: .suspending)
        let unfold = try await measure {
          _ = owner.unshade(id)
          try await wait("hitch unfold \(round)", timeout: unfoldLimit) {
            self.onscreen(self.id) && self.owner.shaded[self.id] == nil
              && self.owner.duoController.windowEffects.activeCount == 0
          }
          try await tail(150)
        }
        folds.append(fold)
        unfolds.append(unfold)
        consecutive = 0
        if CACurrentMediaTime() - started > 6 {
          print(String(format: "INFO hitch fold round %d: slow round %.1f s", round, CACurrentMediaTime() - started))
        }
      } catch {
        consecutive += 1
        let message = "round \(round): \(error.localizedDescription) [\(hitchFoldState())]"
        foldFailures.append(message)
        print("INFO hitch fold \(message)")
        fflush(stdout)
        try await hitchRecover(element: element, round: round)
        if consecutive >= 2 {
          print("INFO hitch fold: \(consecutive) rounds in a row failed; stopping fold/unfold early")
          break
        }
      }
      try await Task.sleep(for: .milliseconds(1500), clock: .suspending)
    }
    print("INFO hitch fold: hide methods \(hides.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))"
      + "\(vm && !animatedInVM ? "; VM: fold cover animation off (the paravirtual GPU never presents it; pass --animated to force)" : "")")
    if !foldFailures.isEmpty {
      print("FAIL hitch fold: \(foldFailures.count) of \(folds.count + foldFailures.count) rounds did not finish; first: \(foldFailures[0])")
    }
    results += [("fold", folds), ("unfold", unfolds)]

    // 窗口浏览开／关（同 soak-browser：只开关面板，不对任何窗口发动作）。
    if WindowBrowserSettings.keyboardPanelEnabled {
      AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 2.0)
      let browser = WindowBrowserController(owner: owner)
      browser.start()
      defer {
        browser.probeClosePanel()
        browser.stop()
      }
      var opens: [[Double]] = [], closes: [[Double]] = []
      for round in 1...rounds {
        var refused = false
        opens.append(try await measure {
          guard browser.openKeyboardPanel() else { refused = true; return }
          try await wait("hitch browser open \(round)", timeout: 5) { browser.probePanelVisible }
          // 列表填进来也算在「打开」里（最多 1.5 秒，没有不算失败）。
          let listed = CACurrentMediaTime()
          while browser.probeListedKeys.isEmpty, CACurrentMediaTime() - listed < 1.5 {
            try await Task.sleep(for: .milliseconds(8), clock: .suspending)
          }
          try await tail(350)
        })
        if refused {
          print("FAIL hitch browser: the panel refused to open at round \(round)")
          break
        }
        closes.append(try await measure {
          browser.probeClosePanel()
          try await wait("hitch browser close \(round)", timeout: 5) { !browser.probePanelVisible }
          try await tail(350)
        })
        try await Task.sleep(for: .milliseconds(200), clock: .suspending)
      }
      results += [("browser-open", opens), ("browser-close", closes)]
    } else {
      print("SKIP hitch browser: Window browser is off in Settings; the probe does not change settings")
    }

    // 看一眼出现／收回（同 soak-glance：先收起临时窗口，再让模拟指针进出卷帘条）。
    if GlanceController.isEnabled {
      let glance = owner.glance
      owner.shade(element, id)
      try await wait("hitch strip shown", timeout: 10) {
        self.owner.shaded[self.id]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
          && self.owner.duoController.windowEffects.activeCount == 0
      }
      // 收起后 0.7 秒内不响应悬停。
      try await Task.sleep(for: .milliseconds(800), clock: .suspending)
      guard let strip = owner.shaded[id]?.overlay?.frame else { throw EffectError.unavailable("hitch: no strip") }
      let onStrip = NSPoint(x: strip.minX + strip.width * 0.6, y: strip.midY)
      let away = NSPoint(x: -9000, y: -9000)
      var shows: [[Double]] = [], hides: [[Double]] = []
      for round in 1...rounds {
        shows.append(try await measure {
          pointer = onStrip
          glance.pointerEntered(id)
          try await wait("hitch glance shown \(round)", timeout: 6) { glance.isShowing }
          try await tail(350)
        })
        hides.append(try await measure {
          pointer = away
          try await wait("hitch glance closed \(round)", timeout: 4) { !glance.hasSession(self.id) }
          try await tail(350)
        })
        try await Task.sleep(for: .milliseconds(300), clock: .suspending)
      }
      _ = owner.unshade(id)
      try await wait("hitch restored", timeout: 8) { self.onscreen(self.id) && self.owner.shaded[self.id] == nil }
      results += [("glance-show", shows), ("glance-hide", hides)]
    } else {
      print("SKIP hitch glance: Glance is off in Settings; the probe does not change settings")
    }

    for (kind, runs) in results where !runs.isEmpty {
      let stats = HitchMeter.merge(runs, refreshHz: recorder.refreshHz)
      print(HitchMeter.line(kind: kind, stats))
      // 最卡的一次是第几轮：第 1 轮常带冷启动（第一次截图、第一次建面板）。
      let perRun = runs.map { HitchMeter.stats(timestamps: $0, refreshHz: recorder.refreshHz).worstFrameMs }
      if let worstRound = perRun.indices.max(by: { perRun[$0] < perRun[$1] }) {
        print(String(format: "INFO hitch %@: worst frame in round %d (%.1f ms)", kind, worstRound + 1, perRun[worstRound]))
      }
      let problems = budget.violations(stats)
      if problems.isEmpty {
        print("PASS hitch \(kind): \(vm ? "within the VM budget" : "within budget")")
      } else {
        print("FAIL hitch \(kind): \(problems.joined(separator: ", "))\(vm ? " (VM budget)" : "")")
      }
      if vm {
        let hardware = HitchMeter.Budget.hardware.violations(stats)
        print("INFO hitch \(kind): on hardware this would be \(hardware.isEmpty ? "PASS" : "FAIL (\(hardware.joined(separator: ", ")))")")
      }
      fflush(stdout)
    }
  }

  /// 超时那一刻的收起状态，一行：生命周期、隐藏方式、卷帘条、真窗口在不在屏、前台是谁、效果是否还在跑。
  func hitchFoldState() -> String {
    let front = NSWorkspace.shared.frontmostApplication
    guard let state = owner.shaded[id] else {
      return "not shaded, onscreen=\(onscreen(id)) frontmost=\(front?.localizedName ?? "-")(\(front?.processIdentifier ?? 0)) effects=\(owner.duoController.windowEffects.activeCount)"
    }
    let overlay = state.overlay.map { "visible=\($0.isVisible) alpha=\(String(format: "%.2f", $0.alphaValue))" } ?? "none"
    return "stage=\(state.lifecycleStage) hide=\(state.hide) overlay(\(overlay)) onscreen=\(onscreen(id)) "
      + "frontmost=\(front?.localizedName ?? "-")(\(front?.processIdentifier ?? 0))\(front?.processIdentifier == state.pid ? "=fixture" : "") "
      + "effects=\(owner.duoController.windowEffects.activeCount)"
  }

  /// 一轮没走完：还收着就展开，等真窗口回到屏上（有界）；复原不了才整组中止。
  func hitchRecover(element: AXUIElement, round: Int) async throws {
    if owner.shaded[id] != nil { _ = owner.unshade(id) }
    do {
      try await wait("hitch recover \(round)", timeout: 10) {
        self.onscreen(self.id) && self.owner.shaded[self.id] == nil
          && self.owner.duoController.windowEffects.activeCount == 0
      }
      print("INFO hitch fold round \(round): recovered (\(hitchFoldState()))")
    } catch {
      throw EffectError.unavailable("hitch: could not restore the fixture window after round \(round) [\(hitchFoldState())]")
    }
  }

  /// 临时窗口所在的屏幕（CG 坐标原点在主屏左上，换成 AppKit 的左下原点再找）。
  private func fixtureScreen() -> NSScreen? {
    guard let frame = bounds(id), let primary = NSScreen.screens.first else { return nil }
    let point = NSPoint(x: frame.midX, y: primary.frame.maxY - frame.midY)
    return NSScreen.screens.first { $0.frame.contains(point) }
  }
}
