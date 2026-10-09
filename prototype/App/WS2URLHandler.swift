import Foundation

/// windowshade:// 链接（AppDelegate 的 application(_:open:) 转到这里）。目前只认 `windowshade://lock`：
///
/// - 形状由 WS2LockRequestPolicy.accepts 校验：没有路径、查询、片段、用户名、端口，别的一律不认；
/// - 只锁屏，不解锁；锁之前先把私人 App 收进刘海（由挂上来的 `lockScreen` 做）；
/// - 链接证明不了是你的手机发的：请求一发出就清掉，不留「自己锁的」归属，回来也不会自动解锁；
/// - 「离开就锁」开着时驱动才挂上 `lockScreen`；没挂就什么链接都不认（默认关）。
@MainActor final class WS2URLHandler {
    static let shared = WS2URLHandler()

    /// 收私人 App、再锁屏。PresenceLockDriver 开着时挂上，关掉时摘下。
    var lockScreen: (@MainActor () -> Void)?

    private var policy = WS2LockRequestPolicy()
    private let now: () -> Double
    private let makeID: () -> UUID

    init(now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         makeID: @escaping () -> UUID = UUID.init) {
        self.now = now
        self.makeID = makeID
    }

    /// 一次送来几条也只锁一次。返回是否真的请求了锁屏。
    @discardableResult
    func open(_ urls: [URL]) -> Bool {
        for url in urls where open(url) { return true }
        return false
    }

    @discardableResult
    func open(_ url: URL) -> Bool {
        guard WS2LockRequestPolicy.accepts(url), let lockScreen else { return false }
        let at = now()
        guard policy.begin(origin: .localLink, at: at, id: makeID()) != nil else { return false }
        lockScreen()
        // 不拿请求号去证明：observedLocked 只给「在场」来源、而且证明对得上的请求留归属，这里一律清空。
        policy.observedLocked(provedRequestID: nil, at: max(at, now()))
        return true
    }

    /// 测试用：这次请求之后有没有留下任何归属（应当永远没有）。
    var ownsLock: Bool { policy.ownedLock != nil || policy.pending != nil }
}
