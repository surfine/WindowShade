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

    private let controller: WS2OwnedLaunchController
    private let title = NSTextField(labelWithString: WSL10n.text("conductor.title", zh: "指挥"))
    private let goButton = NSButton(title: WSL10n.text("notch.action.goThere", zh: "过去"), target: nil, action: nil)
    private let discard = NSButton(title: WSL10n.text("conductor.discard", zh: "丢弃"), target: nil, action: nil)
    private let sessions = NSStackView()
    private let modelMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let effortMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let editor = NSTextField(string: "")
    private let speak = NSButton(title: WSL10n.text("conductor.speak", zh: "按住说话"), target: nil, action: nil)
    private let transcriber: any VoiceTranscriber
    private var voice: VoiceDraftSession?
    private var voiceTick: Task<Void, Never>?
    private let write = NSButton(title: WSL10n.text("conductor.adoptDraft", zh: "采用草稿"), target: nil, action: nil)
    private let send = NSButton(title: WSL10n.text("conductor.send", zh: "发送"), target: nil, action: nil)
    private let interrupt = NSButton(title: WSL10n.text("conductor.stopTurn", zh: "停止本轮"), target: nil, action: nil)
    private let backendMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let claudeConductor: ClaudeConductor
    private let claudeStatus = NSTextField(wrappingLabelWithString: "")
    private let claudeScroll = NSScrollView()
    private let claudeText = NSTextView()
    private let claudeActions = NSStackView()
    private let claudeSpeak = NSButton(title: WSL10n.text("conductor.speak", zh: "按住说话"), target: nil, action: nil)
    private let claudeSend = NSButton(title: WSL10n.text("conductor.send", zh: "发送"), target: nil, action: nil)
    private let claudeStop = NSButton(title: WSL10n.text("conductor.stopTurn", zh: "停止本轮"), target: nil, action: nil)
    private let remoteHint = NSTextField(wrappingLabelWithString: "")
    private let menus = NSStackView()
    private let actions = NSStackView()
    private let devices = NSStackView()
    private let receipt = NSTextField(wrappingLabelWithString: "")
    private var adoptedDraft: WS2OwnedLaunchController.ConductorDraft?
    private var displayedTarget: WS2OwnedLaunchController.ConductorTarget?
    private var displayedTurn: String?
    private let deviceMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let enableButton = NSButton(title: WSL10n.text("conductor.enableNow", zh: "本次启用"), target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
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

    var isClaudeBackend: Bool { backendMenu.indexOfSelectedItem == 1 }
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
        self.claudeConductor = ClaudeConductor(workingDirectory: projectURL, mayUse: { true })
        super.init(frame: .zero)
        claudeConductor.onChange = { [weak self] in self?.renderClaude() }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
        ])
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        // 页头：标题 + “过去”（去会话所在的终端窗口）。
        goButton.target = self
        goButton.action = #selector(goToSession)
        goButton.bezelStyle = .rounded
        goButton.isHidden = true
        let header = NSStackView(views: [title, goButton])
        header.spacing = 8
        stack.addArrangedSubview(header)
        backendMenu.addItems(withTitles: [
            WSL10n.text("conductor.backend.codex", zh: "Codex"),
            WSL10n.text("conductor.backend.claude", zh: "Claude（只读）"),
        ])
        backendMenu.target = self
        backendMenu.action = #selector(pickBackend)
        backendMenu.setAccessibilityLabel(WSL10n.text("conductor.backend.label", zh: "助手"))
        stack.addArrangedSubview(backendMenu)
        remoteHint.font = .systemFont(ofSize: 11)
        remoteHint.textColor = .secondaryLabelColor
        remoteHint.maximumNumberOfLines = 2
        remoteHint.isHidden = true
        stack.addArrangedSubview(remoteHint)
        remoteHint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        sessions.orientation = .vertical
        sessions.alignment = .leading
        sessions.spacing = 4
        stack.addArrangedSubview(sessions)
        modelMenu.setAccessibilityLabel(WSL10n.text("conductor.nextModel", zh: "下一轮模型"))
        effortMenu.setAccessibilityLabel(WSL10n.text("conductor.nextEffort", zh: "下一轮思考程度"))
        modelMenu.toolTip = WSL10n.text("conductor.nextModel.tip", zh: "下一轮使用的模型，不改变正在运行的这一轮。")
        effortMenu.toolTip = WSL10n.text("conductor.nextEffort.tip", zh: "下一轮使用的思考程度，不改变正在运行的这一轮。")
        modelMenu.target = self
        modelMenu.action = #selector(pickModel)
        effortMenu.target = self
        effortMenu.action = #selector(pickEffort)
        let nextLabel = NSTextField(labelWithString: WSL10n.text("conductor.nextRound", zh: "下一轮"))
        menus.orientation = .horizontal
        menus.spacing = 8
        [nextLabel, modelMenu, effortMenu].forEach { menus.addArrangedSubview($0) }
        stack.addArrangedSubview(menus)
        editor.placeholderString = WSL10n.text("conductor.draftPlaceholder", zh: "草稿")
        editor.setAccessibilityLabel(WSL10n.text("conductor.draftLabel", zh: "待记下的草稿"))
        editor.isEditable = true
        editor.isBezeled = true
        editor.delegate = self
        // 丢弃挨着草稿框：两种助手共用这一个框，也共用这一个键。草稿只在这里丢；返回、收起都留着。
        discard.target = self
        discard.action = #selector(discardDraft)
        discard.bezelStyle = .rounded
        discard.toolTip = WSL10n.text("conductor.discard.tip", zh: "清空这份草稿。返回或收起页面不会清空。")
        discard.setContentHuggingPriority(.required, for: .horizontal)
        discard.setContentCompressionResistancePriority(.required, for: .horizontal)
        let draftRow = NSStackView(views: [editor, discard])
        draftRow.distribution = .fill
        draftRow.spacing = 8
        stack.addArrangedSubview(draftRow)
        draftRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        write.target = self
        write.action = #selector(commitDraft)
        write.bezelStyle = .rounded
        write.toolTip = WSL10n.text("conductor.write.tip", zh: "只把现在的文字留在这台 Mac 上。不会发给助手。")
        send.target = self
        send.action = #selector(sendDraft)
        send.bezelStyle = .rounded
        send.toolTip = WSL10n.text("conductor.send.tip", zh: "只发送已采用的草稿。运行时补进当前这一轮，下一轮的模型和档位不会改动这一轮。")
        interrupt.target = self
        interrupt.action = #selector(interruptTurn)
        interrupt.bezelStyle = .rounded
        interrupt.toolTip = WSL10n.text("conductor.stop.tip", zh: "请求停止当前这一轮，等助手确认后才显示已停止。")
        speak.target = self
        speak.action = #selector(speakPressed(_:))
        _ = speak.sendAction(on: [.leftMouseDown, .leftMouseUp])
        speak.bezelStyle = .rounded
        speak.toolTip = WSL10n.text("conductor.speak.tip", zh: "按住说一句，松手得到草稿；只在这台 Mac 上识别。")
        actions.spacing = 8
        [speak, write, send, interrupt].forEach { actions.addArrangedSubview($0) }
        stack.addArrangedSubview(actions)
        receipt.font = .systemFont(ofSize: 11)
        receipt.textColor = .secondaryLabelColor
        receipt.maximumNumberOfLines = 2
        stack.addArrangedSubview(receipt)
        receipt.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        deviceMenu.setAccessibilityLabel(WSL10n.text("conductor.pad.label", zh: "本次连接的手柄"))
        enableButton.target = self
        enableButton.action = #selector(toggleDevice)
        enableButton.image = NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: nil)
        devices.spacing = 8
        [deviceMenu, enableButton].forEach { devices.addArrangedSubview($0) }
        stack.addArrangedSubview(devices)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 2
        stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        claudeStatus.font = .systemFont(ofSize: 11)
        claudeStatus.textColor = .secondaryLabelColor
        claudeStatus.maximumNumberOfLines = 3
        stack.addArrangedSubview(claudeStatus)
        claudeStatus.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        claudeText.isEditable = false
        claudeText.isSelectable = true
        claudeText.drawsBackground = false
        claudeText.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        claudeText.isVerticallyResizable = true
        claudeText.autoresizingMask = [.width]
        claudeScroll.documentView = claudeText
        claudeScroll.hasVerticalScroller = true
        claudeScroll.borderType = .bezelBorder
        stack.addArrangedSubview(claudeScroll)
        claudeScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        claudeScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        claudeSpeak.target = self
        claudeSpeak.action = #selector(speakPressed(_:))
        _ = claudeSpeak.sendAction(on: [.leftMouseDown, .leftMouseUp])
        claudeSpeak.bezelStyle = .rounded
        claudeSpeak.toolTip = WSL10n.text("conductor.speak.tip", zh: "按住说一句，松手得到草稿；只在这台 Mac 上识别。")
        claudeSend.target = self
        claudeSend.action = #selector(sendClaudeDraft)
        claudeSend.bezelStyle = .rounded
        claudeStop.target = self
        claudeStop.action = #selector(stopClaude)
        claudeStop.bezelStyle = .rounded
        claudeActions.spacing = 8
        [claudeSpeak, claudeSend, claudeStop].forEach { claudeActions.addArrangedSubview($0) }
        stack.addArrangedSubview(claudeActions)
        claudeStatus.isHidden = true
        claudeScroll.isHidden = true
        claudeActions.isHidden = true
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
        let text = editor.stringValue
        onKeepDraft?(isClaudeBackend && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? KeptDraft(claude: true, text: text) : nil)
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
                sessions.addArrangedSubview(NSTextField(labelWithString: WSL10n.text("conductor.sessions.none", zh: "还没有会话")))
            }
            for row in rows {
                let button = NSButton(title: row.label, target: self, action: #selector(pickSession(_:)))
                button.bezelStyle = .rounded
                bound[listID(row.id)] = row
                button.identifier = NSUserInterfaceItemIdentifier(listID(row.id))
                sessions.addArrangedSubview(button)
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
            let mark = highlighted?.id == row.id && highlighted?.revision == row.revision ? "✓ " : ""
            button.title = mark + row.label
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
        let efforts = snap.model.flatMap { controller.models[$0] }?.sorted() ?? []
        if efforts != effortIDs || effortMenu.numberOfItems == 0 {
            effortIDs = efforts
            rendering = true
            effortMenu.removeAllItems()
            effortMenu.addItems(withTitles: [WSL10n.text("conductor.effort", zh: "程度")] + efforts)
            rendering = false
        }
        rendering = true
        effortMenu.selectItem(at: snap.effort.flatMap { effortIDs.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        rendering = false
        let fresh = inputIsCurrent()
        modelMenu.isEnabled = fresh && displayedTarget != nil && !modelIDs.isEmpty && controller.canStageConductorConfig
        effortMenu.isEnabled = fresh && displayedTarget != nil && controller.model != nil && controller.canStageConductorConfig
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

    @objc private func pickEffort() {
        guard !rendering, inputIsCurrent(), effortMenu.indexOfSelectedItem > 0,
              effortIDs.indices.contains(effortMenu.indexOfSelectedItem - 1) else { return }
        let id = effortIDs[effortMenu.indexOfSelectedItem - 1]
        let choices: Set<String> = controller.model.flatMap { controller.models[$0] } ?? []
        guard let target = displayedTarget,
              ConductorPageSnapshot.acceptChoice(id, catalogue: choices),
              controller.stageConductorEffort(id, target: target) else { sync(); return }
    }

    @objc private func pickBackend() {
        cancelVoice()
        if isClaudeBackend {
            _ = claudeConductor.ensure()
        } else {
            claudeConductor.stop()
        }
        editor.stringValue = ""
        remoteNotch("")
        updateBackendVisibility()
        remoteTargetChanged?(isClaudeBackend ? nil : controller.conductorTarget?.context)
        sync()
    }

    private func updateBackendVisibility() {
        let claude = isClaudeBackend
        for view in [sessions, menus, actions, receipt, devices, status] as [NSView] {
            view.isHidden = claude
        }
        claudeStatus.isHidden = !claude
        claudeScroll.isHidden = !claude
        claudeActions.isHidden = !claude
        editor.placeholderString = claude
            ? WSL10n.text("conductor.claude.placeholder", zh: "对 Claude 说一句")
            : WSL10n.text("conductor.draftPlaceholder", zh: "草稿")
        if claude { renderClaude() }
    }

    private func renderClaude() {
        guard isClaudeBackend else { return }
        claudeStatus.stringValue = claudeBackendStatus()
        if claudeText.string != claudeConductor.transcript {
            claudeText.string = claudeConductor.transcript
            claudeText.scrollToEndOfDocument(nil)
        }
        let hasText = !editor.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        claudeSend.isEnabled = inputIsCurrent() && hasText &&
            claudeConductor.status != .missing && claudeConductor.status != .running
        claudeStop.isEnabled = inputIsCurrent() && claudeConductor.status == .running
        discard.isEnabled = inputIsCurrent() && !editor.stringValue.isEmpty
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
            return claudeConductor.model.map { base + " · " + $0 } ?? base
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
        backendMenu.selectItem(at: 1)
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
        if controller.conductorTarget != nil { _ = controller.editDraft("") }
        syncActions()
    }

    @objc private func goToSession() { goThere?() }

    /// 手机遥控会话的即时提示（画到第几拍、认出了什么、等待确认……）。
    func remoteNotch(_ text: String) {
        remoteHint.stringValue = text
        remoteHint.isHidden = text.isEmpty
    }

    // 页面级探针（--conductor-claude-probe）：不产生用户可见入口，只给自驱验收调。
    var probeInputIsCurrent: Bool { inputIsCurrent() }
    var probeIsClaude: Bool { isClaudeBackend }
    var probeClaudeStatus: ClaudeConductor.Status { claudeConductor.status }
    var probeClaudeTranscript: String { claudeConductor.transcript }
    func probeSelectClaude() { backendMenu.selectItem(at: 1); pickBackend() }
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
