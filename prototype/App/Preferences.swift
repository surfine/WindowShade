// 设置窗口与引导页：设置窗口/引导页视图构建、权限引导状态刷新、
// 偏好开关动作。作为 AppDelegate 扩展实现。

import Cocoa
import Carbon.HIToolbox
import ServiceManagement

private let prefCardWidth: CGFloat = 560
private let prefRowInset: CGFloat = 14
private let prefTrailingControlColumnWidth: CGFloat = 152

extension AppDelegate {
@objc func toggleTitlebarDoubleClick(_ sender: NSMenuItem) {
        titlebarDoubleClickEnabled.toggle()
        UserDefaults.standard.set(titlebarDoubleClickEnabled, forKey: shadeTitlebarDoubleClickDefaultsKey)
        rebuildMenu()
        refreshPreferencesWindowIfOpen()
    }


@objc func togglePinnedPreviewAction() {
        pinnedPreviewController.pinCurrentTargetPreview()
    }

@objc func cancelPinnedPreviewMenuItem(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        pinnedPreviewController.stopPreviewFromMenu(id: CGWindowID(number.uint32Value))
        rebuildMenu()
    }

@objc func stopAllPinnedPreviewsAction() {
        pinnedPreviewController.stopAllPreviews(reason: "menu-stop-all")
        rebuildMenu()
    }

@objc func toggleSuspendPinnedPreviewsAction() {
        pinnedPreviewController.toggleSuspendAll()
        rebuildMenu()
    }

    func soundName(defaultsKey: String, fallback: String) -> String {
        let name = UserDefaults.standard.string(forKey: defaultsKey) ?? fallback
        return shadeSoundChoices.contains(where: { $0.name == name }) ? name : fallback
    }

    func playShadeSound(_ name: String) {
        guard soundEnabled else { return }
        let sound = NSSound(named: NSSound.Name(name))
        guard let sound else { return }
        sound.play()
    }

    func playFoldSound() {
        playShadeSound(soundName(defaultsKey: shadeFoldSoundDefaultsKey, fallback: shadeDefaultFoldSound))
    }

    func playUnfoldSound() {
        playShadeSound(soundName(defaultsKey: shadeUnfoldSoundDefaultsKey, fallback: shadeDefaultUnfoldSound))
    }

    func refreshPreferencesWindowIfOpen() {
        if let settingsWindow = duoController.settingsWindow,
           settingsWindow.window?.isVisible == true {
            settingsWindow.refreshSettings()
            return
        }
        guard let window = preferencesWindow, window.isVisible else { return }
        window.contentView = makePreferencesContentView()
    }

    func quietNotice(_ message: String, log: String? = nil) {
        wlog(log ?? "notice: \(message)")
        statusNoticeWorkItem?.cancel()
        // 菜单栏标题保持短小（完整文案在 tooltip 与可访问性值里），
        // 否则一句长提示会把状态栏条挤得很宽，顶开旁边的菜单栏项目。
        statusItem.button?.title = " \(PaperSurfaceAccessibility.statusItemNoticeTitle(message))"
        statusItem.button?.toolTip = message
        statusItem.button?.setAccessibilityValue(message)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.statusNoticeWorkItem = nil
            self.rebuildMenu()
        }
        statusNoticeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

/// 系统标准“关于”面板 + 一句用途说明与许可信息（代理应用从状态栏菜单进入）。
@objc func showAboutPanel() {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        as? String ?? ""
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    NSApp.orderFrontStandardAboutPanel(options: StandardMenu.aboutPanelOptions(
        version: version, build: build))
    NSApp.activate()
}

@objc func showPreferences() {
        showSettingsWindow()
    }

