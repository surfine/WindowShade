import Cocoa

/// 刘海唯一的展示仲裁：一块屏同一时刻只有一个主人。
///
/// 协调器只做准入与撤销；视图怎么收尾由 `cancel` 闭包同步完成，收尾做完协调器才发布新租约。
/// 展示租约不是授权账：它只决定谁在刘海里露面，不能批准任何动作。
@MainActor
final class NotchLeaseHub {
    /// 编译期登记的主人表。层与协调器里的 permits 表一致，不接受表外的名字。
    enum Owner: String {
        case authorization, conductor, notchShelf, launchpad, windowBrowser, pomodoro

        var layer: WS2.Layer {
            switch self {
            case .authorization: return .authorization
            case .conductor: return .interaction
            case .notchShelf, .launchpad, .windowBrowser, .pomodoro: return .opened
            }
        }
    }

    struct CancelNotice {
        let owner: Owner
        let display: WS2.DisplayID
        let reason: WS2.LeaseRevocation
    }

    /// 一次申请的默认期限。到期不续，协调器在下次采样时撤销。
    static let defaultLifetime: UInt64 = 600 * WS2.Duration.second

    private let bootID = UUID()
    private let clock = WS2ContinuousClock()
    private var held: [WS2.DisplayID: (owner: Owner, handle: WS2.LeaseHandle)] = [:]
    private let displays: () -> Set<WS2.DisplayID>
    private let locked: () -> Bool
    private let cancelHandler: (CancelNotice) -> Void

    private lazy var coordinator = InteractionCoordinator(
        bootID: bootID,
        clock: clock,
        environment: { [weak self] in
            guard let self else { return InteractionCoordinator.Environment(unlocked: false, displays: []) }
            return InteractionCoordinator.Environment(unlocked: !self.locked(), displays: self.displays())
        },
        cancel: { [weak self] handle, reason in self?.route(handle, reason) })

    init(displays: @escaping () -> Set<WS2.DisplayID>,
         locked: @escaping () -> Bool = { EffectSecurityBoundary.lockState == .locked },
         cancel: @escaping (CancelNotice) -> Void) {
        self.displays = displays
        self.locked = locked
        self.cancelHandler = cancel
    }

    // MARK: - 申请与释放

    /// 申请这块屏的展示权。同一主人重复申请是幂等的；被别人占着返回 false，调用方不要抢。
    @discardableResult
    func acquire(_ owner: Owner, on display: WS2.DisplayID,
                 lifetime: UInt64 = NotchLeaseHub.defaultLifetime) -> Bool {
        if held[display]?.owner == owner { return true }
        let now = clock.now()
        let request = WS2.LeaseRequest(ownerID: owner.rawValue, display: display, layer: owner.layer,
                                       requestedAt: now, deadline: now.adding(lifetime),
                                       containsPrivateContent: owner == .authorization)
        switch coordinator.acquire(request) {
        case .acquired(let handle):
            held[display] = (owner, handle)
            return true
        case .busy, .unavailable:
            return false
        }
    }

    func release(_ owner: Owner, on display: WS2.DisplayID) {
        guard let current = held[display], current.owner == owner else { return }
        // 先让协调器走完撤销与收尾（route 会把这一格账清掉），再兜底清一次。
        coordinator.release(current.handle, at: clock.now())
        held[display] = nil
    }

    /// 这块屏现在是谁的；没有主人返回 nil。
    func owner(of display: WS2.DisplayID) -> Owner? { held[display]?.owner }

    func isCurrent(_ owner: Owner, on display: WS2.DisplayID) -> Bool {
        guard let current = held[display], current.owner == owner else { return false }
        return coordinator.isCurrent(current.handle)
    }

    // MARK: - 提醒与持续活动

    /// 记一条提醒。返回 true 表示它现在能露面；false 表示被上面的层挡着——
    /// 这时只留一个小点，按规则以后也不重播。
    @discardableResult
    func remind(on display: WS2.DisplayID) -> Bool {
        let now = clock.now()
        coordinator.remind(on: display, at: now)
        guard let snapshot = coordinator.snapshots(at: now).first(where: { $0.display == display }) else { return false }
        return snapshot.layer == .alert
    }

    func publishOngoing(_ ids: [String], on display: WS2.DisplayID) {
        coordinator.publishOngoing(ids, on: display)
    }

    // MARK: - 屏障与采样

    /// 锁屏、睡眠、失去会话、关掉功能：清掉可见内容和输入，撤销当前租约。
    func invalidate(_ reason: WS2.LeaseRevocation) {
        // 先走屏障：撤销活跃租约、通知收尾，route 会清掉那一格；剩下的记账在这里兜底清空。
        coordinator.invalidate(reason, at: clock.now())
        held.removeAll()
    }

    func removeDisplay(_ display: WS2.DisplayID) {
        coordinator.removeDisplay(display, at: clock.now())
        held[display] = nil
    }

    /// 让协调器按当前时间结算到期与提醒；面板的秒表调用它。
    func tick() {
        _ = coordinator.snapshots(at: clock.now())
    }

    func snapshot(_ display: WS2.DisplayID) -> WS2.VisibilitySnapshot? {
        coordinator.snapshots(at: clock.now()).first { $0.display == display }
    }

    private func route(_ handle: WS2.LeaseHandle, _ reason: WS2.LeaseRevocation) {
        let owner = held[handle.display]?.owner
        held[handle.display] = nil
        guard let owner else { return }
        cancelHandler(CancelNotice(owner: owner, display: handle.display, reason: reason))
    }
}
