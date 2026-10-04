import Cocoa

/// 指挥模式的设置只记在这台 Mac 上。打开开关不会宣告、不会连接、不会发声。
enum WS2ConductorSettings {
    static let enabledKey = "WindowShade.Conductor.Enabled"
    static let soundKey = "WindowShade.Conductor.Sound"
    static func slotKey(_ index: Int) -> String { "WindowShade.Conductor.ModelSlot.\(index)" }

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
        let intro = "看当前会话、改模型、写草稿。不会发送，也不会连接。"
        stack.addArrangedSubview(WS2SettingsCopy.content(name: nil, subtitle: intro, symbol: nil).view)
        let enabled = conductorSwitch(on: WS2ConductorSettings.flag(WS2ConductorSettings.enabledKey, in: store),
                                      action: #selector(prefConductorEnabled(_:)), name: "指挥模式")
        let sound = conductorSwitch(on: WS2ConductorSettings.flag(WS2ConductorSettings.soundKey, in: store),
                                    action: #selector(prefConductorSound(_:)), name: "提示音")
        var rows = [
            conductorRow(name: "指挥模式", subtitle: "先记住，还不会连接", symbol: nil, control: enabled),
            conductorRow(name: "已配对的 iPhone", subtitle: "还没有", symbol: "iphone", control: conductorStatus("未知")),
            conductorRow(name: "提示音", subtitle: "先记住，还不会响", symbol: nil, control: sound),
        ]
        for index in 1...4 {
            let field = NSTextField(string: WS2ConductorSettings.text(WS2ConductorSettings.slotKey(index), in: store))
            field.placeholderString = "还没填"
            field.identifier = NSUserInterfaceItemIdentifier(String(index))
            field.target = self
            field.action = #selector(prefConductorSlot(_:))
            field.setAccessibilityLabel("模型位置 \(index)")
            field.widthAnchor.constraint(equalToConstant: 180).isActive = true
            rows.append(conductorRow(name: "模型位置 \(index)", subtitle: "只存在这里", symbol: nil, control: field))
        }
        let card = makeUnifiedSettingsCard(rows)
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return root
    }

    @objc func prefConductorEnabled(_ sender: NSSwitch) {
        WS2ConductorSettings.setFlag(sender.state == .on, WS2ConductorSettings.enabledKey, in: .standard)
    }
    @objc func prefConductorSound(_ sender: NSSwitch) {
        WS2ConductorSettings.setFlag(sender.state == .on, WS2ConductorSettings.soundKey, in: .standard)
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
    private func conductorRow(name: String, subtitle: String, symbol: String?, control: NSView) -> NSView {
        let labels = WS2SettingsCopy.content(name: name, subtitle: subtitle, symbol: symbol).view
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [labels, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        return row
    }
}
