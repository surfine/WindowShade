import Cocoa

/// 由共享岛承载的具体视图：会话、指挥、审批卡、番茄钟卡片都实现它。
/// 尺寸由视图自己报，岛按它算高度；租约被撤销时先 `revoke()` 再换 UI。
@MainActor protocol WS2LeaseContent: NotchInteractiveContent {
    var inputIsCurrent: (() -> Bool) { get set }
    var interactionSize: NSSize { get }
    func revoke()
}

/// 刘海唯一的展示仲裁：一块屏同一时刻只有一个主人。
///
/// 协调器只做准入与撤销；视图怎么收尾由 `cancel` 闭包同步完成，收尾做完协调器才发布新租约。
/// 展示租约不是授权账：它只决定谁在刘海里露面，不能批准任何动作。
@MainActor
final class NotchLeaseHub {
    /// 编译期登记的主人表。层与协调器里的 permits 表一致，不接受表外的名字。
    enum Owner: String {
        case authorization, conductor, notchShelf, launchpad, windowBrowser, pomodoro
        case agentSessions, agentReview

        var layer: WS2.Layer {
            switch self {
            case .authorization, .agentReview: return .authorization
            case .conductor: return .interaction
            case .notchShelf, .launchpad, .windowBrowser, .pomodoro, .agentSessions: return .opened
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
    private weak var controller: NotchController?
    private weak var contentPanel: NotchPanel?
    private var contentView: (NSView & WS2LeaseContent)?
    private var contentHandle: WS2.LeaseHandle?
    private var contentDismissed: ((WS2.LeaseRevocation) -> Void)?
    private var contentDeadline: Task<Void, Never>?
    private var authHandle: WS2.LeaseHandle?

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

    /// 接上宿主：内容型展示要知道用哪块屏，授权层要把租约交给认证控制器。
    func attach(controller: NotchController) {
        self.controller = controller
        controller.authentication.acquireInteraction = { [weak self] panel in
            self?.beginAuthorization(on: panel) ?? false
        }
        controller.authentication.releaseInteraction = { [weak self] in self?.endAuthorization() }
        controller.authentication.isInteractionCurrent = { [weak self] in
            guard let self, let lease = self.authHandle else { return false }
            return self.coordinator.isCurrent(lease)
        }
    }

    // MARK: - 内容型展示（会话、指挥、审批卡、卡片）

    /// 显式的用户动作换掉我们自己的旧内容，但永远不换掉原生认证。
    @discardableResult
    func show(_ content: NSView & WS2LeaseContent, ownerID: String, layer: WS2.Layer = .opened,
              onDismiss: @escaping (WS2.LeaseRevocation) -> Void = { _ in }) -> Bool {
        guard !locked(), controller?.authentication.isPresenting != true,
              let panel = controller?.authenticationPanel(),
              let screen = panel.screen ?? NSScreen.main,
              let display = NotchController.displayID(screen).map({ WS2.DisplayID(value: $0) }),
              let owner = Owner(rawValue: ownerID) else { return false }
        // 由协调器原子决定换页：绝不能先关掉审阅来腾地方，申请失败时旧页必须原样留着。
        let previous = contentHandle
        let now = clock.now()
        let request = WS2.LeaseRequest(ownerID: owner.rawValue, display: display, layer: layer,
                                       requestedAt: now, deadline: now.adding(120 * WS2.Duration.second),
                                       containsPrivateContent: true)
        guard case .acquired(let lease) = coordinator.acquire(request, replacing: previous),
              coordinator.isCurrent(lease) else { return false }
        held[display] = (owner, lease)
        contentView = content; contentPanel = panel; contentHandle = lease; contentDismissed = onDismiss
        content.inputIsCurrent = { [weak self] in self?.coordinator.isCurrent(lease) == true }
        content.onCancel = { [weak self, weak content] in
            guard let content else { return }
            self?.dismiss(ifShowing: content)
        }
        panel.setInteraction(content)
        panel.makeKeyAndOrderFront(nil)
        contentDeadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 120 * WS2.Duration.second) } catch { return }
            guard let self, self.contentHandle == lease else { return }
            _ = self.coordinator.snapshots(at: self.clock.now())
        }
        return true
    }

    /// 关掉预览并且不向审批宿主报告取消：下一步交给原生认证。
    func handOffToAuthorization() { contentDismissed = nil; dismiss() }

    func dismiss() {
        guard let handle = contentHandle else { return }
        coordinator.release(handle, at: clock.now())
    }

    func dismiss(ifShowing content: NSView) {
        if contentView === content { dismiss() }
    }

    func handOffToAuthorization(ifShowing content: NSView) -> Bool {
        guard contentView === content else { return false }
        handOffToAuthorization(); return true
    }

    /// 已挂载内容当前持有的租约句柄：视图要在同一租约下路由输入时用它。
    func inputHandle(for content: NSView) -> WS2.LeaseHandle? {
        guard contentView === content, let handle = contentHandle, coordinator.isCurrent(handle) else { return nil }
        return handle
    }

    func stop() {
        invalidate(.disabled)
        controller?.authentication.acquireInteraction = nil
        controller?.authentication.releaseInteraction = nil
        controller?.authentication.isInteractionCurrent = nil
    }

    private func beginAuthorization(on panel: NotchPanel) -> Bool {
        guard !locked(), let display = panel.displayID else { return false }
        let now = clock.now()
        let request = WS2.LeaseRequest(ownerID: Owner.authorization.rawValue, display: display, layer: .authorization,
                                       requestedAt: now, deadline: now.adding(31 * WS2.Duration.second),
                                       containsPrivateContent: true)
        guard case .acquired(let lease) = coordinator.acquire(request),
              coordinator.isCurrent(lease) else { return false }
        held[display] = (.authorization, lease)
        authHandle = lease
        return true
    }

    private func endAuthorization() {
        guard let authHandle else { return }
        coordinator.release(authHandle, at: clock.now())
        self.authHandle = nil
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
        if contentHandle == handle {
            let content = contentView, panel = contentPanel, callback = contentDismissed
            contentHandle = nil; contentView = nil; contentPanel = nil; contentDismissed = nil
            contentDeadline?.cancel(); contentDeadline = nil
            content?.inputIsCurrent = { false }
            content?.revoke()
            if let content, panel?.isShowingInteraction(content) == true { panel?.setInteraction(nil) }
            callback?(reason)
        }
        if authHandle == handle {
            // 先清账：原生 cancel 会再调一次 releaseInteraction。
            authHandle = nil
            controller?.authentication.cancel(animated: false, restoreFocus: false)
        }
        let owner = held[handle.display]?.owner
        held[handle.display] = nil
        guard let owner else { return }
        cancelHandler(CancelNotice(owner: owner, display: handle.display, reason: reason))
    }
}
