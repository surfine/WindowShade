import Cocoa
import ScreenCaptureKit

/// Opt-in development diagnostic. Never entered during ordinary application startup.
/// Captures a moving test window or display and reports counters; no captured images are saved.
@MainActor
final class EffectSoakProbe {
  private final class MotionView: NSView {
    var time = 0.0
    override func draw(_ dirtyRect: NSRect) {
      NSColor.white.setFill()
      bounds.fill()
      for row in 0..<12 {
        let x = 30 + 100 * (1 + sin(time * 2 + Double(row) * 0.15))
        NSColor.systemBlue.setFill()
        NSRect(x: x, y: Double(row) * 30, width: 100, height: 12).fill()
        for column in 0..<16 {
          (Int(time * 60) + row + column) % 2 == 0
            ? NSColor.black.setFill() : NSColor.white.setFill()
          NSRect(x: 300 + column * 16, y: row * 30, width: 12, height: 12).fill()
        }
      }
    }
  }
  private let duration: Double
  private let output: URL
  private var window: NSWindow?
  private var session: EffectSession?
  private let motion = MotionView()
  private let sensor = LidAngleSource()
  private var sensorTimes: [Double] = []
  private var readings = 0
  private var started = 0.0
  private var lastReport = 0.0
  private var reports: [[String: Any]] = []
  private var finished = false
  private var ticks = 0
  private let script = EffectSoakScript.smoke
  private var soak = EffectSoakTracker()
  init(duration: Double, output: URL) {
    self.duration = duration
    self.output = output
  }