    private func makeSettingsPageRoot() -> (NSView, NSStackView) {
        // 背景由设置窗口的详情区统一铺满，页面保持透明。
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

    // 与效果页一致：页内不重复大标题，只留一行说明。
    private func makeSettingsHeader(title: String, subtitle: String, symbolName: String? = nil) -> NSView {
        let caption = NSTextField(wrappingLabelWithString: subtitle)
        caption.font = SystemAppearancePolicy.font(relativeToBody: -1)
        caption.textColor = .secondaryLabelColor
        caption.maximumNumberOfLines = 2
        return caption
    }

    func makeShadeSettingsPage() -> NSView {
        let (root, stack) = makeSettingsPageRoot()
        stack.addArrangedSubview(makeSettingsHeader(
            title: "卷帘", subtitle: "设置怎么收起窗口、收起后什么样、要不要提示音。", symbolName: "rectangle.compress.vertical"))

        let trigger = makeUnifiedSettingsCard([
            makeUnifiedToggleRow(name: "双击标题栏收起窗口", subtitle: titlebarDoubleClickPreferenceSubtitle(),
                                 isOn: titlebarDoubleClickEnabled, action: #selector(prefToggleTitlebarDoubleClick(_:))),
        ])
        stack.addArrangedSubview(makePrefGroupLabel("触发"))
        stack.addArrangedSubview(trigger)
        trigger.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: trigger)

        let appearanceSeg = NSSegmentedControl(labels: ["跟原来一样", "统一标题栏"],
                                                trackingMode: .selectOne,
                                                target: self,
                                                action: #selector(prefSelectAppearanceSegment(_:)))
        appearanceSeg.selectedSegment = appearanceMode == .proxyTitleBar ? 1 : 0
        stack.addArrangedSubview(makePrefGroupLabel("外观"))
        let appearance = makeUnifiedSettingsCard([
            makeUnifiedControlRow(name: "收起后的样子", subtitle: "跟原来一样，或换成统一的标题栏", control: appearanceSeg),
            makeUnifiedToggleRow(name: "浮在其他窗口上面", subtitle: "收起的窗口也不会被别的窗口挡住",
                                 isOn: floatingOnTop, action: #selector(prefToggleFloating(_:))),
            makeUnifiedToggleRow(name: "卷帘条半透明", subtitle: "让它更透一些，能看到后面的内容",
                                 isOn: translucent, action: #selector(prefToggleTranslucent(_:))),
        ])
        stack.addArrangedSubview(appearance)
        appearance.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)

        stack.addArrangedSubview(makePrefGroupLabel("声音"))
        let sound = makeUnifiedSettingsCard([
            makeUnifiedToggleRow(name: "收起和展开时播放音效", subtitle: nil,
                                 isOn: soundEnabled, action: #selector(prefToggleSound(_:))),
            makeUnifiedControlRow(name: "收起音效", subtitle: nil,
                                  control: makeSoundPopup(selected: foldSoundName, action: #selector(prefSelectFoldSound(_:)))),
            makeUnifiedControlRow(name: "展开音效", subtitle: nil,
                                  control: makeSoundPopup(selected: unfoldSoundName, action: #selector(prefSelectUnfoldSound(_:)))),
        ])
        stack.addArrangedSubview(sound)
        sound.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return root
    }

    func makePermissionsSettingsPage() -> NSView {
        let (root, stack) = makeSettingsPageRoot()
        stack.addArrangedSubview(makeSettingsHeader(
            title: "权限与启动", subtitle: "WindowShade 只在需要时使用系统权限。", symbolName: "lock.shield"))
        stack.addArrangedSubview(makePrefGroupLabel("权限"))
        let permissions = makeUnifiedSettingsCard([
            makeUnifiedPermissionRow(symbol: "accessibility", name: "辅助功能",
                                     subtitle: "找到、移动和恢复窗口",
                                     granted: hasAccessibilityPermission(), action: #selector(openAccessibilitySettingsAction)),
            makeUnifiedPermissionRow(symbol: "rectangle.inset.filled.and.person.filled",
                                     name: "屏幕录制", subtitle: "截取窗口画面做预览",
                                     granted: hasScreenRecordingPermission(), action: #selector(openScreenRecordingSettingsAction)),
        ], separatorInset: 46)
        stack.addArrangedSubview(permissions)
        permissions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(makePrefGroupLabel("启动"))
        let launch = makeUnifiedSettingsCard([
            makeUnifiedToggleRow(name: "登录时自动启动", subtitle: launchAtLoginSubtitle(),
                                 isOn: launchAtLoginEnabled(), action: #selector(prefToggleLaunchAtLogin(_:))),
        ])
        stack.addArrangedSubview(launch)
        launch.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return root
    }

    func makePreferencesContentView() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: prefCardWidth + 44, height: 700))
        let stack = NSStackView(frame: root.bounds.insetBy(dx: 22, dy: 20))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.autoresizingMask = [.width, .height]
        root.addSubview(stack)

        func addGroup(_ title: String, _ card: NSView) {
            stack.addArrangedSubview(makePrefGroupLabel(title))
            stack.addArrangedSubview(card)
            stack.setCustomSpacing(16, after: card)
        }

        let general = makePrefCard([
            makePrefToggleRow(name: "双击标题栏收起窗口", subtitle: titlebarDoubleClickPreferenceSubtitle(),
                              isOn: titlebarDoubleClickEnabled, action: #selector(prefToggleTitlebarDoubleClick(_:))),
            makePrefToggleRow(name: "卷帘条浮动于上方", subtitle: "折叠后的标题栏保持在其他窗口之上",
                              isOn: floatingOnTop, action: #selector(prefToggleFloating(_:))),
            makePrefToggleRow(name: "卷帘条半透明", subtitle: "略微降低卷帘条不透明度",
                              isOn: translucent, action: #selector(prefToggleTranslucent(_:))),
            makePrefToggleRow(name: "登录时自动启动", subtitle: launchAtLoginSubtitle(),
                              isOn: launchAtLoginEnabled(), action: #selector(prefToggleLaunchAtLogin(_:))),
        ])
        addGroup("通用", general)

        let appearanceSeg = NSSegmentedControl(labels: ["跟原来一样", "统一标题栏"],
                                               trackingMode: .selectOne,
                                               target: self,
                                               action: #selector(prefSelectAppearanceSegment(_:)))
        appearanceSeg.selectedSegment = appearanceMode == .proxyTitleBar ? 1 : 0
        appearanceSeg.sizeToFit()
        addGroup("外观", makePrefCard([
            makePrefControlRow(name: "收起后的样子", subtitle: "跟原来一样，或换成统一的标题栏", control: appearanceSeg),
        ]))

        addGroup("声音", makePrefCard([
            makePrefToggleRow(name: "收起和展开时播放音效", subtitle: nil,
                              isOn: soundEnabled, action: #selector(prefToggleSound(_:))),
            makePrefControlRow(name: "收起音效", subtitle: nil,
                               control: makeSoundPopup(selected: foldSoundName, action: #selector(prefSelectFoldSound(_:)))),
            makePrefControlRow(name: "展开音效", subtitle: nil,
                               control: makeSoundPopup(selected: unfoldSoundName, action: #selector(prefSelectUnfoldSound(_:)))),
        ]))

        addGroup("权限", makePrefCard([
            makePermissionRow(kind: .preferences, width: prefCardWidth, symbol: "accessibility", name: "辅助功能", subtitle: "找到、移动和恢复窗口",
                              granted: hasAccessibilityPermission(), action: #selector(openAccessibilitySettingsAction)),
            makePermissionRow(kind: .preferences, width: prefCardWidth, symbol: "rectangle.inset.filled.and.person.filled", name: "屏幕录制", subtitle: "截取窗口画面做预览",
                              granted: hasScreenRecordingPermission(), action: #selector(openScreenRecordingSettingsAction)),
        ]))

        return root
    }

    func makePrefGroupLabel(_ text: String) -> NSView {
        // 分组标题只有文字，与「效果」「高级」两页保持一致。
        let field = NSTextField(labelWithString: text)
        field.font = SystemAppearancePolicy.font(relativeToBody: -1, weight: .semibold)
        field.textColor = .secondaryLabelColor
        return field
    }

    private func makeUnifiedSettingsCard(_ rows: [NSView], separatorInset: CGFloat = 16) -> NSView {
        let card = SettingsGroupBox()
        card.wantsLayer = true
        card.translatesAutoresizingMaskIntoConstraints = false

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 0
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
        ])

        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = NSBox()
                separator.boxType = .separator
                let line = NSView()
                separator.translatesAutoresizingMaskIntoConstraints = false
                line.addSubview(separator)
                inner.addArrangedSubview(line)
                NSLayoutConstraint.activate([
                    line.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -16),
                    line.heightAnchor.constraint(equalToConstant: 0.5),
                    separator.leadingAnchor.constraint(equalTo: line.leadingAnchor, constant: separatorInset - 16),
                    separator.trailingAnchor.constraint(equalTo: line.trailingAnchor),
                    separator.centerYAnchor.constraint(equalTo: line.centerYAnchor),
                ])
            }
            inner.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        }
        return card
    }

    func makePermissionDesignSample() -> NSView {
        makeUnifiedSettingsCard([
            makeUnifiedPermissionRow(symbol: "accessibility", name: "辅助功能",
                subtitle: "找到、移动和恢复窗口", granted: false,
                action: #selector(openAccessibilitySettingsAction)),
            makeUnifiedPermissionRow(symbol: "rectangle.inset.filled.and.person.filled", name: "屏幕录制",
                subtitle: "截取窗口画面做预览", granted: true,
                action: #selector(openScreenRecordingSettingsAction)),
        ], separatorInset: 46)
    }

    private func makeUnifiedLabels(name: String, subtitle: String?) -> NSStackView {
        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        let title = NSTextField(labelWithString: name)
        title.font = SystemAppearancePolicy.font(relativeToBody: 0)
        labels.addArrangedSubview(title)
        if let subtitle {
            let detail = NSTextField(wrappingLabelWithString: subtitle)
            detail.font = SystemAppearancePolicy.font(relativeToBody: -2)
            detail.textColor = .secondaryLabelColor
            detail.maximumNumberOfLines = 2
            labels.addArrangedSubview(detail)
            detail.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
        }
        return labels
    }

    private func makeUnifiedToggleRow(name: String, subtitle: String?, isOn: Bool,
                                      action: Selector) -> NSView {
        let toggle = NSSwitch()
        toggle.state = isOn ? .on : .off
        toggle.target = self
        toggle.action = action
        toggle.setAccessibilityLabel(name)
        toggle.controlSize = .regular
        let labels = makeUnifiedLabels(name: name, subtitle: subtitle)
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [labels, toggle])
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            labels.trailingAnchor.constraint(equalTo: toggle.leadingAnchor, constant: -14),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 8),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -8),
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: subtitle == nil ? 40 : 48).isActive = true
        return row
    }

    private func makeUnifiedControlRow(name: String, subtitle: String?, control: NSControl) -> NSView {
        control.sizeToFit()
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        let labels = makeUnifiedLabels(name: name, subtitle: subtitle)
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
        return row
    }

    private func makeUnifiedPermissionRow(symbol: String, name: String, subtitle: String,
                                           granted: Bool, action: Selector) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: name) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let labels = makeUnifiedLabels(name: name, subtitle: subtitle)
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let chip = NSButton(title: granted ? "✓ 已授权" : "● 去授权", target: self, action: action)
        chip.isBordered = false
        chip.font = SystemAppearancePolicy.font(relativeToBody: -1)
        chip.contentTintColor = granted ? .systemGreen : .systemOrange
        SystemCornerRadius.apply(to: chip, radius: SystemCornerRadius.control)
        chip.setAccessibilityLabel("\(name)，\(granted ? "已授权，打开设置" : "去授权")")
        chip.setContentHuggingPriority(.required, for: .horizontal)
        let trailing = chip
        let row = NSStackView(views: [icon, labels, trailing])
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            labels.trailingAnchor.constraint(equalTo: trailing.leadingAnchor, constant: -12),
            trailing.trailingAnchor.constraint(equalTo: row.trailingAnchor),
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        return row
    }

    func makePrefCard(_ rows: [NSView]) -> NSView {
        let card = NSView()
        SystemCornerRadius.apply(to: card, radius: SystemCornerRadius.card)
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = SystemAppearancePolicy.cgColor(
            NSColor.separatorColor, for: card)
        card.layer?.backgroundColor = SystemAppearancePolicy.cgColor(
            NSColor.controlBackgroundColor, for: card)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalToConstant: prefCardWidth).isActive = true

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 0
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            inner.topAnchor.constraint(equalTo: card.topAnchor),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        for (i, row) in rows.enumerated() {
            if i > 0 {
                let sep = NSBox()
                sep.boxType = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                inner.addArrangedSubview(sep)
                sep.widthAnchor.constraint(equalToConstant: prefCardWidth).isActive = true
            }
            inner.addArrangedSubview(row)
        }
        return card
    }

    func makePrefRow(height: CGFloat) -> NSView {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: prefCardWidth, height: height))
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: prefCardWidth).isActive = true
        row.heightAnchor.constraint(equalToConstant: height).isActive = true
        return row
    }

    func makePrefName(_ text: String, y: CGFloat) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = SystemAppearancePolicy.font(relativeToBody: 0)
        let width = prefCardWidth - (prefRowInset * 2) - prefTrailingControlColumnWidth - 12
        field.frame = NSRect(x: prefRowInset, y: y, width: width, height: 18)
        return field
    }

    func makePrefSubtitle(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = SystemAppearancePolicy.font(relativeToBody: -2)
        field.textColor = .tertiaryLabelColor
        let width = prefCardWidth - (prefRowInset * 2) - prefTrailingControlColumnWidth - 12
        field.frame = NSRect(x: prefRowInset, y: 9, width: width, height: 15)
        return field
    }

    func makePrefToggleRow(name: String, subtitle: String?, isOn: Bool, action: Selector) -> NSView {
        let h: CGFloat = subtitle == nil ? 42 : 54
        let row = makePrefRow(height: h)
        row.addSubview(makePrefName(name, y: subtitle == nil ? (h - 18) / 2 : h - 14 - 18))
        if let subtitle = subtitle { row.addSubview(makePrefSubtitle(subtitle)) }
        let sw = NSSwitch()
        sw.state = isOn ? .on : .off
        sw.target = self
        sw.action = action
        sw.sizeToFit()
        let swW = sw.frame.width
        let swH = sw.frame.height
        sw.frame = NSRect(x: prefCardWidth - prefRowInset - swW, y: floor((h - swH) / 2), width: swW, height: swH)
        sw.autoresizingMask = [.minXMargin]
        row.addSubview(sw)
        return row
    }

    func makePrefControlRow(name: String, subtitle: String?, control: NSControl) -> NSView {
        let h: CGFloat = subtitle == nil ? 44 : 54
        let row = makePrefRow(height: h)
        row.addSubview(makePrefName(name, y: subtitle == nil ? (h - 18) / 2 : h - 14 - 18))
        if let subtitle = subtitle { row.addSubview(makePrefSubtitle(subtitle)) }
        control.sizeToFit()
        let cw = control.frame.width
        let ch = control.frame.height
        control.frame = NSRect(x: prefCardWidth - prefRowInset - cw, y: floor((h - ch) / 2), width: cw, height: ch)
        control.autoresizingMask = [.minXMargin]
        row.addSubview(control)
        return row
    }

    func makeSoundPopup(selected: String, action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 170, height: 26), pullsDown: false)
        for sound in shadeSoundChoices {
            popup.addItem(withTitle: sound.label)
            popup.lastItem?.representedObject = sound.name
            if sound.name == selected {
                popup.select(popup.lastItem)
            }
        }
        popup.target = self
        popup.action = action
        return popup
    }

    func titlebarDoubleClickPreferenceSubtitle() -> String {
        if let triple = systemTitlebarTripleClickDescription() {
            return "双击标题栏收起窗口；\(triple)"
        }
        return "在任意窗口标题栏双击即可收起"
    }

    func makePrefButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    func launchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func launchAtLoginSubtitle() -> String {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                return "WindowShade 会在登录后自动运行"
            case .requiresApproval:
                return "需要在系统设置中批准登录项"
            case .notRegistered:
                return "开机后自动运行 WindowShade"
            case .notFound:
                return "当前 app bundle 不支持登录项"
            @unknown default:
                return "开机后自动运行 WindowShade"
            }
        }
        return "当前系统不支持"
    }

    @objc func prefToggleTitlebarDoubleClick(_ sender: NSSwitch) {
        titlebarDoubleClickEnabled = sender.state == .on
        UserDefaults.standard.set(titlebarDoubleClickEnabled, forKey: shadeTitlebarDoubleClickDefaultsKey)
        rebuildMenu()
    }

    @objc func prefToggleFloating(_ sender: NSSwitch) {
        floatingOnTop = sender.state == .on
        UserDefaults.standard.set(floatingOnTop, forKey: shadeFloatingOnTopDefaultsKey)
        refreshOverlayPresentation(bringForward: floatingOnTop)
        rebuildMenu()
    }

    @objc func prefToggleTranslucent(_ sender: NSSwitch) {
        translucent = sender.state == .on
        UserDefaults.standard.set(translucent, forKey: shadeTranslucentDefaultsKey)
        refreshOverlayPresentation()
        rebuildMenu()
    }

    @objc func prefSelectAppearanceSegment(_ sender: NSSegmentedControl) {
        setAppearanceMode(sender.selectedSegment == 1 ? .proxyTitleBar : .nativeScreenshot)
    }

    @objc func prefToggleSound(_ sender: NSSwitch) {
        soundEnabled = sender.state == .on
        UserDefaults.standard.set(soundEnabled, forKey: shadeSoundEnabledDefaultsKey)
    }

    @objc func prefToggleLaunchAtLogin(_ sender: NSSwitch) {
        guard #available(macOS 13.0, *) else {
            sender.state = .off
            quietNotice("系统不支持", log: "launch-at-login: unsupported macOS")
            return
        }
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
                wlog("launch-at-login: register status=\(SMAppService.mainApp.status)")
            } else {
                try SMAppService.mainApp.unregister()
                wlog("launch-at-login: unregister status=\(SMAppService.mainApp.status)")
            }
        } catch {
            sender.state = launchAtLoginEnabled() ? .on : .off
            quietNotice("无法修改开机自启", log: "launch-at-login: failed \(error.localizedDescription)")
        }
        refreshPreferencesWindowIfOpen()
    }

    @objc func prefSelectFoldSound(_ sender: NSPopUpButton) {
        foldSoundName = sender.selectedItem?.representedObject as? String ?? shadeDefaultFoldSound
        UserDefaults.standard.set(foldSoundName, forKey: shadeFoldSoundDefaultsKey)
        playFoldSound()
    }

    @objc func prefSelectUnfoldSound(_ sender: NSPopUpButton) {
        unfoldSoundName = sender.selectedItem?.representedObject as? String ?? shadeDefaultUnfoldSound
        UserDefaults.standard.set(unfoldSoundName, forKey: shadeUnfoldSoundDefaultsKey)
        playUnfoldSound()
    }

    @objc func openAccessibilitySettingsAction() {
        openAccessibilityPrivacySettings()
    }

    @objc func openScreenRecordingSettingsAction() {
        openScreenRecordingPrivacySettings()
    }

