import Cocoa
/// An owned app-server session's review/allow path. No shell is launched by this type.
/// `deliver` MUST synchronously admit a bounded write for THIS connection and deadline.
/// See workorders/02-审批与进程.md: a generic unbounded async closure is not a conforming writer.
@MainActor final class WS2CodexApprovalHost {
    private(set) var wire: CodexWire
    let connectionID: UUID
    private let clock: any WS2Clock
    private let island: WS2IslandCoordinator
    private let authentication: NotchAuthenticationController
    private let service: AuthorizationService
    private let scopeStillValid: (WS2ApprovalReview) -> Bool
    private let currentContext: () -> WS2.Context?
    private let deliver: (UUID, [Data], WS2.Instant) -> Bool
    private let closeTransport: () -> Void
    private var gate = WS2ApprovalReviewGate()
    private var reviews: [WS2.RequestID:WS2ApprovalReview] = [:]
    private var authInFlight = false
    private var closed = false
    private weak var presentedView: WS2CommandReviewView?
    private var presentationTask: Task<Void,Never>?
    var onEvent: ((CodexWire.Event) -> Void)?
    var onUnavailable: ((String) -> Void)?
    init(wire: CodexWire, connectionID: UUID, clock: any WS2Clock, island: WS2IslandCoordinator,
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
                    if let context = currentContext(), let thread = wire.threadID, let turn = wire.turnID,
                       let review = try? WS2ApprovalReview.command(connection:connectionID,id:id,method:method,params:params,
                            context:context,thread:thread,turn:turn,now:clock.now()), scopeStillValid(review), reviews.count < 8 {
                        reviews[id] = review
                    } else {
                        // Owned app-server has no guaranteed native UI to hand off to. Decline, do not silently allow.
                        try wire.denyApproval(id)
                        onUnavailable?("这项操作无法在这里完整确认，已拒绝这次请求")
                    }
                }
                onEvent?(event)
            }
            let removed = reviews.filter { wire.approvals[$0.key] != $0.value.params }.map(\.key)
            for id in removed { reviews[id] = nil }
            if let current = gate.current, !isCurrent(current) { abandonCurrent(decline:false) }
            flush(deadline:clock.now().adding(WS2.Duration.second))
        } catch { invalidate() }
    }
    @discardableResult func present(_ id: WS2.RequestID) -> Bool {
        guard !closed, gate.current == nil, let review = reviews[id], isCurrent(review), scopeStillValid(review),
              clock.now() < review.deadline else { return false }
        gate.replace(with:review)
        let view = WS2CommandReviewView(review:review,clock:clock)
        view.confirm = { [weak self] began,sequence in self?.confirm(beganAt:began,sequence:sequence) }
        view.decline = { [weak self] in self?.abandonCurrent(decline:true) }
        guard island.show(view,ownerID:"agentReview",layer:.authorization,onDismiss:{ [weak self] _ in
            self?.abandonCurrent(decline:true)
        }) else { gate.clear(); return false }
        presentedView = view
        presentationTask = Task { [weak self,weak view] in
            // Wait for the existing island's layout/animation completion, not an assumed fixed animation length.
            for _ in 0..<100 {
                do { try await Task.sleep(nanoseconds:10_000_000) } catch { return }
                guard let self, let view, self.gate.current == review, self.isCurrent(review) else { return }
                if let panel = view.window as? NotchPanel, panel.isVisible, panel.isSettledForProbe,
                   view.bounds.width > 0, view.bounds.height > 0, view.inputIsCurrent() {
                    do { try self.gate.didPresent(at:self.clock.now(),after:0); view.enableConfirmation() }
                    catch { self.abandonCurrent(decline:true) }
                    return
                }
            }
            self?.abandonCurrent(decline:true)
        }
        return true
    }
    private func confirm(beganAt: WS2.Instant, sequence: UInt64) {
        guard let review = gate.current, isCurrent(review), scopeStillValid(review) else { abandonCurrent(decline:true); return }
        do { try gate.beginConfirmation(beganAt:beganAt,sequence:sequence,now:clock.now(),current:review,
                                        unlocked:service.lockState() == .unlocked) }
        catch { return }
        guard let target = try? target(review) else { abandonCurrent(decline:true); return }
        presentationTask?.cancel(); presentationTask = nil
        guard let view = presentedView, island.handOffToAuthorization(ifShowing:view) else {
            abandonCurrent(decline:true); return
        }
        presentedView = nil; authInFlight = true
        authentication.authorize(target) { [weak self] grant in
            guard let self else { return }; self.authInFlight = false
            guard let grant, self.isCurrent(review), self.scopeStillValid(review),
                  self.gate.mayConsume(current:review,now:self.clock.now(),unlocked:self.service.lockState() == .unlocked),
                  let actualTarget = try? self.target(review) else { self.abandonCurrent(decline:true); return }
            // This call consumes a genuine ledger grant against the exact immutable request. Never replace with a Bool.
            guard self.service.consume(grant,purpose:.approveAgentAction,currentTarget:actualTarget) == nil else {
                self.abandonCurrent(decline:true); return
            }
            // No await or delayed animation lies between recheck, consume and response admission.
            do {
                try self.wire.enqueueApprovalResponse(review.id,expectedMethod:review.method,expectedParams:review.params,decision:.acceptOnce)
                self.reviews[review.id] = nil; self.gate.clear()
                self.flush(deadline:min(review.deadline,self.clock.now().adding(WS2.Duration.second)))
            } catch { self.invalidate() } // consumed grants and ambiguous writes never get retried
        }
    }
    private func target(_ review: WS2ApprovalReview) throws -> AuthTarget {
        .init(purpose:.approveAgentAction,kind:"agent.command.once.v1",fields:[.init(name:"review",value:Array(try review.targetBytes()))])
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
            if gate.current?.id == id { abandonCurrent(decline:false) }
        }
        flush(deadline:clock.now().adding(WS2.Duration.second))
    }
    private func flush(deadline: WS2.Instant) {
        let frames = wire.drain(); guard !frames.isEmpty else { return }
        if clock.now() >= deadline || !deliver(connectionID,frames,deadline) { invalidate() }
    }
    private func abandonCurrent(decline: Bool) {
        let id = gate.current?.id, oldView = presentedView
        presentedView = nil
        gate.clear(); presentationTask?.cancel(); presentationTask = nil
        // Clearing first prevents a cancel callback from recursively declining the same request.
        if authInFlight { authInFlight = false; authentication.cancel() }
        if let oldView { island.dismiss(ifShowing:oldView) }
        if let id { reviews[id] = nil; if decline { try? wire.denyApproval(id); flush(deadline:clock.now().adding(WS2.Duration.second)) } }
    }
    func invalidate() {
        guard !closed else { return }; closed = true
        abandonCurrent(decline:false); reviews.removeAll(); wire.close(); closeTransport()
    }
}

