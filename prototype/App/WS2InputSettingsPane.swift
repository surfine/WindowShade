import Cocoa

extension AppDelegate {
    func makePointerSettingsPage() -> NSView {
        inputController.apply()
        let prefs = inputController.preferences
        let (root, stack) = inputPageRoot()
        stack.addArrangedSubview(inputCaption(WSL10n.text("settings.input.caption", zh: "滚动和按键默认不改。")))
        let rows = [
            inputRow(name: WSL10n.setting("settings.input.smooth.name", zh: "平滑滚动"),
                     subtitle: inputState(inputController.scrollStatus(prefersChange: prefs.smooth != nil)),
                     detail: WSL10n.setting("settings.input.smooth.detail", zh: "打开之后，滚轮的一格会变成一段连续滚动。现在还不能确认事件来自哪只鼠标，所以先不改。"),
                     symbol: nil, control: smoothPopup(prefs)),
            inputRow(name: WSL10n.setting("settings.input.mouseDirection.name", zh: "鼠标滚动方向"),
                     subtitle: mouseDirectionSubtitle(prefs),
                     detail: WSL10n.setting("settings.input.mouseDirection.detail", zh: "只准备改鼠标的滚动。还不能确认事件来自哪只鼠标时，先不改。"),
                     symbol: nil, control: inputSwitch(on: prefs.mouseInvert, enabled: true, action: #selector(prefInputMouseDirection(_:)), name: WSL10n.text("settings.input.mouseDirection.name", zh: "鼠标滚动方向"))),
            inputRow(name: WSL10n.setting("settings.input.trackpadDirection.name", zh: "触控板滚动方向"),
                     subtitle: prefs.trackpadInvert
                        ? WSL10n.setting("settings.input.trackpadDirection.pending", zh: "触控板的滚动先不改")
                        : WSL10n.setting("settings.input.sameAsSystem", zh: "跟系统一样"),
                     detail: WSL10n.setting("settings.input.trackpadDirection.detail", zh: "这一项先存着。触控板的滚动现在还不能改。"),
                     symbol: nil, control: inputSwitch(on: prefs.trackpadInvert, enabled: true, action: #selector(prefInputTrackpadDirection(_:)), name: WSL10n.text("settings.input.trackpadDirection.name", zh: "触控板滚动方向"))),
            inputRow(name: WSL10n.setting("settings.input.fine.name", zh: "⌥ 精细"),
                     subtitle: inputState(InputStatusCopy.auxiliary(on: prefs.fine,
                                                                    offPhrase: "关着",
                                                                    onPhrase: "一格只滚一行",
                                                                    decision: inputController.scrollDecision)),
                     detail: WSL10n.setting("settings.input.fine.detail", zh: "按住 ⌥ 时，一条滚动只走一行。要和平滑滚动或鼠标滚动方向一起开。"),
                     symbol: nil, control: inputSwitch(on: prefs.fine, enabled: true, action: #selector(prefInputFine(_:)), name: WSL10n.text("settings.input.fine.name", zh: "⌥ 精细"))),
            inputRow(name: WSL10n.setting("settings.input.sideButtons.name", zh: "侧键后退、前进"),
                     subtitle: inputState(InputStatusCopy.auxiliary(on: prefs.sideButtons,
                                                                    offPhrase: "关着",
                                                                    onPhrase: "后退和前进",
                                                                    decision: inputController.scrollDecision)),
                     detail: WSL10n.setting("settings.input.sideButtons.detail", zh: "侧键 4、5 准备用作这个 App 的后退和前进。要和平滑滚动或鼠标滚动方向一起开。"),
                     symbol: nil, control: inputSwitch(on: prefs.sideButtons, enabled: true, action: #selector(prefInputSide(_:)), name: WSL10n.text("settings.input.sideButtons.name", zh: "侧键后退、前进"))),
            inputRow(name: WSL10n.setting("settings.input.middleFold.name", zh: "中键收起窗口"),
                     subtitle: middleSubtitle(prefs),
                     detail: WSL10n.setting("settings.input.middleFold.detail", zh: "在标题栏上用中键点一下收起或展开；往上拖也是收起，往下拖展开。默认关，打开才装钩子。"),
                     symbol: "rectangle.compress.vertical",
                     control: inputSwitch(on: prefs.middleFold, enabled: true,
                                          action: #selector(prefInputMiddleFold(_:)), name: WSL10n.text("settings.input.middleFold.name", zh: "中键收起窗口"))),
            inputRow(name: WSL10n.setting("settings.input.threeFinger.name", zh: "三指轻点是中键"),
                     subtitle: WSL10n.setting("settings.input.notChecked", zh: "还没核对，先不用"),
                     detail: WSL10n.setting("settings.input.threeFinger.detail", zh: "三指轻点还没核对，先不能开。"),
                     symbol: nil, control: inputSwitch(on: false, enabled: inputController.touchAvailable, action: nil, name: WSL10n.text("settings.input.threeFinger.name", zh: "三指轻点是中键"))),
            inputRow(name: WSL10n.setting("settings.input.fourFinger.name", zh: "四指轻点打开看不见的窗口"),
                     subtitle: WSL10n.setting("settings.input.notChecked", zh: "还没核对，先不用"),
                     detail: WSL10n.setting("settings.input.fourFinger.detail", zh: "四指轻点还没核对，先不能开。"),
                     symbol: "macwindow.on.rectangle", control: inputSwitch(on: false, enabled: inputController.touchAvailable, action: nil, name: WSL10n.text("settings.input.fourFinger.name", zh: "四指轻点打开看不见的窗口"))),
            inputRow(name: WSL10n.setting("settings.input.exceptions.name", zh: "例外的 App"),
                     subtitle: prefs.exceptions.isEmpty
                        ? WSL10n.setting("settings.input.exceptions.empty", zh: "还没有例外")
                        : WSL10n.setting("settings.input.exceptions.count", zh: "%@ 个应用", String(prefs.exceptions.count)),
                     detail: WSL10n.setting("settings.input.exceptions.detail", zh: "一行一个应用标识。列在这里的，滚动保持原样。"),
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
        stack.addArrangedSubview(inputCaption(WSL10n.text("settings.remote.caption", zh: "遥控模式没开时，遥控器不起作用。")))
        var rows = [
            inputRow(name: WSL10n.setting("settings.remote.siri.name", zh: "Siri 遥控器"),
                     subtitle: WSL10n.setting("settings.remote.siri.sub", zh: "遥控模式没开，连接状态未知。"),
                     detail: WSL10n.setting("settings.remote.siri.detail", zh: "遥控模式没开时不查找遥控器，所以看不到有没有配对。"),
                     symbol: "appletvremote.gen4", control: inputStatus(WSL10n.text("settings.remote.status.unknown", zh: "未知"))),
            inputRow(name: WSL10n.setting("settings.remote.mode.name", zh: "遥控模式"),
                     subtitle: remoteSubtitle(on: prefs.remoteMode, host: host),
                     detail: WSL10n.setting("settings.remote.mode.detail", zh: "打开后，这台 Mac 出现在 iPhone 上的遥控器的列表里。关掉就不再出现，连着的也会断开。"),
                     symbol: "iphone", control: inputSwitch(on: prefs.remoteMode, enabled: true, action: #selector(prefInputRemoteMode(_:)), name: WSL10n.text("settings.remote.mode.name", zh: "遥控模式"))),
            // 指挥模式是遥控模式下面的一项：总开关关着时灰着，也跟着关。
            inputRow(name: WSL10n.setting("settings.remote.conductor.name", zh: "指挥模式"),
                     subtitle: prefs.remoteMode
                        ? (conductorOn ? WSL10n.setting("settings.remote.status.on", zh: "开着") : WSL10n.setting("settings.remote.status.off", zh: "关着"))
                        : WSL10n.setting("settings.remote.conductor.needRemote", zh: "先打开遥控模式"),
                     detail: WSL10n.setting("settings.remote.conductor.detail", zh: "用遥控器走进刘海那一排里的会话：看会话、换模型、留草稿。"),
                     symbol: nil, control: inputSwitch(on: prefs.remoteMode && conductorOn, enabled: prefs.remoteMode,
                                                       action: #selector(prefInputConductor(_:)), name: WSL10n.text("settings.remote.conductor.name", zh: "指挥模式"))),
        ]
        if prefs.remoteMode {
            let peers = host?.pairedPeers ?? []
            if peers.isEmpty {
                rows.append(inputRow(name: WSL10n.setting("settings.remote.peers.name", zh: "已配对的 iPhone"),
                                     subtitle: WSL10n.setting("settings.remote.peers.empty", zh: "还没有"),
                                     detail: WSL10n.setting("settings.remote.peers.emptyDetail", zh: "在 iPhone 上的遥控器里选这台 Mac，就能配对。"),
                                     symbol: nil, control: inputStatus("")))
            }
            for peer in peers {
                let name = peer.displayName ?? WS2RemoteCopy.fallbackName
                let remove = NSButton(title: WSL10n.text("settings.remote.peer.remove", zh: "移除"), target: self, action: #selector(prefInputRemovePeer(_:)))
                remove.bezelStyle = .rounded
                remove.identifier = NSUserInterfaceItemIdentifier(peer.identifier.map { String(format: "%02x", $0) }.joined())
                remove.setAccessibilityLabel(WSL10n.text("settings.remote.peer.removeA11y", zh: "移除 %@", name))
                rows.append(inputRow(name: WSL10n.setting("settings.remote.peer.name", zh: "%@ · 已配对", name),
                                     subtitle: WSL10n.setting("settings.remote.peers.name", zh: "已配对的 iPhone"),
                                     detail: WSL10n.setting("settings.remote.peer.detail", zh: "移除后，这台 iPhone 不能再遥控，也不能指挥。"),
                                     symbol: nil, control: remove))
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
        let detail = WSL10n.setting("settings.remote.gamepad.detail", zh: "用十字键选，× 确认，○ 返回，△ 回到刘海那一排（按住 0.5 秒打开启动台），Options 播放或暂停。游戏在前台时手柄整个让开。")
        let rows = control.rows()
        guard !rows.isEmpty else {
            return [inputRow(name: WSL10n.setting("settings.remote.gamepad.name", zh: "游戏手柄"),
                             subtitle: WSL10n.setting("settings.remote.gamepad.none", zh: "没连上"),
                             detail: WSL10n.setting("settings.remote.gamepad.noneDetail", zh: "连上手柄后，这里会出现“控制这台 Mac”。"),
                             symbol: "gamecontroller", control: inputStatus(""))]
        }
        return rows.map { row in
            let subtitle: SettingsText
            switch row.access {
            case .off: subtitle = WSL10n.setting("settings.remote.status.off", zh: "关着")
            case .viewOnly: subtitle = WSL10n.setting("settings.remote.gamepad.viewOnly", zh: "只能看")
            case .controls:
                subtitle = row.yieldingToPage
                    ? WSL10n.setting("settings.remote.gamepad.yieldPage", zh: "指挥页在用")
                    : (row.yielding
                        ? WSL10n.setting("settings.remote.gamepad.yieldGame", zh: "游戏在前台，先让开")
                        : WSL10n.setting("settings.remote.status.on", zh: "开着"))
            }
            let toggle = inputSwitch(on: row.access != .off, enabled: true, action: #selector(prefGamepadControl(_:)),
                                     name: WSL10n.text("settings.remote.gamepad.control", zh: "控制这台 Mac · %@", row.name))
            toggle.identifier = NSUserInterfaceItemIdentifier(row.id.uuidString)
            return inputRow(name: WSL10n.setting("settings.remote.gamepad.control", zh: "控制这台 Mac · %@", row.name),
                            subtitle: subtitle, detail: detail,
                            symbol: "gamecontroller", control: toggle)
        }
    }

    @objc func prefGamepadControl(_ sender: NSSwitch) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        WS2GamepadDesktopControl.shared.setEnabled(sender.state == .on, padID: id)
        refreshPreferencesWindowIfOpen()
    }

    private func remoteSubtitle(on: Bool, host: WS2RemoteHost?) -> SettingsText {
        guard on else { return WSL10n.setting("settings.remote.status.off", zh: "关着") }
        switch host?.status {
        case .listening?:
            return host?.operatorIdentifier != nil
                ? WSL10n.setting("settings.remote.status.connected", zh: "iPhone 已连接")
                : WSL10n.setting("settings.remote.status.listening", zh: "在听")
        case .failed?: return WSL10n.setting("settings.remote.status.failed", zh: "没能打开，先关掉再开")
        case .starting?: return WSL10n.setting("settings.remote.status.starting", zh: "正在打开")
        case .off?, nil: return WSL10n.setting("settings.remote.status.off", zh: "关着")
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
        alert.messageText = WSL10n.text("settings.input.exceptions.name", zh: "例外的 App")
        alert.informativeText = WSL10n.text("settings.input.exceptions.detail", zh: "一行一个应用标识。列在这里的，滚动保持原样。")
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
        alert.addButton(withTitle: WSL10n.text("settings.input.exceptions.save", zh: "保存"))
        alert.addButton(withTitle: WSL10n.text("settings.common.cancel", zh: "取消"))
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

    private func mouseDirectionSubtitle(_ prefs: WS2InputPreferences.Value) -> SettingsText {
        guard prefs.mouseInvert else { return WSL10n.setting("settings.input.sameAsSystem", zh: "跟系统一样") }
        return inputState(inputController.scrollStatus(prefersChange: true))
    }

    private func middleSubtitle(_ prefs: WS2InputPreferences.Value) -> SettingsText {
        if inputController.middleTap.systemStopped { return WSL10n.setting("settings.input.middleFold.systemStopped", zh: "被系统停掉了，先关掉再开") }
        if prefs.middleFold {
            return inputController.middleListening
                ? WSL10n.setting("settings.remote.status.on", zh: "开着")
                : WSL10n.setting("settings.input.middleFold.notInstalled", zh: "还没装上")
        }
        return WSL10n.setting("settings.remote.status.off", zh: "关着")
    }

    /// 滚动安装状态的显示串：状态来自 Core 的状态机（中文源句=语义身份），
    /// 这里按源句映射到目录键，显示随当前语言。
    private func inputState(_ phrase: String) -> SettingsText {
        switch phrase {
        case "关着": return WSL10n.setting("settings.remote.status.off", zh: "关着")
        case "开着": return WSL10n.setting("settings.remote.status.on", zh: "开着")
        case "关着，不改滚动": return WSL10n.setting("settings.input.status.offNoChange", zh: "关着，不改滚动")
        case "一格只滚一行": return WSL10n.setting("settings.input.fine.on", zh: "一格只滚一行")
        case "后退和前进": return WSL10n.setting("settings.input.sideButtons.on", zh: "后退和前进")
        case "还没确认是哪只鼠标": return WSL10n.setting("settings.input.status.wheelUnknown", zh: "还没确认是哪只鼠标")
        case "还没确认滚动来自哪只": return WSL10n.setting("settings.input.status.sourceUnverified", zh: "还没确认滚动来自哪只")
        case "系统停掉了，滚动保持原样": return WSL10n.setting("settings.input.status.systemStopped", zh: "系统停掉了，滚动保持原样")
        case "先打开平滑滚动或滚动方向": return WSL10n.setting("settings.input.status.needSmooth", zh: "先打开平滑滚动或滚动方向")
        default:
            if phrase.hasPrefix("由 ") && phrase.hasSuffix(" 接管") {
                let who = String(phrase.dropFirst(2).dropLast(3))
                return WSL10n.setting("settings.input.status.yielded", zh: "由 %@ 接管", who)
            }
            // 未知源句原样透出并留痕：新状态出现时由测试/棘轮发现，不在这里悄悄造键。
            wlog("settings.input: unmapped scroll status phrase=\(phrase)")
            return SettingsText(key: "settings.input.status.unmapped", zh: phrase)
        }
    }

    private func smoothPopup(_ prefs: WS2InputPreferences.Value) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: [
            WSL10n.text("settings.input.smooth.off", zh: "关"),
            WSL10n.text("settings.input.smooth.light", zh: "轻"),
            WSL10n.text("settings.input.smooth.medium", zh: "中"),
            WSL10n.text("settings.input.smooth.trackpadLike", zh: "像触控板"),
        ])
        switch prefs.smooth {
        case .light: popup.selectItem(at: 1)
        case .medium: popup.selectItem(at: 2)
        case .trackpadLike: popup.selectItem(at: 3)
        case nil: popup.selectItem(at: 0)
        }
        popup.target = self
        popup.action = #selector(prefInputSmooth(_:))
        popup.setAccessibilityLabel(WSL10n.text("settings.input.smooth.name", zh: "平滑滚动"))
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
        let button = NSButton(title: WSL10n.text("settings.input.exceptions.edit", zh: "编辑…"), target: self, action: #selector(prefInputEditExceptions))
        button.bezelStyle = .rounded
        button.setAccessibilityLabel(WSL10n.text("settings.input.exceptions.name", zh: "例外的 App"))
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

    private func inputRow(name: SettingsText, subtitle: SettingsText, detail: SettingsText,
                          symbol: String?, control: NSView, indent: Bool = false) -> NSView {
        let content = WS2SettingsCopy.content(name: name, subtitle: subtitle, detail: detail, symbol: symbol)
        WS2SettingsCopy.pinInfoTrailing(content)
        let row = WS2SettingsRow(content: content, control: control, leadingInset: indent ? 24 : 0)
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        return row
    }
}
