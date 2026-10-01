// 应用内更新：设置里“更新”一组的行（“权限与启动”页，“启动”下面）。
// 行的样子照 Preferences.swift 的 makeUnifiedToggleRow / makeUnifiedControlRow；卡片由设置页自己包。
//
// 接线（Preferences.swift 的 makePermissionsSettingsPage，“启动”那张卡片之后）：
//     stack.setCustomSpacing(18, after: launch)
//     stack.addArrangedSubview(makePrefGroupLabel(UpdateCopy.settingsGroup))
//     let update = makeUnifiedSettingsCard(UpdaterController.shared.makeSettingsRows())
//     stack.addArrangedSubview(update)
//     update.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

import Cocoa

extension UpdaterController {
    /// 自动检查更新、检查频率、当前版本（带“检查更新”按钮，结果写在这一行）；
    /// 更新后 7 天内多出“看更新记录”和“回到 x.y.z”。
    func makeSettingsRows() -> [NSView] {
        let toggle = NSSwitch()
        toggle.state = automaticallyChecks ? .on : .off
        toggle.target = self
        toggle.action = #selector(settingsToggleAutomaticChecks(_:))
        toggle.setAccessibilityLabel(UpdateCopy.autoCheck)

        let frequency = NSSegmentedControl(labels: [UpdateCopy.daily, UpdateCopy.weekly], trackingMode: .selectOne,
                                           target: self, action: #selector(settingsSelectFrequency(_:)))
        frequency.selectedSegment = checkInterval >= UpdateSettingsKeys.weekly ? 1 : 0
        frequency.isEnabled = automaticallyChecks
        frequency.setAccessibilityLabel(UpdateCopy.frequency)

        let checkButton = NSButton(title: UpdateCopy.checkButton, target: self, action: #selector(checkForUpdatesAction(_:)))
        checkButton.bezelStyle = .push
        checkButton.isEnabled = isAvailable

        let (versionRow, status) = Self.row(name: UpdateCopy.currentVersionRow(currentVersion), subtitle: settingsStatus ?? "",
                                            control: checkButton)
        status?.isHidden = settingsStatus == nil
        if let status { bindSettings(statusLabel: status, frequency: frequency) }

        var rows: [NSView] = [
            Self.row(name: UpdateCopy.autoCheck, subtitle: UpdateCopy.autoCheckDetail, control: toggle).0,
            Self.row(name: UpdateCopy.frequency, subtitle: nil, control: frequency).0,
            versionRow,
        ]
        if let previous = rollbackVersion {
            let notes = NSButton(title: UpdateCopy.releaseNotes, target: self, action: #selector(settingsOpenReleaseNotes))
            notes.isBordered = false
            notes.contentTintColor = .linkColor
            rows.append(Self.row(name: nil, subtitle: nil, control: notes, leading: true).0)
            let rollback = NSButton(title: UpdateCopy.rollback(previous), target: self, action: #selector(settingsRollBack))
            rollback.bezelStyle = .push
            rows.append(Self.row(name: UpdateCopy.rollbackDetail, subtitle: nil, control: rollback).0)
        }
        return rows
    }

    /// 关掉自动检查更新会让这台 Mac 收不到安全更新，所以要用 Touch ID 确认（docs/touch-id-island.md）。
    /// 开关先保持“开”，拿到一次性授权、并按此刻的实际值重算目标消费成功后，才真的关掉。重新打开不需要确认。
    /// 这台 Mac 没法确认（没有 Touch ID、刘海关着）时直接改：没有可用来确认的东西。
    /// 局限：同一用户下的其他程序仍能直接改偏好文件；这里挡的是“有人在没锁的 Mac 前从设置里把它关掉”。
    @objc func settingsToggleAutomaticChecks(_ sender: NSSwitch) {
        let wantsOn = sender.state == .on
        guard !wantsOn, automaticallyChecks else { automaticallyChecks = wantsOn; return }
        sender.state = .on
        let target = AuthTarget.setting(UpdateSettingsKeys.automaticChecks, from: true, to: false)
        let started = confirmChange?(target) { [weak self, weak sender] grant in
            guard let self else { return }
            let current = AuthTarget.setting(UpdateSettingsKeys.automaticChecks, from: self.automaticallyChecks, to: false)
            if let grant, AuthorizationService.shared.consume(grant, purpose: .changeSecurityPolicy, currentTarget: current) == nil {
                self.automaticallyChecks = false
            }
            sender?.state = self.automaticallyChecks ? .on : .off
        } ?? false
        if !started {
            automaticallyChecks = false
            sender.state = .off
        }
    }

    @objc func settingsSelectFrequency(_ sender: NSSegmentedControl) {
        checkInterval = sender.selectedSegment == 1 ? UpdateSettingsKeys.weekly : UpdateSettingsKeys.daily
    }

    @objc func settingsOpenReleaseNotes() {
        NSWorkspace.shared.open(UpdateLinks.releaseNotes)
    }

    @objc func settingsRollBack() {
        rollBackToPrevious()
    }

    /// 返回这一行和它的说明文字（结果写在说明里）。
    private static func row(name: String?, subtitle: String?, control: NSControl, leading: Bool = false) -> (NSView, NSTextField?) {
        control.sizeToFit()
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        if leading {
            let row = NSStackView(views: [control])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
            return (row, nil)
        }
        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        if let name {
            let title = NSTextField(wrappingLabelWithString: name)
            title.font = SystemAppearancePolicy.font(relativeToBody: 0)
            labels.addArrangedSubview(title)
        }
        var detail: NSTextField?
        if let subtitle {
            let field = NSTextField(wrappingLabelWithString: subtitle)
            field.font = SystemAppearancePolicy.font(relativeToBody: -2)
            field.textColor = .secondaryLabelColor
            field.maximumNumberOfLines = 2
            labels.addArrangedSubview(field)
            field.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
            detail = field
        }
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [labels, control])
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            labels.trailingAnchor.constraint(equalTo: control.leadingAnchor, constant: -14),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 8),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -8),
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: subtitle == nil ? 40 : 48).isActive = true
        return (row, detail)
    }
}
