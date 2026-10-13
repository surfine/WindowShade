import Cocoa

/// 指挥模式的设置只记在这台 Mac 上。开关在“遥控模式”下面（总开关关着时跟着关），这一页只放它的细项。
enum WS2ConductorSettings {
    static let enabledKey = "WindowShade.Conductor.Enabled"
    static let soundKey = "WindowShade.Conductor.Sound"
    static func slotKey(_ index: Int) -> String { "WindowShade.Conductor.ModelSlot.\(index)" }
    /// 编程会话：Claude Code 的 hook 报到本机 socket（WS2HookServer）。默认关，不依赖遥控模式。
    static let codingSessionsKey = "WindowShade.Conductor.CodingSessions"
    static var hookHelperPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/WindowShadeHook").path
    }
    /// 只生成给用户自己粘贴的配置，不写 ~/.claude（WS2HookConfigPreview.writesUserHome 永远是 false）。
    static func hookConfiguration(helper: String = hookHelperPath) -> String? {
        guard WS2HookConfigPreview.writesUserHome == false,
              let preview = try? WS2HookConfiguration.preview(original: Data("{}".utf8), executable: helper, connected: true)
        else { return nil }
        return String(data: preview.replacement, encoding: .utf8)
    }

    static func flag(_ key: String, in store: UserDefaults) -> Bool {
        store.object(forKey: key) as? Bool == true
    }
    static func setFlag(_ on: Bool, _ key: String, in store: UserDefaults) {
        if on { store.set(true, forKey: key) } else { store.removeObject(forKey: key) }
    }
    static func text(_ key: String, in store: UserDefaults) -> String {
        store.string(forKey: key) ?? ""
    }
    static func setText(_ value: String, _ key: String, in store: UserDefaults) {
        let trimmed = String(value.prefix(512))
        if trimmed.isEmpty { store.removeObject(forKey: key) } else { store.set(trimmed, forKey: key) }
    }
}

