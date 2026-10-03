// 原创的配对限流。此类型既不实现 SRP，也不证明控制中心协议兼容。
import Foundation
struct PairingAttemptWindow: Sendable {
    enum Failure: Error { case badTime, coolingDown, alreadyOpen, invalidPIN, unavailable }
    private(set) var deadline: Double?
    private(set) var cooldownUntil: Double = 0
    private(set) var failures = 0
    private var lastTime = 0.0
    private var pin: String?
    static let lifetime = 60.0
    static let cooldown = 300.0
    // 跨进程持久化不能保存单调时刻；重启时 caller 必须重新施加 300 秒冷却。
    init(restartedWithIncompleteAttempt: Bool = false, at now: Double = 0) {
        lastTime = now.isFinite && now >= 0 ? now : 0
        cooldownUntil = restartedWithIncompleteAttempt ? lastTime + Self.cooldown : 0
    }
    mutating func open(at now: Double, makePIN: () -> String) throws -> String {
        guard now.isFinite, now >= lastTime else { throw Failure.badTime }; lastTime = now
        guard now >= cooldownUntil else { throw Failure.coolingDown }
        guard deadline == nil || now >= deadline! else { throw Failure.alreadyOpen }
        let candidate = makePIN()
        guard candidate.utf8.count == 4, candidate.utf8.allSatisfy({ (48...57).contains($0) }) else { throw Failure.invalidPIN }
        pin = candidate; if failures >= 3 { failures = 0 }; deadline = now + Self.lifetime
        return candidate
    }
    func mayAttempt(at now: Double) -> Bool {
        now.isFinite && now >= lastTime && now >= cooldownUntil && deadline.map { now < $0 } == true && pin != nil && failures < 3
    }
    mutating func failed(at now: Double) throws {
        guard mayAttempt(at:now) else { throw Failure.unavailable }; lastTime = now
        failures += 1
        if failures == 3 { cooldownUntil = now + Self.cooldown; deadline = nil; pin = nil }
    }
    mutating func finish(at now: Double) throws {
        guard mayAttempt(at:now) else { throw Failure.unavailable }; lastTime = now; failures = 0; deadline = nil; pin = nil
    }
    mutating func cancel() { deadline = nil; pin = nil } // 取消不能抹去冷却。
    static func randomPIN() -> String { String(format:"%04d",Int.random(in:0...9999)) }
}
