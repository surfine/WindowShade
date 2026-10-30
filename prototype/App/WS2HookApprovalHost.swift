import Cocoa

/// Claude Code 的 PermissionRequest 在刘海里露面：允许这一次 / 不允许。
///
/// 允许的路径只有一条：Touch ID 验过、授权账消费成功、并且这次请求还挂着，才回 allow。
/// 卡被收走、Touch ID 用不了、或者刘海正被别的东西占着时回“{}”，让 Claude Code 在自己的终端里问；
/// 绝不替它决定。只读工具点一下就能允许，其余（shell、写入、MCP）一律要 Touch ID。
@MainActor final class WS2HookApprovalHost {
    static let agentName = "Claude Code"
    static let receiptHold: UInt64 = MotionHold.receiptDuration
    private let server: WS2HookServer
    private let island: NotchLeaseHub
    private let authentication: NotchAuthenticationController
    private let service: AuthorizationService
    private var current: WS2HookServer.PermissionAsk?
    private weak var presented: WS2HookApprovalView?
    private var authInFlight = false
    private var receiptTask: Task<Void, Never>?
    /// 每次开始/放弃一次放行都换一代；旧一代的回调不算。
    private var attempt: UInt64 = 0
    private var closed = false
    /// 换卡时故意收走旧卡：这次收走不算“人交回终端”。
    private var replacing = false

    init(server: WS2HookServer, island: NotchLeaseHub, authentication: NotchAuthenticationController,
         service: AuthorizationService = .shared) {
        self.server = server; self.island = island; self.authentication = authentication
        self.service = service
    }

    /// 只读工具：点一下“允许这一次”。其余都算说不清，要 Touch ID。
    static func risk(tool: String) -> WS2.Risk {
        ["Read", "Grep", "Glob", "LS", "NotebookRead"].contains(tool) ? .normal : .unknown
    }

    func arrive(_ ask: WS2HookServer.PermissionAsk) {
        guard !closed else { return }
        // Touch ID 正开着：这一件交回终端，不排队。
        guard !authInFlight else { server.deferToHost(sessionID: ask.sessionID); return }
        if current == ask, presented != nil { return }
        // 同一会话又来了下一次（上一件在终端里处理掉了）：换掉旧卡，旧连接由 listener 自己收尾。
        receiptTask?.cancel(); receiptTask = nil
        replacing = true
        dismissCard()
        replacing = false
        current = ask
        present()
    }

    /// 这一次“等你”在别处有结果了（终端里处理掉了、过期）：卡收走，不再留着。
    func statusChanged(sessionID: String, status: AgentSessions.Status) {
        guard let ask = current, ask.sessionID == sessionID, status != .waiting else { return }
        current = nil
        dismissCard()
    }

    /// 关掉编程会话开关时调用：卡收走，连接由服务端关闭。
    func invalidate() {
        guard !closed else { return }
        closed = true
        attempt &+= 1
        receiptTask?.cancel(); receiptTask = nil
        authInFlight = false
        current = nil
        replacing = true
        dismissCard()
        replacing = false
    }

