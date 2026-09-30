import Foundation
@main struct LockOverlayLifecycleTests {
    static func main() {
        precondition(SessionLockState.resolve(locked: nil, onConsole: nil, loginDone: nil, dictionaryPresent: false) == .unknown)
        precondition(SessionLockState.resolve(locked: nil, onConsole: true, loginDone: nil, dictionaryPresent: true) == .unknown)
        precondition(SessionLockState.resolve(locked: nil, onConsole: true, loginDone: true, dictionaryPresent: true) == .unlocked)
        precondition(SessionLockState.resolve(locked: true, onConsole: true, loginDone: true, dictionaryPresent: true) == .locked)
        precondition(SessionLockState.resolve(locked: false, onConsole: false, loginDone: true, dictionaryPresent: true) == .unknown)
        precondition(SessionLockState.resolve(locked: true, onConsole: false, loginDone: true, dictionaryPresent: true) == .unknown)
        var life = LockOverlayLifecycle()
        precondition(life.update(enabled: false, lock: .locked, awake: true, now: 1) == .none)
        precondition(life.update(enabled: true, lock: .unknown, awake: true, now: 2) == .none)
        guard case .begin(let first) = life.update(enabled: true, lock: .locked, awake: true, now: 3) else { fatalError() }
        precondition(life.accepts(first))
        precondition(life.update(enabled: true, lock: .locked, awake: true, now: 3.2) == .none)
        precondition(life.update(enabled: true, lock: .locked, awake: false, now: 3.3) == .retreat)
        precondition(!life.accepts(first))
        guard case .begin(let second) = life.update(enabled: true, lock: .locked, awake: true, now: 4) else { fatalError() }
        precondition(second != first && life.accepts(second))
        precondition(life.update(enabled: true, lock: .locked, awake: true, now: 6.5) == .retreat)
        precondition(life.update(enabled: true, lock: .locked, awake: true, now: 7) == .none, "Never restart an expired layer on every poll")
        precondition(life.update(enabled: true, lock: .unlocked, awake: true, now: 8) == .none)
        guard case .begin(let third) = life.update(enabled: true, lock: .locked, awake: true, now: 9) else { fatalError() }
        precondition(life.update(enabled: true, lock: .unknown, awake: true, now: 9.1) == .retreat)
        precondition(!life.accepts(third))
        _ = life.update(enabled: true, lock: .locked, awake: true, now: 10)
        precondition(life.update(enabled: true, lock: .locked, awake: true, now: .nan) == .retreat)
        var spring = FoldSpring()
        spring.reset(0.4, velocity: -0.5)
        precondition(spring.velocity == -0.5 && spring.value == 0.4)
        spring.advance(to: 0, dt: 0.01)
        precondition(spring.value < 0.4 && spring.value > 0, "Handoff preserves visible position and direction")
        print("LockOverlayLifecycleTests passed")
    }
}
