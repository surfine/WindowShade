import Foundation

@main struct DuoCoreTests {
  final class Clock {
    var time = 0.0
    var tasks: [(Double, () -> Void)] = []
    func schedule(_ delay: Double, _ action: @escaping () -> Void) {
      tasks.append((time + delay, action))
    }
    func advance(_ delta: Double) {
      let end = time + delta
      while let next = tasks.enumerated().min(by: { $0.element.0 < $1.element.0 }),
        next.element.0 <= end
      {
        tasks.remove(at: next.offset)
        time = next.element.0
        next.element.1()
      }
      time = end
    }
  }
  static func main() async throws {
    precondition(FoldDriver.progress(angle: 114) == 0 && FoldDriver.progress(angle: 95) == 0)
    precondition(FoldDriver.progress(angle: 35) == 1 && FoldDriver.progress(angle: 0) == 1)
    precondition(
      FoldDriver.progress(angle: .nan) == 0
        && FoldDriver.progress(angle: 45, start: 10, end: 90) == 0)
    var previous = 0.0
    for angle in stride(from: 95.0, through: 35.0, by: -0.1) {
      let value = FoldDriver.progress(angle: angle)
      precondition(value >= previous && value <= 1)
      previous = value
    }
    var spring = FoldSpring()
    for _ in 0..<120 { spring.advance(to: 0.5, dt: 1 / 60) }
    precondition(spring.value == 0.5, "Half-open must stay folded indefinitely")
    for dt in [0.0, 0.016, 1, 30, Double.nan] {
      spring.advance(to: 1, dt: dt)
      precondition(spring.value.isFinite)
    }
    for _ in 0..<180 { spring.advance(to: 0, dt: 1 / 60) }
    precondition(spring.value == 0, "Open endpoint must become exactly clear")
    var transition = FoldTransition(value: 0)
    transition.request(folded: true, at: 0)
    transition.advance(at: 0.14)
    // `settle` 弹簧：0.14s 应在途中（不再要求 smoothstep 半程恰为 0.5）。
    precondition(transition.value > 0.15 && transition.value < 0.95, "Fold spring mid-flight")
    let mid = transition.value
    transition.request(folded: true, at: 0.14)
    transition.advance(at: 0.2)
    precondition(transition.value >= mid, "Duplicate target must not restart the timeline")
    let visible = transition.value
    transition.request(folded: false, at: 0.2)
    precondition(transition.value == visible, "Reversal must start at the visible position")
    // 打开用 `calm`：再推进约 0.8s 应落定。
    var t = 0.2
    while t < 1.2 {
      t += 1.0 / 60
      transition.advance(at: t)
    }
    precondition(transition.value == 0 && transition.settled)
    for i in 0..<1000 {
      transition.request(folded: i % 2 == 0, at: Double(i) / 100)
      transition.advance(at: Double(i) / 100 + 0.005)
      precondition((0...1).contains(transition.value))
    }
    precondition(LidReport.precise.decode([7, 0x98, 0x2C, 0, 0]) == 114.16)
    try motionTiltTests()
    precondition(LidReport.whole.decode([1, 95, 0]) == 95)
    for bytes: [UInt8] in [[], [7], [1, 95, 0], [7, 255, 255, 255, 255], [7, 0x51, 0x46, 0, 0]] {
      precondition(LidReport.precise.decode(bytes) == nil)
    }
    precondition(LidReport.precise.decode([7, 0x50, 0x46, 0, 0]) == 180)
    var probes: [LidReport] = []
    precondition(
      LidReport.detect(read: {
        probes.append($0)
        return $0 == .whole ? 95 : nil
      }) == .whole)
    precondition(probes == [.precise, .whole])
    precondition(LidReport.detect(read: { _ in nil }) == nil)
    precondition(LidReport.detect(read: { _ in 95 }) == .precise)
    var slot = LatestEffectFrame<Int>()
    let old = slot.reset()
    slot.receive(.complete, token: old, frame: 1)
    slot.receive(.complete, token: old, frame: 2)
    precondition(slot.value == 2, "Never queue obsolete frames")
    slot.receive(.idle, token: old, frame: nil)
    precondition(slot.value == 2)
    slot.receive(.complete, token: old, frame: nil)
    precondition(slot.value == 2)
    precondition(slot.receive(.unavailable, token: old, frame: nil) && slot.value == nil)
    let fresh = slot.reset()
    slot.receive(.complete, token: fresh, frame: 3)
    slot.receive(.complete, token: old, frame: 99)
    precondition(slot.value == 3)
    precondition(!slot.receive(.unavailable, token: old, frame: nil) && slot.value == 3)
    slot.reset()
    precondition(slot.value == nil)
    var now=0.0, active=true, available:Int?
    let missing=await EffectFrameAwaiter<Int>.first(timeout:0.6,now:{now},isCurrent:{active},latest:{available},pause:{now += 0.01})
    precondition(missing==nil && now>=0.6)
    now=0
    let ready=await EffectFrameAwaiter<Int>.first(timeout:0.6,now:{now},isCurrent:{active},latest:{available},pause:{now += 0.01;available=7})
    precondition(ready==7)
    now=0;available=nil
    let cancelled=await EffectFrameAwaiter<Int>.first(timeout:0.6,now:{now},isCurrent:{active},latest:{available},pause:{now += 0.01;active=false;available=99})
    precondition(cancelled==nil && now<0.6)
    try restorationTests()
    deferredRestoreCompletionTests()
    foldVerificationTests()
    titlebarIntentTests()
    print(
      "PASS: angle endpoints, bounded spring, held position, duplicate/reverse transitions, report decoding, latest-only frames, stale producer isolation, injected restore clock, timeout/retry/cancellation, durable restart/write failure"
    )
  }
  static func titlebarIntentTests() {
    let early = TitlebarTripleClickIntent()
    precondition(!early.request(), "Third click must wait for capture and hide verification")
    precondition(!early.request(), "Repeated clicks must not submit more work")
    precondition(early.completeFold(success: true))
    precondition(!early.completeFold(success: true) && !early.request())

    let late = TitlebarTripleClickIntent()
    precondition(!late.completeFold(success: true), "A double click alone must stay folded")
    precondition(late.request())
    precondition(!late.request())

    for thirdClickFirst in [true, false] {
      let failed = TitlebarTripleClickIntent()
      if thirdClickFirst { precondition(!failed.request()) }
      precondition(!failed.completeFold(success: false))
      precondition(!failed.request() && !failed.completeFold(success: true),
                   "Failure must not revive on a late success")
    }
    let cancelled = TitlebarTripleClickIntent()
    precondition(!cancelled.request())
    cancelled.cancel()
    precondition(!cancelled.completeFold(success: true) && !cancelled.request())
  }
  static func foldVerificationTests() {
    final class Scenario {
      let clock = Clock()
      var generation = 1
      var hidden = false
      var minimized = false
      var probes = 0
      var rescues = 0
      var rescueProbes = 0
      var completions: [Bool] = []
      lazy var verifier = FoldVerifier(
        schedule: clock.schedule, isCurrent: { [unowned self] in generation == 1 },
        observe: { [unowned self] in probes += 1; return hidden },
        minimize: { [unowned self] in rescues += 1 },
        observeMinimized: { [unowned self] in rescueProbes += 1; return minimized },
        completion: { [unowned self] in completions.append($0) })
    }
    let delayed = Scenario()
    delayed.verifier.start()
    delayed.verifier.start()
    delayed.clock.advance(0.2)
    precondition(delayed.completions.isEmpty && delayed.probes == 1)
    delayed.hidden = true
    delayed.clock.advance(1)
    precondition(delayed.completions == [true] && delayed.rescues == 0,
                 "Report success only after observation, without unnecessary rescue")

    for success in [true, false] {
      let rescue = Scenario()
      rescue.minimized = success
      rescue.verifier.start()
      rescue.clock.advance(0.7)
      precondition(rescue.completions.isEmpty && rescue.rescues == 1)
      rescue.clock.advance(1)
      precondition(rescue.completions == [success] && rescue.rescueProbes == 1,
                   "Rollback only after the rescue has also failed")
    }

    // The cheap on-screen signal reveals the strip as soon as the window has left the
    // screen, without extra probes of the (possibly busy) app.
    do {
      let clock = Clock()
      var offScreen = false
      var probes = 0
      var completions: [Bool] = []
      let quick = FoldVerifier(
        schedule: clock.schedule, isCurrent: { true },
        observe: { probes += 1; return false }, minimize: {}, observeMinimized: { false },
        quickObserve: { offScreen }, completion: { completions.append($0) })
      quick.start()
      clock.advance(0.05)
      precondition(completions.isEmpty, "Nothing is confirmed while the window is still on screen")
      offScreen = true
      clock.advance(0.035)
      precondition(completions == [true] && probes == 0,
                   "Leaving the screen confirms the hide before the first full probe")
      clock.advance(2)
      precondition(completions == [true] && probes == 0, "Completion is reported once")
      let lateClock = Clock()
      var lateOffScreen = false
      var lateProbes = 0
      var lateCompletions: [Bool] = []
      let late = FoldVerifier(
        schedule: lateClock.schedule, isCurrent: { true },
        observe: { lateProbes += 1; return false }, minimize: {}, observeMinimized: { false },
        quickObserve: { lateOffScreen }, completion: { lateCompletions.append($0) })
      late.start()
      lateClock.advance(0.3)
      precondition(lateProbes == 1 && lateCompletions.isEmpty, "First full probe failed")
      lateOffScreen = true
      lateClock.advance(0.035)
      precondition(lateCompletions == [true] && lateProbes == 1,
                   "Between the full probes the cheap signal keeps being watched")
    }

    // 规格 R19：只有“最小化 + 台前调度”放宽，其余组合与原来一样是 0。
    precondition(FoldVerifier.lateObservationWindow(hideIsMinimize: true, stageManager: true) > 0)
    for (minimize, stage) in [(true, false), (false, true), (false, false)] {
      precondition(FoldVerifier.lateObservationWindow(hideIsMinimize: minimize, stageManager: stage) == 0,
                   "Outside Stage Manager minimize the verification timing is unchanged")
    }
    // 最小化在 2 s 才落地：原时序在 0.95 s 判 visible（回滚），放宽后等到它并判 hidden；
    // 两种都只补救一次。永远不落地时，到点按 visible 结案，不会无限等。
    for (late, landsAt, expected, settledBy) in [
      (0.0, 2.0, FoldVerifier.Observation.visible, 0.96),
      (FoldVerifier.stageManagerMinimizeLateWindow, 2.0, .hidden, 2.21),  // 0.95 后每 0.25 s 一读
      (FoldVerifier.stageManagerMinimizeLateWindow, 99.0, .visible,
       0.95 + FoldVerifier.stageManagerMinimizeLateWindow + 0.01),
    ] {
      let clock = Clock()
      var salvages = 0
      var results: [FoldVerifier.Observation] = []
      let reading = { clock.time >= landsAt ? FoldVerifier.Observation.hidden : .visible }
      let verifier = FoldVerifier(
        schedule: clock.schedule, isCurrent: { true },
        observation: reading, salvage: { salvages += 1; return true },
        salvagedObservation: reading, lateObservationWindow: late,
        result: { results.append($0) })
      verifier.start()
      clock.advance(settledBy - 0.02)
      precondition(results.isEmpty, "No verdict before the window closes (late=\(late))")
      clock.advance(0.03)
      precondition(results == [expected] && salvages == 1,
                   "late=\(late) landsAt=\(landsAt): got \(results), salvages=\(salvages)")
      clock.advance(10)
      precondition(results.count == 1, "Verdict is reported once")
    }

    stageStripTests()
    for replacedAt in [0.0, 0.2, 0.7] {
      let stale = Scenario()
      stale.verifier.start()
      stale.clock.advance(replacedAt)
      let previousProbes = stale.probes
      let previousRescues = stale.rescues
      stale.generation = 2 // Same window ID, newly installed folded session.
      stale.clock.advance(2)
      precondition(stale.probes == previousProbes && stale.rescues == previousRescues
                   && stale.rescueProbes == 0 && stale.completions.isEmpty,
                   "Old verification must never mutate, acknowledge or roll back its replacement")
    }
  }
  // 规格 R19：台前调度侧条卡片的几何判据与展开后请回来的步骤。
  static func stageStripTests() {
    let screen = CGRect(x: 0, y: 0, width: 1280, height: 800)
    let ax = CGSize(width: 320, height: 232)
    // VM 实测：AX 320x232，外框 82x100 贴左缘。
    precondition(StageStrip.looksParked(windowServerBounds: CGRect(x: 16, y: 427, width: 82, height: 100),
                                        axSize: ax, displays: [screen]))
    // 程序坞在左时侧条在右缘。
    precondition(StageStrip.looksParked(windowServerBounds: CGRect(x: 1180, y: 300, width: 82, height: 100),
                                        axSize: ax, displays: [screen]))
    // 第二块屏（全局坐标偏移）上贴左缘同样成立：判据跟着所在屏走，不是写死的坐标。
    let second = CGRect(x: 1280, y: -200, width: 1920, height: 1080)
    precondition(StageStrip.looksParked(windowServerBounds: CGRect(x: 1296, y: 100, width: 90, height: 110),
                                        axSize: CGSize(width: 900, height: 600), displays: [screen, second]))
    // 原样在屏上（外框 = AX 尺寸）：不是。
    precondition(!StageStrip.looksParked(windowServerBounds: CGRect(x: 900, y: 448, width: 320, height: 232),
                                         axSize: ax, displays: [screen]))
    // 贴着左缘、但没缩小（用户把窗口放在左边）：不是。
    precondition(!StageStrip.looksParked(windowServerBounds: CGRect(x: 0, y: 100, width: 320, height: 232),
                                         axSize: ax, displays: [screen]))
    // 缩小了但在屏幕中间（例如动画半途或别的变换）：不是。
    precondition(!StageStrip.looksParked(windowServerBounds: CGRect(x: 600, y: 400, width: 82, height: 100),
                                         axSize: ax, displays: [screen]))
    // 用户自己把窗口拖小：AX 尺寸一起变小，比例不掉，不是。
    precondition(!StageStrip.looksParked(windowServerBounds: CGRect(x: 16, y: 427, width: 82, height: 100),
                                         axSize: CGSize(width: 82, height: 100), displays: [screen]))
    // 只缩了一边：不是。
    precondition(!StageStrip.looksParked(windowServerBounds: CGRect(x: 16, y: 427, width: 82, height: 232),
                                         axSize: ax, displays: [screen]))
    // 不在任何屏上、读数非法、没有屏：判不出就是 false。
    precondition(!StageStrip.looksParked(windowServerBounds: CGRect(x: -5000, y: 0, width: 82, height: 100),
                                         axSize: ax, displays: [screen]))
    precondition(!StageStrip.looksParked(windowServerBounds: CGRect(x: 16, y: 427, width: 82, height: 100),
                                         axSize: CGSize(width: CGFloat.nan, height: 232), displays: [screen]))
    precondition(!StageStrip.looksParked(windowServerBounds: CGRect(x: 16, y: 427, width: 0, height: 0),
                                         axSize: ax, displays: [screen]))
    precondition(!StageStrip.looksParked(windowServerBounds: CGRect(x: 16, y: 427, width: 82, height: 100),
                                         axSize: ax, displays: []))

    let n = StageStrip.restoreCheckDelays.count
    precondition(StageStrip.restoreCheckDelays.last! < 1.5, "Last nudge precedes restore verification's 1.5 s limit")
    precondition(zip(StageStrip.restoreCheckDelays, StageStrip.restoreCheckDelays.dropFirst()).allSatisfy { $0 < $1 })
    for attempt in 0..<n {
      precondition(StageStrip.restoreStep(parked: false, attempt: attempt) == .done, "Back on stage: stop touching it")
    }
    precondition(StageStrip.restoreStep(parked: true, attempt: 0) == .nudge(escalated: false))
    for attempt in 1..<(n - 1) {
      precondition(StageStrip.restoreStep(parked: true, attempt: attempt) == .nudge(escalated: true))
    }
    precondition(StageStrip.restoreStep(parked: true, attempt: n - 1) == .giveUp, "Bounded: the last check only reports")
    print("PASS: stage strip thumbnail classification and bounded restore nudges (R19)")
  }
  static func deferredRestoreCompletionTests() {
    let clock = Clock()
    var observation = RestoreObservation.pending
    var acknowledged = false
    var completions: [Bool] = []
    let verifier = RestoreVerifier(
      now: { clock.time }, schedule: clock.schedule, isCurrent: { true },
      observe: { observation }, acknowledge: { acknowledged = true },
      completion: {
        precondition(acknowledged, "Successful completion follows journal acknowledgement")
        completions.append($0)
      })
    verifier.start()
    precondition(completions.isEmpty, "Restore caller must receive its element before completion")
    clock.advance(0.3)
    precondition(completions.isEmpty, "Slow restoration must not complete at a guessed 140ms delay")
    observation = .visible
    clock.advance(0.06)
    precondition(completions == [true])
    clock.advance(2)
    precondition(completions == [true], "Follow-up window action must run once")

    // Even an immediately visible source completes on the scheduled turn.
    let immediate = RestoreVerifier(
      now: { clock.time }, schedule: clock.schedule, isCurrent: { true },
      observe: { .visible }, acknowledge: {}, completion: { completions.append($0) })
    immediate.start()
    precondition(completions == [true])
    clock.advance(0)
    precondition(completions == [true, true])
  }
  static func restorationTests() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "WindowShade-tests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let journal = DurableShadeJournal(url: dir.appendingPathComponent("journal.plist"))
    try journal.save([["id": 42, "stage": "preparing"]])
    precondition(
      try! DurableShadeJournal(url: journal.url).load()?.first?["stage"] as? String == "preparing")
    let clock = Clock()
    var state = RestoreObservation.pending
    var current = true
    var completed: [Bool] = []
    var events: [String] = []
    func verifier() -> RestoreVerifier {
      RestoreVerifier(
        now: { clock.time }, schedule: clock.schedule, isCurrent: { current }, observe: { state },
        acknowledge: {
          events.append("acknowledge")
          try! journal.save([])
        }, completion: { completed.append($0) })
    }
    verifier().start()
    clock.advance(2)
    precondition(completed == [false] && events.isEmpty)
    precondition(try! journal.load()?.count == 1, "Failed restore must retain recovery record")
    state = .visible
    verifier().start()
    clock.advance(0)
    precondition(completed == [false, true] && events == ["acknowledge"])
    precondition(try! journal.load()?.isEmpty == true, "Only successful observation clears journal")
    state = .pending
    verifier().start()
    current = false
    clock.advance(2)
    precondition(completed.count == 2, "Old session cannot acknowledge or complete")
    current = true
    state = .closed
    verifier().start()
    clock.advance(0)
    precondition(completed.count == 2, "Transient missing window is not confirmed closure")
    clock.advance(0.06)
    precondition(completed.last == false && events.count == 2)
    // A real filesystem failure must happen before a caller can perform its hidden-window mutation.
    let blocker = dir.appendingPathComponent("regular-file")
    try Data([0]).write(to: blocker)
    var hidden = false
    do {
      try DurableShadeJournal(url: blocker.appendingPathComponent("journal")).save([["id": 42]])
      hidden = true
    } catch {}
    precondition(!hidden)
  }

  /// 原来 DuoController.receiveMotion 的算法，逐字抄下来做对照。
  struct LegacyMotion {
    var motion = SIMD2<Double>.zero
    var motionFiltered = SIMD3<Double>.zero
    var motionBaseline: SIMD3<Double>?
    var motionTime: Double = 0
    mutating func receive(_ acceleration: SIMD3<Double>, time: Double) {
      if motionTime == 0 {
        motionTime = time
        motionFiltered = acceleration
        motionBaseline = acceleration
        return
      }
      let dt = motionTime > 0 ? time - motionTime : 0
      motionTime = time
      let alpha = dt > 0 && dt < 1 ? 1 - exp(-dt / 0.08) : 0.35
      motionFiltered += (acceleration - motionFiltered) * alpha
      if motionBaseline == nil {
        motionBaseline = motionFiltered
      }
      guard let baseline = motionBaseline else { return }
      let delta = motionFiltered - baseline
      motion = SIMD2(
        min(0.45, max(-0.45, delta.x * 0.7)),
        min(0.45, max(-0.45, delta.y * 0.7)))
    }
  }

  static func motionTiltTests() throws {
    // 挪到传感器队列上的滤波必须与原来主线程上的逐位一致：同一串读数，同样的输出。
    var generator = SystemRandomNumberGenerator()
    for run in 0..<50 {
      var legacy = LegacyMotion()
      var filter = MotionTiltFilter()
      var published = SIMD2<Double>.zero
      var time = 1000.0 + Double(run)
      for step in 0..<2000 {
        // 正常 16 ms、偶尔挤在一起、偶尔停顿超过 1 秒（走 0.35 的分支）、偶尔大幅倾斜到限幅。
        let gap: Double
        switch step % 97 {
        case 0: gap = 1.5
        case 13: gap = 0.0005
        default: gap = 0.016 + Double.random(in: -0.004...0.004, using: &generator)
        }
        time += gap
        let big = step % 331 < 20
        let acceleration = SIMD3<Double>(
          Double.random(in: big ? -1.2...1.2 : -0.002...0.002, using: &generator),
          Double.random(in: big ? -1.2...1.2 : -0.002...0.002, using: &generator),
          -1 + Double.random(in: -0.002...0.002, using: &generator))
        legacy.receive(acceleration, time: time)
        if let next = filter.update(acceleration, at: time) { published = next }
        precondition(
          published == legacy.motion, "tilt filter diverged at run \(run) step \(step)")
      }
    }
    var first = MotionTiltFilter()
    precondition(first.update(SIMD3(0.3, 0.3, -0.9), at: 5) == nil, "First reading only sets the baseline")
    precondition(first.update(SIMD3(0.3, 0.3, -0.9), at: 5.016) == .zero, "Resting posture is not a tilt")

    // 沿用旧值的门槛：内建屏最大 3456×2234，折算成屏幕位移不超过 0.05 像素。
    let threshold = TiltHold.threshold(pixelWidth: 3456, pixelHeight: 2234)
    precondition(threshold.x * 0.055 * 3456 <= 0.0501 && threshold.y * 0.040 * 2234 <= 0.0501)
    var hold = TiltHold()
    precondition(hold.update(SIMD2(0.01, 0.01), threshold: threshold) == SIMD2(0.01, 0.01),
      "First frame of a session takes the exact value")
    let base = SIMD2<Float>(0.01, 0.01)
    precondition(hold.update(base + SIMD2(threshold.x * 0.5, 0), threshold: threshold) == base,
      "Sub-pixel noise keeps the previous frame")
    precondition(hold.update(base + SIMD2(0, -threshold.y * 0.9), threshold: threshold) == base)
    let moved = base + SIMD2(threshold.x * 1.01, 0)
    precondition(hold.update(moved, threshold: threshold) == moved,
      "A change past the threshold shows on the same frame")
    // 慢慢漂：每步都在门槛内，但累计超过门槛的那一帧就跟上，偏差永远小于门槛。
    var drift = moved
    for _ in 0..<200 {
      drift.x += threshold.x * 0.3
      let shown = hold.update(drift, threshold: threshold)
      precondition(abs(shown.x - drift.x) < threshold.x, "Held value never lags more than the threshold")
    }
    // 跨过“在动”的门槛（渲染器和着色器都用 1e-4）当帧跟上，渲染路径与原来相同。
    var edge = TiltHold()
    let still = SIMD2<Float>(0.00009, 0)
    let barely = SIMD2<Float>(0.00011, 0)
    let wide = SIMD2<Float>(repeating: 1)
    precondition(edge.update(still, threshold: wide) == still)
    precondition(edge.update(barely, threshold: wide) == barely, "Crossing into motion is never held")
    precondition(edge.update(still, threshold: wide) == still, "Crossing out of motion is never held")
    precondition(edge.update(.zero, threshold: wide) == .zero, "Switching tilt off is exact")
    edge.reset()
    precondition(edge.update(barely, threshold: wide) == barely, "Reset primes the next session")
    var exact = TiltHold()
    let zero = SIMD2<Float>(repeating: 0)
    for value in [SIMD2<Float>(0.2, 0.1), SIMD2(0.2000001, 0.1), SIMD2(0.2, 0.1000001)] {
      precondition(exact.update(value, threshold: zero) == value, "No threshold means no holding")
    }
    print("PASS: tilt filter matches the main-thread version bit for bit; sub-pixel hold is bounded")
  }
}