  func run() {
    let window = NSWindow(
      contentRect: NSRect(x: 40, y: 100, width: 600, height: 380), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.title = "WindowShade · 持续运行测试（可关闭进程结束）"
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isReleasedWhenClosed = false
    window.contentView = motion
    window.orderFrontRegardless()
    self.window = window
    sensor.onReading = { [weak self] reading in
      guard let self else { return }
      readings += 1
      sensorTimes.append(reading.readMilliseconds)
      if sensorTimes.count > 3600 { sensorTimes.removeFirst(sensorTimes.count - 3600) }
    }
    sensor.start()
    Task { @MainActor [self] in
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: false)
        guard
          let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }),
          let own = content.applications.first(where: { $0.processID == getpid() }),
          let moving = content.windows.first(where: {
            $0.windowID == CGWindowID(window.windowNumber)
          })
        else {
          throw EffectError.unavailable("诊断显示器或窗口不可用")
        }
        let session = try EffectSession(
          frame: NSRect(x: 660, y: 100, width: 600, height: 380), desktop: false)
        self.session = session
        session.panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        session.renderer.view.autoResizeDrawable = false
        let screen = screenForDisplayID(display.displayID)
        let scale = screen?.backingScaleFactor ?? 2
        let size = CGSize(width: display.frame.width * scale, height: display.frame.height * scale)
        session.renderer.view.drawableSize = size
        let filter = SCContentFilter(
          display: display, excludingApplications: [own], exceptingWindows: [moving])
        try await session.start(
          filter: filter, pixels: size, color: EffectColorSpace.display(screen))
        if let first = session.source.frame() {
          print(
            "METADATA buffer=\(CVPixelBufferGetWidth(first.buffer))x\(CVPixelBufferGetHeight(first.buffer)) uv=\(first.contentUV) scale=\(first.scale) contentScale=\(first.contentScale)"
          )
        }
        started = CACurrentMediaTime()
        lastReport = started
        // PERF-11：资格要读主线程停顿的真数字。这里只装 RunLoop observer（抓栈线程仍按开关），
        // 并把累计计数归零——这一次跑出来的停顿只算这一段，不带上启动序列的账。
        MainThreadStallSentinel.shared.start()
        _ = MainThreadStallSentinel.shared.stallCounters(reset: true)
        session.onFailure = { [weak self] in self?.finish(error: "capture or presentation failed") }
        session.source.onStop = { [weak self] error in
          self?.finish(error: error.localizedDescription)
        }
        session.source.onContentUnavailable = { [weak self] in
          self?.finish(error: "capture became unavailable")
        }
        session.tick = { [weak self] now in self?.tick(now) }
        session.show()
        print("START duration=\(duration)s displayCapture=\(Int(size.width))x\(Int(size.height))")
        fflush(stdout)
      } catch { finish(error: error.localizedDescription) }
    }
  }
  private func tick(_ now: Double) {
    guard !finished, let session else { return }
    let elapsed = now - started
    ticks += 1
    motion.time = elapsed
    motion.needsDisplay = true
    // 显式阶段脚本：每个阶段都有名字、时长与进度，8 秒就能覆盖一整轮。
    soak.advance(to: elapsed)
    session.renderer.parameters.progress = script.progress(at: elapsed)
    if now - lastReport >= 60 || reports.isEmpty {
      report(now)
      lastReport = now
    }
    if elapsed >= duration { finish(error: nil) }
  }
  private static func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    return result == KERN_SUCCESS ? info.resident_size : 0
  }
  /// JSONSerialization 不接受可选值：缺样本的字段写成 `not_available`，不填 0。
  /// 判定那边（PerfQualification）用的是原始 `[String: Double?]`，避免两处各自定义「缺」。
  private static func jsonFields(_ fields: [String: Double?]) -> [String: Any] {
    fields.mapValues { $0.map { $0 as Any } ?? "not_available" }
  }
  private func report(_ now: Double) {
    let times = sensorTimes.sorted()
    var row: [String: Any] = [
      "elapsed": now - started, "residentBytes": Self.residentBytes(), "sensorReadings": readings,
      "sensorReadP95ms": times.isEmpty
        ? 0 : times[min(times.count - 1, Int(Double(times.count) * 0.95))],
      "displayTicks": ticks, "capturedFrames": session?.source.frame()?.id ?? 0,
      "phase": script.phase(at: now - started)?.rawValue ?? "none",
      "renderFields": Self.jsonFields(session?.renderer.metricFields() ?? [:]),
      "sourceFields": Self.jsonFields(session?.source.metricFields() ?? [:]),
    ]
    for (key, value) in soak.fields() { row["soak.\(key)"] = value }
    reports.append(row)
    print(row)
    fflush(stdout)
  }
  private func finish(error: String?) {
    guard !finished else { return }
    finished = true
    report(CACurrentMediaTime())
    sensor.stop()
    sensor.onReading = nil
    let releasedSession = WeakReference(session)
    let releasedSource = WeakReference(session?.source)
    let releasedRenderer = WeakReference(session?.renderer)
    session?.stop()
    session = nil
    window?.orderOut(nil)
    window = nil
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
      let released = (session: releasedSession.value == nil,
                      source: releasedSource.value == nil,
                      renderer: releasedRenderer.value == nil)
      let qualification = PerfQualification.evaluate(
        qualificationSample(
          releasedSession: released.session, releasedSource: released.source,
          releasedRenderer: released.renderer))
      var result: [String: Any] = [
        "duration": duration, "error": error ?? "", "reports": reports,
        "releasedSession": released.session,
        "releasedSource": released.source,
        "releasedRenderer": released.renderer,
        "residentAfterStop": Self.residentBytes(),
        "system": ProcessInfo.processInfo.operatingSystemVersionString,
        "soak": soak.fields(),
        "soakFullCoverage": soak.hasFullCoverage,
        "soakCycleSeconds": script.cycleDuration,
        "soakMinPhaseSeconds": script.minPhaseDuration,
        "qualificationVerdict": qualification.verdict.rawValue,
        "metadata": Self.metadata(),
      ]
      for (key, value) in qualification.fields() { result[key] = value }
      do {
        try FileManager.default.createDirectory(
          at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
          .write(to: output, options: .atomic)
      } catch {
        fputs("FAIL: cannot write diagnostic: \(error)\n", stderr)
        exit(1)
      }
      print("QUALIFY \(qualification.summary())")
      if qualification.verdict == .fail {
        print("QUALIFY failures: \(qualification.failures.joined(separator: ","))")
      }
      if qualification.verdict == .notAvailable {
        print("QUALIFY incomplete: \(qualification.unavailable.joined(separator: ","))")
      }
      print("END \(output.path)")
      fflush(stdout)
      // 功能、覆盖、释放都过，且资格不失败才算这次的绿灯；`not_available` 不是通过，不能假冒绿灯。
      exit(
        error == nil && released.session && released.source && released.renderer
          && soak.hasFullCoverage && qualification.verdict == .pass ? 0 : 1)
    }
  }
  /// PERF-11：把这一段的数字收成一个资格样本。缺的字段留 nil，判定时记 `not_available`。
  private func qualificationSample(
    releasedSession: Bool, releasedSource: Bool, releasedRenderer: Bool
  ) -> PerfQualificationSample {
    let renderer = session?.renderer.metricFields() ?? [:]
    let source = session?.source.metricFields() ?? [:]
    let sentinel = MainThreadStallSentinel.shared
    // 哨兵没装上（例如不是从主线程启动）时不能报 0 次停顿，那会把「没量」读成通过。
    let counters: (count: Int, longestMs: Double)? =
      sentinel.isRunning ? sentinel.stallCounters() : nil
    let unreleased = [releasedSession, releasedSource, releasedRenderer].filter { !$0 }.count
    return PerfQualificationSample(
      animationFPS: renderer["fps"] ?? nil,
      sourceFPS: source["sourceFPS"] ?? nil,
      newSourceFPS: renderer["newSourceFPS"] ?? nil,
      captureToPresentP95ms: renderer["captureToPresentP95ms"] ?? nil,
      gpuTimeP95ms: renderer["gpuP95ms"] ?? nil,
      gpuToBusyP95ms: renderer["gpuToBusyP95ms"] ?? nil,
      presentedCount: renderer["presentedCount"] ?? nil,
      stalePresentedFrames: renderer["stalePresentedFrames"] ?? nil,
      mainThreadStalls: counters.map { Double($0.count) },
      longestStallMs: counters.map { $0.longestMs },
      unreleasedObjects: Double(unreleased))
  }
  /// 跑这一次的机器与环境。资格数字离开这些元数据就没法比较，所以存在同一份输出里。
  private static func metadata() -> [String: Any] {
    let process = ProcessInfo.processInfo
    var out: [String: Any] = [
      "host": hostModel(),
      "os": process.operatingSystemVersionString,
      "processorCount": process.processorCount,
      "physicalMemoryBytes": process.physicalMemory,
      "thermalState": thermalStateName(process.thermalState),
      "lowPowerMode": process.isLowPowerModeEnabled,
      "stallSamplerEnabled": Diagnostics.stallSamplerOn,
      "instrumentation": process.environment["WINDOWSHADE_PERF_INSTRUMENTATION"] ?? "none",
      // 进程内拿不到逐帧 GPU busy 的公开计数器（Instruments/Metal 工具才有）。
      // 缺就写 not_available，不拿猜的数字凑一格。
      "gpuCounters": "not_available",
    ]
    if let screen = NSScreen.main {
      out["display"] = "\(Int(screen.frame.width))x\(Int(screen.frame.height))"
      out["displayScale"] = screen.backingScaleFactor
    }
    return out
  }
  private static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
  }
  private static func hostModel() -> String {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
    var value = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.model", &value, &size, nil, 0) == 0 else { return "unknown" }
    return String(decoding: value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }
  private final class WeakReference<T: AnyObject> {
    weak var value: T?
    init(_ value: T?) { self.value = value }
  }
}
