import Foundation

/// 决定 74（Aaron 2026-10-31）：锁屏时的第二道 = 和你自己那台 iPhone 之间的 Pair-Verify 加密连线（遥控器那一条），
/// 而且要**刚刚**重新证明过一次。纯规则：不开 socket、不碰钥匙串、不读时钟（时间由调用方传单调秒）。
///
/// 证明 = 一次挑战加一次应答，挑战绑在「这一次锁屏」（`epoch`）和一个随机数（`nonce`）上，只能用一次：
/// - 握手：锁着时手机新连进来走完 Pair-Verify。Mac 在 M2 里给的是这次新生成的临时公钥，手机在 M3 里用它的长期私钥
///   签了这把临时公钥——这一签就是对这次挑战的应答，录下来拿到下一次握手里也对不上。挑战在 M1 时发出，M3 验过才算答上。
/// - 回声：锁之前就连着、锁屏后留下来的那条连线上，Mac 发一条加密请求（事务号就是 nonce），手机回的加密应答带着同一个事务号。
///   会话密钥来自那次握手，收发计数器只往前走，旧的应答重放会解不开。
///
/// 第二道只在下面全部成立时算 `verified`：确知锁着；这一次锁屏里答上过一个挑战；答上到现在不超过 `freshness` 秒；
/// 那条连线此刻还活着。答上过但连线断了，或者过了时限，就是 `presentUnverified`；从没答上过也没有连线就是 `absent`。
///
/// 省电：只在要刷脸的那一小段（亮屏、开盖、唤醒）打开 `window` 秒的核对窗口；窗口外不发挑战、不收新连线。
enum CompanionLockVerify {
    /// 答上之后多少秒内还算数。闸门判的那一刻超过它就退回 presentUnverified。
    static let freshness: Double = 10
    /// 一次亮屏打开的核对窗口有多长（够一轮刷脸加转头挑战之前那几秒）。再次亮屏会续上。
    static let window: Double = 15
    /// 同时在等应答的挑战最多几个（每条连线一个，加上正在握手的）。
    static let maximumOutstanding = 4
    /// 回声挑战用的方法名。不是遥控器认识的任何命令；对端只要回一条带同一事务号的加密应答（空的或报错的都行）。
    /// 手机那一侧会不会回，待真机核对；不回也只是退回握手那条路。
    static let echoMethod = "_wsLockVerify"

    enum Status: Equatable, Sendable { case verified, presentUnverified, absent }

    /// 锁着时收到的一条加密消息该怎么办。除了答挑战，一律拒绝：不执行、不回、不动界面，只记类别。
    enum LockedMessage: Equatable, Sendable {
        case verifyAnswer(nonce: UInt32)
        case refuse(Refusal)
    }

    /// 拒绝的类别（日志只记这个，不记内容、不记设备）。
    enum Refusal: String, Equatable, Sendable, CaseIterable {
        case input        // 按键、触摸、键盘
        case media        // 音量、播放
        case session      // 开会话、停会话
        case profile      // 设备信息、订阅事件、各种 Fetch
        case pairing      // 锁着时一律不配对
        case reply        // 应答，但不是答我们发出的挑战
        case other
    }

    static func classify(kind: UInt64?, method: String?, transaction: UInt64?) -> LockedMessage {
        if kind == 3 {
            guard let transaction, transaction > 0, transaction <= UInt64(UInt32.max) else { return .refuse(.reply) }
            return .verifyAnswer(nonce: UInt32(transaction))
        }
        guard let method else { return .refuse(.other) }
        switch method {
        case "_hidC", "_hidT", "_touchStart", "_touchStop", "_touchC", "_tiStart", "_tiStop", "_tiC", "_tiD":
            return .refuse(.input)
        case "_mcc", "MediaControlCommand", "_vol":
            return .refuse(.media)
        case "_sessionStart", "_sessionStop", "TVRCSessionStart", "TVRCSessionStop":
            return .refuse(.session)
        case "_systemInfo", "SystemInfo", "_interest", "_launchApp", "_ping":
            return .refuse(.profile)
        default:
            return method.hasPrefix("Fetch") ? .refuse(.profile) : .refuse(.other)
        }
    }
}

