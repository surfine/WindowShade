import Cocoa
/// An owned app-server session's review/allow path. No shell is launched by this type.
/// `deliver` MUST synchronously admit a bounded write for THIS connection and deadline.
/// See workorders/02-审批与进程.md: a generic unbounded async closure is not a conforming writer.
///
/// 审批卡进刘海（M01）：紧凑卡经租约宿主挂进刘海；同层先来先出，只有队首露面，它有结果后下一件才出现；
/// “已允许这一次”只在这次请求的 acceptOnce 真的写出之后才写。放行仍只经授权账：一次性、绑定用途和目标。
@MainActor final class WS2CodexApprovalHost: WS2OwnedProtocolHost {
    /// 命令审批一律按 shell 算：说不清，不猜（AgentSessions.risk）。所以卡上总是“用 Touch ID 允许”。
    /// 普通风险免指纹的“允许这一次”要账本出一种不靠签名的授权，现在没有；这里不开那条路。
    static let commandRisk = AgentSessions.risk(of: .shell)
    /// 回执在卡上停留的时间，与原生认证成功后对勾停留的时间一致。
    static let receiptHold: UInt64 = 800 * WS2.Duration.millisecond
    private(set) var wire: CodexWire
    let connectionID: UUID
    private let clock: any WS2Clock
    private let island: NotchLeaseHub
    private let authentication: NotchAuthenticationController
    private let service: AuthorizationService
    private let scopeStillValid: (WS2ApprovalReview) -> Bool
    private let currentContext: () -> WS2.Context?
    private let deliver: (UUID, [Data], WS2.Instant) -> Bool
    private let closeTransport: () -> Void
    private var gate = WS2ApprovalReviewGate()
    private var reviews: [WS2.RequestID:WS2ApprovalReview] = [:]
    /// 同层排队与真回执。只有队首露面。
    private var desk = AgentApprovalDesk<WS2.RequestID>()
    private var authInFlight = false
    /// 每次放弃或开始一次放行都换一代；旧一代的认证回调一律不算。
    private var attempt: UInt64 = 0
    /// 正在调 authorize：这期间同步回来的 nil 是“这会儿用不了”，不是“没确认”。
    private var authStarting = false
    private var closed = false
    private weak var presentedView: WS2CommandReviewView?
    private var presentationTask: Task<Void,Never>?
    private var receiptTask: Task<Void,Never>?
    private var nextTask: Task<Void,Never>?
    var onEvent: ((CodexWire.Event) -> Void)?
    var onUnavailable: ((String) -> Void)?
    init(wire: CodexWire, connectionID: UUID, clock: any WS2Clock, island: NotchLeaseHub,
         authentication: NotchAuthenticationController, service: AuthorizationService? = nil,
         currentContext: @escaping () -> WS2.Context?, scopeStillValid: @escaping (WS2ApprovalReview) -> Bool,
         deliver: @escaping (UUID,[Data],WS2.Instant) -> Bool, closeTransport: @escaping () -> Void) {
        self.wire = wire; self.connectionID = connectionID; self.clock = clock; self.island = island
        self.authentication = authentication; self.service = service ?? .shared
        self.currentContext = currentContext; self.scopeStillValid = scopeStillValid; self.deliver = deliver; self.closeTransport = closeTransport
    }
    // The owned process uses THIS wire; never construct a second wire for request IDs or initialization.
    var nextDeadline: WS2.Instant? {
        (wire.pending.values.map(\.deadline) + reviews.values.map(\.deadline)).min()
    }
    func beginProtocol() throws {
        guard !closed else { throw CodexWire.Failure.closed }
        try wire.initialize(now: clock.now()); flush(deadline: clock.now().adding(WS2.Duration.second))
    }
    func startThread(cwd: String, model: String) throws {
        guard !closed else { throw CodexWire.Failure.closed }
        try wire.startThread(cwd: cwd, model: model, now: clock.now())
        flush(deadline: clock.now().adding(WS2.Duration.second))
    }
    func resumeThread(_ id: String) throws {
        guard !closed else { throw CodexWire.Failure.closed }
        try wire.resumeThread(id: id, now: clock.now()); flush(deadline: clock.now().adding(WS2.Duration.second))
    }
    func startTurn(text: String, model: String, effort: String) throws {
        guard !closed else { throw CodexWire.Failure.closed }
        try wire.startTurn(text: text, model: model, effort: effort, now: clock.now())
        flush(deadline: clock.now().adding(WS2.Duration.second))
    }
    func steer(text: String, expectedTurn: String) throws {
        guard !closed else { throw CodexWire.Failure.closed }
        try wire.steer(text: text, expectedTurnID: expectedTurn, now: clock.now())
        flush(deadline: clock.now().adding(WS2.Duration.second))
    }
    func interruptTurn() throws {
        guard !closed else { throw CodexWire.Failure.closed }
        try wire.interrupt(now: clock.now()); flush(deadline: clock.now().adding(WS2.Duration.second))
    }
    func receive(_ bytes: Data) {
        guard !closed else { return }
        do {
            let events = try wire.ingest(bytes,now:clock.now())
            for event in events {
                if case .approval(let id,let method,let params) = event {
                    // 第二件不再被拒：排到队尾，等前一件有结果后才出现。只有超过同层上限（连同正在显示的 8 件）才拒。
                    if let context = currentContext(), let thread = wire.threadID, let turn = wire.turnID,
                       let review = try? WS2ApprovalReview.command(connection:connectionID,id:id,method:method,params:params,
                            context:context,thread:thread,turn:turn,now:clock.now()), scopeStillValid(review),
                       reviews[id] == nil, reviews.count < AgentApprovalDesk<WS2.RequestID>.limit, desk.arrive(id) {
                        reviews[id] = review
                    } else {
                        // Owned app-server has no guaranteed native UI to hand off to. Decline, do not silently allow.
                        try wire.denyApproval(id)
                        onUnavailable?(WSL10n.text("agent.approval.cannotConfirm", zh: "这项操作无法在这里完整确认，已拒绝这次请求"))
                    }
                }
                onEvent?(event)
            }
            let removed = reviews.filter { wire.approvals[$0.key] != $0.value.params }.map(\.key)
            for id in removed where gate.current?.id != id { reviews[id] = nil; _ = desk.resolve(id, .withdrawn) }
            if let current = gate.current, !isCurrent(current) { abandonCurrent(decline:false) }
            flush(deadline:clock.now().adding(WS2.Duration.second))
            presentHead()
        } catch { invalidate() }
    }
    /// 只有队首能露面。排在后面的要等前一件有结果（允许、不允许、过期、撤回）。
    @discardableResult func present(_ id: WS2.RequestID) -> Bool {
        guard !closed, gate.current == nil, !authInFlight, receiptTask == nil, desk.head == id,
              let review = reviews[id], isCurrent(review), scopeStillValid(review),
              clock.now() < review.deadline else { return false }
        gate.replace(with:review)
        let agent = review.context.session.provider.displayName
        let summary = AgentApprovalCard.summary(of: review.visibleCommand)
        let view = WS2CommandReviewView(review:review, agent:agent, summary:summary, risk:Self.commandRisk,
                                        note:desk.note.map { AgentApprovalCard.text($0, agent:agent) },
                                        touchIDAvailable:desk.note != .touchIDUnavailable, clock:clock)
        view.confirm = { [weak self] began,sequence in self?.confirm(beganAt:began,sequence:sequence) }
        view.decline = { [weak self] in self?.deny() }
        view.handOff = { [weak self] in self?.handToTerminal() }
        guard island.show(view,ownerID:"agentReview",layer:.authorization,onDismiss:{ [weak self] _ in
            guard let self else { return }
            self.abandonCurrent(decline:true); self.scheduleNext()
        }) else { gate.clear(); return false }
        presentedView = view
        NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
            .announcement: AgentApprovalCard.announcement(agent:agent, summary:summary),
            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        presentationTask = Task { [weak self,weak view] in
            // Wait for the existing island's layout/animation completion, not an assumed fixed animation length.
            for _ in 0..<100 {
                do { try await Task.sleep(for: .milliseconds(10), clock: .suspending) } catch { return }
                guard let self, let view, self.gate.current == review, self.isCurrent(review) else { return }
                if let panel = view.window as? NotchPanel, panel.isVisible, panel.isSettledForProbe,
                   view.bounds.width > 0, view.bounds.height > 0, view.inputIsCurrent() {
                    // 只认出现之后的新一下：gate 记下出现的时刻，之前开始的按压不算（同 confirmationIsFresh）。
                    do { try self.gate.didPresent(at:self.clock.now(),after:0); view.enableConfirmation() }
                    catch { self.abandonCurrent(decline:true) }
                    return
                }
            }
            self?.abandonCurrent(decline:true)
        }
        return true
    }
    /// 队首空着就把它挂出来；露不出来（刘海被别的放行占着）就留在队里，下一次有动静时再试。
    private func presentHead() {
        while !closed, gate.current == nil, !authInFlight, receiptTask == nil, let id = desk.head {
            if let review = reviews[id], isCurrent(review), scopeStillValid(review) { _ = present(id); return }
            // 排队时失效了：不再出现。还挂在线上的，照过期的规矩拒掉，不悄悄放着。
            reviews[id] = nil; _ = desk.resolve(id, .expired)
            if wire.approvals[id] != nil { try? wire.denyApproval(id); flush(deadline:clock.now().adding(WS2.Duration.second)) }
        }
    }
    /// 从回调里接下一件：等这一轮展示仲裁收完尾再挂，不在别人的转换里申请。
    private func scheduleNext() {
        guard !closed, nextTask == nil else { return }
        nextTask = Task { [weak self] in
            guard let self else { return }
            self.nextTask = nil; self.presentHead()
        }
    }
    private func confirm(beganAt: WS2.Instant, sequence: UInt64) {
        guard let review = gate.current, isCurrent(review), scopeStillValid(review) else { abandonCurrent(decline:true); return }
        do { try gate.beginConfirmation(beganAt:beganAt,sequence:sequence,now:clock.now(),current:review,
                                        unlocked:service.lockState() == .unlocked) }
        catch { return }
        guard let target = try? target(review) else { abandonCurrent(decline:true); return }
        guard authentication.canAuthorize else {
            // 用不了就说用不了，并给“在终端里处理”的退路；不降成点一下就放行。
            if let receipt = desk.resolve(review.id, .touchIDUnavailable) {
                presentedView?.touchIDUnavailable(AgentApprovalCard.text(receipt, agent:review.context.session.provider.displayName))
            }
            return
        }
        guard desk.beginAllowing(review.id) else { return }
        presentationTask?.cancel(); presentationTask = nil
        guard let view = presentedView, island.handOffToAuthorization(ifShowing:view) else {
            abandonCurrent(decline:true); return
        }
        presentedView = nil; authInFlight = true
        attempt &+= 1; let mine = attempt
        authStarting = true; defer { authStarting = false }
        authentication.authorize(target, whenGone: { [weak self] in self?.scheduleNext() }) { [weak self] grant in
            guard let self, self.attempt == mine else { return }
            self.authInFlight = false
            let agent = review.context.session.provider.displayName
            guard let grant else {
                // 取消、超时、指纹不符：请求还在，卡带着这句回来，要重新按一下。同步回来的是这会儿用不了。
                // 等的时候失效了：交给 presentHead 按排队失效的规矩拿掉。
                self.gate.clear()
                if self.isCurrent(review), self.reviews[review.id] != nil {
                    _ = self.desk.resolve(review.id, self.authStarting ? .touchIDUnavailable : .notConfirmed)
                }
                self.scheduleNext(); return
            }
            guard self.isCurrent(review), self.scopeStillValid(review),
                  self.gate.mayConsume(current:review,now:self.clock.now(),unlocked:self.service.lockState() == .unlocked),
                  let actualTarget = try? self.target(review) else {
                self.abandonCurrent(decline:true)
                self.authentication.showReceipt(AgentApprovalCard.text(.denied, agent:agent), succeeded:false); return
            }
            // This call consumes a genuine ledger grant against the exact immutable request. Never replace with a Bool.
            guard self.service.consume(grant,purpose:.approveAgentAction,currentTarget:actualTarget) == nil else {
                self.abandonCurrent(decline:true)
                self.authentication.showReceipt(AgentApprovalCard.text(.denied, agent:agent), succeeded:false); return
            }
            // No await or delayed animation lies between recheck, consume and response admission.
            do {
                try self.wire.enqueueApprovalResponse(review.id,expectedMethod:review.method,expectedParams:review.params,decision:.acceptOnce)
                self.reviews[review.id] = nil; self.gate.clear()
                self.flush(deadline:min(review.deadline,self.clock.now().adding(WS2.Duration.second)))
                // 真回执：这次请求的应答已被有界写入接收。写不出去时连接已断，不写“已允许”。
                let outcome: AgentApprovalDesk<WS2.RequestID>.Outcome = self.closed ? .notDelivered : .delivered
                if let receipt = self.desk.resolve(review.id, outcome) {
                    self.authentication.showReceipt(AgentApprovalCard.text(receipt, agent:agent), succeeded:receipt == .allowedOnce)
                }
            } catch {
                if let receipt = self.desk.resolve(review.id, .notDelivered) {
                    self.authentication.showReceipt(AgentApprovalCard.text(receipt, agent:agent), succeeded:false)
                }
                self.invalidate() // consumed grants and ambiguous writes never get retried
            }
        }
    }
    /// 不允许：立刻拒，卡上写“没有允许”，停一下再收走，然后下一件。
    private func deny() {
        guard let review = gate.current, let view = presentedView, !authInFlight, desk.head == review.id else { return }
        gate.clear(); presentationTask?.cancel(); presentationTask = nil
        reviews[review.id] = nil
        let receipt = desk.resolve(review.id, .denied)
        try? wire.denyApproval(review.id); flush(deadline:clock.now().adding(WS2.Duration.second))
        guard !closed, let receipt else { return }
        view.showReceipt(AgentApprovalCard.text(receipt, agent:review.context.session.provider.displayName))
        receiptTask = Task { [weak self, weak view] in
            do { try await Task.sleep(for: .nanoseconds(Self.receiptHold), clock: .suspending) } catch { return }
            guard let self else { return }
            self.receiptTask = nil
            if let view, self.presentedView === view { self.presentedView = nil; self.island.dismiss(ifShowing:view) }
            self.presentHead()
        }
    }
    /// Touch ID 用不了时的退路：卡收走，这件留给助手自己的界面，到期仍按原规矩拒。轮下一件。
    private func handToTerminal() {
        guard let review = gate.current, let view = presentedView, !authInFlight, desk.head == review.id,
              desk.note == .touchIDUnavailable else { return }
        gate.clear(); presentationTask?.cancel(); presentationTask = nil
        _ = desk.resolve(review.id, .withdrawn)
        presentedView = nil; island.dismiss(ifShowing:view)
        presentHead()
    }
    private func target(_ review: WS2ApprovalReview) throws -> AuthTarget {
        // 助手名和命令摘要跟请求一起进目标：刘海那一行、系统认证理由都由它生成，写的就是要放行的这件。
        .init(purpose:.approveAgentAction,kind:"agent.command.once.v1",fields:[
            .init(name:"review",value:Array(try review.targetBytes())),
            .init(name:"agent",value:Array(review.context.session.provider.displayName.utf8)),
            .init(name:"summary",value:Array(AgentApprovalCard.summary(of:review.visibleCommand).utf8))])
    }
    private func isCurrent(_ review: WS2ApprovalReview) -> Bool {
        !closed && review.connection == connectionID && currentContext() == review.context && wire.state == .ready &&
        wire.threadID == review.thread && wire.turnID == review.turn && wire.approvals[review.id] == review.params &&
        wire.approvalMethods[review.id] == review.method && clock.now() < review.deadline
    }
    func tick() {
        guard !closed else { return }
        _ = wire.tick(now:clock.now())
        if wire.state == .closed { invalidate(); return }
        for id in reviews.filter({ clock.now() >= $0.value.deadline }).map(\.key) {
            try? wire.denyApproval(id); reviews[id] = nil
            if gate.current?.id == id { abandonCurrent(decline:false) } else { _ = desk.resolve(id, .expired) }
        }
        flush(deadline:clock.now().adding(WS2.Duration.second))
        presentHead()
    }
    private func flush(deadline: WS2.Instant) {
        let frames = wire.drain(); guard !frames.isEmpty else { return }
        if clock.now() >= deadline || !deliver(connectionID,frames,deadline) { invalidate() }
    }
    private func abandonCurrent(decline: Bool) {
        let id = gate.current?.id, oldView = presentedView
        presentedView = nil; attempt &+= 1
        gate.clear(); presentationTask?.cancel(); presentationTask = nil
        receiptTask?.cancel(); receiptTask = nil
        // Clearing first prevents a cancel callback from recursively declining the same request.
        if authInFlight { authInFlight = false; authentication.cancel() }
        if let oldView { island.dismiss(ifShowing:oldView) }
        if let id {
            reviews[id] = nil; _ = desk.resolve(id, decline ? .denied : .withdrawn)
            if decline { try? wire.denyApproval(id); flush(deadline:clock.now().adding(WS2.Duration.second)) }
        }
    }
    func invalidate() {
        guard !closed else { return }; closed = true
        nextTask?.cancel(); nextTask = nil
        abandonCurrent(decline:false); reviews.removeAll(); desk = AgentApprovalDesk(); wire.close(); closeTransport()
    }
}

