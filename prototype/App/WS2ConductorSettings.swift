import Cocoa

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
        // 页头不是行：hugging 提到 required，页头按文字宽度站，ⓘ 不被撑到整页宽。
        let header = WS2SettingsCopy.content(
            name: nil,
            subtitle: WSL10n.setting("conductor.settings.intro", zh: "选择已连接的会话、准备下一轮模型和草稿；发送前单独确认。"),
            symbol: nil).view
        header.setContentHuggingPriority(.required, for: .horizontal)
        stack.addArrangedSubview(header)
        let on = WS2InputPreferences.load(from: store).remoteMode && WS2ConductorSettings.flag(WS2ConductorSettings.enabledKey, in: store)
        // 提示音只剩「实时活动」那一栏的一行（拍板 2026-10-29 第 1 条）；拍子听它，这一页不再重复摆。
        var rows = [
            conductorRow(name: WSL10n.setting("conductor.settings.mode", zh: "指挥模式"),
                         subtitle: WSL10n.setting("conductor.settings.mode.sub", zh: "先在遥控模式里打开"), symbol: nil,
                         control: conductorStatus(on ? WSL10n.text("conductor.settings.on", zh: "开着")
                                                      : WSL10n.text("conductor.settings.off", zh: "关着"))),
        ]
        let coding = conductorSwitch(on: WS2ConductorSettings.flag(WS2ConductorSettings.codingSessionsKey, in: store),
                                     action: #selector(prefConductorCodingSessions(_:)), name: WSL10n.text("notch.kind.session", zh: "编程会话"))
        rows.append(conductorRow(name: WSL10n.setting("notch.kind.session", zh: "编程会话"),
                                 subtitle: WSL10n.setting("conductor.settings.coding.sub", zh: "在刘海里看 Claude Code 在跑还是在等你"),
                                 symbol: nil, control: coding))
        let connect = NSButton(title: WSL10n.text("conductor.settings.hookConnect", zh: "连接"), target: self,
                                action: #selector(prefConductorConnectHook(_:)))
        connect.bezelStyle = .rounded
        connect.setAccessibilityLabel(WSL10n.text("conductor.settings.hookConnect", zh: "连接"))
        let copy = NSButton(title: WSL10n.text("conductor.settings.copyConfig", zh: "拷贝配置"), target: self,
                            action: #selector(prefConductorCopyHookConfig(_:)))
        copy.bezelStyle = .rounded
        copy.setAccessibilityLabel(WSL10n.text("conductor.settings.copyConfig.label", zh: "拷贝 Claude Code 的配置"))
        let helperReady = FileManager.default.isExecutableFile(atPath: WS2ConductorSettings.hookHelperPath)
        copy.isEnabled = helperReady
        let status = WS2HookConfigStore().currentStatus()
        connect.isEnabled = helperReady && status.writable
        connect.title = status.connected
            ? WSL10n.text("conductor.settings.hookDisconnect", zh: "断开")
            : WSL10n.text("conductor.settings.hookConnect", zh: "连接")

        let controls = NSStackView(views: [connect, copy])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8
        // 状态与卸载提醒放进副句：连接着的那句自带卸载提醒。三种副句都是走目录的整句。
        let subtitle: SettingsText = status.connected
            ? WSL10n.setting("conductor.settings.hookConfig.connectedSub", zh: "已连接，Claude Code 会报到刘海。卸载 WindowShade 前先在这里断开")
            : (helperReady ? WSL10n.setting("conductor.settings.hookNotConnected", zh: "未连接")
                           : WSL10n.setting("conductor.settings.hookConfig.missing", zh: "这个版本里没有"))
        rows.append(conductorRow(name: WSL10n.setting("conductor.settings.hookConfig", zh: "Claude Code 的配置"),
                                 subtitle: subtitle,
                                 symbol: nil, control: controls))
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

    @objc func prefConductorCodingSessions(_ sender: NSSwitch) {
        WS2ConductorSettings.setFlag(sender.state == .on, WS2ConductorSettings.codingSessionsKey, in: .standard)
    }
    /// A2 连接：先给看差异，确认才写；写之前备份。断开只删自己那几行。
    @objc func prefConductorConnectHook(_ sender: NSButton) {
        let store = WS2HookConfigStore()
        let status = store.currentStatus()
        guard status.writable else {
            sender.title = WSL10n.text("conductor.settings.hookConnect", zh: "连接")
            NSSound.beep()
            return
        }
        if status.connected {
            if store.disconnect() != nil { NSSound.beep(); return }
            refreshConductorSettingsIfOpen()
            return
        }
        guard let preview = store.previewConnect() else { NSSound.beep(); return }
        guard confirmHookChange(preview, in: sender.window) else { return }
        if store.connect() != nil { NSSound.beep(); return }
        refreshConductorSettingsIfOpen()
    }

    /// 差异确认页：文件、备份位置、要加的行。取消就不写任何东西。
    private func confirmHookChange(_ preview: WS2HookConfigStore.ChangePreview, in window: NSWindow?) -> Bool {
        let alert = NSAlert()
        alert.messageText = WSL10n.text("conductor.settings.hookDiffTitle", zh: "将要改动这个文件")
        let lines = preview.events.map { event in
            "\(event) → \(preview.command)"
        }.joined(separator: "\n")
        alert.informativeText = preview.path + "\n\n"
            + WSL10n.text("conductor.settings.hookDiffBody", zh: "会先在旁边存一份备份。将加入下面这几行：")
            + "\n" + lines
        alert.alertStyle = .informational
        alert.addButton(withTitle: WSL10n.text("conductor.settings.hookConnect", zh: "连接"))
        alert.addButton(withTitle: WSL10n.text("settings.common.cancel", zh: "取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 连接/断开之后这一行要换样子：重建设置页这一页（不动别的页）。
    private func refreshConductorSettingsIfOpen() {
        (NSApp.delegate as? AppDelegate)?.refreshPreferencesWindowIfOpen()
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