/// 一次锁屏里的挑战与证明。每次锁上、解开都换一代（epoch），旧的挑战和证明一起作废。
struct CompanionLockVerifier: Equatable, Sendable {
    struct Challenge: Equatable, Sendable {
        let epoch: UInt64
        let nonce: UInt32
        let issuedAt: Double
    }

    enum Rejection: String, Equatable, Sendable, Error {
        case notLocked = "not-locked"
        case windowClosed = "window-closed"
        case oldLock = "old-lock"
        case unknownNonce = "unknown-nonce"
        case stale = "stale"
        case clock = "clock"
    }

    private(set) var epoch: UInt64 = 0
    private(set) var locked = false
    private var windowEnd: Double?
    private var outstanding: [Challenge] = []
    private var provenAt: Double?
    private var provenEpoch: UInt64?

    var outstandingCount: Int { outstanding.count }

    /// 锁上或解开（只在真的变了时调）。新的一代：窗口、挑战、证明全清。
    mutating func setLocked(_ locked: Bool) {
        self.locked = locked
        epoch &+= 1
        windowEnd = nil
        outstanding.removeAll()
        provenAt = nil
        provenEpoch = nil
    }

    /// 核对模式被关掉（代填那一段清了）：这一代作废，锁态不变。
    mutating func reset() {
        let wasLocked = locked
        setLocked(wasLocked)
    }

    /// 亮屏、开盖、唤醒：打开或续上核对窗口。没锁着不开。
    @discardableResult
    mutating func openWindow(now: Double) -> Bool {
        guard locked, now.isFinite else { return false }
        let end = now + CompanionLockVerify.window
        windowEnd = max(windowEnd ?? end, end)
        return true
    }

    func isWindowOpen(now: Double) -> Bool {
        guard locked, now.isFinite, let windowEnd else { return false }
        return now <= windowEnd
    }

    /// 发一个挑战。窗口没开、nonce 是 0 或重复、在等的太多都不发（过期的先清掉）。
    mutating func issue(nonce: UInt32, now: Double) -> Challenge? {
        guard isWindowOpen(now: now), nonce != 0 else { return nil }
        outstanding.removeAll { now < $0.issuedAt || now - $0.issuedAt > CompanionLockVerify.freshness }
        guard !outstanding.contains(where: { $0.nonce == nonce }),
              outstanding.count < CompanionLockVerify.maximumOutstanding else { return nil }
        let challenge = Challenge(epoch: epoch, nonce: nonce, issuedAt: now)
        outstanding.append(challenge)
        return challenge
    }

    /// 撤回一个挑战（那条连线断了）。
    mutating func withdraw(nonce: UInt32) {
        outstanding.removeAll { $0.nonce == nonce }
    }

    /// 应答。挑战用一次就没了（答对答错都不能再答）。
    mutating func answer(nonce: UInt32, epoch: UInt64, now: Double) -> Result<Void, Rejection> {
        guard locked else { return .failure(.notLocked) }
        guard epoch == self.epoch else { return .failure(.oldLock) }
        guard let index = outstanding.firstIndex(where: { $0.nonce == nonce && $0.epoch == epoch }) else {
            return .failure(.unknownNonce)
        }
        let challenge = outstanding.remove(at: index)
        guard now.isFinite, now >= challenge.issuedAt else { return .failure(.clock) }
        guard now - challenge.issuedAt <= CompanionLockVerify.freshness else { return .failure(.stale) }
        provenAt = now
        provenEpoch = epoch
        return .success(())
    }

    /// 闸门要的那一项。`linkAlive`：此刻有一条锁着时留下或新连上的已验签连线。
    func status(now: Double, linkAlive: Bool) -> CompanionLockVerify.Status {
        guard locked, now.isFinite else { return linkAlive ? .presentUnverified : .absent }
        if linkAlive, let provenAt, provenEpoch == epoch, now >= provenAt,
           now - provenAt <= CompanionLockVerify.freshness {
            return .verified
        }
        return linkAlive || provenEpoch == epoch ? .presentUnverified : .absent
    }
}
