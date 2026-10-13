import Cocoa

/// A native list inside the existing Island. It chooses a model, never sends a draft or grants permission.
@MainActor final class WS2ModelPickerView: NSView, WS2LeaseContent, NSTableViewDataSource, NSTableViewDelegate {
    var onCancel: (() -> Void)?
    var inputIsCurrent: () -> Bool = { false }
    /// 屏宽的 50% × 13.6%（`ConductorShape`）。宿主在显示前可以给定屏宽；没给就取所在屏，再取主屏。
    var hostScreenWidth: CGFloat?
    var interactionSize: NSSize {
        let width = hostScreenWidth ?? window?.screen?.frame.width ?? NSScreen.main?.frame.width ?? 1440
        let size = ConductorShape.size(.modelPicker, screenWidth: width)
        return NSSize(width: size.width, height: size.height)
    }
    let pageID = UUID()
    let input = WS2VisibleListInput()
    private let controller: WS2OwnedLaunchController
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let deviceMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let enableButton = NSButton(title: WSL10n.text("conductor.enableNow", zh: "本次启用"), target: nil, action: nil)
    private let chooseButton = NSButton(title: WSL10n.text("conductor.picker.use", zh: "使用此模型"), target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: WSL10n.text("conductor.picker.padIdle", zh: "尚未启用手柄"))
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
        // 左边是模型列表，右边是手柄和按钮：刘海里这块只有屏宽 13.6% 高，竖着排放不下。
        let list = NSStackView(); list.orientation = .vertical; list.alignment = .leading; list.spacing = 6
        let controls = NSStackView(); controls.orientation = .vertical; controls.alignment = .leading; controls.spacing = 6
        for view in [list, controls] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            list.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            list.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            controls.leadingAnchor.constraint(equalTo: list.trailingAnchor, constant: 14),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            controls.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            controls.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
            controls.widthAnchor.constraint(equalToConstant: 200)])
        let title = NSTextField(labelWithString: WSL10n.text("conductor.picker.title", zh: "选择模型")); title.font = .systemFont(ofSize: 15, weight: .semibold)
        list.addArrangedSubview(title)
        let column = NSTableColumn(identifier: .init("model")); column.title = WSL10n.text("conductor.picker.column", zh: "当前助手提供的模型")
        column.width = 300; column.minWidth = 100
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.autoresizingMask = [.width]
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 28; table.allowsEmptySelection = false
        table.allowsMultipleSelection = false; table.delegate = self; table.dataSource = self
        table.target = self; table.doubleAction = #selector(useSelection); table.setAccessibilityLabel(WSL10n.text("conductor.picker.tableLabel", zh: "当前可用模型"))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder; scroll.documentView = table
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        list.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        deviceMenu.setAccessibilityLabel(WSL10n.text("conductor.pad.label", zh: "本次连接的手柄"))
        enableButton.target = self; enableButton.action = #selector(toggleDevice)
        enableButton.image = NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: nil)
        chooseButton.target = self; chooseButton.action = #selector(useSelection)
        let back = NSButton(title: WSL10n.text("conductor.picker.back", zh: "返回会话"), target: self, action: #selector(goBack))
        for control in [deviceMenu, enableButton, chooseButton, back] as [NSControl] { control.controlSize = .small }
        deviceMenu.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let actionRow = NSStackView(views: [chooseButton, back]); actionRow.spacing = 8
        controls.addArrangedSubview(deviceMenu); controls.addArrangedSubview(enableButton); controls.addArrangedSubview(actionRow)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        controls.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
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
        // 形状进场用 pop（岛负责）；内容淡入，减少动态效果时用更短的同一种淡化。
        if window != nil {
            wantsLayer = true
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0; fade.toValue = 1; fade.duration = Motion.Fade.fadeIn()
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer?.add(fade, forKey: "content-fade")
        }
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
            catch { rows = []; input.revoke(); status.stringValue = WSL10n.text("conductor.picker.listUnavailable", zh: "模型列表暂时不可用") }
            rendering = true; table.reloadData(); rendering = false; showSelection()
        } else if lastChosen != controller.model {
            lastChosen = controller.model
            if let id = lastChosen { _ = input.select(id) }
        }
        input.ready = isInputReady
        chooseButton.isEnabled = isInputReady && input.selection.selectedID != nil
        enableButton.isEnabled = isInputReady && !shownDevices.isEmpty
        renderHint()
    }
    func renderDevices(_ devices: [WS2ControllerDevice]) {
        let previous = deviceMenu.indexOfSelectedItem
        let chosen = shownDevices.indices.contains(previous) ? shownDevices[previous].attachment : nil
        shownDevices = devices
        deviceMenu.isHidden = devices.isEmpty
        enableButton.isHidden = devices.isEmpty
        deviceMenu.removeAllItems()
        for (index, device) in devices.enumerated() {
            let clean = String(String.UnicodeScalarView(device.label.unicodeScalars.filter {
                $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
            })).prefix(64)
            let padName = clean.isEmpty ? WSL10n.text("conductor.pad.generic", zh: "游戏手柄") : String(clean)
            let enabledMark = device.enabled ? " · " + WSL10n.text("conductor.pad.enabled", zh: "已启用") : ""
            deviceMenu.addItem(withTitle: "\(index + 1). \(padName)\(enabledMark)")
        }
        if let chosen, let index = devices.firstIndex(where: { $0.attachment == chosen }) { deviceMenu.selectItem(at: index) }
        enableButton.title = devices.contains(where: \.enabled) ? WSL10n.text("conductor.pad.disable", zh: "停用手柄")
                                                                  : WSL10n.text("conductor.enableNow", zh: "本次启用")
        renderHint()
        enableButton.isEnabled = isInputReady && !devices.isEmpty
    }
    private func renderHint() {
        guard !rows.isEmpty else { status.stringValue = WSL10n.text("conductor.picker.none", zh: "还没有可选模型"); return }
        guard controller.canChooseModel else { status.stringValue = WSL10n.text("conductor.picker.cannot", zh: "暂时不能选择模型"); return }
        if let armedID { status.stringValue = WSL10n.text("conductor.picker.armed", zh: "松开 A 使用：%@", armedID); return }
        status.stringValue = shownDevices.contains(where: \.enabled)
                ? WSL10n.text("conductor.picker.padHint", zh: "方向键选择，A 使用模型，B 返回。离开本页即停用。") : shownDevices.isEmpty ? "没有检测到游戏手柄；仍可用鼠标选择。" : "启用前先松开按键。仅操作当前列表。"
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
        if enableDevice?(id) != true {
            status.stringValue = WS2GamepadHandlerSeats.shared.desktopHoldsAny
                ? WSL10n.text("conductor.pad.status.turnOffInSettings", zh: "先在设置里关掉控制这台 Mac")
                : WSL10n.text("conductor.picker.enableFailed", zh: "未能启用；请点击此页，再松开所有按键。")
        }
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
