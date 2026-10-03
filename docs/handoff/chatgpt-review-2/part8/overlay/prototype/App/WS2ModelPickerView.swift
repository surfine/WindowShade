import Cocoa

/// A native list inside the existing Island. It chooses a model, never sends a draft or grants permission.
@MainActor final class WS2ModelPickerView: NSView, WS2LeaseContent, NSTableViewDataSource, NSTableViewDelegate {
    var onCancel: (() -> Void)?
    var inputIsCurrent: () -> Bool = { false }
    var interactionSize: NSSize { NSSize(width: 520, height: 420) }
    let pageID = UUID()
    let input = WS2VisibleListInput()
    private let controller: WS2OwnedLaunchController
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let deviceMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let enableButton = NSButton(title: "本次启用", target: nil, action: nil)
    private let chooseButton = NSButton(title: "使用此模型", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "尚未启用手柄")
    private var rows: [String] = []
    private var shownDevices: [WS2ControllerDevice] = []
    private var lastBackend: UUID?
    private var armedID: String?
    private var lastChosen: String?
    private var lastAvailable = false
    private var rendering = false
    private var focusObservers: [NSObjectProtocol] = []
    var expectedLease: WS2.LeaseHandle?
    var currentLease: (() -> WS2.LeaseHandle?)?
    var enableDevice: ((UUID) -> Bool)?
    var disableDevice: ((UUID) -> Void)?
    var changedEnvironment: (() -> Void)?
    var didChoose: (() -> Void)?
    var navigateBack: (() -> Void)?

