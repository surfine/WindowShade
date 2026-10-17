import Cocoa
import Darwin

/// 规格 R39 的资源账：本进程的内存足迹、打开的文件描述符、窗口数、线程数，以及对「后半程是否还在涨」的判定。
/// 只读本进程自己的计数（task_info、proc_pidinfo、task_threads），不碰别的进程。
struct SoakSample {
  let round: Int
  let footprintMB: Double
  let descriptors: Int
  let windows: Int
  let threads: Int

  @MainActor static func take(round: Int) -> SoakSample {
    SoakSample(round: round, footprintMB: footprint(), descriptors: openDescriptors(),
               windows: NSApp.windows.count, threads: threadCount())
  }

  static func footprint() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
  }

  static func openDescriptors() -> Int {
    let bytes = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, nil, 0)
    return bytes > 0 ? Int(bytes) / MemoryLayout<proc_fdinfo>.size : -1
  }

  static func threadCount() -> Int {
    var list: thread_act_array_t?
    var count = mach_msg_type_number_t(0)
    guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let list else { return -1 }
    for index in 0..<Int(count) { mach_port_deallocate(mach_task_self_, list[index]) }
    vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)),
                  vm_size_t(Int(count) * MemoryLayout<thread_t>.size))
    return Int(count)
  }
}

/// 后半程的有界增长门槛。比较的是「中段」与「末尾」两次采样：热身期的一次性分配（缓存、首次才建的面板）不算增长，
/// 线性泄漏会让后半程继续涨。
enum SoakThreshold {
  /// 内存足迹：后半程涨幅上限。参照：一次收起的截图缓存约 1–3 MB；泄漏一张截图每轮就是这个量级，100 轮会远超 4 MB。
  static let footprintMB = 4.0
  /// 文件描述符：稳态应当一个不涨。留 5 个余量给系统偶发的缓存文件；每轮漏一个，100 轮后半程就是 +50。
  static let descriptors = 5
  /// 线程：libdispatch 线程池随负载浮动几条；每轮多一条的话 100 轮是 +50。
  static let threads = 4
}

extension GlanceProbe {
  /// 判定并打印。窗口数用「末尾不超过中段」：第一次用到才建的面板是一次性的，之后还在涨才算。
  func soakVerdict(label: String, rounds: Int, samples: [SoakSample], warmup: Int) throws {
    guard let first = samples.first, let last = samples.last, samples.count >= 3 else {
      throw EffectError.unavailable("\(label) needs at least \(warmup + 20) rounds")
    }
    let middle = samples[samples.count / 2]
    let lateGrowth = last.footprintMB - middle.footprintMB
    print(String(format: "INFO %@: %d rounds, footprint %.1f -> %.1f -> %.1f MB (warm, middle, end), windows %d -> %d, descriptors %d -> %d -> %d, threads %d -> %d -> %d",
      label, rounds, first.footprintMB, middle.footprintMB, last.footprintMB, first.windows, last.windows,
      first.descriptors, middle.descriptors, last.descriptors, first.threads, middle.threads, last.threads))
    let rising = zip(samples, samples.dropFirst()).allSatisfy { $1.footprintMB > $0.footprintMB }
    print("INFO \(label): footprint strictly rising across every sample: \(rising)")
    if lateGrowth > SoakThreshold.footprintMB {
      print(String(format: "FAIL %@: footprint still growing in the second half (+%.1f MB)", label, lateGrowth))
    } else {
      print(String(format: "PASS %@: footprint flat in the second half (%+.1f MB)", label, lateGrowth))
    }
    if last.windows > middle.windows {
      print("FAIL \(label): window count still growing in the second half \(middle.windows) -> \(last.windows)")
    } else {
      print("PASS \(label): window count flat in the second half (\(middle.windows) -> \(last.windows))")
    }
    if last.descriptors < 0 || middle.descriptors < 0 {
      print("FAIL \(label): could not count open descriptors")
    } else if last.descriptors - middle.descriptors > SoakThreshold.descriptors {
      print("FAIL \(label): open descriptors still growing in the second half \(middle.descriptors) -> \(last.descriptors)")
    } else {
      print("PASS \(label): open descriptors flat in the second half (\(middle.descriptors) -> \(last.descriptors))")
    }
    if last.threads < 0 || middle.threads < 0 {
      print("FAIL \(label): could not count threads")
    } else if last.threads - middle.threads > SoakThreshold.threads {
      print("FAIL \(label): thread count still growing in the second half \(middle.threads) -> \(last.threads)")
    } else {
      print("PASS \(label): thread count flat in the second half (\(middle.threads) -> \(last.threads))")
    }
  }

  /// 让系统的 leaks 看一眼自己：数无人引用的内存块。会把本进程暂停几秒，探针此刻没有别的事。
  func soakLeaksSummary(label: String) {
    let leaks = Process()
    leaks.executableURL = URL(fileURLWithPath: "/usr/bin/leaks")
    leaks.arguments = ["\(ProcessInfo.processInfo.processIdentifier)"]
    let pipe = Pipe()
    leaks.standardOutput = pipe
    leaks.standardError = Pipe()
    if (try? leaks.run()) != nil {
      let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      leaks.waitUntilExit()
      for line in text.split(separator: "\n") where line.contains("leaks for") || line.contains("nodes malloced") {
        print("INFO \(label) leaks: \(line.trimmingCharacters(in: .whitespaces))")
      }
    } else {
      print("INFO \(label) leaks: could not run /usr/bin/leaks")
    }
  }

