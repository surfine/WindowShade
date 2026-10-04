import Foundation

/// 离开倒数的模拟。停在「倒数 10」，不把请求锁定交给系统。
enum WS2AwaySimulation {
    struct Preview: Equatable, Sendable {
        var line: String
        var requestedLock: Bool
    }

    static func countdownPreview() -> Preview {
        var lock = PresenceLock(bootID: UUID())
        let start = WS2.Instant(nanoseconds: 0)
        _ = lock.handle(.enable, at: start)
        _ = lock.handle(.systemUnlocked, at: start)
        _ = lock.handle(.connected(.phone, generation: 1), at: start)
        _ = lock.handle(.readStarted(.phone, generation: 1, request: 1), at: start)
        _ = lock.handle(.readSucceeded(.phone, generation: 1, request: 1), at: seconds(0.1))
        _ = lock.handle(.disconnected(.phone, generation: 1), at: seconds(1))
        let effects = lock.handle(.tick, at: seconds(2.5))
        let number = effects.compactMap { effect -> Int? in
            if case .countdown(let value, _) = effect { return value }
            return nil
        }.first
        let requested = effects.contains { effect in
            if case .requestLock = effect { return true }
            return false
        }
        let line = number.map { "倒数 \($0)" } ?? "未知"
        return Preview(line: line, requestedLock: requested)
    }

    private static func seconds(_ value: Double) -> WS2.Instant {
        WS2.Instant(nanoseconds: UInt64(value * 1_000_000_000))
    }
}