    var backendEpoch: UUID? { controller.session?.connectionID }
    var isInputReady: Bool {
        inputIsCurrent() && expectedLease != nil && currentLease?() == expectedLease &&
        window?.isKeyWindow == true && NSApp.isActive && controller.canChooseModel && !rows.isEmpty
    }
    init(controller: WS2OwnedLaunchController) {
        self.controller = controller
        super.init(frame: .zero)
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16), stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -14)])
        let title = NSTextField(labelWithString: "选择模型"); title.font = .systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(title)
        let column = NSTableColumn(identifier: .init("model")); column.title = "当前助手提供的模型"
        column.width = 460; column.minWidth = 140
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.autoresizingMask = [.width]
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 30; table.allowsEmptySelection = false
        table.allowsMultipleSelection = false; table.delegate = self; table.dataSource = self
        table.target = self; table.doubleAction = #selector(useSelection); table.setAccessibilityLabel("当前可用模型")
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder; scroll.documentView = table
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 224).isActive = true
        deviceMenu.setAccessibilityLabel("本次连接的手柄")
        enableButton.target = self; enableButton.action = #selector(toggleDevice)
        enableButton.image = NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: nil)
        chooseButton.target = self; chooseButton.action = #selector(useSelection)
        let back = NSButton(title: "返回会话", target: self, action: #selector(goBack))
        let deviceRow = NSStackView(views: [deviceMenu, enableButton]); deviceRow.spacing = 8
        let actionRow = NSStackView(views: [chooseButton, back]); actionRow.spacing = 8
        stack.addArrangedSubview(deviceRow); stack.addArrangedSubview(actionRow)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true; stack.addArrangedSubview(status)
        input.onArmed = { [weak self] id in self?.armedID = id; self?.renderHint() }
        input.onSelection = { [weak self] _ in self?.showSelection() }
        input.onActivate = { [weak self] id in
            guard let self, self.isInputReady, self.controller.chooseModel(id) else { return false }
            self.didChoose?(); return true
        }
        input.onCancel = { [weak self] in self?.navigateBack?() }
        sync()
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusObservers.forEach { NotificationCenter.default.removeObserver($0) }; focusObservers.removeAll()
        if let window {
            focusObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.input.cancelAll(); self?.sync(); self?.changedEnvironment?() }
            })
            // Regaining focus refreshes local controls, but never re-enables a controller.
            for (name, object) in [(NSWindow.didBecomeKeyNotification, window as AnyObject),
                                   (NSApplication.didBecomeActiveNotification, NSApp as AnyObject)] {
                focusObservers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sync(); self?.changedEnvironment?() }
                })
            }
        }
        changedEnvironment?()
    }
    func sync() {
        let ids = controller.models.keys.sorted(), available = controller.canChooseModel, epoch = backendEpoch
        if ids != rows || available != lastAvailable || epoch != lastBackend {
            input.ready = false; input.bind(nil); changedEnvironment?()
            rows = ids; lastAvailable = available; lastBackend = epoch; lastChosen = controller.model
            do { try input.replace(ids.map { .init(id: $0, enabled: available) }, selectedID: controller.model) }
            catch { rows = []; input.revoke(); status.stringValue = "模型列表暂时不可用" }
            rendering = true; table.reloadData(); rendering = false; showSelection()
        } else if lastChosen != controller.model {
            lastChosen = controller.model
            if let id = lastChosen { _ = input.select(id) }
        }
        input.ready = isInputReady
        chooseButton.isEnabled = isInputReady && input.selection.selectedID != nil
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
        if let chosen, let index = devices.firstIndex(where: { $0.attachment == chosen }) { deviceMenu.selectItem(at: index) }
        enableButton.title = devices.contains(where: \.enabled) ? "停用手柄" : "本次启用"
        renderHint()
        enableButton.isEnabled = isInputReady && !devices.isEmpty
    }
    private func renderHint() {
        if let armedID { status.stringValue = "松开 A 使用：" + armedID; return }
        status.stringValue = shownDevices.contains(where: \.enabled) ? "方向键选择，A 使用模型，B 返回。离开本页即停用。" : shownDevices.isEmpty ? "没有检测到游戏手柄；仍可用鼠标选择。" : "启用前先松开按键。仅操作当前列表。"
    }
    private func showSelection() {
        guard let id = input.selection.selectedID, let row = rows.firstIndex(of: id) else { return }
        rendering = true; table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row); rendering = false
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let key = NSUserInterfaceItemIdentifier("modelCell")
        let label = (tableView.makeView(withIdentifier: key, owner: self) as? NSTextField) ?? NSTextField(labelWithString: "")
        label.identifier = key; label.stringValue = rows[row]; label.toolTip = rows[row]
        label.lineBreakMode = .byTruncatingMiddle; return label
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !rendering, inputIsCurrent(), rows.indices.contains(table.selectedRow) else { return }
        _ = input.select(rows[table.selectedRow])
    }
    @objc private func toggleDevice() {
        guard inputIsCurrent(), controller.canChooseModel else { return }
        if let enabled = shownDevices.first(where: \.enabled) { disableDevice?(enabled.attachment); return }
        // Only this explicit local click activates WindowShade. Device callbacks never take application focus.
        NSApp.activate(ignoringOtherApps: true); window?.makeKey()
        sync()
        guard isInputReady, shownDevices.indices.contains(deviceMenu.indexOfSelectedItem) else { return }
        let id = shownDevices[deviceMenu.indexOfSelectedItem].attachment
        if enableDevice?(id) != true { status.stringValue = "未能启用；请点击此页，再松开所有按键。" }
    }
    @objc private func useSelection() {
        guard isInputReady, let id = input.selection.selectedID else { return }
        input.cancelAll()
        if controller.chooseModel(id) { didChoose?() }
    }
    @objc private func goBack() { if inputIsCurrent() { navigateBack?() } }
    func revoke() {
        input.revoke(); inputIsCurrent = { false }; expectedLease = nil
        focusObservers.forEach { NotificationCenter.default.removeObserver($0) }; focusObservers.removeAll()
        changedEnvironment?(); onCancel?()
    }
}

extension WS2ModelPickerView: WS2DeviceActionSink {
    var ready: Bool { isInputReady }
    var motionReady: Bool { false }
    func prepare(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool { input.ready = isInputReady; return input.prepare(ticket) }
    func cancelPrepared(context: WS2SemanticInputRouter.Context, presses: [UInt64]) { input.cancel(context: context, presses: presses) }
    func execute(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool { input.ready = isInputReady; return input.execute(ticket) }
    func move(_ effect: GamepadMapping.Effect, context: WS2SemanticInputRouter.Context) -> Bool { false }
}
