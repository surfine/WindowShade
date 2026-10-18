import Foundation

/// 「锁屏并收起私人 App」这个 App Intent（WindowShadeIntents.swift）和离开就锁驱动之间的一道门。
/// 取代原来的 windowshade://lock 链接：不自造 URL scheme，系统的捷径、Spotlight、Siri 都能调。
///
/// - 只锁屏，不解锁；锁之前先把私人 App 收进刘海（由挂上来的 `lockScreen` 做）；
/// - 捷径证明不了是你的手机发的：请求一发出就清掉，不留「自己锁的」归属，回来也不会自动解锁；
/// - 「离开就锁」开着时驱动才挂上 `lockScreen`；没挂就不做，Intent 会告诉用户先去打开（默认关）。
@MainActor final class WS2LockIntentBridge {
    enum Outcome: Equatable {
        /// 已经请求锁屏（私人 App 先收进刘海）。
        case locked
        /// 离开就锁没开，或驱动还没挂上；什么都没做。
        case notAvailable
        /// 同一瞬间的第二次请求；第一次还在路上。
        case rejected
    }

    static let shared = WS2LockIntentBridge()

    /// 收私人 App、再锁屏。PresenceLockDriver 开着时挂上，关掉时摘下。
    var lockScreen: (@MainActor () -> Void)?

    var isAvailable: Bool { lockScreen != nil }

    private var policy = WS2LockRequestPolicy()
    private let now: () -> Double
    private let makeID: () -> UUID

    init(now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         makeID: @escaping () -> UUID = UUID.init) {
        self.now = now
        self.makeID = makeID
    }

    func requestLock() -> Outcome {
        guard let lockScreen else { return .notAvailable }
        let at = now()
        guard policy.begin(origin: .manual, at: at, id: makeID()) != nil else { return .rejected }
        lockScreen()
        // 不拿请求号去证明：observedLocked 只给「在场」来源、而且证明对得上的请求留归属，这里一律清空。
        policy.observedLocked(provedRequestID: nil, at: max(at, now()))
        return .locked
    }

    /// 测试用：这次请求之后有没有留下任何归属（应当永远没有）。
    var ownsLock: Bool { policy.ownedLock != nil || policy.pending != nil }
}
