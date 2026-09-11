import Cocoa
import ScreenCaptureKit

/// Opt-in development diagnostic. Never entered during ordinary application startup.
/// Captures a moving test window or display and reports counters; no captured images are saved.
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
    sensor.setEngaged(true)
    Task { @MainActor in
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
    // Alternate a held half-open position and repeated reversals, without source freezes.
    session.renderer.parameters.progress = Float(
      elapsed.truncatingRemainder(dividingBy: 20) < 10 ? 0.5 : 0.5 + 0.45 * sin(elapsed * 2))
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
  private func report(_ now: Double) {
    let times = sensorTimes.sorted()
    let row: [String: Any] = [
      "elapsed": now - started, "residentBytes": Self.residentBytes(), "sensorReadings": readings,
      "sensorReadP95ms": times.isEmpty
        ? 0 : times[min(times.count - 1, Int(Double(times.count) * 0.95))],
      "displayTicks": ticks, "capturedFrames": session?.source.frame()?.id ?? 0,
      "render": session?.renderer.metrics() ?? "stopped",
    ]
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
      let result: [String: Any] = [
        "duration": duration, "error": error ?? "", "reports": reports,
        "releasedSession": releasedSession.value == nil,
        "releasedSource": releasedSource.value == nil,
        "releasedRenderer": releasedRenderer.value == nil,
        "residentAfterStop": Self.residentBytes(),
        "system": ProcessInfo.processInfo.operatingSystemVersionString,
      ]
      do {
        try FileManager.default.createDirectory(
          at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
          .write(to: output, options: .atomic)
      } catch {
        fputs("FAIL: cannot write diagnostic: \(error)\n", stderr)
        exit(1)
      }
      print("END \(output.path)")
      fflush(stdout)
      exit(
        error == nil && releasedSession.value == nil && releasedSource.value == nil
          && releasedRenderer.value == nil ? 0 : 1)
    }
  }
  private final class WeakReference<T: AnyObject> {
    weak var value: T?
    init(_ value: T?) { self.value = value }
  }
}