@objc func showWelcomeGuide() {
        showPermissionOnboardingIfNeeded(force: true)
    }

    func showPermissionOnboardingIfNeeded(force: Bool) {
        let missing = !hasAccessibilityPermission() || !hasScreenRecordingPermission()
        let shouldShowFirstRun = !UserDefaults.standard.bool(forKey: shadeOnboardingShownDefaultsKey)
        guard missing || shouldShowFirstRun || force else { return }
        if !force && UserDefaults.standard.bool(forKey: shadeOnboardingShownDefaultsKey) { return }
        showPermissionOnboarding()
    }

    func showPermissionOnboarding() {
        if let window = onboardingWindow {
            window.contentView = makeOnboardingContentView()
            window.setContentSize(window.contentView?.frame.size ?? window.frame.size)
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let content = makeOnboardingContentView()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: content.frame.size),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "欢迎使用 WindowShade"
        window.isReleasedWhenClosed = false
        // 引导页是独立工具窗口，不参与系统标签页合并。
        window.tabbingMode = .disallowed
        window.center()
        window.contentView = content
        onboardingWindow = window
        refreshOnboardingState()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        onboardingRefreshTimer?.invalidate()
        if onboardingPermissionStack != nil {
            onboardingRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else { timer.invalidate(); return }
                guard let window = self.onboardingWindow, window.isVisible else {
                    timer.invalidate()
                    self.onboardingRefreshTimer = nil
                    return
                }
                self.refreshOnboardingState()
            }
        } else {
            onboardingRefreshTimer = nil
        }
    }

    func makeOnboardingContentView() -> NSView {
        onboardingPermissionStack = nil
        onboardingProgressLabel = nil
        onboardingDoneButton = nil
        onboardingCaption = nil

        let needsPermissions = !hasAccessibilityPermission() || !hasScreenRecordingPermission()
        let height: CGFloat = needsPermissions ? 615 : 595
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 500, height: height))
        // 减少透明度时不使用半透明页面材质，改用不透明语义底色。
        let appearance = SystemAppearanceCapabilities.current
        root.material = SystemAppearancePolicy.usesOpaqueFallback(appearance)
            ? .contentBackground : .underPageBackground
        root.blendingMode = .withinWindow
        root.isEmphasized = appearance.increaseContrast
            && !appearance.reduceTransparency
        let stack = NSStackView(frame: root.bounds.insetBy(dx: 24, dy: 22))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.autoresizingMask = [.width, .height]
        root.addSubview(stack)

        // Header: app icon + title
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        header.addArrangedSubview(makeOnboardingAppIconView(size: 40))
        let title = NSTextField(labelWithString: "把窗口留在原地，暂时收起内容")
        title.font = SystemAppearancePolicy.font(relativeToBody: 7, weight: .semibold)
        header.addArrangedSubview(title)
        stack.addArrangedSubview(header)

        let copy = NSTextField(labelWithString: "WindowShade 只做三件事：把窗口收起来、把窗口置顶、跟着合盖动一动。它不会关掉窗口，也不会改动桌面排布。")
        copy.font = SystemAppearancePolicy.font(relativeToBody: 0)
        copy.textColor = .secondaryLabelColor
        copy.lineBreakMode = .byWordWrapping
        copy.maximumNumberOfLines = 6
        copy.preferredMaxLayoutWidth = onboardingContentWidth
        stack.addArrangedSubview(copy)

        stack.addArrangedSubview(makeOnboardingUsageCard())
        if !needsPermissions {
            stack.addArrangedSubview(makeOnboardingFeatureCard())
        }

        if needsPermissions {
            let permissionCopy = NSTextField(labelWithString: "这两项权限让 WindowShade 能找到、移动和恢复窗口，也能截取窗口画面。")
            permissionCopy.font = SystemAppearancePolicy.font(relativeToBody: -1)
            permissionCopy.textColor = .tertiaryLabelColor
            permissionCopy.lineBreakMode = .byWordWrapping
            permissionCopy.maximumNumberOfLines = 3
            permissionCopy.preferredMaxLayoutWidth = onboardingContentWidth
            stack.addArrangedSubview(permissionCopy)

            let progress = NSTextField(labelWithString: "")
            progress.font = SystemAppearancePolicy.font(relativeToBody: 0, weight: .medium)
            stack.addArrangedSubview(progress)
            onboardingProgressLabel = progress

            let permissionStack = NSStackView()
            permissionStack.orientation = .vertical
            permissionStack.alignment = .leading
            permissionStack.spacing = 10
            stack.addArrangedSubview(permissionStack)
            onboardingPermissionStack = permissionStack
        }

        if needsPermissions {
            let buttonRow = NSStackView()
            buttonRow.orientation = .horizontal
            buttonRow.spacing = 10
            let later = NSButton(title: "稍后再说", target: self, action: #selector(dismissOnboarding))
            later.bezelStyle = .rounded
            buttonRow.addArrangedSubview(later)
            let done = NSButton(title: "完成设置", target: self, action: #selector(finishOnboarding))
            done.bezelStyle = .rounded
            done.keyEquivalent = "\r"
            buttonRow.addArrangedSubview(done)
            buttonRow.widthAnchor.constraint(equalToConstant: onboardingContentWidth).isActive = true
            stack.addArrangedSubview(buttonRow)
            onboardingDoneButton = done

            let caption = NSTextField(labelWithString: "两项都授权后就能开始用")
            caption.font = SystemAppearancePolicy.font(relativeToBody: -2)
            caption.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(caption)
            onboardingCaption = caption
        }

        return root
    }

    func onboardingSymbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSImageView? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let view = NSImageView()
        view.image = image.withSymbolConfiguration(config)
        view.contentTintColor = color
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    func makeOnboardingAppIconView(size: CGFloat) -> NSImageView {
        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        let baseImage = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: size, height: size))
        let image = baseImage.copy() as? NSImage ?? baseImage
        image.size = NSSize(width: size, height: size)
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
        return view
    }

    func makeOnboardingUsageCard() -> NSView {
        var rows: [(String, String)] = [
            ("keyboard", "⌃⌘C：折叠 / 展开当前窗口"),
            ("pin", "⌃⌘P：置顶或取消置顶当前窗口"),
            ("cursorarrow.click", "双击标题栏：收起或展开那个窗口"),
            ("eye", "单击卷帘条：看一眼收起的窗口"),
            ("number", "⌃⌘1…9：按菜单顺序展开已收起的窗口"),
            ("menubar.rectangle", "菜单栏：管理窗口和效果"),
        ]
        if let triple = systemTitlebarTripleClickDescription() {
            rows.insert(("cursorarrow.rays", triple), at: 1)
        }
        return makeOnboardingInfoCard(title: "常用入口", rows: rows)
    }

    func makeOnboardingFeatureCard() -> NSView {
        let rows: [(String, String)] = [
            ("rectangle.on.rectangle", "置顶：让窗口一直待在其他窗口前面"),
            ("rectangle.stack", "合盖效果：在设置 → 效果中开启"),
            ("paintpalette", "卷帘：收起后跟原来一样，或换成统一标题栏"),
            ("power", "启动：登录后自动打开"),
        ]
        return makeOnboardingInfoCard(title: "工作方式", rows: rows)
    }

    func makeOnboardingInfoCard(title: String, rows: [(String, String)]) -> NSView {
        let titleH: CGFloat = 22
        let rowH: CGFloat = 24
        let height = 14 + titleH + CGFloat(rows.count) * rowH + 10
        let card = SettingsGroupBox(frame: NSRect(x: 0, y: 0, width: onboardingContentWidth, height: height))
        card.wantsLayer = true

        card.widthAnchor.constraint(equalToConstant: onboardingContentWidth).isActive = true
        card.heightAnchor.constraint(equalToConstant: height).isActive = true

        let heading = NSTextField(labelWithString: title)
        heading.font = SystemAppearancePolicy.font(relativeToBody: -1, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        heading.frame = NSRect(x: 14, y: height - 14 - 16, width: 200, height: 16)
        card.addSubview(heading)

        var y = height - 14 - titleH - 18
        for (symbol, text) in rows {
            if let icon = onboardingSymbol(symbol, pointSize: 12, color: .secondaryLabelColor) {
                icon.frame = NSRect(x: 14, y: y, width: 16, height: 16)
                card.addSubview(icon)
            }
            let label = NSTextField(labelWithString: text)
            label.font = SystemAppearancePolicy.font(relativeToBody: 0)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 38, y: y - 1, width: onboardingContentWidth - 52, height: 18)
            card.addSubview(label)
            y -= rowH
        }
        return card
    }

    enum PermissionRowKind { case onboarding, preferences }

    // Shared permission row. `.onboarding` draws an emphasized standalone card
    // (yellow tint + 去授权 button when pending); `.preferences` is a borderless
    // row inside a grouped card (status text + 打开设置 link).
    func makePermissionRow(kind: PermissionRowKind, width: CGFloat, symbol: String,
                                   name: String, subtitle: String, granted: Bool, action: Selector) -> NSView {
        let isOnboarding = kind == .onboarding
        let height: CGFloat = isOnboarding ? 58 : 56
        let row = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        row.heightAnchor.constraint(equalToConstant: height).isActive = true

        if isOnboarding {
            SystemCornerRadius.apply(to: row, radius: SystemCornerRadius.card)
            row.layer?.backgroundColor = SystemAppearancePolicy.cgColor(
                NSColor.controlBackgroundColor, for: row)
        }

        // 权限状态只在行尾呈现，整行保持中性。
        let iconColor: NSColor = .secondaryLabelColor
        let iconBox: CGFloat = isOnboarding ? 22 : 20
        let iconX: CGFloat = isOnboarding ? 16 : 14
        let textX: CGFloat = isOnboarding ? 50 : 44
        if let icon = onboardingSymbol(symbol, pointSize: isOnboarding ? 18 : 17, color: iconColor) {
            icon.frame = NSRect(x: iconX, y: (height - iconBox) / 2, width: iconBox, height: iconBox)
            row.addSubview(icon)
        }
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 13, weight: isOnboarding ? .medium : .regular)
        nameLabel.frame = NSRect(x: textX, y: isOnboarding ? 30 : height - 13 - 18, width: 240, height: 18)
        row.addSubview(nameLabel)
        let sub = NSTextField(labelWithString: subtitle)
        sub.font = .systemFont(ofSize: isOnboarding ? 12 : 11)
        sub.textColor = isOnboarding ? .secondaryLabelColor : .tertiaryLabelColor
        sub.frame = NSRect(x: textX, y: 10, width: isOnboarding ? 240 : 230, height: isOnboarding ? 16 : 15)
        row.addSubview(sub)

        // Trailing
        switch kind {
        case .onboarding where granted:
            let status = NSTextField(labelWithString: "已授权")
            status.font = SystemAppearancePolicy.font(relativeToBody: -1, weight: .medium)
            status.textColor = .systemGreen
            status.alignment = .right
            status.frame = NSRect(x: width - 92, y: (height - 16) / 2, width: 60, height: 16)
            row.addSubview(status)
            if let check = onboardingSymbol("checkmark.circle.fill", pointSize: 13, color: .systemGreen) {
                check.frame = NSRect(x: width - 92 - 20, y: (height - 16) / 2, width: 16, height: 16)
                row.addSubview(check)
            }
        case .onboarding:
            let button = NSButton(title: "去授权", target: self, action: action)
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.isBordered = false
            button.title = "● 去授权"
            button.contentTintColor = .systemOrange
            button.font = SystemAppearancePolicy.font(relativeToBody: -1)
            SystemCornerRadius.apply(to: button, radius: SystemCornerRadius.control)
            button.sizeToFit()
            let bw = max(button.frame.width, 64)
            button.frame = NSRect(x: width - 16 - bw, y: (height - button.frame.height) / 2, width: bw, height: button.frame.height)
            row.addSubview(button)
        case .preferences:
            let link = NSButton(title: "打开设置", target: self, action: action)
            link.isBordered = false
            link.font = SystemAppearancePolicy.font(relativeToBody: -1)
            link.attributedTitle = NSAttributedString(string: "打开设置",
                attributes: [.foregroundColor: NSColor.controlAccentColor, .font: SystemAppearancePolicy.font(relativeToBody: -1)])
            link.sizeToFit()
            let lw = link.frame.width
            link.frame = NSRect(x: width - 14 - lw, y: (height - link.frame.height) / 2, width: lw, height: link.frame.height)
            link.autoresizingMask = [.minXMargin]
            row.addSubview(link)

            let statusColor: NSColor = granted ? .systemGreen : .systemOrange
            let status = NSTextField(labelWithString: granted ? "已授权" : "未授权")
            status.font = SystemAppearancePolicy.font(relativeToBody: -1, weight: .medium)
            status.textColor = statusColor
            status.sizeToFit()
            let sw = status.frame.width
            status.frame = NSRect(x: link.frame.minX - 12 - sw, y: (height - 16) / 2, width: sw, height: 16)
            status.autoresizingMask = [.minXMargin]
            row.addSubview(status)
            if let dot = onboardingSymbol(granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill", pointSize: 12, color: statusColor) {
                dot.frame = NSRect(x: status.frame.minX - 17, y: (height - 15) / 2, width: 15, height: 15)
                dot.autoresizingMask = [.minXMargin]
                row.addSubview(dot)
            }
        }
        return row
    }

    func refreshOnboardingState() {
        guard let permissionStack = onboardingPermissionStack else { return }
        let ax = hasAccessibilityPermission()
        let screen = hasScreenRecordingPermission()

        permissionStack.arrangedSubviews.forEach {
            permissionStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let card = makeUnifiedSettingsCard([
            makeUnifiedPermissionRow(symbol: "accessibility", name: "辅助功能",
                subtitle: "找到、移动和恢复窗口", granted: ax,
                action: #selector(openAccessibilitySettingsAction)),
            makeUnifiedPermissionRow(symbol: "rectangle.inset.filled.and.person.filled", name: "屏幕录制",
                subtitle: "截取窗口画面做预览", granted: screen,
                action: #selector(openScreenRecordingSettingsAction)),
        ], separatorInset: 46)
        permissionStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalToConstant: onboardingContentWidth).isActive = true

        let grantedCount = (ax ? 1 : 0) + (screen ? 1 : 0)
        let allGranted = grantedCount == 2
        if let progress = onboardingProgressLabel {
            if allGranted {
                progress.stringValue = "权限已就绪"
                progress.textColor = .systemGreen
            } else {
                progress.stringValue = "还差\(2 - grantedCount)步权限 · \(grantedCount) / 2 已完成"
                progress.textColor = .labelColor
            }
        }
        onboardingDoneButton?.isEnabled = allGranted
        onboardingCaption?.isHidden = allGranted
    }
    @objc func toggleFloatingOnTop(_ sender: NSMenuItem) {
        floatingOnTop.toggle()
        UserDefaults.standard.set(floatingOnTop, forKey: shadeFloatingOnTopDefaultsKey)
        refreshOverlayPresentation(bringForward: floatingOnTop)
        rebuildMenu()
        refreshPreferencesWindowIfOpen()
    }

    @objc func toggleTranslucent(_ sender: NSMenuItem) {
        translucent.toggle()
        UserDefaults.standard.set(translucent, forKey: shadeTranslucentDefaultsKey)
        refreshOverlayPresentation()
        rebuildMenu()
        refreshPreferencesWindowIfOpen()
    }

    // MARK: 窗口浏览

    @objc func openWindowBrowserPanel() {
        windowBrowserController?.openKeyboardPanel()
    }

    func makeWindowBrowserSettingsPage() -> NSView {
        let (root, stack) = makeSettingsPageRoot()
        stack.addArrangedSubview(makeSettingsHeader(
            title: "窗口浏览",
            subtitle: "在 Dock 图标上看这个应用的全部窗口，也可以用菜单或快捷键打开。",
            symbolName: "rectangle.on.rectangle"))

        let triggers = makeUnifiedSettingsCard([
            makeUnifiedToggleRow(
                name: "Dock 悬停查看窗口",
                subtitle: "鼠标停在 Dock 图标上时显示窗口面板。不会启动没在运行的应用。",
                isOn: WindowBrowserSettings.dockEnabled,
                action: #selector(prefToggleWindowBrowserDock(_:))),
            makeUnifiedToggleRow(
                name: "从菜单打开窗口浏览",
                subtitle: "在菜单里加入“选择窗口…”；默认不占用快捷键",
                isOn: WindowBrowserSettings.keyboardPanelEnabled,
                action: #selector(prefToggleWindowBrowserKeyboard(_:))),
        ])
        stack.addArrangedSubview(makePrefGroupLabel("触发"))
        stack.addArrangedSubview(triggers)
        triggers.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: triggers)

        let recorder = WindowBrowserHotKeyRecorderView()
        recorder.configure(current: WindowBrowserSettings.hotKey)
        recorder.onCapture = { [weak self] hotKey in
            guard let self else { return }
            let previous = WindowBrowserSettings.hotKey
            WindowBrowserSettings.hotKey = hotKey
            if hotKey != nil, !self.registerWindowBrowserHotKey() {
                WindowBrowserSettings.hotKey = previous
                _ = self.registerWindowBrowserHotKey()
            }
            recorder.configure(current: WindowBrowserSettings.hotKey)
        }

        let preview = makeUnifiedSettingsCard([
            makeUnifiedToggleRow(
                name: "普通窗口实时预览（实验）",
                subtitle: "选中窗口 0.4 秒后开始放实时画面。默认关闭。",
                isOn: WindowBrowserSettings.livePreviewEnabled,
                action: #selector(prefToggleWindowBrowserLive(_:))),
            makeUnifiedControlRow(
                name: "打开窗口浏览",
                subtitle: "打开开关后，菜单和快捷键才会出现",
                control: {
                    let button = NSButton(title: "打开面板…", target: self,
                                          action: #selector(openWindowBrowserPanel))
                    button.bezelStyle = .rounded
                    return button
                }()),
            makeUnifiedControlRow(
                name: "独立快捷键",
                subtitle: "用同一组合打开或关闭面板。需包含 ⌃ 或 ⌥。",
                control: recorder),
            makeUnifiedControlRow(
                name: "按应用排除",
                subtitle: excludedAppsSubtitle(),
                control: {
                    let button = NSButton(title: "编辑排除清单…", target: self,
                                          action: #selector(prefEditWindowBrowserExclusions))
                    button.bezelStyle = .rounded
                    return button
                }()),
        ])
        stack.addArrangedSubview(makePrefGroupLabel("面板"))
        stack.addArrangedSubview(preview)
        preview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: preview)

        // 外观：跟随系统（可用的系统玻璃 / 原生材质）或明确的不透明纸面。
        // 玻璃环境不可用时不会显示一个实际不起作用的玻璃开关。
        let appearanceControl = NSSegmentedControl(labels: ["跟随系统外观", "不透明背景"],
                                                   trackingMode: .selectOne,
                                                   target: self,
                                                   action: #selector(prefChangeWindowBrowserAppearance(_:)))
        appearanceControl.selectedSegment =
            WindowBrowserAppearanceStyle.current == .paper ? 1 : 0
        let styleControl = NSSegmentedControl(
            labels: WindowBrowserSettings.PreferredStyle.allCases.map(\.displayName),
            trackingMode: .selectOne, target: self,
            action: #selector(prefChangeWindowBrowserStyle(_:)))
        styleControl.selectedSegment = WindowBrowserSettings.PreferredStyle.allCases
            .firstIndex(of: WindowBrowserSettings.preferredStyle) ?? 0
        let appearance = makeUnifiedSettingsCard([
            makeUnifiedControlRow(
                name: "外观",
                subtitle: "开启系统的“减少透明度”时，自动使用不透明背景。",
                control: appearanceControl),
            makeUnifiedControlRow(
                name: "默认显示方式",
                subtitle: "自动：窗口多的时候用列表，少的时候用缩略图。面板里的切换只影响这一次。",
                control: styleControl),
            makeUnifiedControlRow(
                name: "排布与撤销",
                subtitle: "在窗口右键菜单里选“排布”：左半、右半、四角、居中、铺满屏幕、"
                    + "移到另一块屏幕。可以先看效果，移好之后还能撤销。",
                control: NSTextField(labelWithString: "")),
        ])
        stack.addArrangedSubview(makePrefGroupLabel("外观"))
        stack.addArrangedSubview(appearance)
        appearance.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: appearance)

        let permissions = makeUnifiedSettingsCard([
            makeUnifiedPermissionRow(symbol: "accessibility", name: "辅助功能",
                subtitle: "识别 Dock 图标，切换、收起、展开和关闭窗口",
                granted: hasAccessibilityPermission(),
                action: #selector(openAccessibilitySettingsAction)),
            makeUnifiedPermissionRow(symbol: "rectangle.inset.filled.and.person.filled", name: "屏幕录制",
                subtitle: "窗口缩略图与实时预览；缺失时显示图标和文字列表",
                granted: hasScreenRecordingPermission(),
                action: #selector(openScreenRecordingSettingsAction)),
        ], separatorInset: 46)
        stack.addArrangedSubview(makePrefGroupLabel("权限"))
        stack.addArrangedSubview(permissions)
        permissions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let note = NSTextField(wrappingLabelWithString:
            "窗口浏览是临时面板：不会替换系统 Dock，不接管原生 Command-Tab，"
            + "不跨 Space 搬运窗口。关闭功能或退出时会释放新增的观察器、截图与预览流；"
            + "原有卷帘、恢复日志与置顶预览不受影响。")
        note.font = SystemAppearancePolicy.font(relativeToBody: -2)
        note.textColor = .secondaryLabelColor
        note.maximumNumberOfLines = 4
        stack.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return root
    }

    private func excludedAppsSubtitle() -> String {
        let ids = WindowBrowserSettings.excludedBundleIDs
        if ids.isEmpty { return "尚未排除任何应用" }
        return "已排除 \(ids.count) 个应用：\(ids.sorted().prefix(2).joined(separator: "、"))"
            + (ids.count > 2 ? " 等" : "")
    }

    @objc func prefToggleWindowBrowserDock(_ sender: NSSwitch) {
        WindowBrowserSettings.dockEnabled = sender.state == .on
        notifyWindowBrowserSettingsChanged()
    }

    @objc func prefToggleWindowBrowserKeyboard(_ sender: NSSwitch) {
        WindowBrowserSettings.keyboardPanelEnabled = sender.state == .on
        notifyWindowBrowserSettingsChanged()
    }

    @objc func prefToggleWindowBrowserLive(_ sender: NSSwitch) {
        WindowBrowserSettings.livePreviewEnabled = sender.state == .on
        notifyWindowBrowserSettingsChanged()
    }

    @objc func prefChangeWindowBrowserAppearance(_ sender: NSSegmentedControl) {
        WindowBrowserAppearanceStyle.current = sender.selectedSegment == 1 ? .paper : .system
        notifyWindowBrowserSettingsChanged()
    }

    @objc func prefChangeWindowBrowserStyle(_ sender: NSSegmentedControl) {
        let styles = WindowBrowserSettings.PreferredStyle.allCases
        guard sender.selectedSegment >= 0, sender.selectedSegment < styles.count else { return }
        WindowBrowserSettings.preferredStyle = styles[sender.selectedSegment]
        notifyWindowBrowserSettingsChanged()
    }

    @objc func prefEditWindowBrowserExclusions() {
        let alert = NSAlert()
        alert.messageText = "按应用排除"
        alert.informativeText = "一行一个应用标识。这里列出的应用不会出现在窗口浏览面板里。"
        // 多行编辑必须用 NSTextView：单行 NSTextField 放不下“每行一个 bundle ID”。
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 140))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 340, height: 140))
        textView.isEditable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = WindowBrowserSettings.excludedBundleIDs.sorted().joined(separator: "\n")
        scroll.documentView = textView
        alert.accessoryView = scroll
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let ids = Set(textView.string
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        WindowBrowserSettings.excludedBundleIDs = ids
        notifyWindowBrowserSettingsChanged()
        refreshPreferencesWindowIfOpen()
    }

    private func notifyWindowBrowserSettingsChanged() {
        NotificationCenter.default.post(name: WindowBrowserNotification.didChangeSettings, object: nil)
    }

}

/// 快捷键记录器：只在设置页明确聚焦时读取键盘事件，不安装任何全局监听。
final class WindowBrowserHotKeyRecorderView: NSControl {
    var onCapture: ((WindowBrowserSettings.HotKey?) -> Void)?
    private let label = NSTextField(labelWithString: "未设置")
    private let recordButton = NSButton(title: "录制…", target: nil, action: nil)
    private let clearButton = NSButton(title: "清除", target: nil, action: nil)
    private var recording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = WindowBrowserTypography.monospacedDigits
        label.lineBreakMode = .byTruncatingTail
        for button in [recordButton, clearButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
        }
        recordButton.target = self
        recordButton.action = #selector(beginRecording)
        clearButton.target = self
        clearButton.action = #selector(clearHotKey)
        for view in [label, recordButton, clearButton] { addSubview(view) }
        widthAnchor.constraint(equalToConstant: 240).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("打开窗口浏览的快捷键")
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    func configure(current: WindowBrowserSettings.HotKey?) {
        label.stringValue = current.map { WindowBrowserSettings.displayName(for: $0) } ?? "未设置"
        setAccessibilityValue(label.stringValue)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        clearButton.frame = NSRect(x: bounds.width - 56, y: (bounds.height - 24) / 2,
                                   width: 56, height: 24)
        recordButton.frame = NSRect(x: bounds.width - 56 - 6 - 64,
                                    y: (bounds.height - 24) / 2, width: 64, height: 24)
        label.frame = NSRect(x: 0, y: (bounds.height - 16) / 2,
                             width: max(60, recordButton.frame.minX - 8), height: 16)
    }

    @objc private func beginRecording() {
        recording = true
        label.stringValue = "请按快捷键…"
        window?.makeFirstResponder(self)
    }

    @objc private func clearHotKey() {
        recording = false
        onCapture?(nil)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            recording = false
            onCapture?(WindowBrowserSettings.hotKey)
            return
        }
        capture(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        capture(event)
        return true
    }

    private func capture(_ event: NSEvent) {
        // 只按修饰键不构成快捷键：保持录制状态，等真正的键。
        guard !WindowBrowserSettings.isModifierOnlyKeyCode(event.keyCode) else { return }
        recording = false
        let hotKey = WindowBrowserSettings.HotKey(
            keyCode: UInt32(event.keyCode),
            modifiers: WindowBrowserHotKeyRecorderView.carbonModifiers(from: event.modifierFlags))
        if WindowBrowserSettings.isReserved(hotKey) {
            NSSound.beep()
            configure(current: WindowBrowserSettings.hotKey)
            return
        }
        onCapture?(hotKey)
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}
