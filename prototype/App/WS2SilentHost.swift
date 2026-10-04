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
    private var frozenID: CGWindowID?
    private var frozenRevision: UInt64 = 1
    private weak var page: WS2SilentPageView?

    func attach(runtime: WS2AppRuntime, owner: AppDelegate) {
        self.runtime = runtime
        self.owner = owner
    }

    @discardableResult
    func open() -> Bool {
        guard let runtime, let owner, NotchController.isEnabled,
              AuthorizationService.shared.lockState() == .unlocked else { return false }
        let view = WS2SilentPageView(host: self)
        guard runtime.island.show(view, ownerID: "silent", onDismiss: { [weak self, weak view] _ in
            guard let self, self.page === view else { return }
            self.page = nil
            self.pending = nil
        }) else { return false }
        page = view
        view.note("看清，再确认。")
        _ = owner
        return true
    }

    func offer(_ commandID: String) {
        if WS2SilentNav.cancels(commandID) {
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
            _ = activityCursor.move(delta)
            page?.note(activityCursor.detail(in: activities))
            return
        }
        if WS2SilentActivityNav.showsDetails(commandID) {
            page?.note(activityCursor.detail(in: activities))
            return
        }
        if let delta = WS2SilentStripNav.delta(commandID) {
            let column = stripCursor.move(delta)
            page?.note("第 \(column) 列")
            return
        }
        if WS2SilentStripNav.showsOverview(commandID) {
            page?.note("第 \(stripCursor.column) 列")
            return
        }
        if let delta = WS2SilentNav.delta(commandID) {
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
            let ok = apply(request)
            let paused = owner?.inputController.hooksPaused ?? false
            let line = WS2SilentReadout.sentence(
                commandID, activities: activities, cover: cover, assistant: assistant, draft: draft, hooksPaused: paused)
            if !ok, commandID == "launcher.openFolder" {
                page?.note("还没选")
            } else {
                page?.note(ok ? line : "这次没有做")
            }
        case .awaiting(let proposal):
            pending = proposal
            page?.note(WS2SilentCopy.line(proposal.command.id) ?? previewLine(proposal))
            page?.setConfirmEnabled(true)
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

    func confirm() {
        guard let proposal = pending else { return }
        accept(proposal, at: nil)
    }

    /// 没有摄像头时，用一串已经分好的角度模拟一次点头。摇头或开始得太早都作废。
    func confirmSimulatedNod() {
        guard let proposal = pending else { return }
        let start = proposal.displayedAt
        let samples = [
            WS2HeadSample(at: start, pitchDown: 0, yaw: 0),
            WS2HeadSample(at: start.adding(WS2.Duration.millisecond * 100), pitchDown: 12, yaw: 1),
            WS2HeadSample(at: start.adding(WS2.Duration.millisecond * 200), pitchDown: 22, yaw: 0),
            WS2HeadSample(at: start.adding(WS2.Duration.millisecond * 300), pitchDown: 4, yaw: 0),
        ]
        guard let nod = WS2HeadGesture.recognize(samples),
              WS2HeadGesture.confirms(nod, displayedAt: proposal.displayedAt) else {
            pending = nil
            page?.setConfirmEnabled(false)
            page?.note("这下不算")
            return
        }
        accept(proposal, at: nod.startedAt)
    }

    private func accept(_ proposal: WS2SilentSession.Proposal, at gestureStart: WS2.Instant?) {
        guard let runtime else { return }
        let live = proposal.command.effect == .draft ? proposal.targetRevision : liveRevision()
        let when = gestureStart ?? runtime.clock.now()
        let step = session.confirm(proposal, at: when, currentRevision: live)
        pending = nil
        page?.setConfirmEnabled(false)
        switch step {
        case .accepted:
            let request = WS2SilentProductPort.request(for: step)
            let ok = apply(request)
            if case .carPlayUnavailable(let id) = request {
                page?.note(WS2SilentSecurity.outcome(id)?.line ?? "还不能接收")
            } else {
                page?.note(WS2SilentResultLine.noted(
                    proposal.command.id, succeeded: ok, draft: draft, assistant: assistant))
            }
        case .rejected:
            page?.note("确认对不上，这一笔作废")
        case .shown, .awaiting, .needsSystemConfirmation:
            page?.note("这次没有做")
        }
    }

    func showSimulatedDistance() {
        let preview = WS2ScreenDistanceSimulation.unknown()
        guard !preview.cancelsAwayCountdown, preview.centimeters == nil else {
            page?.note("这次没有做")
            return
        }
        page?.note(preview.line)
    }

    func showSimulatedCamera() {
        let preview = WS2CameraSimulation.noCamera()
        guard !preview.grantsUnlock, !preview.reportsNoPerson, preview.centimeters == nil else {
            page?.note("这次没有做")
            return
        }
        page?.note(preview.line)
    }

    func showSimulatedAway() {
        let preview = WS2AwaySimulation.countdownPreview()
        page?.note(preview.requestedLock ? "这次没有做" : preview.line)
    }

    func showSimulatedPhrase() {
        let id = WS2SilentPhrases.starterCommandIDs[0]
        let word = WS2SilentCopy.line(id) ?? ""
        let profile = WS2SilentPhraseProfile(speech: .mandarin, words: [id: word])
        let seen = WS2SilentPhraseSample(speech: .mandarin, seenWord: word, cameraAvailable: true, microphoneWord: "别的")
        let heardOnly = WS2SilentPhraseSample(speech: .mandarin, seenWord: nil, cameraAvailable: false, microphoneWord: word)
        var voice = WS2SilentVoiceEnrollment()
        let match = WS2SilentPhrases.match(seen, profile: profile)
        guard case .sameAsTap(let commandID) = match,
              voice.show(match) == .lineShown,
              !voice.executes(match),
              !voice.recordedMicrophone,
              !voice.hardwareMatched,
              WS2SilentPhrases.match(heardOnly, profile: profile) == .unknown else {
            page?.note("还没录过")
            return
        }
        page?.note(WS2SilentCopy.line(commandID) ?? "还没录过")
    }

    func showSimulatedPosture() {
        let decision = WS2Posture.decide(WS2PostureInput(eye: .nearSustained, head: .level))
        page?.note(decision.notchPhrase ?? "没有提醒")
    }

    func sendSeparately() {
        offer("assistant.sendDraft")
    }

    private func apply(_ request: WS2SilentHostRequest) -> Bool {
        guard let runtime, let owner else { return false }
        let screen = NSScreen.main
        let window = frozenWindow()
        var localDraft = draft
        var localAssistant = assistant
        let ok = WS2SilentApply.perform(
            request,
            launchpad: owner.launchpad,
            runtime: runtime,
            gestures: owner.gestures,
            screen: screen,
            window: window,
            draft: &localDraft,
            boundSessionID: nil,
            activities: activities,
            assistant: &localAssistant,
            cover: &cover)
        draft = localDraft
        assistant = localAssistant
        return ok
    }

    private func freezeIfNeeded() {
        guard let win = focusedWindow(), let id = windowID(of: win) else { return }
        if frozenID != id {
            frozenID = id
            frozenRevision &+= 1
            if frozenRevision == 0 { frozenRevision = 1 }
        }
    }

    private func frozenWindow() -> WS2SilentApply.WindowTarget? {
        guard let id = frozenID, let win = focusedWindow(), windowID(of: win) == id else { return nil }
        return .init(id: id, element: win, revision: frozenRevision)
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
    var inputIsCurrent: (() -> Bool) = { true }
    var interactionSize: NSSize { NSSize(width: 344, height: 168) }
    func revoke() { inputIsCurrent = { false } }
    private let status = NSTextField(labelWithString: "")
    private let confirm = IslandChip(title: "确认", symbol: "checkmark", style: .solid)
    private let nod = IslandChip(title: "模拟点头", symbol: "arrow.down", style: .glass)
    private let posture = IslandChip(title: "离屏幕近了", symbol: "eye", style: .glass)
    private let phrase = IslandChip(title: "口令", symbol: "text.bubble", style: .glass)
    private let away = IslandChip(title: "离开", symbol: "iphone", style: .glass)
    private let camera = IslandChip(title: "镜头", symbol: "web.camera", style: .glass)
    private let distance = IslandChip(title: "距离", symbol: "ruler", style: .glass)
    private let rowA = NSStackView()
    private let rowB = NSStackView()
    private var pageIndex = 0
    private weak var host: WS2SilentHost?

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
        nod.target = self
        nod.action = #selector(tapNod)
        nod.alphaValue = 0
        nod.isEnabled = false
        posture.target = self
        posture.action = #selector(tapPosture)
        phrase.target = self
        phrase.action = #selector(tapPhrase)
        away.target = self
        away.action = #selector(tapAway)
        camera.target = self
        camera.action = #selector(tapCamera)
        distance.target = self
        distance.action = #selector(tapDistance)
        let actions = NSStackView(views: [confirm, nod, posture, phrase, away, camera, distance])
        actions.orientation = .horizontal
        actions.spacing = 6
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

    private func showPage(_ index: Int) {
        let ids = WS2SilentCatalog.commands.map(\.id)
        let pageSize = 7
        let pages = max(1, (ids.count + pageSize - 1) / pageSize)
        pageIndex = (index % pages + pages) % pages
        let start = pageIndex * pageSize
        let slice = Array(ids[start..<min(ids.count, start + pageSize)])
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
        nod.isEnabled = on
        let show = on ? 1.0 : 0.0
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            confirm.alphaValue = show
            nod.alphaValue = show
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            confirm.animator().alphaValue = show
            nod.animator().alphaValue = show
        }
    }

    @objc private func tapMore() {
        showPage(pageIndex + 1)
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

    @objc private func tapNod() {
        guard inputIsCurrent() else { return }
        host?.confirmSimulatedNod()
    }

    @objc private func tapPosture() {
        guard inputIsCurrent() else { return }
        host?.showSimulatedPosture()
    }

    @objc private func tapPhrase() {
        guard inputIsCurrent() else { return }
        host?.showSimulatedPhrase()
    }

    @objc private func tapAway() {
        guard inputIsCurrent() else { return }
        host?.showSimulatedAway()
    }

    @objc private func tapCamera() {
        guard inputIsCurrent() else { return }
        host?.showSimulatedCamera()
    }

    @objc private func tapDistance() {
        guard inputIsCurrent() else { return }
        host?.showSimulatedDistance()
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