  /// 采样点：热身末（第 10 轮）之后每 `every` 轮一次，加最后一轮。
  func soakShouldSample(round: Int, rounds: Int, every: Int, warmup: Int) -> Bool {
    round == warmup || round % every == 0 || round == rounds
  }

  /// `--soak-sample-every N` 覆盖默认采样间隔。
  func soakSampleEvery(default fallback: Int) -> Int {
    let args = CommandLine.arguments
    return args.firstIndex(of: "--soak-sample-every")
      .flatMap { args.indices.contains($0 + 1) ? Int(args[$0 + 1]) : nil }
      .map { max(1, $0) } ?? fallback
  }

  /// 窗口浏览开合：同一个控制器连续开、关键盘面板 `rounds` 次。只开关面板，不对任何窗口发动作。
  func soakBrowser(rounds: Int) async throws {
    guard WindowBrowserSettings.keyboardPanelEnabled else {
      print("SKIP soak-browser: Window browser is off in Settings; the probe does not change settings")
      return
    }
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 2.0)
    let browser = WindowBrowserController(owner: owner)
    browser.start()
    defer {
      browser.probeClosePanel()
      browser.stop()
    }
    let every = soakSampleEvery(default: 10)
    let warmup = 10
    var samples: [SoakSample] = []
    for round in 1...rounds {
      guard browser.openKeyboardPanel() else {
        print("FAIL soak-browser: the panel refused to open at round \(round)")
        return
      }
      try await wait("browser panel visible \(round)", timeout: 5) { browser.probePanelVisible }
      // 等列表里出现内容（最多 3 秒，没有也不算失败：这里量的是资源，不是列表速度）。
      let listed = CACurrentMediaTime()
      while browser.probeListedKeys.isEmpty, CACurrentMediaTime() - listed < 3 {
        try await Task.sleep(for: .milliseconds(50), clock: .suspending)
      }
      browser.probeClosePanel()
      try await wait("browser panel closed \(round)", timeout: 5) { !browser.probePanelVisible }
      try await Task.sleep(for: .milliseconds(200), clock: .suspending)
      if soakShouldSample(round: round, rounds: rounds, every: every, warmup: warmup) {
        let sample = SoakSample.take(round: round)
        samples.append(sample)
        print(String(format: "SOAK browser round %d: footprint %.1f MB, windows %d, descriptors %d, threads %d",
          round, sample.footprintMB, sample.windows, sample.descriptors, sample.threads))
        fflush(stdout)
      }
    }
    try soakVerdict(label: "soak-browser", rounds: rounds, samples: samples, warmup: warmup)
    soakLeaksSummary(label: "soak-browser")
  }

  /// 悬停看一眼：先收起临时窗口，再让指针进、出卷帘条 `rounds` 次，每次等看一眼出现与收回。
  func soakGlance(element: AXUIElement, rounds: Int) async throws {
    guard GlanceController.isEnabled else {
      print("SKIP soak-glance: Glance is off in Settings; the probe does not change settings")
      return
    }
    let glance = owner.glance
    owner.shade(element, id)
    try await wait("strip shown") {
      self.owner.shaded[self.id]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
        && self.owner.duoController.windowEffects.activeCount == 0
    }
    // 收起后 0.7 秒内不响应悬停。
    try await Task.sleep(for: .milliseconds(800), clock: .suspending)
    guard let strip = owner.shaded[id]?.overlay?.frame else { throw EffectError.unavailable("no strip") }
    let onStrip = NSPoint(x: strip.minX + strip.width * 0.6, y: strip.midY)
    let away = NSPoint(x: -9000, y: -9000)
    let every = soakSampleEvery(default: 10)
    let warmup = 10
    var samples: [SoakSample] = []
    for round in 1...rounds {
      pointer = onStrip
      glance.pointerEntered(id)
      try await wait("glance shown \(round)", timeout: 6) { glance.isShowing }
      try await Task.sleep(for: .milliseconds(250), clock: .suspending)
      pointer = away
      try await wait("glance closed \(round)", timeout: 4) { !glance.hasSession(self.id) }
      try await Task.sleep(for: .milliseconds(300), clock: .suspending)
      if soakShouldSample(round: round, rounds: rounds, every: every, warmup: warmup) {
        let sample = SoakSample.take(round: round)
        samples.append(sample)
        print(String(format: "SOAK glance round %d: footprint %.1f MB, windows %d, descriptors %d, threads %d",
          round, sample.footprintMB, sample.windows, sample.descriptors, sample.threads))
        fflush(stdout)
      }
    }
    guard owner.shaded[id] != nil, !onscreen(id) else {
      throw EffectError.unavailable("the glance loop left the window unfolded or visible")
    }
    try soakVerdict(label: "soak-glance", rounds: rounds, samples: samples, warmup: warmup)
    soakLeaksSummary(label: "soak-glance")
    _ = owner.unshade(id)
  }
}
