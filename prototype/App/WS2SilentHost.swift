import Cocoa

/// 静音操作挂在已有刘海里。命令先冻结对象，确认过期就作废。
/// 采用草稿和发送是两次动作。点头逻辑在 Core；这里用点击表示确认。
@MainActor
final class WS2SilentHost {
    private weak var runtime: WS2AppRuntime?
    private weak var owner: AppDelegate?
    private var session = WS2SilentSession()
    private var draft = WS2SilentDraftHost()
    private var assistant = WS2SilentAssistant()
    private var activities = WS2SilentActivityBoard()
    private var activityCursor = WS2SilentActivityCursor()
    private var stripCursor = WS2SilentStripCursor()
    private var cover = WS2SilentCover.State()
    private var pending: WS2SilentSession.Proposal?
    private var confirmSequence: UInt64 = 0
    private var frozenID: CGWindowID?
    private var frozenPID: pid_t = 0
    private var frozenRevision: UInt64 = 1
    private var frozenScreen: NSScreen?
    private weak var page: WS2SilentPageView?
    /// 最近一次确认实际交出去的结果。没有待确认的提案时不动它。
    private(set) var lastResult: SilentExecutionResult?
    private var operations = WS2SilentOperationLedger()
    private var glanceWatchGeneration: UInt64 = 0
    /// 本次静音页打开时的意图 lease；关掉页面就作废，不跨页复用。
    private var intentLease = UUID()
    private var intentBoot = UUID()
    private let mouthSource = FaceObservationSource()
    private var mouthTask: Task<Void, Never>?
    private var mouthFrames: [WS2MouthFrame] = []
    private var mouthCandidate: String?
    private var mouthCandidateAt: Double = 0
    private var mouthLastFrameAt: Double = 0
    private var mouthGeneration: UInt64?

