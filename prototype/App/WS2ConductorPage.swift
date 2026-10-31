import Cocoa

/// 指挥页复用唯一 owned controller。采用草稿和发送分开，所有动作绑定正在显示的会话。
@MainActor final class WS2ConductorPageView: NSView, WS2LeaseContent, WS2DeviceActionSink, NSTextFieldDelegate {
    var onCancel: (() -> Void)?
    var remoteTargetChanged: ((WS2.Context?) -> Void)?
    var inputIsCurrent: () -> Bool = { false }
    var interactionSize: NSSize { NSSize(width: 460, height: 360) }
    let pageID = UUID()
    let input = WS2VisibleListInput()
    var expectedLease: WS2.LeaseHandle?
    var currentLease: (() -> WS2.LeaseHandle?)?
    var enableDevice: ((UUID) -> Bool)?
    var disableDevice: ((UUID) -> Void)?
    var changedEnvironment: (() -> Void)?
    /// 收起时留下的草稿（只有 Claude 那一侧要留：Codex 的草稿本来就记在 controller 上）。
    struct KeptDraft: Equatable { let claude: Bool; let text: String }
    /// 页面收起（返回、点外面、换页）时交出草稿；nil = 没有要留的。
    var onKeepDraft: ((KeptDraft?) -> Void)?
    /// 从那一排的会话格走进来时才有：页头的“过去”。
    var goThere: (() -> Void)? { didSet { goButton.isHidden = goThere == nil } }
    /// 切到 Codex 时先把 Claude 那一侧的草稿收在这里，切回来放回；草稿只用“丢弃”丢。
    private var claudeDraft = ""
    private var claudeShown = false

    private let controller: WS2OwnedLaunchController
    // 块 1 · 头：返回、项目 · 助手、在跑、过去、Codex / Claude（只读）。
    private let backButton = NSButton(title: "", target: nil, action: nil)
    private let title = NSTextField(labelWithString: WSL10n.text("conductor.title", zh: "指挥"))
    private let runningLabel = NSTextField(labelWithString: WSL10n.text("notch.row.running", zh: "在跑"))
    private let goButton = WS2ConductorPill(title: WSL10n.text("notch.action.goThere", zh: "过去"), kind: .ghost)
    private let backend = WS2BackendControl()
    // 块 2 · 下一轮：模型、程度。
    private let menus = NSStackView()
    private let modelMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let effortLabel = NSTextField(labelWithString: WSL10n.text("conductor.effort", zh: "程度"))
    private let effortChips = WS2ConductorLevelChips()
    // 块 3 · 转写：Codex 侧是会话列表，Claude 侧是最近的转写。
    private let sessions = NSStackView()
    private let sessionsScroll = NSScrollView()
    private let claudeScroll = NSScrollView()
    private let claudeText = NSTextView()
    private var shownTranscript = ""
    // 块 4 · 草稿：说话、草稿、丢弃、采用草稿 / 发送 / 补进本轮。
    private let draftCard = NSStackView()
    private let draftState = NSTextField(labelWithString: "")
    private let wave = WS2ConductorWaveView()
    private let editor = NSTextField(string: "")
    private let discard = WS2ConductorPill(title: WSL10n.text("conductor.discard", zh: "丢弃"), kind: .ghost)
    private let speak = WS2ConductorPill(title: "", kind: .mic)
    private let write = WS2ConductorPill(title: WSL10n.text("conductor.adoptDraft", zh: "采用草稿"), kind: .primary)
    private let send = WS2ConductorPill(title: WSL10n.text("conductor.send", zh: "发送"), kind: .primary)
    private let claudeSend = WS2ConductorPill(title: WSL10n.text("conductor.send", zh: "发送"), kind: .primary)
    // 底下一行：提示，右边是停止本轮。
    private let interrupt = WS2ConductorPill(title: WSL10n.text("conductor.stopTurn", zh: "停止本轮"), kind: .ghost)
    private let claudeStop = WS2ConductorPill(title: WSL10n.text("conductor.stopTurn", zh: "停止本轮"), kind: .ghost)
    private let remoteHint = WS2ConductorHintLabel(wrappingLabelWithString: "")
    private let receipt = WS2ConductorHintLabel(wrappingLabelWithString: "")
    private let status = WS2ConductorHintLabel(wrappingLabelWithString: "")
    private let claudeStatus = WS2ConductorHintLabel(wrappingLabelWithString: "")
    private let devices = NSStackView()
    private let deviceMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let enableButton = NSButton(title: WSL10n.text("conductor.enableNow", zh: "本次启用"), target: nil, action: nil)

    private let transcriber: any VoiceTranscriber
    private var voice: VoiceDraftSession?
    private var voiceTick: Task<Void, Never>?
    private let claudeConductor: ClaudeConductor
    /// 这台 Mac 上没有 claude 时，点灰着的 Claude 开关打开设置里的编程会话那一行（不弹窗）。
    var onOpenCodingSettings: (() -> Void)?
    private var adoptedDraft: WS2OwnedLaunchController.ConductorDraft?
    private var displayedTarget: WS2OwnedLaunchController.ConductorTarget?
    private var displayedTurn: String?
    /// 这一轮开始时「程度」是哪一档（页面自己看到的；没看到开始就取页面打开时那一档）。只用来画实心那一格。
    private var runningEffort: String?
    private var lastSeenTurn: String?
    private var shownDevices: [WS2ControllerDevice] = []
    private var previousRows: [ConductorPageSnapshot.Row] = []
    private var previousListRevision: UInt64 = 0
    private var highlighted: ConductorPageSnapshot.Selection?
    private var bound: [String: ConductorPageSnapshot.Row] = [:]
    private struct Shown: Equatable { let id: String; let revision: UInt64 }
    private var renderedIdentity: [Shown]?
    private var modelIDs: [String] = []
    private var effortIDs: [String] = []
    private var rendering = false
    private var focusObservers: [NSObjectProtocol] = []

