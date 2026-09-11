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
    precondition(abs(transition.value - 0.5) < 1e-10)
    transition.request(folded: true, at: 0.14)
    transition.advance(at: 0.2)
    precondition(transition.value > 0.75, "Duplicate target must not restart the timeline")
    let visible = transition.value
    transition.request(folded: false, at: 0.2)
    precondition(transition.value == visible, "Reversal must start at the visible position")
    transition.advance(at: 1)
    precondition(transition.value == 0 && transition.settled)
    for i in 0..<1000 {
      transition.request(folded: i % 2 == 0, at: Double(i) / 100)
      transition.advance(at: Double(i) / 100 + 0.005)
      precondition((0...1).contains(transition.value))
    }
    precondition(LidReport.precise.decode([7, 0x98, 0x2C, 0, 0]) == 114.16)
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
    print(
      "PASS: angle endpoints, bounded spring, held position, duplicate/reverse transitions, report decoding, latest-only frames, stale producer isolation, injected restore clock, timeout/retry/cancellation, durable restart/write failure"
    )
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
}