    private func present() {
        guard !closed, let ask = current, presented == nil, receiptTask == nil else { return }
        let tool = ask.tool.isEmpty ? "tool" : ask.tool
        let risk = Self.risk(tool: tool)
        let touchIDAvailable = authentication.canAuthorize
        let view = WS2HookApprovalView(tool: tool, project: ask.project, risk: risk,
                                       touchIDAvailable: touchIDAvailable)
        view.allow = { [weak self] in self?.allow() }
        view.deny = { [weak self] in self?.deny() }
        view.useTerminal = { [weak self] in self?.deferToHost() }
        guard island.show(view, ownerID: "agentReview", layer: .authorization, onDismiss: { [weak self] _ in
            self?.dismissed()
        }) else {
            // 刘海正被别的东西占着：不抢，交回终端。
            current = nil
            server.deferToHost(sessionID: ask.sessionID)
            return
        }
        presented = view
        NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
            .announcement: AgentApprovalCard.announcement(agent: Self.agentName, summary: tool),
            .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// 允许这一次。高风险先过 Touch ID；验过了再消费一次性授权，最后才回 allow。
    private func allow() {
        guard !closed, let ask = current, let view = presented, !authInFlight,
              view.inputIsCurrent() else { return }
        guard authentication.canAuthorize else { deferToHost(); return }
        let target = AuthTarget(purpose: .approveAgentAction, kind: "agent.hook.once.v1", fields: [
            .init(name: "session", value: Array(ask.sessionID.utf8)),
            .init(name: "tool", value: Array(ask.tool.utf8)),
            .init(name: "request", value: Array(ask.digest)),
        ])
        attempt &+= 1; let mine = attempt
        authInFlight = true
        guard island.handOffToAuthorization(ifShowing: view) else {
            authInFlight = false
            deferToHost()
            return
        }
        presented = nil
        authentication.authorize(target, whenGone: { [weak self] in self?.authorizationGone() }) { [weak self] grant in
            guard let self, self.attempt == mine else { return }
            self.authInFlight = false
            guard let grant else {
                // 取消、超时、指纹不符：不降成点一下放行，交回终端。
                self.current = nil
                self.server.deferToHost(sessionID: ask.sessionID)
                return
            }
            guard self.server.isWaiting(sessionID: ask.sessionID),
                  self.service.consume(grant, purpose: .approveAgentAction, currentTarget: target) == nil else {
                self.current = nil
                self.server.deferToHost(sessionID: ask.sessionID)
                self.authentication.showReceipt(AgentApprovalCard.text(.notConfirmed, agent: Self.agentName), succeeded: false)
                return
            }
            guard self.server.decide(sessionID: ask.sessionID, allow: true, completion: { sent in
                Task { @MainActor in
                    self.current = nil
                    self.authentication.showReceipt(AgentApprovalCard.text(sent ? .allowedOnce : .notDelivered,
                                                                           agent: Self.agentName), succeeded: sent)
                }
            }) else {
                self.current = nil
                self.server.deferToHost(sessionID: ask.sessionID)
                self.authentication.showReceipt(AgentApprovalCard.text(.notConfirmed, agent: Self.agentName), succeeded: false)
                return
            }
        }
    }

    /// 不允许：立即回 deny，卡上写“没有允许”，停一下再收走。
    private func deny() {
        guard !closed, let ask = current, let view = presented, !authInFlight,
              view.inputIsCurrent() else { return }
        current = nil
        guard server.decide(sessionID: ask.sessionID, allow: false) else {
            presented = nil
            island.dismiss(ifShowing: view)
            return
        }
        view.showReceipt(AgentApprovalCard.text(.denied, agent: Self.agentName))
        receiptTask = Task { [weak self, weak view] in
            do { try await Task.sleep(for: .nanoseconds(Self.receiptHold), clock: .suspending) } catch { return }
            guard let self else { return }
            self.receiptTask = nil
            if let view, self.presented === view { self.presented = nil; self.island.dismiss(ifShowing: view) }
            self.present()
        }
    }

    /// 交回 Claude Code 自己的终端：回“{}”，不替它决定。
    private func deferToHost() {
        guard let ask = current else { return }
        current = nil
        let view = presented
        presented = nil
        server.deferToHost(sessionID: ask.sessionID)
        if let view { island.dismiss(ifShowing: view) }
    }

    /// 卡被岛收走（Esc、换页、锁屏）：等同交回终端。
    private func dismissed() {
        guard !closed, !replacing, let ask = current else { return }
        current = nil
        server.deferToHost(sessionID: ask.sessionID)
    }

    /// Touch ID 的画面离开了：没有别的排队项，什么都不用接。
    private func authorizationGone() {}

    private func dismissCard() {
        guard let view = presented else { return }
        presented = nil
        island.dismiss(ifShowing: view)
    }

    // 页面级探针：只在 --hook-approval-probe 里用。
    var probePresented: WS2HookApprovalView? { presented }
    func probeDismiss() { dismissCard() }
}

/// 刘海里的 hook 审批卡。尺寸和摆法照稿《刘海里的编程会话》§3：408 宽、压进岛的上限；
/// 只写四件事（哪个助手、哪个项目、要做什么、风险），内容从右耳的琥珀点长出来。放行逻辑不在这里。
@MainActor final class WS2HookApprovalView: NSView, WS2LeaseContent {
    static let size = NSSize(width: SessionCardStyle.cardSize.width, height: SessionCardStyle.cardSize.height)
    var onCancel: (() -> Void)?
    var inputIsCurrent: (() -> Bool) = { false }
    var interactionSize: NSSize { Self.size }
    var allow: (() -> Void)?
    var deny: (() -> Void)?
    var useTerminal: (() -> Void)?
    /// 琥珀点在卡里的位置（卡的坐标）；不传就用右耳那颗点的中心。
    var bloomOrigin: CGPoint?
    private let content = NSView()
    private let bloom = WS2SessionCardChrome.Bloom()
    private let headline: NSTextField
    private let byline: NSTextField
    private let waiting = NSTextField(labelWithString: AgentApprovalCard.waiting)
    private let dot = WS2SessionCardChrome.makeAmberDot()
    private let ear = WS2SessionCardChrome.makeEar()
    private let riskLine: WS2SessionCardChrome.RiskLine?
    private let no: NSButton
    private let primary: NSButton
    private let primaryIsTerminal: Bool

