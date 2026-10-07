import Cocoa

/// 指挥页复用唯一 owned controller。采用草稿和发送分开，所有动作绑定正在显示的会话。
@MainActor final class WS2ConductorPageView: NSView, WS2LeaseContent, WS2DeviceActionSink, NSTextFieldDelegate {
    var onCancel: (() -> Void)?
    var inputIsCurrent: () -> Bool = { false }
    var interactionSize: NSSize { NSSize(width: 460, height: 360) }
    let pageID = UUID()
    let input = WS2VisibleListInput()
    var expectedLease: WS2.LeaseHandle?
    var currentLease: (() -> WS2.LeaseHandle?)?
    var enableDevice: ((UUID) -> Bool)?
    var disableDevice: ((UUID) -> Void)?
    var changedEnvironment: (() -> Void)?

    private let controller: WS2OwnedLaunchController
    private let title = NSTextField(labelWithString: "指挥")
    private let sessions = NSStackView()
    private let modelMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let effortMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let editor = NSTextField(string: "")
    private let write = NSButton(title: "采用草稿", target: nil, action: nil)
    private let send = NSButton(title: "发送", target: nil, action: nil)
    private let interrupt = NSButton(title: "停止本轮", target: nil, action: nil)
    private let receipt = NSTextField(wrappingLabelWithString: "")
    private var adoptedDraft: WS2OwnedLaunchController.ConductorDraft?
    private var displayedTarget: WS2OwnedLaunchController.ConductorTarget?
    private var displayedTurn: String?
    private let deviceMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let enableButton = NSButton(title: "本次启用", target: nil, action: nil)
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

    var backendEpoch: UUID? { controller.session?.connectionID }
    var isInputReady: Bool {
        inputIsCurrent() && expectedLease != nil && currentLease?() == expectedLease &&
            window?.isKeyWindow == true && NSApp.isActive && backendEpoch != nil
    }

