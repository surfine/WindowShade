import Foundation

@main enum PresencePolicyTests {
    static func main() {
        var checks = 0
        func check(_ pass: Bool, _ label: String) {
            guard pass else { fatalError(label) }
            checks += 1
        }
        func observation(_ at: Double, camera: PresencePolicy.CameraState = .noPersonInUsableFrame,
                         companion: PresencePolicy.CompanionState = .verifiedDeparted,
                         input: Double? = 0, generation: UInt64 = 7,
                         session: PresencePolicy.SessionState = .unlocked,
                         captured: Double? = nil) -> PresencePolicy.Observation {
            .init(generation: generation, session: session, now: at, lastInputAt: input,
                  camera: .init(state: camera, capturedAt: captured ?? at),
                  companion: .init(state: companion, observedAt: at))
        }
        var policy = PresencePolicy()
        check(policy.observe(observation(100)) == .inactive, "unarmed cannot act")
        check(policy.arm(generation: 7, verifiedAt: 100, now: 100), "fresh authentication arms")
        for t in 101...116 { _ = policy.observe(observation(Double(t))) }
        check(policy.observe(observation(117)) == .shadowDeparture, "default only observes")

        var config = PresencePolicy.Configuration()
        config.automaticLock = true
        func armed() -> PresencePolicy {
            var result = PresencePolicy(configuration: config)
            precondition(result.arm(generation: 7, verifiedAt: 100, now: 100))
            return result
        }
        policy = armed()
        for t in 101...110 {
            check(policy.observe(observation(Double(t))) == .observingDeparture, "sustained evidence required")
        }
        check(policy.observe(observation(111)) == .countdown(until: 116), "grace starts after evidence")
        for t in 112...115 { _ = policy.observe(observation(Double(t))) }
        check(policy.observe(observation(116)) == .requestSystemLock, "requests once after grace")
        check(policy.observe(observation(117)) == .inactive, "cannot spam system requests")
        policy = armed()
        for t in 101...111 { _ = policy.observe(observation(Double(t))) }
        check(policy.observe(observation(112, input: 112)) == .observingDeparture, "input cancels countdown")
        check(policy.observe(observation(113, camera: .personDetected)) == .present, "person cancels")
        check(policy.observe(observation(114, companion: .verifiedNearby)) == .present, "nearby cancels")
        check(policy.observe(observation(115, camera: .unknown)) == .unknown, "obscured is unknown")
        check(policy.observe(observation(116, companion: .unknown)) == .unknown, "disconnect alone is unknown")
        check(policy.observe(observation(117, captured: 110)) == .unknown, "stale frame cannot vote")
        check(policy.observe(observation(118, captured: 119)) == .unknown, "future frame cannot vote")
        check(policy.observe(observation(119, input: nil)) == .unknown, "unknown idle does not become zero")
        check(policy.observe(observation(120, input: 121)) == .unknown, "future input invalid")
        check(policy.observe(observation(121, input: .nan)) == .unknown, "nonfinite invalid")
        check(policy.observe(observation(122, generation: 8)) == .inactive, "generation change disarms")
        check(policy.observe(observation(123)) == .inactive, "old generation not restored")
        for state in [PresencePolicy.SessionState.locked, .sleeping, .unknown] {
            policy = armed()
            check(policy.observe(observation(101, session: state)) == .inactive, "session boundary disarms")
            check(policy.observe(observation(102)) == .inactive, "no automatic rearm")
        }
        policy = armed()
        for t in 101...110 { _ = policy.observe(observation(Double(t))) }
        check(policy.observe(observation(115)) == .observingDeparture, "sampling gap resets continuity")
        check(policy.observe(observation(114)) == .unknown, "rewind rejected")
        check(policy.observe(observation(116)) == .observingDeparture, "rewind clears candidate")
        policy.disarm()
        check(!policy.arm(generation: 7, verifiedAt: 110, now: 110), "reset retains watermark")
        check(!policy.arm(generation: 7, verifiedAt: 100, now: 120), "expired proof rejected")
        check(!policy.arm(generation: 7, verifiedAt: 122, now: 121), "future proof rejected")
        check(!policy.arm(generation: 7, verifiedAt: .nan, now: 121), "nonfinite proof rejected")
        config.cancelGrace = 0
        policy = PresencePolicy(configuration: config)
        check(!policy.arm(generation: 7, verifiedAt: 100, now: 100), "cannot remove grace")
        check(policy.observe(observation(101)) == .inactive, "invalid configuration inert")
        print("PresencePolicy: \(checks) checks passed")
    }
}
