import Foundation
import CoreGraphics
@main struct Tests {
    static func main() {
        let training = UUID(), held = UUID()
        func sample(_ id: String?, _ base: Double, _ session: UUID) -> WS2MouthRecording {
            .init(session: session, commandID: id, frames: (0..<20).map { .init(time: Double($0) * 0.05, values: [base + Double($0) * 0.001, 0.2]) })
        }
        let a = sample("ui.windows", 0, training), b = sample("ui.activities", 0.8, training)
        let profile = WS2MouthProfile(speech: "mandarin", templates: [a,b], maximumDistance: 0.06, minimumMargin: 0.1)
        precondition(WS2MouthMatcher.match(sample(nil, 0.01, held), speech: "mandarin", profile: profile) == "ui.windows")
        precondition(WS2MouthMatcher.match(a, speech: "wu", profile: profile) == nil)
        precondition(WS2MouthMatcher.match(sample(nil, 0.4, held), speech: "mandarin", profile: profile) == nil)
        precondition(WS2MouthMatcher.evaluate([a], speech: "mandarin", profile: profile) == nil)
        let evaluation = WS2MouthMatcher.evaluate([sample(nil, 0.4, held), sample("ui.windows", 0.01, held)], speech: "mandarin", profile: profile)!
        precondition(evaluation.noCommandSamples == 1 && evaluation.falseTriggers == 0)
        var bad = a.frames; bad[5].time = bad[4].time
        precondition(!WS2MouthRecording(session: held, commandID: nil, frames: bad).valid)
        precondition(WS2MouthFrame.make(time: .nan, points: Array(repeating: .zero, count: 12)) == nil)
        var evidence = WS2DeviceEvidenceSession()
        let device = UUID(), old = evidence.begin(device: device, now: 1)!
        precondition(evidence.observe(.protectedAccess, lease: old, now: 2))
        precondition(evidence.current(now: 2)?.authenticatedIdentity == false)
        precondition(evidence.current(now: 7) == nil)
        evidence.end(.revoked, lease: old)
        precondition(evidence.current(now: 3) == nil)
        let new = evidence.begin(device: UUID(), now: 4)!
        precondition(!evidence.observe(.protectedAccess, lease: old, now: 5))
        evidence.end(.disconnected, lease: old)
        precondition(evidence.active == new)
        precondition(!evidence.observe(.connected, lease: new, now: 3))
        print("PASS mouth template rejection, holdout separation, device evidence epochs (synthetic only)")
    }
}
