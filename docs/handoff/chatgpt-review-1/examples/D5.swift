// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Foundation
// 这里只生成 PIN；协议证明必须使用已审计的服务端配对实现。
func makePairingPIN() -> String {
    var rng = SystemRandomNumberGenerator()
    return (0..<4).map { _ in String(Int.random(in: 0...9, using: &rng)) }.joined()
}
struct PairingWindow {
    let deadline: Double
    private(set) var failures = 0
    mutating func failedAttempt() { failures = min(3, failures + 1) }
    func mayAttempt(now: Double) -> Bool {
        now.isFinite && now < deadline && failures < 3
    }
}