    var isClaudeBackend: Bool { backend.selectedSegment == 1 }
    var backendEpoch: UUID? { isClaudeBackend ? claudeConductor.epoch : controller.session?.connectionID }
    var isInputReady: Bool {
        guard !isClaudeBackend else { return false }
        return inputIsCurrent() && expectedLease != nil && currentLease?() == expectedLease &&
            window?.isKeyWindow == true && NSApp.isActive && backendEpoch != nil
    }

    // 默认参数在非隔离上下文求值，MainActor 的构造器不能当默认值；改为体内构造。
    init(controller: WS2OwnedLaunchController, transcriber: (any VoiceTranscriber)? = nil) {
        self.controller = controller
        self.transcriber = transcriber ?? MacVoiceTranscriber()
        let projectURL: () -> URL = { [weak controller] in
            MainActor.assumeIsolated {
                controller?.projectURL ?? FileManager.default.homeDirectoryForCurrentUser
            }
        }
        self.claudeConductor = ClaudeConductor(
            workingDirectory: projectURL, mayUse: { true },
            notLoggedInLine: WSL10n.text("conductor.claude.notLoggedIn", zh: "Claude 没登录。在终端里运行 claude 登录后再试"))
        super.init(frame: .zero)
        // 刘海是黑的：页面在深色外观里画，不跟系统外观走。
        appearance = NSAppearance(named: .darkAqua)
        claudeConductor.onChange = { [weak self] in self?.renderClaude() }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
        ])
        let dim = NSColor.white.withAlphaComponent(0.6)
        func small(_ label: NSTextField) {
            label.font = .systemFont(ofSize: 11)
            label.textColor = dim
        }

        // 块 1 · 头
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        backButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        backButton.imagePosition = .imageOnly
        backButton.isBordered = false
        backButton.contentTintColor = .white
        backButton.target = self
        backButton.action = #selector(backPressed)
        backButton.setAccessibilityLabel(WSL10n.text("conductor.view.back", zh: "返回"))
        backButton.toolTip = WSL10n.text("conductor.view.back", zh: "返回")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .white
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        small(runningLabel)
        runningLabel.isHidden = true
        // 页头的“过去”：去会话所在的终端窗口。
        goButton.target = self
        goButton.action = #selector(goToSession)
        goButton.isHidden = true
        backend.segmentCount = 2
        backend.setLabel(WSL10n.text("conductor.backend.codex", zh: "Codex"), forSegment: 0)
        backend.setLabel(WSL10n.text("conductor.backend.claude", zh: "Claude（只读）"), forSegment: 1)
        backend.trackingMode = .selectOne
        backend.controlSize = .small
        backend.selectedSegment = 0
        backend.target = self
        backend.action = #selector(pickBackend)
        backend.setAccessibilityLabel(WSL10n.text("conductor.backend.label", zh: "助手"))
        backend.onUnavailableClaudeClick = { [weak self] in self?.onOpenCodingSettings?() }
        refreshClaudeSwitch()
        backend.setContentHuggingPriority(.required, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [backButton, title, runningLabel, goButton, spacer, backend])
        header.spacing = 8
        header.alignment = .centerY
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // 块 2 · 下一轮
        let nextLabel = NSTextField(labelWithString: WSL10n.text("conductor.nextRound", zh: "下一轮"))
        small(nextLabel)
        small(effortLabel)
        modelMenu.controlSize = .small
        modelMenu.font = .systemFont(ofSize: 11)
        modelMenu.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        modelMenu.widthAnchor.constraint(lessThanOrEqualToConstant: 150).isActive = true
        modelMenu.setAccessibilityLabel(WSL10n.text("conductor.nextModel", zh: "下一轮模型"))
        effortChips.setAccessibilityLabel(WSL10n.text("conductor.nextEffort", zh: "下一轮思考程度"))
        modelMenu.toolTip = WSL10n.text("conductor.nextModel.tip", zh: "下一轮使用的模型，不改变正在运行的这一轮。")
        effortChips.toolTip = WSL10n.text("conductor.nextEffort.tip", zh: "下一轮使用的思考程度，不改变正在运行的这一轮。")
        modelMenu.target = self
        modelMenu.action = #selector(pickModel)
        effortChips.onPick = { [weak self] index in self?.pickEffort(index) }
        menus.orientation = .horizontal
        menus.spacing = 8
        menus.alignment = .centerY
        [nextLabel, modelMenu, effortLabel, effortChips].forEach { menus.addArrangedSubview($0) }
        stack.addArrangedSubview(menus)
        menus.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true

        // 块 3 · 转写（Codex 侧：会话列表；Claude 侧：转写）
        sessions.orientation = .vertical
        sessions.alignment = .leading
        sessions.spacing = 2
        sessions.translatesAutoresizingMaskIntoConstraints = false
        let sessionsDoc = WS2ConductorFlippedView()
        sessionsDoc.translatesAutoresizingMaskIntoConstraints = false
        sessionsDoc.addSubview(sessions)
        sessionsScroll.documentView = sessionsDoc
        sessionsScroll.drawsBackground = false
        sessionsScroll.borderType = .noBorder
        sessionsScroll.hasVerticalScroller = true
        sessionsScroll.autohidesScrollers = true
        let clip = sessionsScroll.contentView
        NSLayoutConstraint.activate([
            sessionsDoc.topAnchor.constraint(equalTo: clip.topAnchor),
            sessionsDoc.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            sessionsDoc.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            sessions.topAnchor.constraint(equalTo: sessionsDoc.topAnchor),
            sessions.leadingAnchor.constraint(equalTo: sessionsDoc.leadingAnchor),
            sessions.trailingAnchor.constraint(equalTo: sessionsDoc.trailingAnchor),
            sessions.bottomAnchor.constraint(equalTo: sessionsDoc.bottomAnchor),
        ])
        stack.addArrangedSubview(sessionsScroll)
        sessionsScroll.heightAnchor.constraint(equalToConstant: 88).isActive = true
        sessionsScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        claudeText.isEditable = false
        claudeText.isSelectable = true
        claudeText.drawsBackground = false
        claudeText.font = .systemFont(ofSize: 11.5)
        claudeText.textColor = NSColor.white.withAlphaComponent(0.82)
        claudeText.isVerticallyResizable = true
        claudeText.autoresizingMask = [.width]
        claudeText.textContainerInset = NSSize(width: 0, height: 2)
        claudeScroll.documentView = claudeText
        claudeScroll.drawsBackground = false
        claudeScroll.hasVerticalScroller = true
        claudeScroll.autohidesScrollers = true
        claudeScroll.borderType = .noBorder
        stack.addArrangedSubview(claudeScroll)
        claudeScroll.heightAnchor.constraint(equalToConstant: 88).isActive = true
        claudeScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // 块 4 · 草稿
        small(draftState)
        draftState.lineBreakMode = .byTruncatingTail
        wave.isHidden = true
        let stateRow = NSStackView(views: [draftState, wave])
        stateRow.spacing = 8
        stateRow.alignment = .centerY
        editor.placeholderString = WSL10n.text("conductor.draft.hint", zh: "按住说话，或在这里打字")
        editor.setAccessibilityLabel(WSL10n.text("conductor.draftLabel", zh: "待记下的草稿"))
        editor.isEditable = true
        editor.isBezeled = false
        editor.drawsBackground = false
        editor.focusRingType = .none
        editor.font = .systemFont(ofSize: 13, weight: .medium)
        editor.textColor = .white
        editor.lineBreakMode = .byTruncatingTail
        editor.delegate = self
        editor.setContentHuggingPriority(.defaultLow, for: .horizontal)
        editor.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let middle = NSStackView(views: [stateRow, editor])
        middle.orientation = .vertical
        middle.alignment = .leading
        middle.spacing = 3
        editor.widthAnchor.constraint(equalTo: middle.widthAnchor).isActive = true
        middle.setContentHuggingPriority(.defaultLow, for: .horizontal)
        middle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // 丢弃挨着草稿框：两种助手共用这一个框，也共用这一个键。草稿只在这里丢；返回、收起都留着。
        discard.target = self
        discard.action = #selector(discardDraft)
        discard.toolTip = WSL10n.text("conductor.discard.tip", zh: "清空这份草稿。返回或收起页面不会清空。")
        write.target = self
        write.action = #selector(commitDraft)
        write.toolTip = WSL10n.text("conductor.write.tip", zh: "只把现在的文字留在这台 Mac 上。不会发给助手。")
        send.target = self
        send.action = #selector(sendDraft)
        send.toolTip = WSL10n.text("conductor.send.tip", zh: "只发送已采用的草稿。运行时补进当前这一轮，下一轮的模型和档位不会改动这一轮。")
        claudeSend.target = self
        claudeSend.action = #selector(sendClaudeDraft)
        speak.target = self
        speak.action = #selector(speakPressed(_:))
        _ = speak.sendAction(on: [.leftMouseDown, .leftMouseUp])
        speak.setAccessibilityLabel(WSL10n.text("conductor.speak", zh: "按住说话"))
        speak.toolTip = WSL10n.text("conductor.speak.tip", zh: "按住说一句，松手得到草稿；只在这台 Mac 上识别。")
        draftCard.orientation = .horizontal
        draftCard.alignment = .centerY
        draftCard.spacing = 10
        draftCard.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        draftCard.wantsLayer = true
        draftCard.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        draftCard.layer?.cornerRadius = 14
        [speak, middle, discard, write, send, claudeSend].forEach { draftCard.addArrangedSubview($0) }
        stack.addArrangedSubview(draftCard)
        draftCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // 底下：手柄（原有功能，稿里没有这一行）、提示、停止本轮
        deviceMenu.controlSize = .small
        deviceMenu.setAccessibilityLabel(WSL10n.text("conductor.pad.label", zh: "本次连接的手柄"))
        enableButton.controlSize = .small
        enableButton.bezelStyle = .rounded
        enableButton.target = self
        enableButton.action = #selector(toggleDevice)
        enableButton.image = NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: nil)
        devices.spacing = 8
        [deviceMenu, enableButton].forEach { devices.addArrangedSubview($0) }
        stack.addArrangedSubview(devices)
        for (label, lines) in [(remoteHint, 1), (receipt, 2), (status, 2), (claudeStatus, 3)] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = NSColor.white.withAlphaComponent(0.5)
            label.maximumNumberOfLines = lines
            label.isHidden = true
        }
        interrupt.target = self
        interrupt.action = #selector(interruptTurn)
        interrupt.toolTip = WSL10n.text("conductor.stop.tip", zh: "请求停止当前这一轮，等助手确认后才显示已停止。")
        claudeStop.target = self
        claudeStop.action = #selector(stopClaude)
        let hints = NSStackView(views: [remoteHint, receipt, status, claudeStatus])
        hints.orientation = .vertical
        hints.alignment = .leading
        hints.spacing = 2
        for label in [remoteHint, receipt, status, claudeStatus] { label.widthAnchor.constraint(equalTo: hints.widthAnchor).isActive = true }
        hints.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [hints, interrupt, claudeStop])
        footer.spacing = 8
        footer.alignment = .top
        stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        input.onActivate = { [weak self] id in self?.activate(id) ?? false }
        input.onCancel = { [weak self] in self?.onCancel?() }
        updateBackendVisibility()
        sync()
    }

    required init?(coder: NSCoder) { nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { cancelVoice(); claudeConductor.stop() }
    }

    /// 应用退出：把 Claude 的子进程一起停掉（页面这时可能还挂在刘海里，不会走 viewWillMove）。
    func shutdownBackends() { claudeConductor.stop() }

    /// Claude 开关：没装就灰着并说明；上一轮没登录就在名字后面标出来。
    private func refreshClaudeSwitch() {
        let installed = claudeConductor.isInstalled
        let base = WSL10n.text("conductor.backend.claude", zh: "Claude（只读）")
        let marked = claudeConductor.needsLogin
            ? base + " · " + WSL10n.text("conductor.backend.signedOut", zh: "没登录") : base
        if backend.label(forSegment: 1) != marked { backend.setLabel(marked, forSegment: 1) }
        backend.setEnabled(installed, forSegment: 1)
        backend.claudeUnavailable = !installed
        backend.toolTip = installed ? nil
            : WSL10n.text("conductor.claude.notInstalled", zh: "这台 Mac 上没有找到 Claude Code")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusObservers.forEach { NotificationCenter.default.removeObserver($0) }
        focusObservers.removeAll()
        guard let window else { changedEnvironment?(); return }
        focusObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.input.cancelAll()
                    self?.sync()
                    self?.changedEnvironment?()
                }
            })
        for (name, object) in [(NSWindow.didBecomeKeyNotification, window as AnyObject),
                               (NSApplication.didBecomeActiveNotification, NSApp as AnyObject)] {
            focusObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sync(); self?.changedEnvironment?() }
                })
        }
        changedEnvironment?()
    }

    func sync() {
        if isClaudeBackend { renderClaude(); return }
        let snap = snapshot()
        let target = controller.conductorTarget
        if displayedTarget != target {
            input.cancelAll()
            displayedTarget = target
            remoteTargetChanged?(target?.context)
        }
        displayedTurn = controller.conductorTurn
        if displayedTurn == nil { runningEffort = nil; lastSeenTurn = nil }
        else if displayedTurn != lastSeenTurn { lastSeenTurn = displayedTurn; runningEffort = controller.effort }
        if let target, let row = snap.rows.first(where: { $0.id == target.context.session && $0.revision == target.context.epoch }) {
            highlighted = .init(id: row.id, revision: row.revision, listRevision: snap.listRevision)
        }
        if let highlighted, !snap.confirm(highlighted) { self.highlighted = nil }
        renderSessions(snap)
        renderMenus(snap)
        if editor.currentEditor() == nil, editor.stringValue != snap.draft {
            editor.stringValue = snap.draft
        }
        syncActions()
        receipt.stringValue = controller.status + (controller.notice.isEmpty ? "" : " · " + controller.notice)
        input.ready = isInputReady
        enableButton.isEnabled = isInputReady && !shownDevices.isEmpty
    }

    private func syncActions() {
        if let value = adoptedDraft, !controller.acceptsConductorDraft(value) { adoptedDraft = nil }
        let marked = (editor.currentEditor() as? NSTextView)?.hasMarkedText() == true
        write.isEnabled = inputIsCurrent() && controller.conductorTarget != nil && !marked
        send.title = adoptedDraft?.turn == nil ? WSL10n.text("conductor.send", zh: "发送")
                                                   : WSL10n.text("conductor.send.steer", zh: "补进本轮")
        send.isEnabled = inputIsCurrent() && !marked && adoptedDraft?.text == editor.stringValue && adoptedDraft != nil
        interrupt.isEnabled = inputIsCurrent() && controller.canInterrupt && displayedTarget != nil && displayedTurn != nil
        discard.isEnabled = inputIsCurrent() && !editor.stringValue.isEmpty
        refreshDraftState()
        applyVisibility()
    }

    /// 草稿卡上的一行小字：草稿 · 在听 / 已采用。听写时声波亮起、话筒实心。
    private func refreshDraftState() {
        var text = WSL10n.text("conductor.draftPlaceholder", zh: "草稿")
        if voice != nil { text += " · " + WSL10n.text("conductor.voice.listening", zh: "在听…松手出草稿") }
        else if !isClaudeBackend, adoptedDraft != nil { text += " · " + WSL10n.text("conductor.status.adopted", zh: "已采用，还没发送") }
        draftState.stringValue = text
        wave.isHidden = voice == nil
        speak.isLive = voice != nil
    }

    private func headerTitle() -> String {
        guard let project = controller.projectURL?.lastPathComponent, !project.isEmpty else {
            return WSL10n.text("conductor.title", zh: "指挥")
        }
        return project + " · " + (isClaudeBackend ? "Claude Code" : "Codex")
    }

    /// 哪些东西这一刻露出来：随助手、随有没有可停的一轮、有没有可丢的草稿。
    private func applyVisibility() {
        let claude = isClaudeBackend
        title.stringValue = headerTitle()
        let claudeRunning = claudeConductor.status == .running
        runningLabel.isHidden = !(claude ? claudeRunning : displayedTurn != nil)
        // Claude 在回答时不能切走（切走会停掉这一轮）；Codex 那一边切换不动它的会话。
        backend.isEnabled = !(claude && claudeRunning)
        sessionsScroll.isHidden = claude
        menus.isHidden = claude
        devices.isHidden = claude
        claudeScroll.isHidden = !claude
        write.isHidden = claude || adoptedDraft != nil
        send.isHidden = claude || adoptedDraft == nil
        claudeSend.isHidden = !claude
        interrupt.isHidden = claude || !interrupt.isEnabled
        claudeStop.isHidden = !claude || !claudeStop.isEnabled
        discard.isHidden = !discard.isEnabled
        receipt.allowed = !claude
        status.allowed = !claude
        claudeStatus.allowed = claude
    }

    func controlTextDidChange(_ notification: Notification) {
        if isClaudeBackend { renderClaude(); return }
        guard notification.object as? NSTextField === editor else { return }
        // Editing after adoption requires a new adoption. Never send a hidden older editor value.
        adoptedDraft = nil
        if inputIsCurrent(), controller.conductorTarget != nil { _ = controller.editDraft(editor.stringValue) }
        syncActions()
    }

    func renderDevices(_ devices: [WS2ControllerDevice]) {
        let previous = deviceMenu.indexOfSelectedItem
        let chosen = shownDevices.indices.contains(previous) ? shownDevices[previous].attachment : nil
        shownDevices = devices
        deviceMenu.removeAllItems()
        for (index, device) in devices.enumerated() {
            let clean = String(String.UnicodeScalarView(device.label.unicodeScalars.filter {
                $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
            })).prefix(64)
            let padName = clean.isEmpty ? WSL10n.text("conductor.pad.generic", zh: "游戏手柄") : String(clean)
            let enabledMark = device.enabled ? " · " + WSL10n.text("conductor.pad.enabled", zh: "已启用") : ""
            deviceMenu.addItem(withTitle: "\(index + 1). \(padName)\(enabledMark)")
        }
        if let chosen, let index = devices.firstIndex(where: { $0.attachment == chosen }) {
            deviceMenu.selectItem(at: index)
        }
        enableButton.title = devices.contains(where: \.enabled) ? WSL10n.text("conductor.pad.disable", zh: "停用手柄")
                                                                  : WSL10n.text("conductor.enableNow", zh: "本次启用")
        if devices.contains(where: \.enabled) {
            status.stringValue = WSL10n.text("conductor.pad.status.unnamed", zh: "方向键选择这一条。确认键的名字还没按这只手柄核对。离开这一页就停用。")
        } else if devices.isEmpty {
            status.stringValue = WSL10n.text("conductor.pad.status.none", zh: "没有检测到游戏手柄。可以用指针选择。")
        } else {
            status.stringValue = WSL10n.text("conductor.pad.status.release", zh: "启用前先松开按键。只操作当前这张列表。")
        }
        enableButton.isEnabled = isInputReady && !devices.isEmpty
    }

    func noteDevicesBusy() {
        status.stringValue = WSL10n.text("conductor.pad.status.elsewhere", zh: "手柄还在另一页，这里先只用指针。")
    }

    func revoke() {
        input.revoke()
        claudeConductor.stop()
        // 收起不删东西：先把 Claude 那一侧的草稿交出去，再清这一页（拍板 10-29 第 2 条）。
        let text = isClaudeBackend ? editor.stringValue : claudeDraft
        onKeepDraft?(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? KeptDraft(claude: true, text: text) : nil)
        claudeDraft = ""
        inputIsCurrent = { false }
        expectedLease = nil
        focusObservers.forEach { NotificationCenter.default.removeObserver($0) }
        focusObservers.removeAll()
        editor.stringValue = ""
        adoptedDraft = nil; displayedTarget = nil; displayedTurn = nil
        changedEnvironment?()
        onCancel?()
    }

    var ready: Bool { isInputReady }
    var motionReady: Bool { false }
    func prepare(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool {
        input.ready = isInputReady
        return input.prepare(ticket)
    }
    func cancelPrepared(context: WS2SemanticInputRouter.Context, presses: [UInt64]) {
        input.cancel(context: context, presses: presses)
    }
    func execute(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool {
        input.ready = isInputReady
        return input.execute(ticket)
    }
    func move(_ effect: GamepadMapping.Effect, context: WS2SemanticInputRouter.Context) -> Bool { false }

    private func snapshot() -> ConductorPageSnapshot {
        let rows = controller.conductorSessions.map { session in
            ConductorPageSnapshot.Row(id: session.context.session, revision: session.context.epoch,
                                      label: label(session))
        }
        let snap = ConductorPageSnapshot.assemble(sessions: rows, previousRows: previousRows,
                                                  previousListRevision: previousListRevision,
                                                  model: controller.model, effort: controller.effort,
                                                  draft: controller.draft)
        previousRows = snap.rows
        previousListRevision = snap.listRevision
        return snap
    }

    private func label(_ session: AgentSessions.Session) -> String {
        let tail = String(String.UnicodeScalarView(session.context.session.id.unicodeScalars.filter {
            $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
        })).suffix(8)
        let name = session.context.session.provider.displayName + " · " + tail
        let summary = session.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty { return name }
        return name + " · " + String(summary.prefix(80))
    }

    private func listID(_ id: WS2.SessionKey) -> String {
        id.provider.rawValue + "\u{1e}" + id.id
    }

    private func renderSessions(_ snap: ConductorPageSnapshot) {
        let rows = Array(snap.rows.prefix(64))
        let identity = rows.map { Shown(id: listID($0.id), revision: $0.revision) }
        let selected = highlighted.flatMap { snap.confirm($0) ? listID($0.id) : nil }
        if identity != renderedIdentity {
            renderedIdentity = identity
            for view in sessions.arrangedSubviews {
                sessions.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            bound.removeAll()
            if rows.isEmpty {
                let none = NSTextField(labelWithString: WSL10n.text("conductor.sessions.none", zh: "还没有会话"))
                none.font = .systemFont(ofSize: 12)
                none.textColor = NSColor.white.withAlphaComponent(0.6)
                sessions.addArrangedSubview(none)
            }
            for row in rows {
                let button = NSButton(title: row.label, target: self, action: #selector(pickSession(_:)))
                button.isBordered = false
                button.wantsLayer = true
                button.layer?.cornerRadius = 8
                button.alignment = .left
                button.lineBreakMode = .byTruncatingTail
                bound[listID(row.id)] = row
                button.identifier = NSUserInterfaceItemIdentifier(listID(row.id))
                sessions.addArrangedSubview(button)
                button.widthAnchor.constraint(equalTo: sessions.widthAnchor).isActive = true
                button.heightAnchor.constraint(equalToConstant: 24).isActive = true
            }
            do { try input.replace(rows.map { .init(id: listID($0.id), enabled: true) }, selectedID: selected) }
            catch {
                input.revoke()
                renderedIdentity = nil
                status.stringValue = WSL10n.text("conductor.list.unavailable", zh: "这张列表暂时不能用")
            }
        } else {
            for row in rows { bound[listID(row.id)] = row }
            if let selected { _ = input.select(selected) }
        }
        for case let button as NSButton in sessions.arrangedSubviews {
            guard let id = button.identifier?.rawValue, let row = bound[id] else { continue }
            let chosen = highlighted?.id == row.id && highlighted?.revision == row.revision
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            // 选中不只靠底色：标题前多一个 ✓。
            button.attributedTitle = NSAttributedString(string: (chosen ? "✓ " : "") + row.label, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: chosen ? .semibold : .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(chosen ? 1 : 0.82),
                .paragraphStyle: paragraph])
            button.layer?.backgroundColor = NSColor.white.withAlphaComponent(chosen ? 0.14 : 0).cgColor
        }
    }

    private func renderMenus(_ snap: ConductorPageSnapshot) {
        let models = controller.models.keys.sorted()
        if models != modelIDs || modelMenu.numberOfItems == 0 {
            modelIDs = models
            rendering = true
            modelMenu.removeAllItems()
            modelMenu.addItems(withTitles: [WSL10n.text("conductor.pickModel", zh: "请选择模型")] + models)
            rendering = false
        }
        rendering = true
        modelMenu.selectItem(at: snap.model.flatMap { modelIDs.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        rendering = false
        let efforts = Self.orderedEfforts(snap.model.flatMap { controller.models[$0] } ?? [])
        effortIDs = efforts
        effortLabel.isHidden = efforts.isEmpty
        effortChips.configure(
            choices: efforts,
            next: snap.effort.flatMap { efforts.firstIndex(of: $0) },
            running: displayedTurn == nil ? nil : runningEffort.flatMap { efforts.firstIndex(of: $0) })
        let fresh = inputIsCurrent()
        modelMenu.isEnabled = fresh && displayedTarget != nil && !modelIDs.isEmpty && controller.canStageConductorConfig
        effortChips.isEnabled = fresh && displayedTarget != nil && controller.model != nil && controller.canStageConductorConfig
    }

    @objc private func pickSession(_ sender: NSButton) {
        guard inputIsCurrent(), let id = sender.identifier?.rawValue, let row = bound[id] else { return }
        let snap = snapshot()
        let selection = ConductorPageSnapshot.Selection(id: row.id, revision: row.revision, listRevision: snap.listRevision)
        guard case .success = snap.acceptSelection(selection) else {
            status.stringValue = WSL10n.text("conductor.status.rowChanged", zh: "这一条已经变了")
            sync()
            return
        }
        guard controller.selectConductorSession(selection.id, revision: selection.revision) else {
            status.stringValue = WSL10n.text("conductor.status.afterTurn", zh: "这一轮结束后再切换")
            sync()
            return
        }
        adoptedDraft = nil
        input.cancelAll()
        sync()
    }

    private func activate(_ id: String) -> Bool {
        guard isInputReady, let row = bound[id] else { return false }
        let snap = snapshot()
        let selection = ConductorPageSnapshot.Selection(id: row.id, revision: row.revision, listRevision: snap.listRevision)
        guard case .success = snap.acceptSelection(selection) else { return false }
        guard controller.selectConductorSession(selection.id, revision: selection.revision) else { return false }
        adoptedDraft = nil
        sync()
        return true
    }

    @objc private func pickModel() {
        guard !rendering, inputIsCurrent(), modelMenu.indexOfSelectedItem > 0,
              modelIDs.indices.contains(modelMenu.indexOfSelectedItem - 1) else { return }
        let id = modelIDs[modelMenu.indexOfSelectedItem - 1]
        guard let target = displayedTarget,
              ConductorPageSnapshot.acceptChoice(id, catalogue: Set(controller.models.keys)),
              controller.stageConductorModel(id, target: target) else { sync(); return }
    }

    /// 稿里程度从低到高排；认不得的名字排在后面，彼此按字母。
    private static let effortOrder = ["minimal", "low", "medium", "high", "xhigh", "max"]
    private static func orderedEfforts(_ values: Set<String>) -> [String] {
        func rank(_ value: String) -> Int { effortOrder.firstIndex(of: value) ?? effortOrder.count }
        return values.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0 < $1 }
    }

    private func pickEffort(_ index: Int) {
        guard !rendering, inputIsCurrent(), effortIDs.indices.contains(index) else { return }
        let id = effortIDs[index]
        let choices: Set<String> = controller.model.flatMap { controller.models[$0] } ?? []
        guard let target = displayedTarget,
              ConductorPageSnapshot.acceptChoice(id, catalogue: choices),
              controller.stageConductorEffort(id, target: target) else { sync(); return }
        // 描边马上换格（sync 会用同一份数据再画一次，值不变）。
        sync()
    }

    @objc private func backPressed() { remoteBack() }

    @objc private func pickBackend() {
        cancelVoice()
        if isClaudeBackend {
            _ = claudeConductor.ensure()
        } else {
            claudeConductor.stop()
        }
        if claudeShown { claudeDraft = editor.stringValue }
        claudeShown = isClaudeBackend
        editor.stringValue = isClaudeBackend ? claudeDraft : ""
        remoteNotch("")
        updateBackendVisibility()
        remoteTargetChanged?(isClaudeBackend ? nil : controller.conductorTarget?.context)
        sync()
    }

    private func updateBackendVisibility() {
        let claude = isClaudeBackend
        editor.placeholderString = claude
            ? WSL10n.text("conductor.claude.placeholder", zh: "对 Claude 说一句")
            : WSL10n.text("conductor.draft.hint", zh: "按住说话，或在这里打字")
        applyVisibility()
        refreshDraftState()
        if claude { renderClaude() }
    }

    private func renderClaude() {
        guard isClaudeBackend else { return }
        refreshClaudeSwitch()
        claudeStatus.stringValue = claudeBackendStatus()
        if shownTranscript != claudeConductor.transcript {
            shownTranscript = claudeConductor.transcript
            renderTranscript(shownTranscript)
            claudeText.scrollToEndOfDocument(nil)
        }
        let hasText = !editor.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        claudeSend.isEnabled = inputIsCurrent() && hasText &&
            claudeConductor.status != .missing && claudeConductor.status != .running
        claudeStop.isEnabled = inputIsCurrent() && claudeConductor.status == .running
        discard.isEnabled = inputIsCurrent() && !editor.stringValue.isEmpty
        refreshDraftState()
        applyVisibility()
    }

    /// 转写：只读模式拒绝的操作用琥珀色单列一行，前面带 ⚠︎，不只靠颜色，也不藏。
    private func renderTranscript(_ text: String) {
        let font = NSFont.systemFont(ofSize: 11.5)
        let out = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let denied = line.hasPrefix("（只读模式")
            let color: NSColor = denied ? .systemOrange : NSColor.white.withAlphaComponent(0.82)
            out.append(NSAttributedString(string: (denied ? "⚠︎ " : "") + line + (index < lines.count - 1 ? "\n" : ""),
                                          attributes: [.font: font, .foregroundColor: color]))
        }
        claudeText.textStorage?.setAttributedString(out)
    }

    private func claudeBackendStatus() -> String {
        switch claudeConductor.status {
        case .idle:
            return WSL10n.text("conductor.claude.idle", zh: "还没有连接 Claude。")
        case .missing:
            return WSL10n.text("conductor.claude.missing", zh: "没找到 claude 命令；先安装 Claude Code，或把它放进 /opt/homebrew/bin、/usr/local/bin、~/.local/bin。")
        case .ready:
            let base = WSL10n.text("conductor.claude.ready", zh: "只读模式：不会改文件，工具请求会被拒绝。")
            return claudeConductor.model.map { base + " · " + $0 } ?? base
        case .running:
            let base = WSL10n.text("conductor.claude.running", zh: "正在回答…")
            let tail = " · " + WSL10n.text("conductor.status.afterTurn", zh: "这一轮结束后再切换")
            return (claudeConductor.model.map { base + " · " + $0 } ?? base) + tail
        case .ended:
            return WSL10n.text("conductor.claude.ended", zh: "这一轮结束了；再发送会接上同一段对话。")
        }
    }

    @objc private func sendClaudeDraft() {
        guard inputIsCurrent() else { return }
        let text = editor.stringValue
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if claudeConductor.send(text) { editor.stringValue = "" }
        renderClaude()
    }

    @objc private func stopClaude() {
        claudeConductor.interrupt()
        renderClaude()
    }

    /// 手机遥控的播放/选择：发送当前草稿（Codex 先采用再发送，Claude 直接发）。
    @discardableResult func remoteSend() -> Bool {
        guard inputIsCurrent() else { return false }
        guard !editor.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if isClaudeBackend {
            sendClaudeDraft()
            return true
        }
        commitDraft()
        guard adoptedDraft != nil else { return false }
        sendDraft()
        return adoptedDraft == nil
    }

    /// 手机遥控的返回：收起指挥页，草稿留着（收起时 `revoke` 交给 `onKeepDraft`）。
    func remoteBack() { onCancel?() }

    /// 打开时放回上次收起留下的草稿。
    func restore(_ kept: KeptDraft) {
        guard kept.claude else { return }
        backend.selectedSegment = 1
        pickBackend()
        editor.stringValue = kept.text
        renderClaude()
    }

    @objc private func discardDraft() {
        guard inputIsCurrent() else { return }
        cancelVoice()
        editor.stringValue = ""
        if isClaudeBackend { renderClaude(); return }
        adoptedDraft = nil
        // 没有目标时 controller 里也可能还留着草稿（会话断开／停下），一样清掉，否则下一次 sync 会放回来。
        _ = controller.editDraft("")
        syncActions()
    }

    @objc private func goToSession() { goThere?() }

    /// 手机遥控会话的即时提示（画到第几拍、认出了什么、等待确认……）。
    func remoteNotch(_ text: String) {
        // 只在 iPhone 连着时出现，一行（稿）；手机上画到哪一拍由刘海右耳说，页面里不重复。
        remoteHint.stringValue = text.isEmpty ? "" : WSL10n.text("conductor.remote.hint", zh: "iPhone 已连接 · 播放键 = 发送 · 返回 = 收起")
        remoteHint.setAccessibilityValue(text)
    }

    // 页面级探针（--conductor-claude-probe）：不产生用户可见入口，只给自驱验收调。
    var probeInputIsCurrent: Bool { inputIsCurrent() }
    var probeIsClaude: Bool { isClaudeBackend }
    var probeClaudeStatus: ClaudeConductor.Status { claudeConductor.status }
    var probeClaudeTranscript: String { claudeConductor.transcript }
    var probeClaudeNeedsLogin: Bool { claudeConductor.needsLogin }
    var probeBackendLabelMentionsLogin: Bool { (backend.label(forSegment: 1) ?? "").contains(WSL10n.text("conductor.backend.signedOut", zh: "没登录")) }
    func probeSelectClaude() { backend.selectedSegment = 1; pickBackend() }
    func probeSelectCodex() { backend.selectedSegment = 0; pickBackend() }
    func probeSetDraft(_ text: String) { editor.stringValue = text; renderClaude() }
    func probeSend() { sendClaudeDraft() }
    func probeStop() { stopClaude() }
    var probeDraft: String { editor.stringValue }
    var probeHasGoThere: Bool { goThere != nil && !goButton.isHidden }
    func probeDiscard() { discardDraft() }

    @objc private func speakPressed(_ sender: NSButton) {
        switch NSApp.currentEvent?.type {
        case .leftMouseDown: beginVoice()
        case .leftMouseUp: endVoice()
        default:
            if voice == nil { beginVoice() } else { endVoice() }
        }
    }

    private var voiceStatusLabel: NSTextField { isClaudeBackend ? claudeStatus : status }

    private func beginVoice() {
        guard inputIsCurrent(), voice == nil else { return }
        var session = VoiceDraftSession()
        guard session.start(at: ProcessInfo.processInfo.systemUptime) else { return }
        voice = session
        refreshDraftState()
        voiceStatusLabel.stringValue = WSL10n.text("conductor.voice.listening", zh: "在听…松手出草稿")
        transcriber.start(onPartial: { [weak self] text in
            guard let self, var session = self.voice else { return }
            session.update(text)
            self.voice = session
            self.voiceStatusLabel.stringValue = text
        }, onFinish: { [weak self] result in
            self?.finishVoice(result)
        })
        voiceTick?.cancel()
        voiceTick = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, var session = self.voice else { return }
                if session.tick(at: ProcessInfo.processInfo.systemUptime) {
                    self.voice = nil
                    self.refreshDraftState()
                    self.transcriber.cancel()
                    self.voiceStatusLabel.stringValue = self.voiceFailureText(.tooLong)
                    return
                }
                self.voice = session
            }
        }
    }

    private func endVoice() {
        guard var session = voice else { return }
        session.stop(at: ProcessInfo.processInfo.systemUptime)
        voice = session
        voiceStatusLabel.stringValue = WSL10n.text("conductor.voice.transcribing", zh: "在转写…")
        transcriber.stop()
    }

    private func finishVoice(_ result: Result<String, VoiceDraftSession.Failure>) {
        voiceTick?.cancel(); voiceTick = nil
        guard var session = voice else { return }
        session.finish(result)
        voice = nil
        refreshDraftState()
        if let draft = session.draft {
            editor.stringValue = draft
            voiceStatusLabel.stringValue = ""
            if isClaudeBackend { renderClaude() }
        } else if let failure = session.failure {
            voiceStatusLabel.stringValue = voiceFailureText(failure)
        }
    }

    private func cancelVoice() {
        voiceTick?.cancel(); voiceTick = nil
        transcriber.cancel()
        voice = nil
        refreshDraftState()
    }

    private func voiceFailureText(_ failure: VoiceDraftSession.Failure) -> String {
        switch failure {
        case .notAuthorized:
            return WSL10n.text("conductor.voice.notAuthorized", zh: "先允许麦克风和语音识别，再按住说话。")
        case .onDeviceUnavailable:
            return WSL10n.text("conductor.voice.onDeviceUnavailable", zh: "这台 Mac 不能在本机识别；语音草稿停用，不会改用云端。")
        case .empty:
            return WSL10n.text("conductor.voice.empty", zh: "没听清，再说一次。")
        case .tooLong:
            return WSL10n.text("conductor.voice.tooLong", zh: "说到 60 秒就停了，草稿没留下。")
        case .interrupted:
            return WSL10n.text("conductor.voice.interrupted", zh: "识别中断了，再说一次。")
        }
    }

    @objc private func commitDraft() {
        guard inputIsCurrent() else { return }
        let marked = (editor.currentEditor() as? NSTextView)?.hasMarkedText() == true
        let before = snapshot()
        let selection = highlighted.flatMap { before.confirm($0) ? $0 : nil }
        switch before.freezeDraft(text: editor.stringValue, hasMarkedText: marked, selection: selection) {
        case .failure(.markedText):
            status.stringValue = WSL10n.text("conductor.status.typing", zh: "还在输入，草稿留着")
        case .failure:
            status.stringValue = WSL10n.text("conductor.status.rowChangedDraftKept", zh: "这一条已经变了，草稿留着")
        case .success(let frozen):
            let live = snapshot()
            switch live.acceptDraft(frozen) {
            case .success(let accepted):
                if let target = displayedTarget,
                   let adopted = controller.adoptConductorDraft(accepted.text, hasMarkedText: marked, target: target) {
                    adoptedDraft = adopted
                    status.stringValue = WSL10n.text("conductor.status.adopted", zh: "已采用，还没发送")
                } else {
                    status.stringValue = WSL10n.text("conductor.status.cannotAdopt", zh: "还不能采用，草稿留着")
                }
            case .failure(.staleModel), .failure(.staleEffort):
                status.stringValue = WSL10n.text("conductor.status.configChanged", zh: "模型和档位已经变了，草稿留着")
            case .failure:
                status.stringValue = WSL10n.text("conductor.status.rowChangedDraftKept", zh: "这一条已经变了，草稿留着")
            }
        }
        sync()
    }

    @objc private func sendDraft() {
        guard inputIsCurrent(), let value = adoptedDraft, editor.stringValue == value.text else { return }
        let marked = (editor.currentEditor() as? NSTextView)?.hasMarkedText() == true
        let accepted: Bool
        if value.turn == nil { accepted = controller.sendConductorDraft(value, hasMarkedText: marked) }
        else { accepted = controller.addConductorDraftToTurn(value, hasMarkedText: marked) }
        if accepted { adoptedDraft = nil }
        else { status.stringValue = WSL10n.text("conductor.status.sessionChanged", zh: "会话已经变了，请重新采用草稿") }
        sync()
    }

    @objc private func interruptTurn() {
        guard inputIsCurrent(), let target = displayedTarget, let turn = displayedTurn else { return }
        _ = controller.interruptConductor(target: target, turn: turn)
        sync()
    }

    @objc private func toggleDevice() {
        guard inputIsCurrent() else { return }
        if let enabled = shownDevices.first(where: \.enabled) {
            disableDevice?(enabled.attachment)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        sync()
        guard isInputReady, shownDevices.indices.contains(deviceMenu.indexOfSelectedItem) else { return }
        let id = shownDevices[deviceMenu.indexOfSelectedItem].attachment
        if enableDevice?(id) != true {
            status.stringValue = WS2GamepadHandlerSeats.shared.desktopHoldsAny
                ? WSL10n.text("conductor.pad.status.turnOffInSettings", zh: "先在设置里关掉控制这台 Mac")
                : WSL10n.text("conductor.pad.status.enableFailed", zh: "未能启用。请点一下这一页，再松开所有按键。")
        }
    }
}

/// 助手开关。Claude 那一格没装时是灰的，但点它要能打开设置：灰掉的格子系统不回应，所以在这里接住。
@MainActor final class WS2BackendControl: NSSegmentedControl {
    var claudeUnavailable = false
    var onUnavailableClaudeClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard claudeUnavailable, segmentCount == 2 else { super.mouseDown(with: event); return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let first = NSAttributedString(string: label(forSegment: 0) ?? "", attributes: attributes).size().width
        let second = NSAttributedString(string: label(forSegment: 1) ?? "", attributes: attributes).size().width
        let boundary = bounds.width * first / max(first + second, 1)
        if convert(event.locationInWindow, from: nil).x > boundary { onUnavailableClaudeClick?() }
        else { super.mouseDown(with: event) }
    }
}