@MainActor private final class WS2ReviewButton: NSButton {
    let clock: any WS2Clock
    private var sequence: UInt64 = 0
    private var press: (WS2.Instant,UInt64)?
    var freshAction: ((WS2.Instant,UInt64)->Void)?
    init(clock: any WS2Clock, title: String) {
        self.clock = clock; super.init(frame:.zero); self.title = title
        target = self; action = #selector(fire)
    }
    required init?(coder:NSCoder) { nil }
    private func begin() -> Bool {
        guard isEnabled, sequence < .max else { return false }; sequence += 1; press = (clock.now(),sequence); return true
    }
    override func mouseDown(with event:NSEvent) { guard begin() else { return }; defer { press = nil }; super.mouseDown(with:event) }
    override func keyDown(with event:NSEvent) {
        guard !event.isARepeat, [" ","\r"].contains(event.charactersIgnoringModifiers ?? ""),begin() else { super.keyDown(with:event);return }
        defer { press = nil }; super.keyDown(with:event)
    }
    override func accessibilityPerformPress() -> Bool {
        guard begin() else { return false }; defer { press = nil }; performClick(nil); return true
    }
    @objc private func fire() { guard let press else { return }; freshAction?(press.0,press.1) }
}

/// 刘海里的审批卡。比例照稿“零件 · 放行”的 210×58；左耳终端符号，右耳琥珀色“等你”。
/// 主句“想执行 …”，副句“助手 · 项目”；完整命令、工作目录、线程放进“去看看”，不在卡面上铺开。
@MainActor final class WS2CommandReviewView: NSView, WS2LeaseContent {
    static let compactSize = NSSize(width:380, height:105)
    static let expandedSize = NSSize(width:380, height:240)
    var onCancel: (() -> Void)?
    var inputIsCurrent: (() -> Bool) = { false }
    var interactionSize: NSSize { showsDetails ? Self.expandedSize : Self.compactSize }
    var confirm: ((WS2.Instant,UInt64)->Void)?
    var decline: (() -> Void)?
    var handOff: (() -> Void)?
    private(set) var showsDetails = false
    private(set) var buttonKinds: [AgentApprovalCard.Button]
    private let ear = NSImageView()
    private let waiting = NSTextField(labelWithString: AgentApprovalCard.waiting)
    private let headline: NSTextField
    private let byline: NSTextField
    private let detailsScroll = NSScrollView()
    private let details = NSTextView()
    private let look: NSButton
    private let no: NSButton
    private var primary: NSButton
    private let approval: WS2ReviewButton
    private let terminal: NSButton
    init(review: WS2ApprovalReview, agent: String, summary: String, risk: WS2.Risk, note: String?,
         touchIDAvailable: Bool, clock: any WS2Clock) {
        buttonKinds = AgentApprovalCard.buttons(for:risk, touchIDAvailable:touchIDAvailable)
        headline = NSTextField(labelWithString: AgentApprovalCard.headline(summary:summary))
        let project = WS2ApprovalReview.visible((review.cwd as NSString).lastPathComponent)
        byline = NSTextField(labelWithString: note ?? AgentApprovalCard.byline(agent:agent, project:project))
        look = NSButton(title:AgentApprovalCard.title(.look), target:nil, action:nil)
        no = NSButton(title:AgentApprovalCard.title(.deny), target:nil, action:nil)
        approval = WS2ReviewButton(clock:clock, title:AgentApprovalCard.title(AgentApprovalCard.needsTouchID(risk) ? .allowWithTouchID : .allowOnce))
        terminal = NSButton(title:AgentApprovalCard.title(.handleInTerminal), target:nil, action:nil)
        primary = touchIDAvailable || !AgentApprovalCard.needsTouchID(risk) ? approval : terminal
        super.init(frame:.zero)
        wantsLayer = true; appearance = NSAppearance(named:.darkAqua)
        ear.image = NSImage(systemSymbolName:"terminal", accessibilityDescription:nil)
        ear.contentTintColor = .white; ear.symbolConfiguration = .init(pointSize:13, weight:.semibold)
        waiting.font = .systemFont(ofSize:11, weight:.semibold); waiting.textColor = .systemOrange; waiting.alignment = .right
        headline.font = .systemFont(ofSize:13, weight:.semibold); headline.textColor = .white
        headline.lineBreakMode = .byTruncatingTail; headline.maximumNumberOfLines = 1
        byline.font = .systemFont(ofSize:11); byline.textColor = .white.withAlphaComponent(0.65)
        byline.lineBreakMode = .byTruncatingTail; byline.maximumNumberOfLines = 1
        details.isEditable = false; details.isSelectable = true; details.isRichText = false
        details.drawsBackground = false; details.textColor = .white.withAlphaComponent(0.85)
        details.font = .monospacedSystemFont(ofSize:11, weight:.regular)
        let labels = WS2ApprovalLabels()
        details.string = labels.command + "\n" + review.visibleCommand + "\n\n" + labels.workingDirectory + "\n"
            + WS2ApprovalReview.visible(review.cwd)
            + "\n\n" + labels.thread(review.thread) + " · " + labels.turn(review.turn)
        details.textContainer?.widthTracksTextView = true; details.isHorizontallyResizable = false; details.isVerticallyResizable = true
        details.minSize = .zero; details.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude, height:CGFloat.greatestFiniteMagnitude)
        details.autoresizingMask = [.width]
        detailsScroll.hasVerticalScroller = true; detailsScroll.drawsBackground = false; detailsScroll.borderType = .noBorder
        detailsScroll.documentView = details; detailsScroll.isHidden = true
        for (button, isPrimary) in [(look, false), (no, false), (approval, true), (terminal, true)] as [(NSButton, Bool)] { Self.style(button, primary:isPrimary) }
        look.target = self; look.action = #selector(toggleDetails)
        no.target = self; no.action = #selector(refuse)
        terminal.target = self; terminal.action = #selector(handToTerminal)
        approval.isEnabled = false
        approval.freshAction = { [weak self] began,sequence in guard let self,self.inputIsCurrent() else{return};self.confirm?(began,sequence) }
        for view in [ear, waiting, headline, byline, detailsScroll, look, no, primary] as [NSView] { addSubview(view) }
        setAccessibilityRole(.group)
        setAccessibilityLabel(AgentApprovalCard.announcement(agent:agent, summary:summary))
    }
    required init?(coder:NSCoder){nil}
    private static func style(_ button: NSButton, primary: Bool) {
        button.isBordered = false; button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.backgroundColor = (primary ? NSColor.white : NSColor.white.withAlphaComponent(0.16)).cgColor
        button.attributedTitle = NSAttributedString(string:button.title, attributes:[
            .font: NSFont.systemFont(ofSize:12, weight:.semibold),
            .foregroundColor: primary ? NSColor.black : NSColor.white])
    }
    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height, inset: CGFloat = 16
        ear.frame = NSRect(x:inset, y:h - 32, width:18, height:18)
        waiting.frame = NSRect(x:w - inset - 48, y:h - 31, width:48, height:16)
        headline.frame = NSRect(x:inset + 26, y:h - 32, width:max(0, w - 2 * inset - 26 - 54), height:18)
        byline.frame = NSRect(x:inset + 26, y:h - 50, width:max(0, w - 2 * inset - 26), height:15)
        var x = w - inset
        for button in [primary, no, look] where !button.isHidden {
            let width = ceil(button.attributedTitle.size().width) + 20
            x -= width; button.frame = NSRect(x:x, y:12, width:width, height:24); x -= 8
        }
        detailsScroll.frame = NSRect(x:inset, y:44, width:max(0, w - 2 * inset), height:max(0, h - 44 - 58))
    }
    func enableConfirmation(){approval.isEnabled=inputIsCurrent()}
    /// 回执写在副句的位置，按钮收起来，念一遍。
    func showReceipt(_ text: String) {
        byline.stringValue = text; byline.textColor = .white
        for button in [look, no, primary] { button.isHidden = true }
        approval.isEnabled = false; confirm = nil; decline = nil; handOff = nil
        needsLayout = true
        NSAccessibility.post(element:self, notification:.announcementRequested,
                             userInfo:[.announcement:text, .priority:NSAccessibilityPriorityLevel.medium.rawValue])
    }
    /// Touch ID 这会儿用不了：说清楚，主按钮换成“在终端里处理”。
    func touchIDUnavailable(_ text: String) {
        byline.stringValue = text
        guard primary !== terminal else { return }
        approval.isEnabled = false; primary.removeFromSuperview(); primary = terminal; addSubview(terminal)
        buttonKinds = buttonKinds.map { $0 == .allowWithTouchID ? .handleInTerminal : $0 }
        needsLayout = true
        NSAccessibility.post(element:self, notification:.announcementRequested,
                             userInfo:[.announcement:text, .priority:NSAccessibilityPriorityLevel.high.rawValue])
    }
    func revoke(){
        inputIsCurrent = { false };approval.isEnabled=false;details.string="";headline.stringValue="";byline.stringValue=""
        confirm=nil;decline=nil;handOff=nil
    }
    @objc private func refuse(){guard inputIsCurrent() else{return};decline?()}
    @objc private func handToTerminal(){guard inputIsCurrent() else{return};handOff?()}
    /// “去看看”：在同一份租约里把卡拉高，露出完整命令、工作目录和线程。
    @objc private func toggleDetails(){
        guard inputIsCurrent() else { return }
        showsDetails.toggle(); detailsScroll.isHidden = !showsDetails; needsLayout = true
        // 岛按内容报的尺寸量高度：让承载它的面板按新尺寸再摆一次。不换主人，不换租约。
        if let panel = window as? NotchPanel, panel.isShowingInteraction(self) { panel.setInteraction(self, animated:true) }
    }
    override func cancelOperation(_ sender:Any?){onCancel?()}
}