@MainActor private final class WS2ReviewButton: NSButton {
    let clock: any WS2Clock
    private var sequence: UInt64 = 0
    private var press: (WS2.Instant,UInt64)?
    var freshAction: ((WS2.Instant,UInt64)->Void)?
    init(clock: any WS2Clock) {
        self.clock = clock; super.init(frame:.zero); title = "用 Touch ID 确认"; bezelStyle = .rounded
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
@MainActor final class WS2CommandReviewView: NSView, WS2LeaseContent {
    var onCancel: (() -> Void)?
    var inputIsCurrent: (() -> Bool) = { false }
    var interactionSize: NSSize { NSSize(width:600,height:360) }
    var confirm: ((WS2.Instant,UInt64)->Void)?
    var decline: (() -> Void)?
    private let approval: WS2ReviewButton
    private let text = NSTextView()
    init(review:WS2ApprovalReview,clock:any WS2Clock) {
        approval = WS2ReviewButton(clock:clock); super.init(frame:.zero)
        let stack=NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=10
        stack.translatesAutoresizingMaskIntoConstraints=false;addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:topAnchor,constant:16),stack.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-16)])
        let heading=NSTextField(labelWithString:"允许这次命令？");heading.font = .systemFont(ofSize:14,weight:.semibold);stack.addArrangedSubview(heading)
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder
        text.isEditable=false;text.isSelectable=true;text.isRichText=false;text.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        text.string = "项目：" + WS2ApprovalReview.visible(review.context.projectID) +
            "\n会话：" + WS2ApprovalReview.visible(review.context.session.id) +
            "\n线程：" + WS2ApprovalReview.visible(review.thread) + "\n轮次：" + WS2ApprovalReview.visible(review.turn) +
            "\n\n工作目录：\n" + WS2ApprovalReview.visible(review.cwd) + "\n\n命令：\n" + review.visibleCommand
        text.textContainer?.widthTracksTextView=true;text.isHorizontallyResizable=false;text.isVerticallyResizable=true
        text.minSize=NSSize(width:0,height:0);text.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        text.autoresizingMask=[.width];scroll.documentView=text;stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true;scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:220).isActive=true
        approval.isEnabled=false;approval.freshAction={ [weak self] began,sequence in guard let self,self.inputIsCurrent() else{return};self.confirm?(began,sequence) }
        let no=NSButton(title:"拒绝",target:self,action:#selector(refuse));no.bezelStyle = .rounded
        let row=NSStackView(views:[no,approval]);row.orientation = .horizontal;row.spacing=12;stack.addArrangedSubview(row)
    }
    required init?(coder:NSCoder){nil}
    func enableConfirmation(){approval.isEnabled=inputIsCurrent()}
    func revoke(){inputIsCurrent = { false };approval.isEnabled=false;text.string="";confirm=nil;decline=nil}
    @objc private func refuse(){guard inputIsCurrent() else{return};decline?()}
    override func cancelOperation(_ sender:Any?){onCancel?()}
}
