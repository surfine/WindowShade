import Cocoa

/// 指挥页读当前助手的会话快照。只切换这一页正在看的会话、改模型或档位、写下草稿。
/// 不发送、不停止、不恢复另一条后端会话。
@MainActor final class WS2ConductorPageView: NSView, WS2LeaseContent, WS2DeviceActionSink {
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
    private let write = NSButton(title: "记下草稿", target: nil, action: nil)
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
        modelMenu.setAccessibilityLabel("实际可用模型")
        effortMenu.setAccessibilityLabel("该模型支持的思考程度")
        modelMenu.target = self
        modelMenu.action = #selector(pickModel)
        effortMenu.target = self
        effortMenu.action = #selector(pickEffort)
        let menus = NSStackView(views: [modelMenu, effortMenu])
        menus.spacing = 8
        stack.addArrangedSubview(menus)
        editor.placeholderString = "草稿"
        editor.setAccessibilityLabel("待记下的草稿")
        editor.isEditable = true
        editor.isBezeled = true
        stack.addArrangedSubview(editor)
        editor.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        write.target = self
        write.action = #selector(commitDraft)
        write.bezelStyle = .rounded
        write.toolTip = "只把现在的文字留在这台 Mac 上。不会发给助手。"
        stack.addArrangedSubview(write)
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
        if let highlighted, !snap.confirm(highlighted) { self.highlighted = nil }
        renderSessions(snap)
        renderMenus(snap)
        if editor.currentEditor() == nil, editor.stringValue != snap.draft {
            editor.stringValue = snap.draft
        }
        write.isEnabled = inputIsCurrent()
        input.ready = isInputReady
        enableButton.isEnabled = isInputReady && !shownDevices.isEmpty
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
        let rows = controller.store.visibleSessions.map { session in
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
        let name = session.context.session.provider.displayName
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
        modelMenu.isEnabled = fresh && !modelIDs.isEmpty && controller.canChooseModel
        effortMenu.isEnabled = fresh && controller.model != nil && controller.canChooseModel
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
        highlighted = selection
        input.cancelAll()
        sync()
    }

    private func activate(_ id: String) -> Bool {
        guard isInputReady, let row = bound[id] else { return false }
        let snap = snapshot()
        let selection = ConductorPageSnapshot.Selection(id: row.id, revision: row.revision, listRevision: snap.listRevision)
        guard case .success = snap.acceptSelection(selection) else { return false }
        highlighted = selection
        sync()
        return true
    }

    @objc private func pickModel() {
        guard !rendering, inputIsCurrent(), modelMenu.indexOfSelectedItem > 0,
              modelIDs.indices.contains(modelMenu.indexOfSelectedItem - 1) else { return }
        let id = modelIDs[modelMenu.indexOfSelectedItem - 1]
        guard ConductorPageSnapshot.acceptChoice(id, catalogue: Set(controller.models.keys)),
              controller.chooseModel(id) else { sync(); return }
    }

    @objc private func pickEffort() {
        guard !rendering, inputIsCurrent(), effortMenu.indexOfSelectedItem > 0,
              effortIDs.indices.contains(effortMenu.indexOfSelectedItem - 1) else { return }
        let id = effortIDs[effortMenu.indexOfSelectedItem - 1]
        let choices: Set<String> = controller.model.flatMap { controller.models[$0] } ?? []
        guard ConductorPageSnapshot.acceptChoice(id, catalogue: choices),
              controller.chooseEffort(id) else { sync(); return }
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
                if controller.editDraft(accepted.text) {
                    status.stringValue = "记下了。还没有发给助手。"
                } else {
                    status.stringValue = "草稿过长，原来的还在"
                }
            case .failure(.staleModel), .failure(.staleEffort):
                status.stringValue = "模型和档位已经变了，草稿留着"
            case .failure:
                status.stringValue = "这一条已经变了，草稿留着"
            }
        }
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