    /// Experimental enrollment is explicit, local and bounded; ordinary page opens do not use a camera.
    private func startPersonalPhrasesIfConfigured() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["WINDOWSHADE_MOUTH_PROFILE"], let camera = env["WINDOWSHADE_MOUTH_CAMERA"],
              let size = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000,
              let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)), bytes.count <= 2_000_000,
              let profile = try? JSONDecoder().decode(WS2MouthProfile.self, from: bytes), profile.valid else { return }
        stopPersonalPhrases()
        let lease = intentLease
        mouthTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.mouthSource.subscribe(deviceID: camera, purpose: .command, validFor: 60,
                    onObservation: { [weak self] frame in
                        guard let self, self.intentLease == lease else { return }
                        guard self.page != nil, AuthorizationService.shared.lockState() == .unlocked else {
                            self.stopPersonalPhrases(); return
                        }
                        self.consumeMouth(frame, profile: profile)
                    }, onFailure: { [weak self] _ in
                        guard let self, self.intentLease == lease else { return }
                        self.stopPersonalPhrases()
                    })
            } catch {
                if self.intentLease == lease { self.stopPersonalPhrases() }
            }
        }
    }
    private func stopPersonalPhrases() {
        mouthTask?.cancel(); mouthTask = nil; mouthSource.stop()
        mouthFrames.removeAll(); mouthCandidate = nil; mouthGeneration = nil
    }
    private func consumeMouth(_ observation: FaceObservation, profile: WS2MouthProfile) {
        guard observation.faceCount == 1, let points = observation.mouthLandmarks,
              let frame = WS2MouthFrame.make(time: observation.observedAt, points: points) else {
            mouthFrames.removeAll(); mouthCandidate = nil; return
        }
        if mouthGeneration != observation.generation || mouthFrames.last.map({ frame.time <= $0.time || frame.time - $0.time > 0.25 }) == true {
            mouthFrames.removeAll(); mouthCandidate = nil
        }
        mouthGeneration = observation.generation
        mouthLastFrameAt = frame.time
        if mouthCandidate != nil, frame.time - mouthCandidateAt > 5 { mouthCandidate = nil; mouthFrames.removeAll(); page?.setConfirmEnabled(false) }
        guard mouthCandidate == nil, pending == nil else { return }
        mouthFrames.append(frame)
        while mouthFrames.count > 100 || mouthFrames.first.map({ frame.time - $0.time > 2.2 }) == true { mouthFrames.removeFirst() }
        guard let first = mouthFrames.first, frame.time - first.time >= 1.5 else { return }
        let sample = WS2MouthRecording(session: intentLease, commandID: nil, frames: mouthFrames)
        guard let candidate = WS2MouthMatcher.match(sample, speech: profile.speech, profile: profile) else { return }
        mouthCandidate = candidate
        mouthCandidateAt = frame.time
        page?.note((WS2SilentCopy.line(candidate) ?? candidate) + "？点一下确认")
        page?.setConfirmEnabled(true)
    }
    var frozenWindowIDForProbe: CGWindowID? { frozenID }
    var hasPendingForProbe: Bool { session.currentProposal != nil }
    /// 探针只读（R03 真机）：操作台账当前显示的那行。「还在等」说明异步轮询没有落定。
    var operationLineForProbe: String { operations.visible }

    func attach(runtime: WS2AppRuntime, owner: AppDelegate) {
        self.runtime = runtime
        self.owner = owner
        // 方便遮挡清除：Esc / 刘海按钮共用；不与验证后显示混用。
        owner.silentPrivacyCover.onClearRequested = { [weak self] in
            self?.noteConvenienceCoverCleared()
        }
    }

    /// 方便遮挡已撤：只同步静音页内存态与文案。
    func noteConvenienceCoverCleared() {
        WS2SilentCover.clearConvenience(&cover)
        page?.note("已撤掉遮挡")
        page?.refreshCoverClearChip(covering: false)
    }

    @discardableResult
    func open() -> Bool {
        guard let runtime, let owner, NotchController.isEnabled,
              AuthorizationService.shared.lockState() == .unlocked else { return false }
        freezeIfNeeded()
        frozenScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        intentLease = UUID()
        intentBoot = AuthorizationService.shared.ledger.bootID
        let view = WS2SilentPageView(host: self)
        guard runtime.island.show(view, ownerID: "silent", onDismiss: { [weak self, weak view] _ in
            guard let self, self.page === view else { return }
            self.stopPersonalPhrases()
            self.page = nil
            self.pending = nil
            self.session.invalidate()
            self.glanceWatchGeneration &+= 1
            self.operations.turnPage()
            self.intentLease = UUID()
        }) else { return false }
        page = view
        startPersonalPhrasesIfConfigured()
        view.note("看清，再确认。")
        view.refreshCoverClearChip(covering: owner.silentPrivacyCover.isCovering)
        return true
    }

    func offer(_ commandID: String) {
        mouthCandidate = nil; mouthFrames.removeAll()
        if commandID == "privacy.clearCover" {
            guard let owner, owner.silentPrivacyCover.isCovering else {
                page?.note("没有遮挡")
                return
            }
            owner.silentPrivacyCover.requestClear()
            return
        }
        if WS2SilentNav.cancels(commandID) {
            session.invalidate()
            pending = nil
            page?.setConfirmEnabled(false)
            page?.note(WS2SilentNav.resultLine(commandID) ?? "已取消")
            return
        }
        if WS2SilentNav.selects(commandID) {
            if pending == nil {
                page?.note("这次没有做")
                return
            }
            confirm()
            return
        }
        if commandID == "nav.help" {
            page?.note(WS2SilentHelp.line)
            return
        }
        if let delta = WS2SilentActivityNav.delta(commandID) {
            invalidatePending()
            if activities.cardIDs.isEmpty {
                _ = activityCursor.move(delta)
            } else {
                _ = activityCursor.showCard(delta, ids: activities.cardIDs)
            }
            page?.note(activityCursor.detail(in: activities))
            return
        }
        if WS2SilentActivityNav.showsDetails(commandID) {
            invalidatePending()
            page?.note(activityCursor.detail(in: activities))
            return
        }
        if let delta = WS2SilentStripNav.delta(commandID) {
            invalidatePending()
            let column = stripCursor.move(delta)
            page?.note("第 \(column) 列")
            return
        }
        if WS2SilentStripNav.showsOverview(commandID) {
            invalidatePending()
            page?.note("第 \(stripCursor.column) 列")
            return
        }
        if let delta = WS2SilentNav.delta(commandID) {
            session.invalidate()
            pending = nil
            page?.setConfirmEnabled(false)
            page?.turn(delta)
            page?.note(WS2SilentNav.resultLine(commandID) ?? "这次没有做")
            return
        }
        guard let runtime else { return }
        freezeIfNeeded()
        let target = targetID(for: commandID)
        let revision = targetRevision(for: commandID)
        let step = session.propose(commandID: commandID, targetID: target, targetRevision: revision, now: runtime.clock.now())
        switch step {
        case .shown:
            pending = nil
            let request = WS2SilentProductPort.request(for: step)
            let shownResult = apply(request)
            page?.note(shownResult.notchLine)
            if commandID == "privacy.cover" || commandID == "scene.conversation" {
                page?.refreshCoverClearChip(covering: owner?.silentPrivacyCover.isCovering == true)
            }
        case .awaiting(let proposal):
            pending = proposal
            let shownAt = max(runtime.clock.now(), proposal.displayedAt)
            let shown = session.noteShown(id: proposal.id, at: shownAt)
            page?.note(WS2SilentCopy.line(proposal.command.id) ?? previewLine(proposal))
            page?.setConfirmEnabled(shown)
        case .needsSystemConfirmation:
            pending = nil
            page?.setConfirmEnabled(false)
            page?.note(WS2SilentSecurity.outcome(commandID)?.line ?? "要用原来的确认")
        case .accepted, .rejected:
            pending = nil
            page?.setConfirmEnabled(false)
            page?.note("这次没有做")
        }
    }

    func confirm(gestureBeganAt: WS2.Instant? = nil) {
        // Experimental visual candidates require a click; they never mint a head-gesture receipt.
        if let candidate = mouthCandidate {
            let now = ProcessInfo.processInfo.systemUptime
            guard gestureBeganAt == nil, now >= mouthLastFrameAt, now - mouthLastFrameAt <= 0.5,
                  now - mouthCandidateAt <= 5, AuthorizationService.shared.lockState() == .unlocked else {
                mouthCandidate = nil; mouthFrames.removeAll(); page?.setConfirmEnabled(false); return
            }
            mouthCandidate = nil; mouthFrames.removeAll(); page?.setConfirmEnabled(false)
            offer(candidate)
            return
        }
        guard let proposal = session.currentProposal else { return }
        accept(proposal, at: gestureBeganAt)
    }

    func invalidatePending() {
        session.invalidate()
        pending = nil
        page?.setConfirmEnabled(false)
        glanceWatchGeneration &+= 1
        operations.turnPage()
    }

    private func accept(_ proposal: WS2SilentSession.Proposal, at gestureStart: WS2.Instant?) {
        guard let runtime, session.currentProposal?.id == proposal.id else {
            pending = nil
            lastResult = .failed("确认对不上，这一笔作废")
            page?.setConfirmEnabled(false)
            page?.note("确认对不上，这一笔作废")
            return
        }
        let live = proposal.command.effect == .draft ? proposal.targetRevision : liveRevision()
        let now = runtime.clock.now()
        let began = gestureStart ?? now
        confirmSequence &+= 1
        if confirmSequence == 0 { confirmSequence = 1 }
        let target = proposal.targetID.isEmpty ? "none" : proposal.targetID
        let step = session.confirm(
            proposal,
            gestureBeganAt: began,
            now: now,
            liveRevision: live,
            sequence: confirmSequence,
            origin: .nativeClick,
            boot: intentBoot,
            lease: intentLease,
            expectedBoot: intentBoot,
            expectedLease: intentLease,
            expectedTarget: target)
        pending = nil
        page?.setConfirmEnabled(false)
        switch step {
        case .accepted:
            let request = WS2SilentProductPort.request(for: step)
            let result = apply(request)
            lastResult = result
            if result.isCompleted {
                page?.note(WS2SilentResultLine.noted(
                    proposal.command.id, succeeded: true, draft: draft, assistant: assistant))
            } else {
                page?.note(result.notchLine)
            }
            if proposal.command.id == "privacy.cover" || proposal.command.id == "scene.conversation" {
                page?.refreshCoverClearChip(covering: owner?.silentPrivacyCover.isCovering == true)
            }
            if case .waiting = result, let id = frozenID {
                watchAsyncEnd(commandID: proposal.command.id, windowID: id)
            }
        case .rejected:
            lastResult = .failed("确认对不上，这一笔作废")
            page?.note("确认对不上，这一笔作废")
        case .shown, .awaiting, .needsSystemConfirmation:
            lastResult = .failed("这次没有做")
            page?.note("这次没有做")
        }
    }

    func sendSeparately() {
        offer("assistant.sendDraft")
    }

    private func apply(_ request: WS2SilentHostRequest) -> SilentExecutionResult {
        guard let runtime, let owner else { return .failed("这一笔没有做成") }
        let screen = frozenScreen
        let window = frozenWindow()
        var localDraft = draft
        var localAssistant = assistant
        let result = WS2SilentApply.perform(
            request,
            launchpad: owner.launchpad,
            runtime: runtime,
            gestures: owner.gestures,
            screen: screen,
            window: window,
            draft: &localDraft,
            boundSessionID: runtime.owned.session?.approval.wire.threadID,
            activities: activities,
            assistant: &localAssistant,
            cover: &cover)
        draft = localDraft
        assistant = localAssistant
        return result
    }

    /// 异步窗口动作终态：短轮询作迁移路径；换页/新候选作废旧 UI 更新权（R03）。
    /// 先校验期限与代次，再读效果；超时必须更新可见状态。
    private func watchAsyncEnd(commandID: String, windowID: CGWindowID) {
        glanceWatchGeneration &+= 1
        let generation = glanceWatchGeneration
        let revision = frozenRevision
        let watchStarted = CACurrentMediaTime()
        let op = operations.begin(
            commandID: commandID,
            targetID: String(windowID),
            targetRevision: revision,
            captureGeneration: generation)
        let deadline = watchStarted + Self.asyncWatchTimeout(commandID)
        func tick() {
            guard generation == glanceWatchGeneration else { return }
            guard let owner else { return }
            let now = CACurrentMediaTime()
            if now >= deadline {
                if operations.finish(id: op, line: "结果未确认") {
                    lastResult = .failed(Self.asyncTimeoutLine(commandID))
                    page?.note("结果未确认")
                }
                return
            }
            guard frozenID == windowID, frozenRevision == revision else {
                _ = operations.finish(id: op, line: "目标已变")
                return
            }
            if let outcome = Self.asyncObserved(
                commandID: commandID, windowID: windowID, owner: owner, watchStarted: watchStarted
            ) {
                let line = outcome ? "已完成" : "结果未确认"
                if operations.finish(id: op, line: line) {
                    if outcome {
                        lastResult = .completed(WS2EffectReceipt(
                            commandID: commandID, targetID: String(windowID), observed: true))
                        let noted = WS2SilentResultLine.noted(
                            commandID, succeeded: true, draft: draft, assistant: assistant)
                        // 看一眼/置顶等故意不写“已叫到前面”；无专属句时用中性「已完成」。
                        page?.note(noted == WS2SilentResultLine.notDone ? "已完成" : noted)
                    } else {
                        lastResult = .failed(Self.asyncTimeoutLine(commandID))
                        page?.note(line)
                    }
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { tick() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { tick() }
    }

    private static func asyncWatchTimeout(_ commandID: String) -> CFTimeInterval {
        switch commandID {
        case "window.collapse", "window.expand": return 3.0
        case "window.pin": return 2.5
        default: return 1.5
        }
    }

    private static func asyncTimeoutLine(_ commandID: String) -> String {
        switch commandID {
        case "window.glance": return "看一眼没有等到画面"
        case "window.pin": return "置顶没有等到画面"
        case "window.collapse": return "收起没有确认"
        case "window.expand": return "展开没有确认"
        case "window.slideOver", "window.leaveSlideOver": return "侧拉没有确认"
        case "window.pip", "window.leavePip": return "画中画没有确认"
        default: return "这一笔没有做成"
        }
    }

    /// `nil` = 继续等；`true`/`false` = 终态成功/失败。
    private static func asyncObserved(
        commandID: String,
        windowID: CGWindowID,
        owner: AppDelegate,
        watchStarted: CFTimeInterval
    ) -> Bool? {
        switch commandID {
        case "window.glance":
            return owner.glance.isLive(windowID) ? true : nil
        case "window.pin":
            // 置顶只有拿到真正的完成回执才算成立。会话一装上 isPreviewing 就为真，但首帧
            // 可能还没到、之后也可能失败（启动中目标变了），拿它当终态会让一笔没做成的
            // 置顶报「已完成」，真机探针踩过。已在置顶那一支走 .alreadySatisfied，不经过这里。
            guard let done = owner.pinnedPreviewController.lastSilentCompletion,
                  done.id == windowID, done.at >= watchStarted else { return nil }
            return done.ok
        case "window.slideOver":
            return owner.slideOver.isSlideOver(windowID) ? true : nil
        case "window.leaveSlideOver":
            return owner.slideOver.isSlideOver(windowID) ? nil : true
        case "window.pip":
            return owner.pip.isInPictureInPicture(windowID) ? true : nil
        case "window.leavePip":
            return owner.pip.isInPictureInPicture(windowID) ? nil : true
        case "window.collapse":
            if let done = owner.lastSilentFoldCompletion,
               done.id == windowID, done.at >= watchStarted {
                return done.ok
            }
            // 已安装卷帘态可作中间观察，仍等 FoldCompletion 终态；超时走 deadline。
            return nil
        case "window.expand":
            // 字典移除不等于可见；要求不再 shaded 且窗口仍在屏上。
            guard owner.shaded[windowID] == nil else { return nil }
            return cgWindowIsCurrentlyOnScreen(windowID) ? true : nil
        default:
            return nil
        }
    }

    private func freezeIfNeeded() {
        guard let win = focusedWindow(), let id = windowID(of: win) else { return }
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        if frozenID != id || frozenPID != pid {
            frozenID = id
            frozenPID = pid
            frozenRevision &+= 1
            if frozenRevision == 0 { frozenRevision = 1 }
        }
    }

    private func frozenWindow() -> WS2SilentApply.WindowTarget? {
        guard let id = frozenID, let win = focusedWindow(), windowID(of: win) == id else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        guard pid == frozenPID else { return nil }
        return .init(id: id, element: win, revision: frozenRevision, pid: pid)
    }

    private func targetID(for commandID: String) -> String {
        switch commandID {
        case "dictation.adopt", "assistant.sendDraft":
            return draft.draftID.isEmpty ? "local-draft" : draft.draftID
        case "launcher.openFolder":
            return ""
        default:
            return frozenID.map(String.init) ?? "none"
        }
    }

    private func targetRevision(for commandID: String) -> UInt64 {
        switch commandID {
        case "dictation.adopt", "assistant.sendDraft":
            return draft.draftID.isEmpty ? 1 : draft.revision
        default:
            return frozenRevision
        }
    }

    private func liveRevision() -> UInt64 {
        guard let id = frozenID, let win = focusedWindow(), windowID(of: win) == id else { return 0 }
        return frozenRevision
    }

    private func previewLine(_ proposal: WS2SilentSession.Proposal) -> String {
        switch proposal.command.id {
        case "window.left": return "左半屏"
        case "window.right": return "右半屏"
        case "window.fill": return "铺满屏幕"
        case "window.collapse": return "收起窗口"
        case "window.expand": return "展开窗口"
        case "window.glance": return "看一眼"
        case "dictation.adopt": return "采用草稿"
        case "assistant.sendDraft": return "再确认发送"
        case "focus.start": return "开始番茄钟"
        default: return "确认这一笔"
        }
    }
}

/// 刘海里的静音页。黑底白字、连续圆角的小块，和设计稿里的岛是同一张表面。
@MainActor
final class WS2SilentPageView: NSView, WS2LeaseContent {
    var onCancel: (() -> Void)?
    var inputIsCurrent: (() -> Bool) = { false }
    var interactionSize: NSSize { NSSize(width: 344, height: 168) }
    func revoke() { inputIsCurrent = { false } }

    func suspendInput() {
        inputIsCurrent = { false }
        setConfirmEnabled(false)
        host?.invalidatePending()
    }
    private let status = NSTextField(labelWithString: "")
    private let confirm = IslandChip(title: "确认", symbol: "checkmark", style: .solid)
    /// 方便遮挡生效时显示；与「揭开遮挡」验证路径分开。
    private let clearCover = IslandChip(title: "撤掉遮挡", symbol: "eye.slash", style: .glass)
    private let rowA = NSStackView()
    private let rowB = NSStackView()
    private var pageIndex = 0
    private weak var host: WS2SilentHost?
    private weak var actionsRow: NSStackView?

    init(host: WS2SilentHost) {
        self.host = host
        super.init(frame: .zero)
        wantsLayer = true
        let title = NSTextField(labelWithString: "静音操作")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .white
        status.font = .systemFont(ofSize: 12, weight: .medium)
        status.textColor = NSColor.white.withAlphaComponent(0.72)
        status.lineBreakMode = .byTruncatingTail
        for row in [rowA, rowB] {
            row.orientation = .horizontal
            row.spacing = 6
            row.distribution = .fillEqually
        }
        showPage(0)
        confirm.target = self
        confirm.action = #selector(tapConfirm)
        confirm.alphaValue = 0
        confirm.isEnabled = false
        clearCover.target = self
        clearCover.action = #selector(tapClearCover)
        clearCover.isHidden = true
        clearCover.identifier = NSUserInterfaceItemIdentifier("privacy.clearCover")
        let actions = NSStackView(views: [clearCover, confirm])
        actions.orientation = .horizontal
        actions.spacing = 6
        actionsRow = actions
        let stack = NSStackView(views: [title, status, rowA, rowB, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            rowA.widthAnchor.constraint(equalTo: stack.widthAnchor),
            rowB.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func note(_ text: String) { status.stringValue = text }

    func refreshCoverClearChip(covering: Bool) {
        clearCover.isHidden = !covering
    }

    private static let pages: [[String]] = [
        ["launcher.open", "ui.windows", "ui.activities", "ui.usage", "ui.settings"],
        ["window.left", "window.right", "window.glance", "window.pin", "nav.back"],
    ]

    private func showPage(_ index: Int) {
        let pages = Self.pages.count
        pageIndex = (index % pages + pages) % pages
        let slice = Self.pages[pageIndex]
        for row in [rowA, rowB] {
            for view in row.arrangedSubviews {
                row.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        }
        var chips: [NSView] = slice.enumerated().map { offset, id in
            let chip = IslandChip(title: WS2SilentCopy.line(id) ?? id, symbol: Self.symbol(id), style: .glass)
            chip.target = self
            chip.action = #selector(tapCommand(_:))
            chip.identifier = NSUserInterfaceItemIdentifier(id)
            _ = offset
            return chip
        }
        let more = IslandChip(title: "更多", symbol: "ellipsis", style: .glass)
        more.target = self
        more.action = #selector(tapMore)
        chips.append(more)
        for (index, chip) in chips.enumerated() {
            (index < 4 ? rowA : rowB).addArrangedSubview(chip)
        }
    }

    private static func symbol(_ id: String) -> String {
        switch id {
        case "launcher.open": return "square.grid.3x3"
        case "window.left": return "rectangle.lefthalf.inset.filled"
        case "window.right": return "rectangle.righthalf.inset.filled"
        case "window.fill": return "rectangle.inset.filled"
        case "window.collapse": return "rectangle.compress.vertical"
        case "window.glance": return "eye"
        case "dictation.adopt": return "checkmark"
        case "assistant.sendDraft": return "paperplane"
        default: return "circle"
        }
    }
    func setConfirmEnabled(_ on: Bool) {
        confirm.isEnabled = on
        let show = on ? 1.0 : 0.0
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            confirm.alphaValue = show
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.fadeDuration
            confirm.animator().alphaValue = show
        }
    }

    @objc private func tapMore() {
        showPage(pageIndex + 1)
        host?.invalidatePending()
        note("第 \(pageIndex + 1) 页")
    }

    func turn(_ delta: Int) {
        showPage(pageIndex + delta)
    }

    @objc private func tapCommand(_ sender: NSButton) {
        guard inputIsCurrent(), let id = sender.identifier?.rawValue else { return }
        host?.offer(id)
    }

    @objc private func tapConfirm() {
        guard inputIsCurrent() else { return }
        host?.confirm()
    }

    @objc private func tapClearCover() {
        guard inputIsCurrent() else { return }
        host?.offer("privacy.clearCover")
    }
}

/// 岛上的一块。玻璃块是半透明白；确认是实心白字黑底反过来。
@MainActor
final class IslandChip: NSButton {
    enum Style { case glass, solid }
    init(title: String, symbol: String, style: Style) {
        super.init(frame: .zero)
        self.title = title
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        imagePosition = .imageLeading
        imageScaling = .scaleProportionallyDown
        font = .systemFont(ofSize: 11, weight: .semibold)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        setButtonType(.momentaryPushIn)
        setAccessibilityLabel(title)
        switch style {
        case .glass:
            contentTintColor = .white
            attributedTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            ])
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        case .solid:
            contentTintColor = .black
            attributedTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: NSColor.black,
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            ])
            layer?.backgroundColor = NSColor.white.cgColor
        }
    }
    required init?(coder: NSCoder) { nil }
}
