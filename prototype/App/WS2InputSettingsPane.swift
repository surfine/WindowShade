import Cocoa

extension AppDelegate {
    func makePointerSettingsPage() -> NSView {
        inputController.apply()
        let prefs = inputController.preferences
        let (root, stack) = inputPageRoot()
        stack.addArrangedSubview(inputCaption("滚动和按键默认不改。"))
        let rows = [
            inputRow(name: "平滑滚动", subtitle: inputController.scrollStatus(prefersChange: prefs.smooth != nil),
                     detail: "打开之后，滚轮的一格会变成一段连续滚动。现在还不能确认事件来自哪只鼠标，所以先不改。",
                     symbol: nil, control: smoothPopup(prefs)),
            inputRow(name: "鼠标滚动方向", subtitle: mouseDirectionSubtitle(prefs),
                     detail: "只准备改鼠标的滚动。还不能确认事件来自哪只鼠标时，先不改。",
                     symbol: nil, control: inputSwitch(on: prefs.mouseInvert, enabled: true, action: #selector(prefInputMouseDirection(_:)), name: "鼠标滚动方向")),
            inputRow(name: "触控板滚动方向", subtitle: prefs.trackpadInvert ? "触控板的滚动先不改" : "跟系统一样",
                     detail: "这一项先存着。触控板的滚动现在还不能改。",
                     symbol: nil, control: inputSwitch(on: prefs.trackpadInvert, enabled: true, action: #selector(prefInputTrackpadDirection(_:)), name: "触控板滚动方向")),
            inputRow(name: "⌥ 精细", subtitle: InputStatusCopy.auxiliary(on: prefs.fine, offPhrase: "关着", onPhrase: "一格只滚一行", decision: inputController.scrollDecision),
                     detail: "按住 ⌥ 时，一条滚动只走一行。要和平滑滚动或鼠标滚动方向一起开。",
                     symbol: nil, control: inputSwitch(on: prefs.fine, enabled: true, action: #selector(prefInputFine(_:)), name: "⌥ 精细")),
            inputRow(name: "侧键后退、前进", subtitle: InputStatusCopy.auxiliary(on: prefs.sideButtons, offPhrase: "关着", onPhrase: "后退和前进", decision: inputController.scrollDecision),
                     detail: "侧键 4、5 准备用作这个 App 的后退和前进。要和平滑滚动或鼠标滚动方向一起开。",
                     symbol: nil, control: inputSwitch(on: prefs.sideButtons, enabled: true, action: #selector(prefInputSide(_:)), name: "侧键后退、前进")),
            inputRow(name: "中键收起窗口",
                     subtitle: middleSubtitle(prefs),
                     detail: "在标题栏上用中键点一下收起或展开；往上拖也是收起，往下拖展开。默认关，打开才装钩子。",
                     symbol: "rectangle.compress.vertical",
                     control: inputSwitch(on: prefs.middleFold, enabled: true,
                                         action: #selector(prefInputMiddleFold(_:)), name: "中键收起窗口")),
            inputRow(name: "三指轻点是中键", subtitle: "还没核对，先不用",
                     detail: "三指轻点还没核对，先不能开。",
                     symbol: nil, control: inputSwitch(on: false, enabled: inputController.touchAvailable, action: nil, name: "三指轻点是中键")),
            inputRow(name: "四指轻点打开看不见的窗口", subtitle: "还没核对，先不用",
                     detail: "四指轻点还没核对，先不能开。",
                     symbol: "macwindow.on.rectangle", control: inputSwitch(on: false, enabled: inputController.touchAvailable, action: nil, name: "四指轻点打开看不见的窗口")),
            inputRow(name: "例外的 App", subtitle: prefs.exceptions.isEmpty ? "还没有例外" : "\(prefs.exceptions.count) 个应用",
                     detail: "一行一个应用标识。列在这里的，滚动保持原样。",
                     symbol: nil, control: inputExceptionsButton()),
        ]
        let card = makeUnifiedSettingsCard(rows)
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return root
    }

    func makeRemoteSettingsPage() -> NSView {
        inputController.apply()
        let prefs = inputController.preferences
        let host = inputController.remoteHostForSettings
        let conductorOn = WS2ConductorSettings.flag(WS2ConductorSettings.enabledKey, in: .standard)
        let (root, stack) = inputPageRoot()
        stack.addArrangedSubview(inputCaption("没打开时不听遥控器。"))
        var rows = [
            inputRow(name: "Siri 遥控器", subtitle: "没在听，连没连上未知",
                     detail: "没打开遥控模式时不听，所以不知道有没有连上。",
                     symbol: "appletvremote.gen4", control: inputStatus("未知")),
            inputRow(name: "遥控模式", subtitle: remoteSubtitle(on: prefs.remoteMode, host: host),
                     detail: "打开后，这台 Mac 出现在 iPhone 上的遥控器的列表里。关掉就不再出现，连着的也会断开。",
                     symbol: "iphone", control: inputSwitch(on: prefs.remoteMode, enabled: true, action: #selector(prefInputRemoteMode(_:)), name: "遥控模式")),
            // 指挥模式是遥控模式下面的一项：总开关关着时灰着，也跟着关。
            inputRow(name: "指挥模式", subtitle: prefs.remoteMode ? (conductorOn ? "开着" : "关着") : "先打开遥控模式",
                     detail: "用遥控器走进刘海那一排里的会话：看会话、换模型、留草稿。",
                     symbol: nil, control: inputSwitch(on: prefs.remoteMode && conductorOn, enabled: prefs.remoteMode,
                                                       action: #selector(prefInputConductor(_:)), name: "指挥模式"),
                     indent: true),
        ]
        if prefs.remoteMode {
            let peers = host?.pairedPeers ?? []
            if peers.isEmpty {
                rows.append(inputRow(name: "已配对的 iPhone", subtitle: "还没有",
                                     detail: "在 iPhone 上的遥控器里选这台 Mac，就能配对。",
                                     symbol: nil, control: inputStatus(""), indent: true))
            }
            for peer in peers {
                let name = peer.displayName ?? WS2RemoteCopy.fallbackName
                let remove = NSButton(title: "移除", target: self, action: #selector(prefInputRemovePeer(_:)))
                remove.bezelStyle = .rounded
                remove.identifier = NSUserInterfaceItemIdentifier(peer.identifier.map { String(format: "%02x", $0) }.joined())
                remove.setAccessibilityLabel("移除 \(name)")
                rows.append(inputRow(name: "\(name) · \(WS2RemoteCopy.pairedSuffix)", subtitle: "已配对的 iPhone",
                                     detail: "移除后，这台 iPhone 不能再遥控，也不能指挥。",
                                     symbol: nil, control: remove, indent: true))
            }
        }
        rows.append(contentsOf: gamepadRows())
        let card = makeUnifiedSettingsCard(rows)
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return root
    }

    /// 每台手柄一行“控制这台 Mac”，默认关。同一时间只有一台能操作，另一台只能看。
    private func gamepadRows() -> [NSView] {
        let control = WS2GamepadDesktopControl.shared
        control.onChange = { [weak self] in self?.refreshPreferencesWindowIfOpen() }
        let detail = "用十字键选，× 确认，○ 返回，△ 回到刘海那一排（按住 0.5 秒打开启动台），Options 播放或暂停。游戏在前台时手柄整个让开。"
        let rows = control.rows()
        guard !rows.isEmpty else {
            return [inputRow(name: "游戏手柄", subtitle: "没连上", detail: "连上手柄后，这里会出现“控制这台 Mac”。",
                             symbol: "gamecontroller", control: inputStatus(""))]
        }
        return rows.map { row in
            let subtitle: String
            switch row.access {
            case .off: subtitle = "关着"
            case .viewOnly: subtitle = "只能看"
            case .controls: subtitle = row.yieldingToPage ? "指挥页在用" : row.yielding ? "游戏在前台，先让开" : "开着"
            }
            let toggle = inputSwitch(on: row.access != .off, enabled: true, action: #selector(prefGamepadControl(_:)),
                                     name: "控制这台 Mac · \(row.name)")
            toggle.identifier = NSUserInterfaceItemIdentifier(row.id.uuidString)
            return inputRow(name: "控制这台 Mac · \(row.name)", subtitle: subtitle, detail: detail,
                            symbol: "gamecontroller", control: toggle)
        }
    }

    @objc func prefGamepadControl(_ sender: NSSwitch) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        WS2GamepadDesktopControl.shared.setEnabled(sender.state == .on, padID: id)
        refreshPreferencesWindowIfOpen()
    }

    private func remoteSubtitle(on: Bool, host: WS2RemoteHost?) -> String {
        guard on else { return "关着" }
        switch host?.status {
        case .listening?: return host?.operatorIdentifier != nil ? "iPhone 已连接" : "在听"
        case .failed?: return "没能打开，先关掉再开"
        case .starting?: return "正在打开"
        case .off?, nil: return "关着"
        }
    }

    @objc func prefInputSmooth(_ sender: NSPopUpButton) {
        var prefs = WS2InputPreferences.load(from: .standard)
        switch sender.indexOfSelectedItem {
        case 1: prefs.smooth = .light
        case 2: prefs.smooth = .medium
        case 3: prefs.smooth = .trackpadLike
        default: prefs.smooth = nil
        }
        WS2InputPreferences.save(prefs, to: .standard)
        inputController.apply()
        refreshPreferencesWindowIfOpen()
    }

    @objc func prefInputMouseDirection(_ sender: NSSwitch) {
        updateInput { $0.mouseInvert = sender.state == .on }
    }

    @objc func prefInputTrackpadDirection(_ sender: NSSwitch) {
        updateInput { $0.trackpadInvert = sender.state == .on }
    }

    @objc func prefInputFine(_ sender: NSSwitch) {
        updateInput { $0.fine = sender.state == .on }
    }

    @objc func prefInputSide(_ sender: NSSwitch) {
        updateInput { $0.sideButtons = sender.state == .on }
    }

    @objc func prefInputMiddleFold(_ sender: NSSwitch) {
        updateInput { $0.middleFold = sender.state == .on }
    }

    @objc func prefInputRemoteMode(_ sender: NSSwitch) {
        let on = sender.state == .on
        // 总开关关掉，指挥模式跟着关；再打开时不自动回来。
        if !on { WS2ConductorSettings.setFlag(false, WS2ConductorSettings.enabledKey, in: .standard) }
        updateInput { $0.remoteMode = on }
    }

    @objc func prefInputConductor(_ sender: NSSwitch) {
        guard inputController.preferences.remoteMode else { refreshPreferencesWindowIfOpen(); return }
        WS2ConductorSettings.setFlag(sender.state == .on, WS2ConductorSettings.enabledKey, in: .standard)
        inputController.apply()
        refreshPreferencesWindowIfOpen()
    }

    /// 撤销这台的配对、断开，刘海里说“这台 iPhone 不能再遥控了”。
    @objc func prefInputRemovePeer(_ sender: NSButton) {
        guard let hex = sender.identifier?.rawValue, hex.count % 2 == 0, !hex.isEmpty else { return }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return }
            bytes.append(byte); index = next
        }
        let identifier = Data(bytes)
        _ = inputController.remoteHostForSettings?.removePeer(identifier: identifier)
        inputController.apply()
        refreshPreferencesWindowIfOpen()
    }

    @objc func prefInputEditExceptions() {
        let prefs = WS2InputPreferences.load(from: .standard)
        let alert = NSAlert()
        alert.messageText = "例外的 App"
        alert.informativeText = "一行一个应用标识。列在这里的，滚动保持原样。"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 140))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 340, height: 140))
        textView.isEditable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = prefs.exceptions.joined(separator: "\n")
        scroll.documentView = textView
        alert.accessoryView = scroll
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let ids = textView.string
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        updateInput { $0.exceptions = ids }
    }

    private func updateInput(_ change: (inout WS2InputPreferences.Value) -> Void) {
        var prefs = WS2InputPreferences.load(from: .standard)
        change(&prefs)
        WS2InputPreferences.save(prefs, to: .standard)
        inputController.apply()
        refreshPreferencesWindowIfOpen()
    }

    private func mouseDirectionSubtitle(_ prefs: WS2InputPreferences.Value) -> String {
        guard prefs.mouseInvert else { return "跟系统一样" }
        return inputController.scrollStatus(prefersChange: true)
    }

    private func middleSubtitle(_ prefs: WS2InputPreferences.Value) -> String {
        if inputController.middleTap.systemStopped { return "被系统停掉了，先关掉再开" }
        if prefs.middleFold { return inputController.middleListening ? "开着" : "还没装上" }
        return "关着"
    }

    private func smoothPopup(_ prefs: WS2InputPreferences.Value) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: ["关", "轻", "中", "像触控板"])
        switch prefs.smooth {
        case .light: popup.selectItem(at: 1)
        case .medium: popup.selectItem(at: 2)
        case .trackpadLike: popup.selectItem(at: 3)
        case nil: popup.selectItem(at: 0)
        }
        popup.target = self
        popup.action = #selector(prefInputSmooth(_:))
        popup.setAccessibilityLabel("平滑滚动")
        return popup
    }

    private func inputSwitch(on: Bool, enabled: Bool, action: Selector?, name: String) -> NSSwitch {
        let toggle = NSSwitch()
        toggle.state = on ? .on : .off
        toggle.isEnabled = enabled
        toggle.controlSize = .regular
        toggle.target = self
        toggle.action = action
        toggle.setAccessibilityLabel(name)
        return toggle
    }

    private func inputExceptionsButton() -> NSButton {
        let button = NSButton(title: "编辑…", target: self, action: #selector(prefInputEditExceptions))
        button.bezelStyle = .rounded
        button.setAccessibilityLabel("例外的 App")
        return button
    }

    private func inputStatus(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = SystemAppearancePolicy.font(relativeToBody: 0)
        field.textColor = .secondaryLabelColor
        field.setAccessibilityLabel(text)
        return field
    }

    private func inputCaption(_ text: String) -> NSTextField {
        let caption = NSTextField(wrappingLabelWithString: text)
        caption.font = SystemAppearancePolicy.font(relativeToBody: -1)
        caption.textColor = .secondaryLabelColor
        caption.maximumNumberOfLines = 2
        return caption
    }

    private func inputPageRoot() -> (NSView, NSStackView) {
        let root = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
        ])
        return (root, stack)
    }

    private func inputRow(name: String, subtitle: String, detail: String, symbol: String?, control: NSView,
                          indent: Bool = false) -> NSView {
        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        let title = NSTextField(labelWithString: name)
        title.font = SystemAppearancePolicy.font(relativeToBody: 0)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.toolTip = detail
        let shown = subtitle.count <= 16 ? subtitle : String(subtitle.prefix(16))
        let line = NSTextField(labelWithString: shown)
        line.font = SystemAppearancePolicy.font(relativeToBody: -2)
        line.textColor = .secondaryLabelColor
        line.lineBreakMode = .byTruncatingTail
        line.maximumNumberOfLines = 1
        line.toolTip = subtitle.count <= 16 ? detail : "\(subtitle)。\(detail)"
        labels.addArrangedSubview(title)
        labels.addArrangedSubview(line)
        var parts: [NSView] = []
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let icon = NSImageView(image: image)
            icon.symbolConfiguration = NSImage.SymbolConfiguration(hierarchicalColor: .controlAccentColor)
            icon.wantsLayer = true
            icon.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
            icon.layer?.cornerRadius = 7
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 28).isActive = true
            parts.append(icon)
        }
        parts.append(labels)
        let content = NSStackView(views: parts)
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 10
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [content, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: indent ? 24 : 0),
            content.trailingAnchor.constraint(equalTo: control.leadingAnchor, constant: -14),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
        ])
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        return row
    }
}