// Uses the same wire and bounded writer as native command reviews.
extension WS2CodexApprovalHost {
    func account(_ action:WS2AccountAction) throws -> WS2.RequestID {
        guard !closed else { throw CodexWire.Failure.closed };let id:WS2.RequestID
        switch action {
        case .config(let cwd):id=try wire.readConfig(cwd:cwd,now:clock.now())
        case .read:id=try wire.readAccount(now:clock.now())
        case .login:id=try wire.beginBrowserLogin(now:clock.now())
        case .cancel(let login):id=try wire.cancelLogin(id:login,now:clock.now())
        case .logout:id=try wire.logout(now:clock.now())
        }
        flush(deadline:clock.now().adding(WS2.Duration.second));return id
    }
}


/// 审批详情里的几行标签（第33批：走目录）。
struct WS2ApprovalLabels {
    var command: String { WSL10n.text("agent.approval.command", zh: "命令") }
    var workingDirectory: String { WSL10n.text("agent.approval.cwd", zh: "工作目录") }
    func thread(_ value: String) -> String { WSL10n.text("agent.approval.thread", zh: "线程 %@", WS2ApprovalReview.visible(value)) }
    func turn(_ value: String) -> String { WSL10n.text("agent.approval.turn", zh: "轮次 %@", WS2ApprovalReview.visible(value)) }
}
