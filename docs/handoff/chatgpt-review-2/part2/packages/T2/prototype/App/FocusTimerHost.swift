import Foundation
@MainActor final class FocusTimerHost {
    private(set) var model: FocusTimer
    private let clock: any WS2Clock
    private let calendarSample: (WS2.Instant, WS2.Instant?) -> FocusTimer.CalendarSample
    private let effects: ([FocusTimer.Effect]) -> Void
    private var wake: Task<Void,Never>?
    private var revision: UInt64 = 0
    var presentation: FocusTimer.Presentation = .hidden { didSet { schedule() } }
    var onChange: ((FocusTimer,WS2.Instant) -> Void)?
    init(model:FocusTimer,clock:any WS2Clock,
         calendarSample:@escaping (WS2.Instant,WS2.Instant?) -> FocusTimer.CalendarSample,
         effects:@escaping ([FocusTimer.Effect]) -> Void) {
        self.model = model; self.clock = clock; self.calendarSample = calendarSample; self.effects = effects
    }
    func handle(_ event: FocusTimer.Event) {
        let now = clock.now(); let sample = calendarSample(now,model.deadline)
        let result = model.handle(event,at:now,calendar:sample)
        effects(result); onChange?(model,now); schedule()
    }
    func stop() { wake?.cancel(); wake = nil; if revision < .max { revision += 1 } }
    private func schedule() {
        stop(); guard revision < .max else { return }
        let now = clock.now()
        guard let end = model.nextWake(at:now,presentation:presentation) else { return }
        let delay = max(1,end.elapsed(since:now)), generation = revision
        wake = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:delay) } catch { return }
            guard let self, !Task.isCancelled, self.revision == generation else { return }
            self.handle(.tick)
        }
    }
    deinit { wake?.cancel() }
}
