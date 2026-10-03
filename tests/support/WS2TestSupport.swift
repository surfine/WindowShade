// 只编进测试二进制；不得放进 prototype/，以免被 build.sh 收入主 App。
import Foundation
struct TestSuite {
    let name: String
    private(set) var assertions = 0
    private(set) var cases = 0
    private(set) var failures = 0
    init(_ name: String) { self.name = name }
    mutating func section(_ id: String, _ description: String) {
        cases += 1; print("CASE \(id) | \(description)")
    }
    mutating func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if condition() { print("ok   \(message)") }
        else { failures += 1; print("FAIL \(message)") }
    }
    func finish() {
        print("\(failures == 0 ? "PASS" : "FAIL") \(name): \(cases) cases, \(assertions) assertions, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
func sec(_ seconds: Double) -> WS2.Instant { WS2.Instant(seconds: seconds)! }
let fixtureBoot = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
func digest(_ byte: UInt8 = 1) -> WS2.Digest { WS2.Digest(Data(repeating: byte, count: 32))! }
func fixtureContext(epoch: UInt64 = 1, provider: WS2.Provider = .codex, session: String = "session-1", project: String = "project-1", peer: String = "paired-peer-1") -> WS2.Context {
    WS2.Context(peerID: peer, projectID: project, session: WS2.SessionKey(provider: provider, id: session), epoch: epoch)
}
func fixtureApproval(context: WS2.Context = fixtureContext(), id: WS2.RequestID = .integer(1), created: Double = 1, end: Double = 121, seq: UInt64 = 2, risk: WS2.Risk = .normal, target: UInt8 = 1) -> WS2.ApprovalRequest {
    WS2.ApprovalRequest(key: WS2.ApprovalKey(session: context.session, epoch: context.epoch, requestID: id),
        context: context, targetDigest: digest(target), summary: "测试动作，不执行", risk: risk,
        createdAt: sec(created), deadline: sec(end), shownAfterSequence: seq)
}
func button(_ key: WS2.Button, _ phase: WS2.ButtonPhase, _ id: UInt64, _ begin: Double, _ at: Double) -> WS2.ButtonEvent {
    WS2.ButtonEvent(button: key, phase: phase, pressID: id, beganAt: sec(begin), at: sec(at))
}
struct DeterministicRandom {
    var state: UInt64 = 0x20261003
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
    mutating func unit() -> Double { Double(next() >> 11) / 9007199254740992.0 }
}