    init(tool: String, project: String, risk: WS2.Risk, touchIDAvailable: Bool) {
        let needsTouchID = AgentApprovalCard.needsTouchID(risk)
        let terminal = needsTouchID && !touchIDAvailable
        primaryIsTerminal = terminal
        headline = NSTextField(labelWithString: AgentApprovalCard.headline(summary: tool))
        byline = NSTextField(labelWithString: AgentApprovalCard.byline(agent: WS2HookApprovalHost.agentName,
                                                                       project: project))
        riskLine = AgentApprovalCard.riskNote(risk).map { WS2SessionCardChrome.RiskLine(note: $0) }
        no = NSButton(title: AgentApprovalCard.title(.deny), target: nil, action: nil)
        primary = NSButton(title: AgentApprovalCard.title(
            terminal ? .handleInTerminal : (needsTouchID ? .allowWithTouchID : .allowOnce)),
            target: nil, action: nil)
        super.init(frame: .zero)
        wantsLayer = true; appearance = NSAppearance(named: .darkAqua)
        content.wantsLayer = true
        waiting.font = .systemFont(ofSize: 11, weight: .semibold)
        waiting.textColor = .systemOrange; waiting.alignment = .right
        headline.font = .systemFont(ofSize: 13, weight: .semibold); headline.textColor = .white
        headline.lineBreakMode = .byTruncatingTail; headline.maximumNumberOfLines = 1
        byline.font = .systemFont(ofSize: 11); byline.textColor = .white.withAlphaComponent(0.65)
        byline.lineBreakMode = .byTruncatingTail; byline.maximumNumberOfLines = 1
        WS2SessionCardChrome.stylePill(no, primary: false)
        WS2SessionCardChrome.stylePill(primary, primary: true,
                                       symbol: needsTouchID && !terminal ? "touchid" : nil)
        addSubview(content)
        var parts: [NSView] = [ear, dot, waiting, headline, byline, no, primary]
        if let riskLine { parts.append(riskLine) }
        for view in parts { content.addSubview(view) }
        no.target = self; no.action = #selector(refuse)
        primary.target = self; primary.action = #selector(act)
        setAccessibilityRole(.group)
        setAccessibilityLabel(AgentApprovalCard.announcement(agent: WS2HookApprovalHost.agentName, summary: tool))
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        content.frame = bounds
        let frames = SessionCardStyle.layout(in: bounds.size, showsRisk: riskLine != nil, showsDetails: false)
        ear.frame = frames.ear; dot.frame = frames.dot; waiting.frame = frames.waiting
        headline.frame = frames.headline; byline.frame = frames.byline
        if let risk = frames.risk { riskLine?.frame = risk }
        WS2SessionCardChrome.layoutPills([primary, no], rightEdge: bounds.width - SessionCardStyle.inset)
        if window != nil {
            bloom.playOnce(on: content, origin: SessionCardStyle.bloomOrigin(layout: frames, override: bloomOrigin))
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { needsLayout = true }
    }

    func showReceipt(_ text: String) {
        byline.stringValue = text; byline.textColor = .white
        no.isHidden = true; primary.isHidden = true; riskLine?.isHidden = true
        allow = nil; deny = nil; useTerminal = nil
        needsLayout = true
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    func revoke() {
        inputIsCurrent = { false }
        allow = nil; deny = nil; useTerminal = nil
    }

    var probePrimaryTitle: String { primary.title }
    var probeHeadline: String { headline.stringValue }

    @objc private func refuse() { guard inputIsCurrent() else { return }; deny?() }
    @objc private func act() {
        guard inputIsCurrent() else { return }
        if primaryIsTerminal { useTerminal?() } else { allow?() }
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