extension AppDelegate {
    func makeConductorSettingsPage() -> NSView {
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
        let store = UserDefaults.standard
        // 页头走 SettingsText 重载：en 用 shortEn 短句（String 重载会吃 16 字硬截）。
        stack.addArrangedSubview(WS2SettingsCopy.content(
            name: nil,
            subtitle: WSL10n.setting("conductor.settings.intro", zh: "选择已连接的会话、准备下一轮模型和草稿；发送前单独确认。"),
            symbol: nil).view)
        let on = WS2InputPreferences.load(from: store).remoteMode && WS2ConductorSettings.flag(WS2ConductorSettings.enabledKey, in: store)
        let sound = conductorSwitch(on: WS2ConductorSettings.flag(WS2ConductorSettings.soundKey, in: store),
                                    action: #selector(prefConductorSound(_:)), name: WSL10n.text("conductor.settings.sound", zh: "提示音"))
        var rows = [
            conductorRow(name: WSL10n.setting("conductor.settings.mode", zh: "指挥模式"),
                         subtitle: WSL10n.setting("conductor.settings.mode.sub", zh: "先在遥控模式里打开"), symbol: nil,
                         control: conductorStatus(on ? WSL10n.text("conductor.settings.on", zh: "开着")
                                                      : WSL10n.text("conductor.settings.off", zh: "关着"))),
            conductorRow(name: WSL10n.setting("conductor.settings.sound", zh: "提示音"),
                         subtitle: WSL10n.setting("conductor.settings.sound.sub", zh: "每一拍轻敲一声。"), symbol: nil,
                         control: sound),
        ]
        let coding = conductorSwitch(on: WS2ConductorSettings.flag(WS2ConductorSettings.codingSessionsKey, in: store),
                                     action: #selector(prefConductorCodingSessions(_:)), name: WSL10n.text("notch.kind.session", zh: "编程会话"))
        rows.append(conductorRow(name: WSL10n.setting("notch.kind.session", zh: "编程会话"),
                                 subtitle: WSL10n.setting("conductor.settings.coding.sub", zh: "在刘海里看 Claude Code 在跑还是在等你"),
                                 symbol: nil, control: coding))
        let copy = NSButton(title: WSL10n.text("conductor.settings.copyConfig", zh: "拷贝配置"), target: self,
                            action: #selector(prefConductorCopyHookConfig(_:)))
        copy.bezelStyle = .rounded
        copy.setAccessibilityLabel(WSL10n.text("conductor.settings.copyConfig.label", zh: "拷贝 Claude Code 的配置"))
        let helperReady = FileManager.default.isExecutableFile(atPath: WS2ConductorSettings.hookHelperPath)
        copy.isEnabled = helperReady
        rows.append(conductorRow(name: WSL10n.setting("conductor.settings.hookConfig", zh: "Claude Code 的配置"),
                                 subtitle: helperReady ? WSL10n.setting("conductor.settings.hookConfig.sub", zh: "拷贝后粘贴到它的设置里")
                                                      : WSL10n.setting("conductor.settings.hookConfig.missing", zh: "这个版本里没有"),
                                 symbol: nil, control: copy))
        for index in 1...4 {
            let field = NSTextField(string: WS2ConductorSettings.text(WS2ConductorSettings.slotKey(index), in: store))
            field.placeholderString = WSL10n.text("conductor.settings.notFilled", zh: "还没填")
            field.identifier = NSUserInterfaceItemIdentifier(String(index))
            field.target = self
            field.action = #selector(prefConductorSlot(_:))
            field.setAccessibilityLabel(WSL10n.text("conductor.settings.modelSlot", zh: "模型位置 %@", String(index)))
            field.widthAnchor.constraint(equalToConstant: 180).isActive = true
            rows.append(conductorRow(name: WSL10n.setting("conductor.settings.modelSlot", zh: "模型位置 %@", String(index)),
                                     subtitle: WSL10n.setting("conductor.settings.localOnly", zh: "只留在这台 Mac 上"),
                                     symbol: nil, control: field))
        }
        let card = makeUnifiedSettingsCard(rows)
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return root
    }

    @objc func prefConductorSound(_ sender: NSSwitch) {
        WS2ConductorSettings.setFlag(sender.state == .on, WS2ConductorSettings.soundKey, in: .standard)
    }
    @objc func prefConductorCodingSessions(_ sender: NSSwitch) {
        WS2ConductorSettings.setFlag(sender.state == .on, WS2ConductorSettings.codingSessionsKey, in: .standard)
    }
    /// 只放进剪贴板，由用户自己粘贴到 Claude Code 的设置里。
    @objc func prefConductorCopyHookConfig(_ sender: NSButton) {
        guard let text = WS2ConductorSettings.hookConfiguration() else {
            sender.title = WSL10n.text("conductor.settings.copyFailed", zh: "没拷上"); return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        sender.title = WSL10n.text("conductor.settings.copied", zh: "已拷贝")
    }
    @objc func prefConductorSlot(_ sender: NSTextField) {
        guard let raw = sender.identifier?.rawValue, let index = Int(raw), (1...4).contains(index) else { return }
        WS2ConductorSettings.setText(sender.stringValue, WS2ConductorSettings.slotKey(index), in: .standard)
    }

    private func conductorSwitch(on: Bool, action: Selector, name: String) -> NSSwitch {
        let toggle = NSSwitch()
        toggle.state = on ? .on : .off
        toggle.target = self
        toggle.action = action
        toggle.setAccessibilityLabel(name)
        return toggle
    }
    private func conductorStatus(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 12)
        field.textColor = .secondaryLabelColor
        return field
    }
    private func conductorRow(name: SettingsText, subtitle: SettingsText, symbol: String?, control: NSView) -> NSView {
        let labels = WS2SettingsCopy.content(name: name, subtitle: subtitle, symbol: symbol).view
        WS2SettingsCopy.pinInfoTrailing(labels)
        let row = WS2SettingsRow(content: labels, control: control, leadingInset: 12, trailingInset: 12)
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        NSLayoutConstraint.activate([
            labels.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 8),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -8),
        ])
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        return row
    }
}
