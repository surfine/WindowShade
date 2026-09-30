import Foundation

/// Authorization for decoration only. Nothing in this state machine can authorize a login.
struct LockOverlayLifecycle {
    enum Action: Equatable { case none, begin(UInt64), retreat }
    private(set) var generation: UInt64 = 0
    private(set) var active = false
    private var consumed = false
    private var wasAwake = false
    private var deadline: Double?

    mutating func update(enabled: Bool, lock: SessionLockState, awake: Bool, now: Double) -> Action {
        guard now.isFinite else { return invalidate() }
        let waking = awake && !wasAwake
        wasAwake = awake
        if lock != .locked || !enabled {
            consumed = false
            return invalidate()
        }
        guard awake else { return invalidate() }
        if waking { consumed = false }
        if let deadline, now >= deadline { return invalidate() }
        guard !active, !consumed else { return .none }
        generation &+= 1
        consumed = true
        active = true
        deadline = now + 2.5
        return .begin(generation)
    }
    mutating func invalidate() -> Action {
        generation &+= 1
        deadline = nil
        let hadSession = active
        active = false
        return hadSession ? .retreat : .none
    }
    func accepts(_ token: UInt64) -> Bool { active && token == generation }
}