    init(controller: WS2OwnedLaunchController) {
        self.controller = controller
        super.init(frame: .zero)
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
        stack.addArrangedSubview(title)
        sessions.orientation = .vertical
        sessions.alignment = .leading
        sessions.spacing = 4
        stack.addArrangedSubview(sessions)
        modelMenu.setAccessibilityLabel("下一轮模型")
        effortMenu.setAccessibilityLabel("下一轮思考程度")
        modelMenu.toolTip = "下一轮使用的模型，不改变正在运行的这一轮。"
        effortMenu.toolTip = "下一轮使用的思考程度，不改变正在运行的这一轮。"
        modelMenu.target = self
        modelMenu.action = #selector(pickModel)
        effortMenu.target = self
        effortMenu.action = #selector(pickEffort)
        let nextLabel = NSTextField(labelWithString: "下一轮")
        let menus = NSStackView(views: [nextLabel, modelMenu, effortMenu])
        menus.spacing = 8
        stack.addArrangedSubview(menus)
        editor.placeholderString = "草稿"
        editor.setAccessibilityLabel("待记下的草稿")
        editor.isEditable = true
        editor.isBezeled = true
        editor.delegate = self
        stack.addArrangedSubview(editor)
        editor.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        write.target = self
        write.action = #selector(commitDraft)
        write.bezelStyle = .rounded
        write.toolTip = "只把现在的文字留在这台 Mac 上。不会发给助手。"
        send.target = self
        send.action = #selector(sendDraft)
        send.bezelStyle = .rounded
        send.toolTip = "只发送已采用的草稿。运行时补进当前这一轮，下一轮的模型和档位不会改动这一轮。"
        interrupt.target = self
        interrupt.action = #selector(interruptTurn)
        interrupt.bezelStyle = .rounded
        interrupt.toolTip = "请求停止当前这一轮，等助手确认后才显示已停止。"
        let actions = NSStackView(views: [write, send, interrupt])
        actions.spacing = 8
        stack.addArrangedSubview(actions)
        receipt.font = .systemFont(ofSize: 11)
        receipt.textColor = .secondaryLabelColor
        receipt.maximumNumberOfLines = 2
        stack.addArrangedSubview(receipt)
        receipt.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        deviceMenu.setAccessibilityLabel("本次连接的手柄")
        enableButton.target = self
        enableButton.action = #selector(toggleDevice)
        enableButton.image = NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: nil)
        let devices = NSStackView(views: [deviceMenu, enableButton])
        devices.spacing = 8
        stack.addArrangedSubview(devices)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 2
        stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        input.onActivate = { [weak self] id in self?.activate(id) ?? false }
        input.onCancel = { [weak self] in self?.onCancel?() }
        sync()
    }

    required init?(coder: NSCoder) { nil }

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
        let snap = snapshot()
        let target = controller.conductorTarget
        if displayedTarget != target {
            input.cancelAll()
            displayedTarget = target
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
        send.title = adoptedDraft?.turn == nil ? "发送" : "补进本轮"
        send.isEnabled = inputIsCurrent() && !marked && adoptedDraft?.text == editor.stringValue && adoptedDraft != nil
        interrupt.isEnabled = inputIsCurrent() && controller.canInterrupt && displayedTarget != nil && displayedTurn != nil
    }

    func controlTextDidChange(_ notification: Notification) {
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
            deviceMenu.addItem(withTitle: "\(index + 1). \(clean.isEmpty ? "游戏手柄" : String(clean))\(device.enabled ? " · 已启用" : "")")
        }
        if let chosen, let index = devices.firstIndex(where: { $0.attachment == chosen }) {
            deviceMenu.selectItem(at: index)
        }
        enableButton.title = devices.contains(where: \.enabled) ? "停用手柄" : "本次启用"
        if devices.contains(where: \.enabled) {
            status.stringValue = "方向键选择这一条。确认键的名字还没按这只手柄核对。离开这一页就停用。"
        } else if devices.isEmpty {
            status.stringValue = "没有检测到游戏手柄。可以用指针选择。"
        } else {
            status.stringValue = "启用前先松开按键。只操作当前这张列表。"
        }
        enableButton.isEnabled = isInputReady && !devices.isEmpty
    }

    func noteDevicesBusy() {
        status.stringValue = "手柄还在另一页，这里先只用指针。"
    }

    func revoke() {
        input.revoke()
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
                sessions.addArrangedSubview(NSTextField(labelWithString: "还没有会话"))
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
                status.stringValue = "这张列表暂时不能用"
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
            modelMenu.addItems(withTitles: ["请选择模型"] + models)
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
            effortMenu.addItems(withTitles: ["程度"] + efforts)
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
            status.stringValue = "这一条已经变了"
            sync()
            return
        }
        guard controller.selectConductorSession(selection.id, revision: selection.revision) else {
            status.stringValue = "这一轮结束后再切换"
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

    @objc private func commitDraft() {
        guard inputIsCurrent() else { return }
        let marked = (editor.currentEditor() as? NSTextView)?.hasMarkedText() == true
        let before = snapshot()
        let selection = highlighted.flatMap { before.confirm($0) ? $0 : nil }
        switch before.freezeDraft(text: editor.stringValue, hasMarkedText: marked, selection: selection) {
        case .failure(.markedText):
            status.stringValue = "还在输入，草稿留着"
        case .failure:
            status.stringValue = "这一条已经变了，草稿留着"
        case .success(let frozen):
            let live = snapshot()
            switch live.acceptDraft(frozen) {
            case .success(let accepted):
                if let target = displayedTarget,
                   let adopted = controller.adoptConductorDraft(accepted.text, hasMarkedText: marked, target: target) {
                    adoptedDraft = adopted
                    status.stringValue = "已采用，还没发送"
                } else {
                    status.stringValue = "还不能采用，草稿留着"
                }
            case .failure(.staleModel), .failure(.staleEffort):
                status.stringValue = "模型和档位已经变了，草稿留着"
            case .failure:
                status.stringValue = "这一条已经变了，草稿留着"
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
        else { status.stringValue = "会话已经变了，请重新采用草稿" }
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
            status.stringValue = "未能启用。请点一下这一页，再松开所有按键。"
        }
    }
}
